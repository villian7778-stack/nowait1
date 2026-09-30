"""Tests for payment binding, replay protection and subscription extension."""
from datetime import datetime, timedelta, timezone
from unittest.mock import MagicMock, patch

import pytest
from fastapi import HTTPException

from tests.conftest import make_chain, ok_list


def _iso(dt):
    return dt.isoformat()


def _body(order="order_1", pay="pay_1", sig="sig"):
    from app.schemas.payment import SubscriptionVerifyRequest
    return SubscriptionVerifyRequest(razorpay_order_id=order, razorpay_payment_id=pay, razorpay_signature=sig)


# ── Subscription extension maths ─────────────────────────────────────────────

class TestExtension:
    def _run(self, existing, plan="basic", duration=30):
        from app.schemas.subscription import SubscriptionCreate
        from app.services import subscription_service

        written = []
        row = {"id": "s1", "shop_id": "shop-001", "plan": plan, "status": "active",
               "started_at": _iso(datetime.now(timezone.utc)), "expires_at": _iso(datetime.now(timezone.utc))}
        chain = make_chain(ok_list([row]))
        chain.update.side_effect = lambda d: written.append(d) or chain
        chain.insert.side_effect = lambda d: written.append(d) or chain
        calls = iter([MagicMock(data={"id": "shop-001"}), MagicMock(data=existing)])
        with patch("app.services.subscription_service.execute_one", side_effect=lambda q: next(calls)), \
             patch("app.services.subscription_service.supabase") as sup:
            sup.table = chain.table
            subscription_service.create_or_renew_subscription(
                "shop-001", "owner-001", SubscriptionCreate(plan=plan, duration_days=duration))
        return written[0]

    def test_new_subscription_starts_now(self):
        now = datetime.now(timezone.utc)
        data = self._run(None, duration=30)
        exp = datetime.fromisoformat(data["expires_at"])
        assert abs((exp - (now + timedelta(days=30))).total_seconds()) < 5

    def test_active_subscription_extends_from_current_end(self):
        now = datetime.now(timezone.utc)
        current_end = now + timedelta(days=10)
        data = self._run({"status": "active", "started_at": _iso(now - timedelta(days=20)),
                          "expires_at": _iso(current_end)}, duration=30)
        exp = datetime.fromisoformat(data["expires_at"])
        assert exp == current_end + timedelta(days=30)        # 10 days left + 30 = 40 from now
        assert data["started_at"] == _iso(now - timedelta(days=20))  # original start kept

    def test_year_extension_adds_365_days(self):
        now = datetime.now(timezone.utc)
        current_end = now + timedelta(days=100)
        data = self._run({"status": "active", "started_at": _iso(now), "expires_at": _iso(current_end)},
                         plan="premium", duration=365)
        assert datetime.fromisoformat(data["expires_at"]) == current_end + timedelta(days=365)

    def test_expired_subscription_restarts_from_now(self):
        now = datetime.now(timezone.utc)
        data = self._run({"status": "active", "started_at": _iso(now - timedelta(days=60)),
                          "expires_at": _iso(now - timedelta(days=5))}, duration=30)
        exp = datetime.fromisoformat(data["expires_at"])
        assert abs((exp - (now + timedelta(days=30))).total_seconds()) < 5

    def test_cancelled_subscription_restarts_from_now(self):
        now = datetime.now(timezone.utc)
        data = self._run({"status": "cancelled", "started_at": _iso(now),
                          "expires_at": _iso(now + timedelta(days=20))}, duration=30)
        exp = datetime.fromisoformat(data["expires_at"])
        assert abs((exp - (now + timedelta(days=30))).total_seconds()) < 5


class TestDaysAndMessage:
    def test_fresh_30_days_reads_30(self):
        from app.services.subscription_service import _days_left
        now = datetime.now(timezone.utc)
        assert _days_left(now + timedelta(days=30), now) == 30

    def test_never_negative(self):
        from app.services.subscription_service import _days_left
        now = datetime.now(timezone.utc)
        assert _days_left(now - timedelta(days=3), now) == 0

    @pytest.mark.parametrize("days,label", [(30, "1 month"), (365, "1 year")])
    def test_already_active_message(self, days, label):
        from app.services.subscription_service import already_active_message
        end = datetime(2026, 10, 1, tzinfo=timezone.utc)
        msg = already_active_message(end, days)
        assert "01 Oct 2026" in msg and label in msg
        assert (end + timedelta(days=days)).strftime("%d %b %Y") in msg


