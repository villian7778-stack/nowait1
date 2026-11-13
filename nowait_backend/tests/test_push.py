"""Push notifications (Firebase Cloud Messaging) - with a throw-away key and a fake Google."""
import base64
import json
from unittest.mock import MagicMock, patch

import jwt
import pytest
from cryptography.hazmat.primitives import serialization
from cryptography.hazmat.primitives.asymmetric import rsa
from fastapi.testclient import TestClient

from app.config import settings
from app.services import notification_service, push_service
from tests.conftest import make_chain, ok, ok_list

_KEY = rsa.generate_private_key(public_exponent=65537, key_size=2048)
CREDS = {
    "project_id": "nowaitt-test",
    "client_email": "push@nowaitt-test.iam.gserviceaccount.com",
    "private_key": _KEY.private_bytes(serialization.Encoding.PEM, serialization.PrivateFormat.PKCS8,
                                      serialization.NoEncryption()).decode(),
}
B64 = base64.b64encode(json.dumps(CREDS).encode()).decode()


@pytest.fixture
def push_on():
    with patch.object(settings, "FIREBASE_CREDENTIALS_BASE64", B64), \
         patch.object(push_service, "_access_token", None):
        yield


class FakeGoogle:
    """Answers the OAuth token call and the FCM send call like Google does."""
    def __init__(self, send_status=200, send_text='{"name": "projects/x/messages/1"}'):
        self.token_calls, self.sends = [], []
        self.send_status, self.send_text = send_status, send_text

    def post(self, url, data=None, json=None, headers=None, timeout=None):
        res = MagicMock()
        if url == push_service._TOKEN_URL:
            claims = jwt.decode(data["assertion"], _KEY.public_key(), algorithms=["RS256"], audience=push_service._TOKEN_URL)
            self.token_calls.append(claims)
            res.json.return_value = {"access_token": "ya29.test", "expires_in": 3600}
            res.raise_for_status.return_value = None
        else:
            self.sends.append({"url": url, "json": json, "headers": headers})
            res.status_code, res.text = self.send_status, self.send_text
        return res


def test_off_without_credentials():
    assert push_service.enabled() is False
    with patch.object(push_service, "_pool") as pool:
        push_service.notify_user("u1", "your_turn", "t", "b")
    pool.submit.assert_not_called()


def test_sends_the_right_message(push_on):
    g = FakeGoogle()
    with patch.object(push_service.httpx, "post", g.post):
        assert push_service.send_now("phone-token", "It's Your Turn!", "Token #12", {"type": "your_turn", "shop_id": "s1"})
        assert push_service.send_now("phone-token", "again", "again")
    assert len(g.token_calls) == 1  # the access token is reused, not fetched per message
    assert g.token_calls[0]["iss"] == CREDS["client_email"]
    assert g.token_calls[0]["scope"] == push_service._SCOPE
    send = g.sends[0]
    assert send["url"] == "https://fcm.googleapis.com/v1/projects/nowaitt-test/messages:send"
    assert send["headers"]["Authorization"] == "Bearer ya29.test"
    msg = send["json"]["message"]
    assert msg["token"] == "phone-token"
    assert msg["notification"] == {"title": "It's Your Turn!", "body": "Token #12"}
    assert msg["data"] == {"type": "your_turn", "shop_id": "s1"}
    assert msg["android"]["notification"]["channel_id"] == "nowait_alerts"


def test_a_dead_phone_token_is_forgotten(push_on):
    g = FakeGoogle(send_status=404, send_text='{"error": {"status": "NOT_FOUND", "details": [{"errorCode": "UNREGISTERED"}]}}')
    with patch.object(push_service.httpx, "post", g.post), patch.object(push_service, "_forget_token") as forget:
        assert push_service.send_now("old-token", "t", "b") is False
    forget.assert_called_once_with("old-token")


def test_network_trouble_never_raises(push_on):
    def boom(*a, **k):
        raise push_service.httpx.ConnectError("down")
    with patch.object(push_service.httpx, "post", boom):
        assert push_service.send_now("tok", "t", "b") is False


