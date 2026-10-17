"""Tests for queue_service.py — display status, cancel, coming, advance, skip, history."""
from unittest.mock import MagicMock, patch
import pytest

from tests.conftest import make_queue_entry, make_shop, make_chain, ok, ok_list


# ── _get_display_status ───────────────────────────────────────────────────────

class TestDisplayStatus:
    def test_serving_is_your_turn(self):
        from app.services.queue_service import _get_display_status
        assert _get_display_status("serving", 1) == "yourTurn"

    def test_waiting_position_3_is_almost_there(self):
        from app.services.queue_service import _get_display_status
        assert _get_display_status("waiting", 3) == "almostThere"

    def test_waiting_position_4_is_waiting(self):
        from app.services.queue_service import _get_display_status
        assert _get_display_status("waiting", 4) == "waiting"

    def test_waiting_position_1_is_almost_there(self):
        from app.services.queue_service import _get_display_status
        assert _get_display_status("waiting", 1) == "almostThere"

    def test_completed_returns_completed(self):
        from app.services.queue_service import _get_display_status
        assert _get_display_status("completed", 0) == "completed"

    def test_cancelled_returns_cancelled(self):
        from app.services.queue_service import _get_display_status
        assert _get_display_status("cancelled", 0) == "cancelled"

    def test_skipped_returns_skipped(self):
        from app.services.queue_service import _get_display_status
        assert _get_display_status("skipped", 0) == "skipped"


# ── cancel_queue ──────────────────────────────────────────────────────────────

class TestCancelQueue:
    def test_raises_404_if_entry_not_found(self):
        from app.services import queue_service
        from fastapi import HTTPException

        with patch("app.services.queue_service.execute_one", return_value=MagicMock(data=None)):
            with pytest.raises(HTTPException) as exc:
                queue_service.cancel_queue("entry-001", "user-001")
            assert exc.value.status_code == 404

    def test_raises_400_if_already_serving(self):
        from app.services import queue_service
        from fastapi import HTTPException

        entry = make_queue_entry(status="serving")
        with patch("app.services.queue_service.execute_one", return_value=MagicMock(data=entry)):
            with pytest.raises(HTTPException) as exc:
                queue_service.cancel_queue("entry-001", "user-001")
            assert exc.value.status_code == 400

    def test_cancels_waiting_entry_and_logs_event(self):
        from app.services import queue_service

        entry = make_queue_entry(status="waiting")
        updates, inserts = [], []
        chain = make_chain(ok_list([]))
        chain.update.side_effect = lambda data: updates.append(data) or chain
        chain.insert.side_effect = lambda data: inserts.append(data) or chain

        with patch("app.services.queue_service.execute_one", return_value=MagicMock(data=entry)), \
             patch("app.services.queue_service.supabase") as mock_sup:
            mock_sup.table = chain.table
            result = queue_service.cancel_queue("entry-001", "user-001")

        assert result["entry_id"] == "entry-001"
        assert any(u.get("status") == "cancelled" for u in updates)
        assert any(i.get("event_type") == "cancelled" for i in inserts)


# ── notify_coming ─────────────────────────────────────────────────────────────

class TestNotifyComing:
    def test_raises_404_if_entry_not_found(self):
        from app.services import queue_service
        from fastapi import HTTPException

        with patch("app.services.queue_service.execute_one", return_value=MagicMock(data=None)):
            with pytest.raises(HTTPException) as exc:
                queue_service.notify_coming("entry-001", "user-001")
            assert exc.value.status_code == 404

    def test_raises_400_if_status_completed(self):
        from app.services import queue_service
        from fastapi import HTTPException

        entry = make_queue_entry(status="completed")
        with patch("app.services.queue_service.execute_one", return_value=MagicMock(data=entry)):
            with pytest.raises(HTTPException) as exc:
                queue_service.notify_coming("entry-001", "user-001")
            assert exc.value.status_code == 400

    def test_sets_coming_at_and_notifies_owner(self):
        from app.services import queue_service

        entry = make_queue_entry(status="waiting", user_id="cust-001")
        shop = {"name": "Raj Salon", "owner_id": "owner-001"}
        profile = {"name": "Ravi"}

        execute_one_calls = iter([
            MagicMock(data=entry),
            MagicMock(data=shop),
            MagicMock(data=profile),
        ])

        updates, notifs = [], []
        chain = make_chain(ok_list([]))
        chain.update.side_effect = lambda data: updates.append(data) or chain

        with patch("app.services.queue_service.execute_one", side_effect=lambda q: next(execute_one_calls)), \
             patch("app.services.queue_service.supabase") as mock_sup, \
             patch("app.services.queue_service.create_notification", side_effect=lambda **kw: notifs.append(kw)):
            mock_sup.table = chain.table
            result = queue_service.notify_coming("entry-001", "cust-001")

        assert result["entry_id"] == "entry-001"
        assert any("coming_at" in u for u in updates)
        owner_notifs = [n for n in notifs if n.get("user_id") == "owner-001"]
        assert len(owner_notifs) == 1
        assert owner_notifs[0]["type"] == "coming"

    def test_only_the_owner_is_notified(self):
        # Single queue per shop: staff are informational, so only the owner gets "on the way".
        from app.services import queue_service

        entry = make_queue_entry(status="waiting", user_id="cust-001", staff_id="staff-uid-001")
        shop = {"name": "Raj Salon", "owner_id": "owner-001"}
        profile = {"name": "Ravi"}

        execute_one_calls = iter([
            MagicMock(data=entry),
            MagicMock(data=shop),
            MagicMock(data=profile),
        ])
        notifs = []
        chain = make_chain(ok_list([]))

        with patch("app.services.queue_service.execute_one", side_effect=lambda q: next(execute_one_calls)), \
             patch("app.services.queue_service.supabase") as mock_sup, \
             patch("app.services.queue_service.create_notification", side_effect=lambda **kw: notifs.append(kw)):
            mock_sup.table = chain.table
            queue_service.notify_coming("entry-001", "cust-001")

        assert [n["user_id"] for n in notifs] == ["owner-001"]


