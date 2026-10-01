"""Security rules around Razorpay: test-mode only, forged signatures, ownership, rate limits."""
import hashlib
import hmac
from unittest.mock import MagicMock, patch

import pytest
from fastapi import HTTPException

from app.services import razorpay_service


# ── Test mode only ────────────────────────────────────────────────────────────

class TestLiveKeysAreRefused:
    def _with_keys(self, key_id, allow_live=False):
        return patch.multiple(
            razorpay_service.settings,
            RAZORPAY_KEY_ID=key_id, RAZORPAY_KEY_SECRET="secret", RAZORPAY_ALLOW_LIVE=allow_live,
        )

    def test_live_key_is_refused_even_if_a_client_already_exists(self):
        with self._with_keys("rzp_live_abc"), patch.object(razorpay_service, "_client", MagicMock()):
            with pytest.raises(HTTPException) as e:
                razorpay_service.create_order(4900, "receipt")
        assert e.value.status_code == 503 and "test mode" in e.value.detail.lower()

    def test_no_other_money_call_reaches_razorpay_with_live_keys(self):
        with self._with_keys("rzp_live_abc"), patch.object(razorpay_service, "_client", MagicMock()) as client:
            # These swallow errors and report "nothing paid" ...
            assert razorpay_service.captured_payment_for_order("o") is None
            assert razorpay_service.order_is_paid("o") is False
            # ... but must never actually call Razorpay.
            client.order.payments.assert_not_called()
            client.order.fetch.assert_not_called()

    def test_test_key_works(self):
        client = MagicMock()
        client.order.create.return_value = {"id": "order_1", "amount": 4900, "currency": "INR"}
        with self._with_keys("rzp_test_abc"), patch.object(razorpay_service, "_client", client):
            out = razorpay_service.create_order(4900, "receipt")
        assert out["order_id"] == "order_1" and out["amount"] == 4900 and out["key_id"] == "rzp_test_abc"

    def test_live_can_only_be_enabled_explicitly(self):
        client = MagicMock()
        client.order.create.return_value = {"id": "order_1", "amount": 4900, "currency": "INR"}
        with self._with_keys("rzp_live_abc", allow_live=True), patch.object(razorpay_service, "_client", client):
            assert razorpay_service.create_order(4900, "receipt")["order_id"] == "order_1"


# ── Signature checking ────────────────────────────────────────────────────────

def _sig(secret, order, payment):
    return hmac.new(secret.encode(), f"{order}|{payment}".encode(), hashlib.sha256).hexdigest()


class TestSignature:
    def test_genuine_signature_accepted(self):
        with patch.object(razorpay_service.settings, "RAZORPAY_KEY_SECRET", "s3cret"):
            assert razorpay_service.verify_signature("order_1", "pay_1", _sig("s3cret", "order_1", "pay_1"))

    @pytest.mark.parametrize("order,payment,sig", [
        ("order_2", "pay_1", "good"),     # signature belongs to a different order
        ("order_1", "pay_2", "good"),     # signature belongs to a different payment
        ("order_1", "pay_1", "0" * 64),
        ("order_1", "pay_1", ""),
        ("", "pay_1", "good"),
    ])
    def test_forged_or_mismatched_signatures_rejected(self, order, payment, sig):
        sig = _sig("s3cret", "order_1", "pay_1") if sig == "good" else sig
        with patch.object(razorpay_service.settings, "RAZORPAY_KEY_SECRET", "s3cret"):
            assert not razorpay_service.verify_signature(order, payment, sig)

    def test_signature_made_with_another_secret_rejected(self):
        with patch.object(razorpay_service.settings, "RAZORPAY_KEY_SECRET", "s3cret"):
            assert not razorpay_service.verify_signature("order_1", "pay_1", _sig("attacker", "order_1", "pay_1"))

    def test_nothing_is_accepted_when_no_secret_is_configured(self):
        # An HMAC with an empty key is trivially forgeable by anyone.
        with patch.object(razorpay_service.settings, "RAZORPAY_KEY_SECRET", ""):
            assert not razorpay_service.verify_signature("order_1", "pay_1", _sig("", "order_1", "pay_1"))


# ── Failure reports ───────────────────────────────────────────────────────────