@pytest.mark.parametrize("kind,pushed", [
    ("your_turn", True), ("almost_there", True), ("skipped", True), ("coming", True),
    ("scheme", False), ("promotion", False), ("queue_update", False),
])
def test_only_queue_alerts_are_pushed(push_on, kind, pushed):
    with patch.object(push_service, "_pool") as pool:
        push_service.notify_user("u1", kind, "t", "b")
    assert pool.submit.called is pushed


def test_push_goes_to_that_users_phone(push_on):
    sb = MagicMock()
    sb.table.side_effect = lambda name: make_chain(ok_list([{"fcm_token": "asha-phone"}]))
    jobs = []
    with patch.object(push_service, "supabase", sb), \
         patch.object(push_service, "_pool", MagicMock(submit=lambda fn: jobs.append(fn))), \
         patch.object(push_service, "send_now") as send:
        push_service.notify_user("asha", "your_turn", "It's Your Turn!", "Token #12", {"shop_id": "s1"})
        jobs[0]()
    send.assert_called_once_with("asha-phone", "It's Your Turn!", "Token #12", {"type": "your_turn", "shop_id": "s1"})


def test_no_push_for_a_user_who_did_not_allow_notifications(push_on):
    sb = MagicMock()
    sb.table.side_effect = lambda name: make_chain(ok_list([{"fcm_token": None}]))
    jobs = []
    with patch.object(push_service, "supabase", sb), \
         patch.object(push_service, "_pool", MagicMock(submit=lambda fn: jobs.append(fn))), \
         patch.object(push_service, "send_now") as send:
        push_service.notify_user("u1", "your_turn", "t", "b")
        jobs[0]()
    send.assert_not_called()


def test_saving_a_notification_also_pushes_it():
    sb = MagicMock()
    sb.table.side_effect = lambda name: make_chain(ok_list([{"id": "n1"}]))
    with patch.object(notification_service, "supabase", sb), \
         patch.object(notification_service.push_service, "notify_user") as notify:
        notification_service.create_notification("u1", "your_turn", "It's Your Turn!", "Token #12", "Shop", "s1")
    notify.assert_called_once_with("u1", "your_turn", "It's Your Turn!", "Token #12", {"shop_id": "s1"})


class TestTokenEndpoints:
    @pytest.fixture
    def client(self):
        from app.dependencies import get_current_user
        from app.main import app
        app.dependency_overrides[get_current_user] = lambda: {"id": "asha", "role": "customer"}
        yield TestClient(app, raise_server_exceptions=False)
        app.dependency_overrides.pop(get_current_user, None)

    def _sb(self):
        calls = []
        def table(name):
            chain = make_chain(ok([]))
            chain.update.side_effect = lambda data: (calls.append(("update", data)), chain)[1]
            chain.eq.side_effect = lambda col, val: (calls.append(("eq", col, val)), chain)[1]
            chain.neq.side_effect = lambda col, val: (calls.append(("neq", col, val)), chain)[1]
            return chain
        sb = MagicMock()
        sb.table.side_effect = table
        return sb, calls

    def test_one_phone_belongs_to_one_account(self, client):
        sb, calls = self._sb()
        with patch("app.database.supabase", sb):
            r = client.post("/auth/fcm-token", json={"fcm_token": "shared-phone"})
        assert r.status_code == 200
        # first: taken away from anyone else using this phone, then saved for this user
        assert calls[:3] == [("update", {"fcm_token": None}), ("eq", "fcm_token", "shared-phone"), ("neq", "id", "asha")]
        assert ("update", {"fcm_token": "shared-phone"}) in calls and ("eq", "id", "asha") in calls

    def test_logout_clears_only_your_token(self, client):
        sb, calls = self._sb()
        with patch("app.database.supabase", sb):
            r = client.delete("/auth/fcm-token")
        assert r.status_code == 200
        assert calls == [("update", {"fcm_token": None}), ("eq", "id", "asha")]

    def test_needs_login(self):
        from app.main import app
        r = TestClient(app).delete("/auth/fcm-token")
        assert r.status_code in (401, 403)


def test_privacy_policy_mentions_notifications():
    from app.main import app
    text = TestClient(app).get("/legal/privacy").text
    assert "send alerts to your phone" in text and "When you log out, we delete this code" in text
    for jargon in ("Firebase", "token", "FCM"):  # plain words for everyone
        assert jargon not in text.split("<b>Notifications:</b>")[1].split("</li>")[0], jargon