# ── create-order guard ───────────────────────────────────────────────────────

class TestCreateOrder:
    def _call(self, expiry, extend, plan="basic", duration=30):
        from app.routers import payments
        from app.schemas.payment import SubscriptionOrderRequest
        owner = {"id": "owner-001", "role": "owner"}
        with patch.object(payments, "_require_shop_owner"), \
             patch.object(payments.subscription_service, "active_expiry", return_value=expiry), \
             patch.object(payments.razorpay_service, "create_order",
                          return_value={"order_id": "o1", "amount": 100, "currency": "INR", "key_id": "k"}), \
             patch.object(payments.payment_transaction_service, "record_order") as rec:
            res = payments.create_subscription_order(
                "shop-001", SubscriptionOrderRequest(plan=plan, duration_days=duration, extend=extend), owner)
        return res, rec

    def test_active_without_extend_returns_409_with_date(self):
        end = datetime.now(timezone.utc) + timedelta(days=12)
        with pytest.raises(HTTPException) as e:
            self._call(end, extend=False)
        assert e.value.status_code == 409
        assert end.strftime("%d %b %Y") in e.value.detail

    def test_active_with_extend_creates_order(self):
        end = datetime.now(timezone.utc) + timedelta(days=12)
        res, rec = self._call(end, extend=True, plan="premium", duration=365)
        assert res["order_id"] == "o1"
        assert rec.call_args[0][5] == {"plan": "premium", "duration_days": 365}

    def test_no_subscription_creates_order(self):
        res, _ = self._call(None, extend=False)
        assert res["order_id"] == "o1"

    def test_invalid_plan_rejected_before_payment(self):
        with pytest.raises(HTTPException) as e:
            self._call(None, extend=False, plan="gold")
        assert e.value.status_code == 400


# ── verify: binding + replay ─────────────────────────────────────────────────

class TestVerify:
    OWNER = {"id": "owner-001", "role": "owner"}

    def _row(self, **kw):
        row = {"owner_id": "owner-001", "shop_id": "shop-001", "purpose": "subscription",
               "status": "created", "metadata": {"plan": "basic", "duration_days": 30}}
        row.update(kw)
        return row

    def _verify(self, row, sig_ok=True, claimed=True):
        from app.routers import payments
        from app.services import payment_transaction_service as pts
        with patch.object(pts, "execute_one", return_value=MagicMock(data=row)), \
             patch.object(payments.razorpay_service, "verify_signature", return_value=sig_ok), \
             patch.object(pts, "claim_paid", return_value=claimed) as claim, \
             patch.object(pts, "mark_failed") as failed, \
             patch.object(pts, "release_claim") as release, \
             patch.object(payments.subscription_service, "create_or_renew_subscription",
                          return_value={"has_active_subscription": True, "subscription": None}) as activate:
            try:
                res = payments.verify_subscription_payment("shop-001", _body(), self.OWNER)
            except HTTPException as e:
                return e, claim, failed, release, activate
        return res, claim, failed, release, activate

    def test_happy_path_uses_stored_plan_not_request(self):
        res, claim, _, _, activate = self._verify(self._row())
        assert res["has_active_subscription"] is True
        claim.assert_called_once()
        data = activate.call_args[0][2]
        assert (data.plan, data.duration_days) == ("basic", 30)

    def test_other_owners_order_rejected(self):
        e, claim, _, _, activate = self._verify(self._row(owner_id="someone-else"))
        assert e.status_code == 403
        activate.assert_not_called()
        claim.assert_not_called()

    def test_order_for_other_shop_rejected(self):
        e, *_ = self._verify(self._row(shop_id="other-shop"))
        assert e.status_code == 403

    def test_promotion_order_cannot_activate_subscription(self):
        e, *_ = self._verify(self._row(purpose="promotion"))
        assert e.status_code == 403

    def test_already_paid_order_rejected(self):
        e, _, _, _, activate = self._verify(self._row(status="paid"))
        assert e.status_code == 409
        activate.assert_not_called()

    def test_lost_race_on_claim_rejected(self):
        e, _, _, _, activate = self._verify(self._row(), claimed=False)
        assert e.status_code == 409
        activate.assert_not_called()

    def test_bad_signature_rejected_and_not_activated(self):
        e, claim, failed, _, activate = self._verify(self._row(), sig_ok=False)
        assert e.status_code == 400
        failed.assert_called_once()
        claim.assert_not_called()
        activate.assert_not_called()

    def test_unknown_order_404(self):
        e, *_ = self._verify(None)
        assert e.status_code == 404

    def test_activation_failure_releases_claim(self):
        from app.routers import payments
        from app.services import payment_transaction_service as pts
        with patch.object(pts, "execute_one", return_value=MagicMock(data=self._row())), \
             patch.object(payments.razorpay_service, "verify_signature", return_value=True), \
             patch.object(pts, "claim_paid", return_value=True), \
             patch.object(pts, "release_claim") as release, \
             patch.object(payments.subscription_service, "create_or_renew_subscription",
                          side_effect=RuntimeError("db down")):
            with pytest.raises(HTTPException) as e:
                payments.verify_subscription_payment("shop-001", _body(), self.OWNER)
        assert e.value.status_code == 500
        release.assert_called_once_with("order_1")


