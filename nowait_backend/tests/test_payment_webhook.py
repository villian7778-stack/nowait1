"""POST /payments/webhook — Razorpay telling the server about payments."""
import hashlib
import hmac
import json
from unittest.mock import patch

import pytest
from fastapi.testclient import TestClient

SECRET = "whsec_test_123"


@pytest.fixture
def client():
    from app.main import app
    return TestClient(app, raise_server_exceptions=False)


def _sign(body: bytes, secret: str = SECRET) -> str:
    return hmac.new(secret.encode(), body, hashlib.sha256).hexdigest()


def _captured(order_id="order_1", payment_id="pay_1", amount=4900):
    return {"event": "payment.captured", "payload": {"payment": {"entity": {
        "id": payment_id, "order_id": order_id, "amount": amount, "currency": "INR", "status": "captured"}}}}


def _order_paid(order_id="order_1"):
    return {"event": "order.paid", "payload": {
        "order": {"entity": {"id": order_id, "status": "paid"}},
        "payment": {"entity": {"id": "pay_1", "order_id": order_id, "amount": 4900}}}}


TXN = {"razorpay_order_id": "order_1", "shop_id": "shop-1", "owner_id": "owner-1", "purpose": "subscription",
       "amount_paise": 4900, "status": "created", "metadata": {"plan": "basic", "duration_days": 30}}


@pytest.fixture
def world():
    """Patches everything the webhook touches and returns the mocks."""
    from app.routers import payments
    with patch.object(payments.settings, "RAZORPAY_WEBHOOK_SECRET", SECRET), \
         patch.object(payments, "payment_transaction_service") as pts, \
         patch.object(payments, "razorpay_service") as rzp, \
         patch.object(payments, "subscription_service") as subs, \
         patch.object(payments, "logger") as log:
        from app.services import razorpay_service as real
        rzp.verify_webhook_signature.side_effect = real.verify_webhook_signature
        pts.get_order.return_value = dict(TXN)
        pts.claim_paid.return_value = True
        rzp.captured_payment_for_order.return_value = {"id": "pay_1", "amount": 4900, "currency": "INR"}
        # verify_webhook_signature reads the secret from the real service's settings
        with patch.object(real.settings, "RAZORPAY_WEBHOOK_SECRET", SECRET):
            yield type("W", (), {"pts": pts, "rzp": rzp, "subs": subs, "log": log})


def _post(client, event, secret=SECRET, raw=None, headers=None):
    body = raw if raw is not None else json.dumps(event).encode()
    h = {"X-Razorpay-Signature": _sign(body, secret), "Content-Type": "application/json"}
    h.update(headers or {})
    return client.post("/payments/webhook", content=body, headers=h)


class TestAuthentication:
    def test_wrong_signature_is_rejected_and_does_nothing(self, client, world):
        r = _post(client, _captured(), secret="not-the-secret")
        assert r.status_code == 400
        world.subs.create_or_renew_subscription.assert_not_called()
        world.pts.claim_paid.assert_not_called()

    def test_missing_signature_is_rejected(self, client, world):
        r = client.post("/payments/webhook", content=json.dumps(_captured()).encode())
        assert r.status_code == 400
        world.pts.claim_paid.assert_not_called()

    def test_a_body_changed_after_signing_is_rejected(self, client, world):
        body = json.dumps(_captured(amount=4900)).encode()
        sig = _sign(body)
        r = client.post("/payments/webhook", content=body.replace(b"4900", b"100"), headers={"X-Razorpay-Signature": sig})
        assert r.status_code == 400

    def test_not_configured_means_503_not_open_door(self, client, world):
        from app.routers import payments
        with patch.object(payments.settings, "RAZORPAY_WEBHOOK_SECRET", ""):
            r = client.post("/payments/webhook", content=b"{}", headers={"X-Razorpay-Signature": _sign(b"{}", "")})
        assert r.status_code == 503
        world.pts.claim_paid.assert_not_called()

    def test_oversized_body_is_refused(self, client, world):
        r = _post(client, None, raw=b"{" + b" " * (70 * 1024) + b"}")
        assert r.status_code == 413

    def test_signed_but_not_json_is_a_400(self, client, world):
        assert _post(client, None, raw=b"not json").status_code == 400
        assert _post(client, None, raw=b"[1,2]").status_code == 400


