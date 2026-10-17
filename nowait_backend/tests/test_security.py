"""Security checks: token verification, the paid Maps proxy, photo uploads, profile completion and
input limits. Each test is an attack (or misuse) that must be refused."""
import io
import json
import time
from unittest.mock import AsyncMock, MagicMock, patch

import jwt
import pytest
from cryptography.hazmat.primitives.asymmetric import ec
from fastapi import HTTPException
from fastapi.testclient import TestClient

from app import dependencies as deps
from app.config import settings

SECRET = settings.SUPABASE_JWT_SECRET


def _claims(**over):
    c = {"sub": "user-1", "aud": "authenticated", "role": "authenticated", "exp": int(time.time()) + 600}
    c.update(over)
    return c


@pytest.fixture
def es256():
    """An ES256 key published as JWKS, like a current Supabase project."""
    private = ec.generate_private_key(ec.SECP256R1())
    jwk = json.loads(jwt.algorithms.ECAlgorithm.to_jwk(private.public_key()))
    jwk.update({"kid": "key-1", "alg": "ES256", "use": "sig"})
    with patch.object(deps, "_get_jwks", return_value=[jwk]):
        yield private, jwk


# ── Token verification ─────────────────────────────────────────────────────────────────

class TestTokens:
    def test_valid_legacy_hs256_token(self):
        assert deps.decode_jwt(jwt.encode(_claims(), SECRET, algorithm="HS256"))["sub"] == "user-1"

    def test_valid_es256_token_from_jwks(self, es256):
        private, _ = es256
        token = jwt.encode(_claims(), private, algorithm="ES256", headers={"kid": "key-1"})
        assert deps.decode_jwt(token)["sub"] == "user-1"

    @pytest.mark.parametrize("make", [
        lambda: jwt.encode(_claims(), "not-the-secret-at-all-padding-xxxxxx", algorithm="HS256"),     # wrong secret
        lambda: jwt.encode(_claims(aud="anon"), SECRET, algorithm="HS256"),                          # wrong audience
        lambda: jwt.encode({k: v for k, v in _claims().items() if k != "aud"}, SECRET, algorithm="HS256"),  # e.g. the service key
        lambda: jwt.encode(_claims(), None, algorithm="none"),                                       # unsigned
        lambda: "not.a.token",
    ])
    def test_forged_or_wrong_tokens_are_refused(self, make):
        with pytest.raises(HTTPException) as e:
            deps.decode_jwt(make())
        assert e.value.status_code == 401

    def test_expired_token(self):
        with pytest.raises(HTTPException) as e:
            deps.decode_jwt(jwt.encode(_claims(exp=int(time.time()) - 10), SECRET, algorithm="HS256"))
        assert e.value.detail == "Token expired"

    def test_algorithm_confusion_with_the_public_key_is_refused(self, es256):
        # Classic attack: sign HS256 using the *public* key as the HMAC secret.
        # (PyJWT won't even create such a token, so build it by hand like an attacker would.)
        import base64
        import hashlib
        import hmac as _hmac
        _, jwk = es256
        b64 = lambda b: base64.urlsafe_b64encode(b).rstrip(b"=")
        head = b64(json.dumps({"alg": "HS256", "typ": "JWT", "kid": "key-1"}).encode())
        body = b64(json.dumps(_claims()).encode())
        for secret in (json.dumps(jwk).encode(), jwk["x"].encode()):
            sig = b64(_hmac.new(secret, head + b"." + body, hashlib.sha256).digest())
            with pytest.raises(HTTPException):
                deps.decode_jwt((head + b"." + body + b"." + sig).decode())

    def test_token_signed_by_another_key_is_refused(self, es256):
        other = ec.generate_private_key(ec.SECP256R1())
        token = jwt.encode(_claims(), other, algorithm="ES256", headers={"kid": "key-1"})
        with pytest.raises(HTTPException):
            deps.decode_jwt(token)

    def test_unknown_or_missing_key_id_is_refused(self, es256):
        private, _ = es256
        for headers in ({"kid": "some-other-key"}, {}):
            with pytest.raises(HTTPException):
                deps.decode_jwt(jwt.encode(_claims(), private, algorithm="ES256", headers=headers))

    def test_token_without_a_user_is_refused(self):
        token = jwt.encode({k: v for k, v in _claims().items() if k != "sub"}, SECRET, algorithm="HS256")
        with pytest.raises(HTTPException) as e:
            deps.get_token_user_id(MagicMock(credentials=token))
        assert e.value.status_code == 401


# ── Maps proxy (billed to our Google key) ───────────────────────────────────────────────