# ── free-bypass endpoints ────────────────────────────────────────────────────

class TestNoFreeFeatured:
    def test_free_featured_promotion_blocked(self):
        from app.schemas.promotion import PromotionCreate
        from app.services import promotion_service
        with pytest.raises(HTTPException) as e:
            promotion_service.create_promotion(
                "shop-001", "owner-001",
                PromotionCreate(title="Featured Promotion", description="x", valid_until="2030-01-01T00:00:00Z"))
        assert e.value.status_code == 403


# ── image upload size cap ────────────────────────────────────────────────────

class TestImageUploadLimit:
    def _post(self, size):
        import io
        from fastapi.testclient import TestClient
        from app.main import app
        from app.dependencies import get_current_owner
        app.dependency_overrides[get_current_owner] = lambda: {"id": "owner-001", "role": "owner"}
        try:
            with patch("app.routers.shops.shop_service.upload_shop_image",
                       return_value={"url": "u", "images": ["u"]}) as up:
                r = TestClient(app).post(
                    "/shops/shop-001/images",
                    files={"file": ("a.jpg", io.BytesIO(b"x" * size), "image/jpeg")})
            return r, up
        finally:
            app.dependency_overrides.pop(get_current_owner, None)

    def test_half_megabyte_accepted(self):
        r, up = self._post(512 * 1024)
        assert r.status_code == 201
        up.assert_called_once()

    def test_over_half_megabyte_rejected_with_message(self):
        r, up = self._post(512 * 1024 + 1)
        assert r.status_code == 413
        assert "0.5 MB" in r.json()["detail"]
        up.assert_not_called()

    def test_wrong_type_rejected(self):
        import io
        from fastapi.testclient import TestClient
        from app.main import app
        from app.dependencies import get_current_owner
        app.dependency_overrides[get_current_owner] = lambda: {"id": "owner-001", "role": "owner"}
        try:
            r = TestClient(app).post("/shops/shop-001/images",
                                     files={"file": ("a.exe", io.BytesIO(b"x"), "application/octet-stream")})
        finally:
            app.dependency_overrides.pop(get_current_owner, None)
        assert r.status_code == 415


class TestCorruptOrderMetadata:
    def test_missing_metadata_releases_claim_instead_of_locking_payment(self):
        from app.routers import payments
        from app.services import payment_transaction_service as pts
        row = {"owner_id": "owner-001", "shop_id": "shop-001", "purpose": "subscription",
               "status": "created", "metadata": None}
        with patch.object(pts, "execute_one", return_value=MagicMock(data=row)), \
             patch.object(payments.razorpay_service, "verify_signature", return_value=True), \
             patch.object(pts, "claim_paid", return_value=True), \
             patch.object(pts, "release_claim") as release:
            with pytest.raises(HTTPException):
                payments.verify_subscription_payment(
                    "shop-001", _body(), {"id": "owner-001", "role": "owner"})
        release.assert_called_once_with("order_1")


class TestRazorpayReceipt:
    def test_receipt_fits_razorpays_40_char_limit(self):
        import uuid
        from app.routers.payments import _receipt
        shop_id = str(uuid.uuid4())
        for prefix in ("sub", "promo"):
            r = _receipt(prefix, shop_id)
            assert len(r) <= 40, r
            assert r.startswith(prefix + "_")
        assert _receipt("sub", shop_id) != _receipt("sub", shop_id)   # unique per order
