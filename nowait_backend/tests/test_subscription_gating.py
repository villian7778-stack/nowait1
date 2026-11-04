"""Schemes and Featured Promotions need an active subscription / free trial - an unsubscribed shop
is hidden from customers, so they would reach nobody (and promotion payments are not refunded)."""
from datetime import datetime, timedelta, timezone
from unittest.mock import MagicMock, patch

import pytest
from fastapi import HTTPException

from app.schemas.promotion import PromotionCreate, PromotionUpdate
from app.services import promotion_service
from tests.conftest import make_chain, ok

NOW = datetime.now(timezone.utc)


def _sub_ends_in(days):
    return patch.object(promotion_service.subscription_service, "active_expiry",
                        return_value=None if days is None else NOW + timedelta(days=days))


def _running_promo_ends_in(days):
    return patch.object(promotion_service, "_running_featured_end",
                        return_value=None if days is None else NOW + timedelta(days=days))


class TestPromotionNeedsSubscription:
    def test_no_subscription_is_refused(self):
        with _sub_ends_in(None), _running_promo_ends_in(None), pytest.raises(HTTPException) as e:
            promotion_service.check_promotion_fits_subscription("s1", 3)
        assert e.value.status_code == 403
        assert "subscription" in e.value.detail.lower()

    @pytest.mark.parametrize("days", [3, 7, 15])
    def test_fits_inside_the_subscription(self, days):
        with _sub_ends_in(30), _running_promo_ends_in(None):
            promotion_service.check_promotion_fits_subscription("s1", days)  # no error

    def test_longer_than_the_subscription_suggests_what_fits(self):
        with _sub_ends_in(10), _running_promo_ends_in(None), pytest.raises(HTTPException) as e:
            promotion_service.check_promotion_fits_subscription("s1", 15)
        assert e.value.status_code == 409
        assert "7 days or fewer" in e.value.detail

    def test_message_says_what_was_asked_and_when_the_subscription_ends(self):
        with _sub_ends_in(3), _running_promo_ends_in(None), pytest.raises(HTTPException) as e:
            promotion_service.check_promotion_fits_subscription("s1", 7)
        assert e.value.detail.startswith("You're trying to get a 7-day promotion, but your subscription ends in 3 days")
        assert "choose 3 days or fewer" in e.value.detail

    def test_nothing_fits_asks_to_extend_first(self):
        with _sub_ends_in(2), _running_promo_ends_in(None), pytest.raises(HTTPException) as e:
            promotion_service.check_promotion_fits_subscription("s1", 3)
        assert e.value.status_code == 409
        assert "Extend your subscription first" in e.value.detail

    def test_an_extension_counts_from_the_running_promotions_end(self):
        # Running promotion ends in 20 days, subscription in 25: +7 would end on day 27.
        with _sub_ends_in(25), _running_promo_ends_in(20):
            promotion_service.check_promotion_fits_subscription("s1", 3)
            with pytest.raises(HTTPException) as e:
                promotion_service.check_promotion_fits_subscription("s1", 7)
        assert "3 days or fewer" in e.value.detail


class TestPaymentOrder:
    def test_no_razorpay_order_without_a_subscription(self):
        from app.routers import payments
        from app.schemas.payment import PromotionOrderRequest
        with patch.object(payments, "_require_shop_owner"), _sub_ends_in(None), _running_promo_ends_in(None), \
             patch.object(payments.razorpay_service, "create_order") as create, \
             pytest.raises(HTTPException) as e:
            payments.create_promotion_order("s1", PromotionOrderRequest(days=3), {"id": "o1"}, {})
        assert e.value.status_code == 403
        create.assert_not_called()  # nothing is charged

    def test_a_paid_promotion_is_always_granted(self):
        """Money already taken (verify / reconcile / webhook): activation never checks the
        subscription, so a payment can't be lost even if the subscription ended meanwhile."""
        sb = MagicMock()
        sb.table.side_effect = lambda name: make_chain(ok([{"id": "p1", "title": "Featured Promotion"}])) \
            if name == "promotions" else make_chain(ok({"id": "s1", "name": "Shop", "city": "Pune"}))
        with _sub_ends_in(None), patch.object(promotion_service, "supabase", sb), \
             patch.object(promotion_service, "execute_one", return_value=ok({"id": "s1", "name": "Shop", "city": "Pune"})):
            out = promotion_service.create_promotion(
                "s1", "o1", PromotionCreate(title="Featured Promotion", description="d",
                                            valid_until=(NOW + timedelta(days=3)).isoformat()), paid=True)
        assert out["id"] == "p1"


class TestSchemesNeedSubscription:
    def _scheme(self):
        return PromotionCreate(title="10% off", description="Weekdays",
                               valid_until=(NOW + timedelta(days=3)).isoformat())

    def test_create_without_subscription_is_refused_and_nothing_written(self):
        sb = MagicMock()
        with _sub_ends_in(None), patch.object(promotion_service, "supabase", sb), \
             patch.object(promotion_service, "execute_one", return_value=ok({"id": "s1", "name": "Shop", "city": "Pune"})), \
             pytest.raises(HTTPException) as e:
            promotion_service.create_promotion("s1", "o1", self._scheme())
        assert e.value.status_code == 403
        assert "promotions" not in [c.args[0] for c in sb.table.call_args_list]  # nothing deleted / inserted

    def test_create_with_subscription_works(self):
        sb = MagicMock()
        sb.table.side_effect = lambda name: make_chain(ok([{"id": "sc1", "title": "10% off"}]))
        with _sub_ends_in(30), patch.object(promotion_service, "supabase", sb), \
             patch.object(promotion_service, "execute_one", return_value=ok({"id": "s1", "name": "Shop", "city": "Pune"})):
            assert promotion_service.create_promotion("s1", "o1", self._scheme())["id"] == "sc1"

    def test_edit_without_subscription_is_refused(self):
        rows = iter([ok({"shop_id": "s1", "title": "10% off"}), ok({"id": "s1"})])
        with _sub_ends_in(None), patch.object(promotion_service, "execute_one", side_effect=lambda q: next(rows)), \
             patch.object(promotion_service, "supabase", MagicMock()), pytest.raises(HTTPException) as e:
            promotion_service.update_promotion("sc1", "o1", PromotionUpdate(description="New text"))
        assert e.value.status_code == 403

    def test_delete_still_works_without_subscription(self):
        rows = iter([ok({"shop_id": "s1"}), ok({"id": "s1"})])
        with _sub_ends_in(None), patch.object(promotion_service, "execute_one", side_effect=lambda q: next(rows)), \
             patch.object(promotion_service, "supabase", MagicMock()):
            assert promotion_service.delete_promotion("sc1", "o1") is True