class TestActivation:
    def test_payment_captured_activates_the_order(self, client, world):
        r = _post(client, _captured())
        assert r.status_code == 200 and r.json() == {"received": True}
        world.pts.claim_paid.assert_called_once_with("order_1", "pay_1", None)
        world.subs.create_or_renew_subscription.assert_called_once()

    def test_order_paid_event_works_too(self, client, world):
        assert _post(client, _order_paid()).status_code == 200
        world.subs.create_or_renew_subscription.assert_called_once()

    def test_we_confirm_with_razorpay_instead_of_trusting_the_payload(self, client, world):
        # The webhook says "captured" but Razorpay's own API says nothing was captured.
        world.rzp.captured_payment_for_order.return_value = None
        assert _post(client, _captured()).status_code == 200
        world.rzp.captured_payment_for_order.assert_called_once_with("order_1")
        world.subs.create_or_renew_subscription.assert_not_called()

    def test_already_activated_order_is_left_alone(self, client, world):
        world.pts.get_order.return_value = {**TXN, "status": "paid"}
        assert _post(client, _captured()).status_code == 200
        world.subs.create_or_renew_subscription.assert_not_called()
        world.pts.claim_paid.assert_not_called()

    def test_retries_and_duplicates_activate_only_once(self, client, world):
        world.pts.claim_paid.side_effect = [True, False]   # the second delivery loses the claim
        _post(client, _captured())
        _post(client, _captured())
        assert world.subs.create_or_renew_subscription.call_count == 1

    def test_underpayment_is_not_activated(self, client, world):
        world.rzp.captured_payment_for_order.return_value = {"id": "pay_1", "amount": 100, "currency": "INR"}
        assert _post(client, _captured(amount=100)).status_code == 200
        world.pts.claim_paid.assert_not_called()
        world.subs.create_or_renew_subscription.assert_not_called()

    def test_unknown_order_is_ignored_but_acknowledged(self, client, world):
        world.pts.get_order.return_value = None
        assert _post(client, _captured(order_id="order_unknown")).status_code == 200
        world.subs.create_or_renew_subscription.assert_not_called()

    def test_failed_activation_releases_the_claim_for_a_retry(self, client, world):
        world.subs.create_or_renew_subscription.side_effect = RuntimeError("db down")
        assert _post(client, _captured()).status_code == 200
        world.pts.release_claim.assert_called_once_with("order_1")

    def test_a_promotion_order_activates_a_promotion(self, client, world):
        world.pts.get_order.return_value = {
            **TXN, "purpose": "promotion", "amount_paise": 7000,
            "metadata": {"title": "Featured Promotion", "description": "d", "days": 7}}
        world.rzp.captured_payment_for_order.return_value = {"id": "pay_1", "amount": 7000, "currency": "INR"}
        with patch("app.routers.payments.promotion_service") as promo:
            assert _post(client, _captured(amount=7000)).status_code == 200
        promo.create_promotion.assert_called_once()


class TestFailureLogging:
    def test_payment_failed_logs_razorpays_reason_and_changes_nothing(self, client, world):
        event = {"event": "payment.failed", "payload": {"payment": {"entity": {
            "id": "pay_9", "order_id": "order_1", "method": "upi",
            "error_code": "BAD_REQUEST_ERROR", "error_reason": "payment_failed", "error_source": "customer",
            "error_step": "payment_authentication", "error_description": "Payment failed\nINFO: forged line"}}}}
        assert _post(client, event).status_code == 200
        logged = " ".join(str(a) for a in world.log.error.call_args[0][1:])
        assert "BAD_REQUEST_ERROR" in logged and "payment_failed" in logged and "upi" in logged
        assert "\n" not in logged                       # cannot forge log lines
        world.pts.mark_failed.assert_not_called()       # a later attempt on the same order may still succeed
        world.subs.create_or_renew_subscription.assert_not_called()

    def test_unrelated_events_are_acknowledged(self, client, world):
        assert _post(client, {"event": "refund.created", "payload": {}}).status_code == 200