# ── get_shop_queue ────────────────────────────────────────────────────────────

class TestGetShopQueue:
    def test_raises_403_if_not_staff_or_owner(self):
        from app.services import queue_service
        from fastapi import HTTPException

        with patch("app.services.queue_service._is_owner", return_value=False):
            with pytest.raises(HTTPException) as exc:
                queue_service.get_shop_queue("shop-001", "random-user")
            assert exc.value.status_code == 403

    def test_queue_paused_flag_in_response(self):
        from app.services import queue_service

        shop_data = {**make_shop(), "queue_paused": True}
        execute_one_calls = iter([MagicMock(data=shop_data)])
        chain = make_chain(ok_list([]))

        with patch("app.services.queue_service._is_owner", return_value=True), \
             patch("app.services.queue_service.execute_one", side_effect=lambda q: next(execute_one_calls)), \
             patch("app.services.queue_service.supabase") as mock_sup:
            mock_sup.table = chain.table
            result = queue_service.get_shop_queue("shop-001", "owner-001")

        assert result["queue_paused"] is True

    def test_owner_sees_all_customers(self):
        from app.services import queue_service

        shop_data = make_shop()
        entries = [
            make_queue_entry(entry_id="e1", token=1, status="serving"),
            make_queue_entry(entry_id="e2", token=2, status="waiting"),
        ]
        # Customer profiles are fetched in one batch query (no per-entry lookups).
        profiles = [{"id": e["user_id"], "name": f"Customer {e['token_number']}", "phone": "+91111"} for e in entries]
        execute_one_calls = iter([MagicMock(data=shop_data)])
        entries_chain, profiles_chain = make_chain(ok_list(entries)), make_chain(ok_list(profiles))

        with patch("app.services.queue_service._is_owner", return_value=True), \
             patch("app.services.queue_service.execute_one", side_effect=lambda q: next(execute_one_calls)), \
             patch("app.services.queue_service._fetch_services_by_ids", return_value=[]), \
             patch("app.services.queue_service.supabase") as mock_sup:
            mock_sup.table.side_effect = lambda name: (profiles_chain if name == "profiles" else entries_chain).table(name)
            result = queue_service.get_shop_queue("shop-001", "owner-001")

        assert result["total_waiting"] == 1
        assert result["now_serving_token"] == 1
        assert len(result["queue"]) == 2


# ── pause / resume ────────────────────────────────────────────────────────────

class TestPauseResumeQueue:
    def test_pause_sets_queue_paused_true(self):
        from app.services import queue_service

        updates, inserts = [], []
        chain = make_chain(ok_list([]))
        chain.update.side_effect = lambda data: updates.append(data) or chain
        chain.insert.side_effect = lambda data: inserts.append(data) or chain

        with patch("app.services.queue_service._is_owner", return_value=True), \
             patch("app.services.queue_service.supabase") as mock_sup:
            mock_sup.table = chain.table
            result = queue_service.pause_queue("shop-001", "owner-001")

        assert result["queue_paused"] is True
        assert any(u.get("queue_paused") is True for u in updates)

    def test_resume_sets_queue_paused_false(self):
        from app.services import queue_service

        updates = []
        chain = make_chain(ok_list([]))
        chain.update.side_effect = lambda data: updates.append(data) or chain
        chain.insert.return_value = chain

        with patch("app.services.queue_service._is_owner", return_value=True), \
             patch("app.services.queue_service.supabase") as mock_sup:
            mock_sup.table = chain.table
            result = queue_service.resume_queue("shop-001", "owner-001")

        assert result["queue_paused"] is False
        assert any(u.get("queue_paused") is False for u in updates)

    def test_pause_raises_403_for_non_owner(self):
        from app.services import queue_service
        from fastapi import HTTPException

        # queue_service imported _is_owner, so patch ITS binding (patching staff_service's does nothing).
        with patch("app.services.queue_service._is_owner", return_value=False), \
             patch("app.services.queue_service.supabase") as mock_sup:
            with pytest.raises(HTTPException) as exc:
                queue_service.pause_queue("shop-001", "staff-uid")
            mock_sup.table.assert_not_called()
            assert exc.value.status_code == 403


# ── get_customer_history ──────────────────────────────────────────────────────

class TestGetCustomerHistory:
    def test_enriches_with_shop_and_service_info(self):
        from app.services import queue_service

        entry = {
            **make_queue_entry(status="completed"),
            "service_id": "svc-001",
            "served_at": "2024-01-01T11:00:00+00:00",
            "actual_service_minutes": 15,
        }
        shop = {"name": "Raj Salon", "category": "Salon", "city": "Pune"}

        execute_one_calls = iter([MagicMock(data=shop)])
        chain = make_chain(ok_list([entry]))

        with patch("app.services.queue_service.execute_one", side_effect=lambda q: next(execute_one_calls)), \
             patch("app.services.queue_service._fetch_services_by_ids",
                   return_value=[{"id": "svc-001", "name": "Haircut"}]), \
             patch("app.services.queue_service.supabase") as mock_sup:
            mock_sup.table = chain.table
            result = queue_service.get_customer_history("cust-001")

        assert len(result) == 1
        assert result[0]["shop_name"] == "Raj Salon"
        assert result[0]["service_name"] == "Haircut"
        assert result[0]["shop_city"] == "Pune"