@pytest.fixture
def client():
    from app.main import app
    yield TestClient(app, raise_server_exceptions=False)
    app.dependency_overrides.clear()


def _as(role):
    from app.dependencies import get_current_user
    from app.main import app
    app.dependency_overrides[get_current_user] = lambda: {"id": f"{role}-1", "role": role}


@pytest.fixture
def google():
    """Captures what we would send to Google instead of calling it."""
    from app import rate_limit
    rate_limit._owner_calls.clear()
    sent = []

    class FakeClient:
        def __init__(self, *a, **k):
            pass

        async def __aenter__(self):
            return self

        async def __aexit__(self, *a):
            return False

        async def get(self, url, params=None):
            sent.append((url, params))
            return MagicMock(status_code=200, json=lambda: {"status": "OK", "results": [], "predictions": []})

    with patch("app.routers.maps.httpx.AsyncClient", FakeClient), patch.object(settings, "GOOGLE_MAP_KEY", "k"):
        yield sent


class TestMaps:
    URLS = ["/maps/geocode?latlng=20.7,77.0", "/maps/places/autocomplete?input=akola",
            "/maps/place/details?place_id=ChIJ1234567890abcdef"]

    @pytest.mark.parametrize("url", URLS)
    def test_strangers_cannot_spend_our_google_credit(self, client, google, url):
        assert client.get(url).status_code in (401, 403)
        assert google == []

    @pytest.mark.parametrize("url", URLS)
    def test_customers_cannot_either(self, client, google, url):
        _as("customer")
        assert client.get(url).status_code == 403
        assert google == []

    def test_owner_can_use_it(self, client, google):
        _as("owner")
        assert client.get("/maps/geocode?latlng=20.7,77.0").status_code == 200
        assert len(google) == 1

    def test_caller_cannot_ask_for_expensive_fields(self, client, google):
        _as("owner")
        client.get("/maps/place/details?place_id=ChIJ1234567890abcdef&fields=reviews,photos,opening_hours")
        assert google[0][1]["fields"] == "geometry,formatted_address"

    def test_unknown_types_and_components_are_replaced(self, client, google):
        _as("owner")
        client.get("/maps/places/autocomplete?input=akola&types=restaurant|cafe&components=anything")
        params = google[0][1]
        assert params["types"] == "geocode" and params["components"] == "country:in"

    @pytest.mark.parametrize("url", ["/maps/geocode?latlng=hello", "/maps/geocode?latlng=999,999",
                                     "/maps/place/details?place_id=../../etc", "/maps/places/autocomplete?input=" + "a" * 101])
    def test_bad_input_never_reaches_google(self, client, google, url):
        _as("owner")
        assert client.get(url).status_code == 422
        assert google == []

    def test_rate_limited_per_owner(self, client, google):
        _as("owner")
        codes = [client.get("/maps/geocode?latlng=20.7,77.0").status_code for _ in range(61)]
        assert codes[:60] == [200] * 60 and codes[60] == 429


# ── Photo uploads ──────────────────────────────────────────────────────────────────────

class TestUploads:
    def _post(self, client, data, name="photo.jpg", ctype="image/jpeg"):
        from app.dependencies import get_current_owner
        from app.main import app
        app.dependency_overrides[get_current_owner] = lambda: {"id": "owner-1", "role": "owner"}
        with patch("app.routers.shops.shop_service.upload_shop_image", return_value={"url": "u", "images": ["u"]}) as up:
            r = client.post("/shops/s1/images", files={"file": (name, io.BytesIO(data), ctype)})
        return r, up

    def test_html_pretending_to_be_a_jpeg_is_refused(self, client):
        r, up = self._post(client, b"<html><script>alert(1)</script></html>", name="x.html")
        assert r.status_code == 415
        up.assert_not_called()

    def test_svg_is_refused(self, client):
        r, up = self._post(client, b'<svg xmlns="http://www.w3.org/2000/svg"><script/></svg>', name="x.svg", ctype="image/jpeg")
        assert r.status_code == 415

    def test_real_png_is_stored_as_png_whatever_the_phone_claims(self, client):
        png = bytes([0x89]) + b"PNG\r\n\x1a\n" + b"\x00" * 64
        r, up = self._post(client, png, name="evil.html", ctype="image/jpeg")
        assert r.status_code == 201
        assert up.call_args.args[4] == "image/png"   # the checked type is what gets stored

    def test_storage_name_never_uses_the_uploaded_file_name(self):
        from app.services import shop_service
        storage = MagicMock()
        with patch.object(shop_service, "execute_one", return_value=MagicMock(data={"id": "s1", "images": []})), \
             patch.object(shop_service, "supabase") as db:
            db.storage.from_.return_value = storage
            storage.get_public_url.return_value = "https://x/s1/a.png"
            shop_service.upload_shop_image("s1", "owner-1", b"data", "../../evil.html", "image/png")
        path = storage.upload.call_args.kwargs["path"]
        assert path.startswith("s1/") and path.endswith(".png") and "evil" not in path and ".." not in path


