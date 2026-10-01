"""Tests for subscription_service.py."""
from unittest.mock import MagicMock, patch
import pytest

from tests.conftest import make_chain, ok, ok_list


def _sub_body(plan="basic", duration=30):
    from app.schemas.subscription import SubscriptionCreate
    return SubscriptionCreate(plan=plan, duration_days=duration)


class TestCreateOrRenewSubscription:
    def test_raises_400_for_invalid_plan(self):
        from app.services import subscription_service
        from fastapi import HTTPException

        with patch("app.services.subscription_service.execute_one", return_value=MagicMock(data={"id": "shop-001"})):
            with pytest.raises(HTTPException) as exc:
                subscription_service.create_or_renew_subscription("shop-001", "owner-001", _sub_body(plan="enterprise"))
            assert exc.value.status_code == 400

    def test_raises_400_for_invalid_duration(self):
        from app.services import subscription_service
        from fastapi import HTTPException

        with patch("app.services.subscription_service.execute_one", return_value=MagicMock(data={"id": "shop-001"})):
            with pytest.raises(HTTPException) as exc:
                subscription_service.create_or_renew_subscription("shop-001", "owner-001", _sub_body(duration=15))
            assert exc.value.status_code == 400

    def test_creates_new_subscription(self):
        from app.services import subscription_service

        inserted = []
        sub_row = {
            "id": "sub-001", "shop_id": "shop-001", "plan": "basic",
            "status": "active", "started_at": "2024-01-01T00:00:00+00:00",
            "expires_at": "2024-02-01T00:00:00+00:00",
        }
        chain = make_chain(ok_list([sub_row]))
        chain.insert.side_effect = lambda data: inserted.append(data) or chain

        execute_one_calls = iter([
            MagicMock(data={"id": "shop-001"}),  # ownership check
            MagicMock(data=None),                 # no existing sub
        ])

        with patch("app.services.subscription_service.execute_one", side_effect=lambda q: next(execute_one_calls)), \
             patch("app.services.subscription_service.supabase") as mock_sup:
            mock_sup.table = chain.table
            result = subscription_service.create_or_renew_subscription("shop-001", "owner-001", _sub_body())

        assert result["has_active_subscription"] is True
        assert len(inserted) == 1
        assert inserted[0]["plan"] == "basic"
        assert inserted[0]["status"] == "active"

    def test_updates_existing_subscription(self):
        from app.services import subscription_service

        updates = []
        sub_row = {
            "id": "sub-001", "shop_id": "shop-001", "plan": "premium",
            "status": "active", "started_at": "2024-01-01T00:00:00+00:00",
            "expires_at": "2025-01-01T00:00:00+00:00",
        }
        chain = make_chain(ok_list([sub_row]))
        chain.update.side_effect = lambda data: updates.append(data) or chain

        execute_one_calls = iter([
            MagicMock(data={"id": "shop-001"}),
            MagicMock(data={"id": "sub-001"}),
        ])

        with patch("app.services.subscription_service.execute_one", side_effect=lambda q: next(execute_one_calls)), \
             patch("app.services.subscription_service.supabase") as mock_sup:
            mock_sup.table = chain.table
            result = subscription_service.create_or_renew_subscription(
                "shop-001", "owner-001", _sub_body(plan="basic", duration=90)
            )

        assert len(updates) == 1
        assert updates[0]["plan"] == "basic"


class TestGetSubscription:
    def test_returns_not_active_when_expired(self):
        from app.services import subscription_service
        from datetime import datetime, timezone, timedelta

        expired_sub = {
            "id": "sub-001",
            "status": "active",
            "expires_at": (datetime.now(timezone.utc) - timedelta(days=1)).isoformat(),
        }
        execute_one_calls = iter([
            MagicMock(data={"id": "shop-001"}),
            MagicMock(data=expired_sub),
        ])
        with patch("app.services.subscription_service.execute_one", side_effect=lambda q: next(execute_one_calls)):
            result = subscription_service.get_subscription("shop-001", "owner-001")

        assert result["has_active_subscription"] is False

    def test_returns_active_when_valid(self):
        from app.services import subscription_service
        from datetime import datetime, timezone, timedelta

        valid_sub = {
            "id": "sub-001",
            "status": "active",
            "expires_at": (datetime.now(timezone.utc) + timedelta(days=30)).isoformat(),
        }
        execute_one_calls = iter([
            MagicMock(data={"id": "shop-001"}),
            MagicMock(data=valid_sub),
        ])
        with patch("app.services.subscription_service.execute_one", side_effect=lambda q: next(execute_one_calls)):
            result = subscription_service.get_subscription("shop-001", "owner-001")

        assert result["has_active_subscription"] is True
        assert result["subscription"]["days_remaining"] > 0


class TestCancelSubscription:
    def test_cancel_marks_cancelled_and_closes_the_shop(self):
        from app.services import subscription_service as ss

        tables = {}

        def table(name):
            tables.setdefault(name, make_chain(ok_list([{"id": "x", "status": "cancelled"}])))
            return tables[name]

        with patch.object(ss, "execute_one", return_value=MagicMock(data={"id": "shop-001"})), \
                patch.object(ss, "supabase") as sb:
            sb.table.side_effect = table
            out = ss.cancel_subscription("shop-001", "owner-001")
        assert out["has_active_subscription"] is False
        assert out["subscription"]["days_remaining"] == 0
        # The router's response model must accept it (it used to 500 after the cancel had gone through).
        from app.schemas.subscription import SubscriptionStatus
        full = {**out["subscription"], "shop_id": "s", "plan": "basic", "started_at": "x", "expires_at": "x", "created_at": "x"}
        SubscriptionStatus(has_active_subscription=False, subscription=full)
        tables["subscriptions"].update.assert_called_with({"status": "cancelled"})
        tables["shops"].update.assert_called_with({"is_open": False})

    def test_a_cancelled_plan_reports_inactive_and_zero_days_left(self):
        from datetime import datetime, timedelta, timezone
        from app.services import subscription_service as ss

        future = (datetime.now(timezone.utc) + timedelta(days=20)).isoformat()
        rows = iter([MagicMock(data={"id": "shop-001"}),
                     MagicMock(data={"status": "cancelled", "expires_at": future, "shop_id": "shop-001"})])
        with patch.object(ss, "execute_one", side_effect=lambda q: next(rows)), patch.object(ss, "supabase"):
            out = ss.get_subscription("shop-001", "owner-001")
        assert out["has_active_subscription"] is False
        assert out["subscription"]["days_remaining"] == 0
