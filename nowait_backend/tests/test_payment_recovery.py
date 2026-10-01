from unittest.mock import MagicMock, patch

import httpx
import pytest

from app.database import _RetryingTransport


class TestRetryingTransport:
    def test_retries_dropped_connection_then_succeeds(self):
        calls = []

        def fake(self, request):
            calls.append(1)
            if len(calls) == 1:
                raise httpx.RemoteProtocolError("Server disconnected")
            return httpx.Response(200, request=request)

        with patch.object(httpx.HTTPTransport, "handle_request", fake):
            resp = _RetryingTransport().handle_request(httpx.Request("GET", "https://x.supabase.co/rest/v1/shops"))
        assert resp.status_code == 200
        assert len(calls) == 2

    def test_gives_up_after_three_attempts(self):
        def fake(self, request):
            raise httpx.RemoteProtocolError("Server disconnected")

        with patch.object(httpx.HTTPTransport, "handle_request", fake):
            with pytest.raises(httpx.RemoteProtocolError):
                _RetryingTransport().handle_request(httpx.Request("GET", "https://x.supabase.co/"))


TXN = {
    "razorpay_order_id": "order_1", "shop_id": "shop-1", "owner_id": "owner-1",
    "purpose": "subscription", "amount_paise": 100, "status": "created",
    "metadata": {"plan": "basic", "duration_days": 30},
}


@patch("app.routers.payments._require_shop_owner")
@patch("app.routers.payments.subscription_service")
@patch("app.routers.payments.payment_transaction_service")
@patch("app.routers.payments.razorpay_service")
class TestReconcile:
    def _run(self):
        from app.routers.payments import reconcile_payments
        return reconcile_payments("shop-1", {"id": "owner-1"})

    def test_activates_captured_order(self, rzp, pts, subs, _owner):
        pts.unfinished_orders.return_value = [TXN]
        rzp.captured_payment_for_order.return_value = {"id": "pay_1", "amount": 100, "status": "captured"}
        pts.claim_paid.return_value = True
        out = self._run()
        assert out["activated"] == [{"order_id": "order_1", "payment_id": "pay_1", "purpose": "subscription"}]
        subs.create_or_renew_subscription.assert_called_once()
        assert subs.create_or_renew_subscription.call_args.args[:2] == ("shop-1", "owner-1")

    def test_skips_unpaid_order(self, rzp, pts, subs, _owner):
        pts.unfinished_orders.return_value = [TXN]
        rzp.captured_payment_for_order.return_value = None
        assert self._run()["activated"] == []
        pts.claim_paid.assert_not_called()

    def test_skips_amount_mismatch(self, rzp, pts, subs, _owner):
        pts.unfinished_orders.return_value = [TXN]
        rzp.captured_payment_for_order.return_value = {"id": "pay_1", "amount": 50, "status": "captured"}
        assert self._run()["activated"] == []
        pts.claim_paid.assert_not_called()

    def test_releases_claim_when_activation_fails(self, rzp, pts, subs, _owner):
        pts.unfinished_orders.return_value = [TXN]
        rzp.captured_payment_for_order.return_value = {"id": "pay_1", "amount": 100, "status": "captured"}
        pts.claim_paid.return_value = True
        subs.create_or_renew_subscription.side_effect = RuntimeError("db down")
        assert self._run()["activated"] == []
        pts.release_claim.assert_called_once_with("order_1")


@patch("app.routers.payments.razorpay_service")
@patch("app.routers.payments.payment_transaction_service")
class TestOrderStatus:
    def _run(self, owner="owner-1"):
        from app.routers.payments import order_status
        return order_status("order_1", {"id": owner})

    def test_reports_paid(self, pts, rzp):
        pts.owns_order.return_value = True
        rzp.order_is_paid.return_value = True
        assert self._run() == {"paid": True}

    def test_hides_other_owners_orders(self, pts, rzp):
        from fastapi import HTTPException
        pts.owns_order.return_value = False
        with pytest.raises(HTTPException) as e:
            self._run()
        assert e.value.status_code == 404
        rzp.order_is_paid.assert_not_called()