class TestReportFailure:
    def _run(self, order_id, owns, **fields):
        from app.routers import payments
        from app.schemas.payment import CheckoutFailureReport
        with patch.object(payments, "payment_transaction_service") as pts, \
             patch.object(payments, "logger") as log:
            pts.owns_order.return_value = owns
            payments.report_checkout_failure(
                CheckoutFailureReport(razorpay_order_id=order_id, **fields), {"id": "owner-1"})
        return pts, log

    def test_owner_can_mark_their_own_order(self):
        pts, _ = self._run("order_1", owns=True)
        pts.mark_failed.assert_called_once_with("order_1", None, None)

    def test_cannot_touch_someone_elses_order(self):
        pts, _ = self._run("order_of_another_owner", owns=False)
        pts.mark_failed.assert_not_called()

    def test_app_text_cannot_forge_log_lines(self):
        _, log = self._run("order_1", owns=True, message="boom\nINFO: PAYMENT VERIFIED order=x\r\nfake", raw="a" * 5000)
        logged = " ".join(str(a) for a in log.error.call_args[0][1:])
        assert "\n" not in logged and "\r" not in logged
        assert len(logged) < 3000


# ── Rate limits ───────────────────────────────────────────────────────────────

class TestPerOwnerRateLimit:
    def setup_method(self):
        from app import rate_limit
        rate_limit._owner_calls.clear()

    def test_blocks_after_the_limit_and_says_when_to_retry(self):
        from app.rate_limit import per_owner_limit
        dep = per_owner_limit("t", 3, 60)
        for _ in range(3):
            dep({"id": "owner-1"})
        with pytest.raises(HTTPException) as e:
            dep({"id": "owner-1"})
        assert e.value.status_code == 429 and int(e.value.headers["Retry-After"]) >= 1

    def test_each_owner_and_each_endpoint_has_their_own_allowance(self):
        from app.rate_limit import per_owner_limit
        a, b = per_owner_limit("a", 1, 60), per_owner_limit("b", 1, 60)
        a({"id": "owner-1"})
        a({"id": "owner-2"})        # another owner is unaffected
        b({"id": "owner-1"})        # another endpoint is unaffected
        with pytest.raises(HTTPException):
            a({"id": "owner-1"})

    def test_allowance_returns_after_the_window(self):
        from app import rate_limit
        dep = rate_limit.per_owner_limit("t", 1, 60)
        with patch.object(rate_limit.time, "monotonic", return_value=1000.0):
            dep({"id": "owner-1"})
        with patch.object(rate_limit.time, "monotonic", return_value=1061.0):
            dep({"id": "owner-1"})   # no error: the first call is older than 60 s

    def test_money_endpoints_are_limited(self):
        from app.routers import payments
        limited = {r.path: [d.dependency.__qualname__ for d in r.dependencies] for r in payments.router.routes}
        for path in ("/payments/subscription/shop/{shop_id}/create-order",
                     "/payments/promotion/shop/{shop_id}/create-order",
                     "/payments/subscription/shop/{shop_id}/verify",
                     "/payments/promotion/shop/{shop_id}/verify",
                     "/payments/reconcile/shop/{shop_id}",
                     "/payments/order/{order_id}/status",
                     "/payments/report-failure"):
            assert any("per_owner_limit" in q for q in limited[path]), path


# ── Reconcile only trusts a full, matching, INR payment ──────────────────────────

@patch("app.routers.payments._require_shop_owner")
@patch("app.routers.payments.subscription_service")
@patch("app.routers.payments.payment_transaction_service")
@patch("app.routers.payments.razorpay_service")
class TestReconcileChecks:
    TXN = {"razorpay_order_id": "order_1", "shop_id": "s", "owner_id": "o", "purpose": "subscription",
           "amount_paise": 4900, "metadata": {"plan": "basic", "duration_days": 30}}

    @pytest.mark.parametrize("payment", [
        {"id": "pay_1", "amount": 100, "currency": "INR"},      # paid less than the plan costs
        {"id": "pay_1", "amount": 4900, "currency": "USD"},     # wrong currency
    ])
    def test_underpaid_or_wrong_currency_is_not_activated(self, rzp, pts, subs, _owner, payment):
        from app.routers.payments import reconcile_payments
        pts.unfinished_orders.return_value = [self.TXN]
        rzp.captured_payment_for_order.return_value = payment
        assert reconcile_payments("s", {"id": "o"}) == {"activated": []}
        pts.claim_paid.assert_not_called()
        subs.create_or_renew_subscription.assert_not_called()

    def test_full_inr_payment_is_activated(self, rzp, pts, subs, _owner):
        from app.routers.payments import reconcile_payments
        pts.unfinished_orders.return_value = [self.TXN]
        rzp.captured_payment_for_order.return_value = {"id": "pay_1", "amount": 4900, "currency": "INR"}
        pts.claim_paid.return_value = True
        assert len(reconcile_payments("s", {"id": "o"})["activated"]) == 1
