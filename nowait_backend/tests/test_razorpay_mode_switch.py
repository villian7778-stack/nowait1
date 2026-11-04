"""Both Razorpay key sets on the server, RAZORPAY_LIVE picks one (test = fake money)."""
import hashlib
import hmac
import json
from unittest.mock import MagicMock, patch

import pytest
from fastapi import HTTPException
from fastapi.testclient import TestClient

from app.config import settings
from app.services import razorpay_service

BOTH = dict(
    RAZORPAY_TEST_KEY_ID="rzp_test_T", RAZORPAY_TEST_KEY_SECRET="test-secret", RAZORPAY_TEST_WEBHOOK_SECRET="test-wh",
    RAZORPAY_LIVE_KEY_ID="rzp_live_L", RAZORPAY_LIVE_KEY_SECRET="live-secret", RAZORPAY_LIVE_WEBHOOK_SECRET="live-wh",
)


def _sign(body: bytes, secret: str) -> str:
    return hmac.new(secret.encode(), body, hashlib.sha256).hexdigest()


@pytest.fixture
def client():
    from app.main import app
    return TestClient(app, raise_server_exceptions=False)


@pytest.fixture(autouse=True)
def _fresh_client():
    with patch.object(razorpay_service, "_client", None), patch.object(razorpay_service, "_client_key", None):
        yield


@pytest.mark.parametrize("live, key, secret, wh", [(False, "rzp_test_T", "test-secret", "test-wh"),
                                                   (True, "rzp_live_L", "live-secret", "live-wh")])
def test_the_switch_picks_the_key_set(live, key, secret, wh):
    with patch.multiple(settings, RAZORPAY_LIVE=live, **BOTH):
        c = razorpay_service.credentials()
        assert (c.mode, c.key_id, c.key_secret, c.webhook_secret) == ("live" if live else "test", key, secret, wh)
        with patch.object(razorpay_service.razorpay, "Client") as Client:
            Client.return_value.order.create.return_value = {"id": "order_1", "amount": 4900, "currency": "INR"}
            out = razorpay_service.create_order(4900, "r1")
        Client.assert_called_once_with(auth=(key, secret))
        assert out["key_id"] == key  # what the app opens checkout with
        # A checkout signature is checked with the same mode's secret.
        good = hmac.new(secret.encode(), b"order_1|pay_1", hashlib.sha256).hexdigest()
        assert razorpay_service.verify_signature("order_1", "pay_1", good)


def test_flipping_the_switch_changes_keys_without_reusing_the_old_client():
    with patch.object(razorpay_service.razorpay, "Client") as Client:
        with patch.multiple(settings, RAZORPAY_LIVE=False, **BOTH):
            razorpay_service._get_client()
        with patch.multiple(settings, RAZORPAY_LIVE=True, **BOTH):
            razorpay_service._get_client()
    assert [c.kwargs["auth"][0] for c in Client.call_args_list] == ["rzp_test_T", "rzp_live_L"]


@pytest.mark.parametrize("live, slot", [(False, dict(RAZORPAY_TEST_KEY_ID="rzp_live_oops", RAZORPAY_TEST_KEY_SECRET="x")),
                                        (True, dict(RAZORPAY_LIVE_KEY_ID="rzp_test_oops", RAZORPAY_LIVE_KEY_SECRET="x"))])
def test_a_key_in_the_wrong_slot_is_refused(live, slot):
    """A live key pasted into the test slot must never take real money, and a test key in the
    live slot would silently take nothing - both are refused."""
    with patch.multiple(settings, RAZORPAY_LIVE=live, **slot), \
         patch.object(razorpay_service.razorpay, "Client") as Client:
        with pytest.raises(HTTPException) as e:
            razorpay_service.create_order(4900, "r1")
    assert e.value.status_code == 503
    Client.assert_not_called()


def test_older_single_key_setup_still_works_and_stays_locked():
    old = dict(RAZORPAY_KEY_ID="rzp_live_old", RAZORPAY_KEY_SECRET="s")
    with patch.multiple(settings, RAZORPAY_ALLOW_LIVE=False, **old), \
         patch.object(razorpay_service.razorpay, "Client") as Client:
        with pytest.raises(HTTPException):
            razorpay_service._get_client()
        Client.assert_not_called()
    with patch.multiple(settings, RAZORPAY_ALLOW_LIVE=True, **old), \
         patch.object(razorpay_service.razorpay, "Client") as Client:
        razorpay_service._get_client()
        Client.assert_called_once_with(auth=("rzp_live_old", "s"))


class TestWebhookBothModes:
    """Both Razorpay webhooks (test and live) may point at the same URL."""

    def _post(self, client, secret):
        body = json.dumps({"event": "order.paid", "payload": {
            "order": {"entity": {"id": "order_9", "status": "paid"}}}}).encode()
        return client.post("/payments/webhook", content=body, headers={"X-Razorpay-Signature": _sign(body, secret)})

    @pytest.mark.parametrize("live, active, other", [(True, "live-wh", "test-wh"), (False, "test-wh", "live-wh")])
    def test_other_mode_is_acknowledged_and_ignored(self, client, live, active, other):
        from app.routers import payments
        with patch.multiple(settings, RAZORPAY_LIVE=live, **BOTH), \
             patch.object(payments, "_handle_webhook_event", return_value={"received": True}) as handle:
            ignored = self._post(client, other)
            handled = self._post(client, active)
            forged = self._post(client, "not-a-secret")
        assert ignored.status_code == 200 and ignored.json().get("ignored") == "other mode"
        assert handled.status_code == 200
        assert forged.status_code == 400
        assert handle.call_count == 1  # only the active mode's event was processed