# ── Profile completion & input limits ──────────────────────────────────────────────────

def test_complete_profile_cannot_rewrite_an_existing_profile():
    from app.schemas.auth import CompleteProfileRequest
    from app.services import auth_service
    body = CompleteProfileRequest(name="Someone", phone="+919999999999", state="Maharashtra", city="Akola", role="owner")
    with patch.object(auth_service, "execute_one", return_value=MagicMock(data={"id": "user-1"})), \
         patch.object(auth_service, "supabase") as db:
        with pytest.raises(HTTPException) as e:
            auth_service.complete_profile("user-1", "a@b.com", body)
    assert e.value.status_code == 409
    db.table.return_value.upsert.assert_not_called()


@pytest.mark.parametrize("model,kwargs", [
    ("app.schemas.promotion.PromotionCreate", {"title": "x" * 101, "description": "d", "valid_until": "2026-01-01"}),
    ("app.schemas.promotion.PromotionCreate", {"title": "t", "description": "x" * 501, "valid_until": "2026-01-01"}),
    ("app.schemas.queue.JoinQueueRequest", {"shop_id": "s1", "service_ids": ["s"] * 21}),
    ("app.schemas.staff.AddStaffByNameRequest", {"name": "x" * 61}),
    ("app.schemas.staff.AddStaffRequest", {"phone": "1" * 40}),
    ("app.schemas.payment.CheckoutFailureReport", {"raw": "x" * 4001}),
    ("app.schemas.payment.SubscriptionVerifyRequest", {"razorpay_order_id": "o" * 65, "razorpay_payment_id": "p", "razorpay_signature": "s"}),
])
def test_oversized_input_is_rejected(model, kwargs):
    import importlib
    from pydantic import ValidationError
    mod, cls = model.rsplit(".", 1)
    with pytest.raises(ValidationError):
        getattr(importlib.import_module(mod), cls)(**kwargs)


# ── Cloudflare in front of the server ──────────────────────────────────────────────────

class TestCloudflare:
    def test_off_by_default_everything_works_as_before(self, client):
        with patch.object(settings, "CLOUDFLARE_ORIGIN_SECRET", ""):
            assert client.get("/").status_code == 200

    @pytest.mark.parametrize("headers", [{}, {"X-Origin-Secret": "wrong"}, {"X-Origin-Secret": "s3cret-but-longer"}])
    def test_requests_going_around_cloudflare_are_refused(self, client, headers):
        with patch.object(settings, "CLOUDFLARE_ORIGIN_SECRET", "s3cret"):
            assert client.get("/", headers=headers).status_code == 403
            assert client.post("/payments/webhook", headers=headers, content=b"{}").status_code == 403

    def test_requests_through_cloudflare_are_served(self, client):
        with patch.object(settings, "CLOUDFLARE_ORIGIN_SECRET", "s3cret"):
            assert client.get("/", headers={"X-Origin-Secret": "s3cret"}).status_code == 200

    def test_health_check_stays_open_for_render(self, client):
        with patch.object(settings, "CLOUDFLARE_ORIGIN_SECRET", "s3cret"):
            assert client.get("/health").status_code == 200

    def _ip(self, headers, secret):
        from starlette.requests import Request
        from app.rate_limit import client_ip
        raw = [(k.lower().encode(), v.encode()) for k, v in headers.items()]
        req = Request({"type": "http", "headers": raw, "client": ("10.0.0.1", 1234)})
        with patch.object(settings, "CLOUDFLARE_ORIGIN_SECRET", secret):
            return client_ip(req)

    def test_rate_limit_uses_cloudflares_visitor_ip(self):
        assert self._ip({"CF-Connecting-IP": "49.36.1.2"}, "s3cret") == "49.36.1.2"

    def test_cloudflare_header_is_ignored_when_not_behind_cloudflare(self):
        # Without the origin lock anyone could send CF-Connecting-IP to dodge the limits.
        assert self._ip({"CF-Connecting-IP": "1.2.3.4"}, "") == "10.0.0.1"


def test_fcm_token_must_be_a_short_string(client):
    _as("customer")
    with patch("app.database.supabase"):
        assert client.post("/auth/fcm-token", json={"fcm_token": {"$ne": 1}}).status_code == 400
        assert client.post("/auth/fcm-token", json={"fcm_token": "x" * 5000}).status_code == 400
