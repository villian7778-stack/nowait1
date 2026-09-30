"""Queue pause + queue limit: messages, blocked-join popup state, reset, validation."""
from unittest.mock import MagicMock, patch

import pytest
from fastapi import HTTPException
from fastapi.testclient import TestClient

from tests.conftest import make_chain, make_owner_user, ok_list


def _events_chain(latest_type=None):
    """supabase mock whose queue_events query returns the newest event (or none)."""
    rows = [{"event_type": latest_type}] if latest_type else []
    chain = make_chain(ok_list(rows))
    inserted = []
    chain.insert.side_effect = lambda d: inserted.append(d) or chain
    return chain, inserted


# ── blocked-join bookkeeping ─────────────────────────────────────────────────

class TestLimitRequestState:
    @pytest.mark.parametrize("latest,expected", [
        (None, False), ("limit_ack", False), ("limit_blocked", True),
    ])
    def test_newest_event_decides(self, latest, expected):
        from app.services import queue_service
        chain, _ = _events_chain(latest)
        with patch("app.services.queue_service.supabase", chain):
            assert queue_service._limit_request_pending("shop-001") is expected

    def test_first_blocked_join_is_recorded(self):
        from app.services import queue_service
        chain, inserted = _events_chain(None)
        with patch("app.services.queue_service.supabase", chain):
            queue_service._record_limit_block("shop-001")
        assert inserted == [{"shop_id": "shop-001", "event_type": "limit_blocked"}]

    def test_repeat_attempts_dont_stack_popups(self):
        from app.services import queue_service
        chain, inserted = _events_chain("limit_blocked")
        with patch("app.services.queue_service.supabase", chain):
            queue_service._record_limit_block("shop-001")
        assert inserted == []

    def test_bookkeeping_failure_never_breaks_join_response(self):
        from app.services import queue_service
        boom = MagicMock()
        boom.table.side_effect = RuntimeError("db down")
        with patch("app.services.queue_service.supabase", boom):
            queue_service._record_limit_block("shop-001")   # must not raise


# ── customer-facing join errors ──────────────────────────────────────────────

class TestJoinMessages:
    def _join(self, rpc_error):
        from app.services import queue_service
        rpc = MagicMock()
        rpc.execute.side_effect = Exception(rpc_error)
        sup = MagicMock()
        sup.rpc.return_value = rpc
        with patch("app.services.queue_service.supabase", sup), \
             patch("app.services.queue_service.execute_one", return_value=MagicMock(data={"avg_wait_minutes": 10, "category": "Salon"})), \
             patch("app.services.queue_service._check_queue_ban"), \
             patch("app.services.queue_service._check_existing_active_queue"), \
             patch("app.services.queue_service._record_limit_block") as rec:
            with pytest.raises(HTTPException) as e:
                queue_service.join_queue("shop-001", "cust-001")
        return e.value, rec

    def test_full_queue_message_and_owner_alert(self):
        err, rec = self._join("QUEUE_FULL: Queue has reached its maximum capacity")
        assert err.status_code == 400
        assert err.detail == "The owner has set a limit for this queue. You are not able to join at this time."
        rec.assert_called_once_with("shop-001")

    def test_paused_message_and_no_owner_alert(self):
        err, rec = self._join("QUEUE_PAUSED: Queue is currently paused")
        assert err.status_code == 400
        assert err.detail == "Queue is paused by the owner."
        rec.assert_not_called()


# ── owner actions ────────────────────────────────────────────────────────────

class TestOwnerActions:
    def test_pause_message(self):
        from app.services import queue_service
        chain, _ = _events_chain()
        with patch("app.services.queue_service._is_owner", return_value=True), \
             patch("app.services.queue_service.supabase", chain):
            res = queue_service.pause_queue("shop-001", "owner-001")
        assert res["queue_paused"] is True
        assert res["message"] == "You paused the queue."

    def test_reset_removes_limit_and_acks(self):
        from app.services import queue_service
        chain, inserted = _events_chain("limit_blocked")
        updates = []
        chain.update.side_effect = lambda d: updates.append(d) or chain
        with patch("app.services.queue_service._is_owner", return_value=True), \
             patch("app.services.queue_service.supabase", chain):
            res = queue_service.resolve_limit_request("shop-001", "owner-001", "reset")
        assert updates == [{"max_queue_size": None}]
        assert inserted[-1]["event_type"] == "limit_ack"
        assert res["max_queue_size"] is None

    @pytest.mark.parametrize("action", ["skip", "close"])
    def test_skip_and_close_keep_the_limit(self, action):
        from app.services import queue_service
        chain, inserted = _events_chain("limit_blocked")
        updates = []
        chain.update.side_effect = lambda d: updates.append(d) or chain
        with patch("app.services.queue_service._is_owner", return_value=True), \
             patch("app.services.queue_service.supabase", chain), \
             patch("app.services.queue_service.execute_one", return_value=MagicMock(data={"max_queue_size": 10})):
            res = queue_service.resolve_limit_request("shop-001", "owner-001", action)
        assert updates == []
        assert inserted[-1]["event_type"] == "limit_ack"
        assert res["max_queue_size"] == 10

    def test_only_the_owner_can_answer(self):
        from app.services import queue_service
        with patch("app.services.queue_service._is_owner", return_value=False):
            with pytest.raises(HTTPException) as e:
                queue_service.resolve_limit_request("shop-001", "someone", "reset")
        assert e.value.status_code == 403

    def test_setting_a_limit_answers_pending_request(self):
        from app.services import queue_service
        chain, inserted = _events_chain("limit_blocked")
        with patch("app.services.queue_service._is_owner", return_value=True), \
             patch("app.services.queue_service.supabase", chain):
            queue_service.set_max_size("shop-001", "owner-001", 12)
        assert inserted[-1]["event_type"] == "limit_ack"


# ── owner queue view flags ───────────────────────────────────────────────────

class TestShopQueueFlags:
    def _view(self, limit, n_entries, pending):
        from app.services import queue_service
        shop = {"id": "shop-001", "name": "Raj", "is_open": True, "queue_paused": False, "max_queue_size": limit}
        entries = [{"id": f"e{i}", "user_id": f"u{i}", "token_number": i + 1,
                    "status": "serving" if i == 0 else "waiting", "service_ids": [], "service_id": None}
                   for i in range(n_entries)]
        chain = make_chain(ok_list(entries))
        with patch("app.services.queue_service._is_owner", return_value=True), \
             patch("app.services.queue_service.execute_one", return_value=MagicMock(data=shop)), \
             patch("app.services.queue_service.supabase", chain), \
             patch("app.services.queue_service._limit_request_pending", return_value=pending):
            return queue_service.get_shop_queue("shop-001", "owner-001")

    def test_under_limit(self):
        r = self._view(limit=12, n_entries=6, pending=True)
        assert (r["active_count"], r["max_queue_size"]) == (6, 12)
        assert r["limit_reached"] is False
        assert r["limit_request_pending"] is False   # stale request ignored below the limit

    def test_at_limit_with_request(self):
        r = self._view(limit=10, n_entries=10, pending=True)
        assert r["limit_reached"] is True
        assert r["limit_request_pending"] is True

    def test_at_limit_without_request(self):
        r = self._view(limit=10, n_entries=10, pending=False)
        assert r["limit_reached"] is True
        assert r["limit_request_pending"] is False

    def test_no_limit_never_reached(self):
        r = self._view(limit=None, n_entries=50, pending=True)
        assert r["limit_reached"] is False
        assert r["limit_request_pending"] is False


# ── HTTP validation ──────────────────────────────────────────────────────────

class TestEndpoints:
    @pytest.fixture
    def client(self):
        from app.main import app
        from app.dependencies import get_current_owner, get_current_user
        owner = make_owner_user()
        app.dependency_overrides[get_current_user] = lambda: owner
        app.dependency_overrides[get_current_owner] = lambda: owner
        yield TestClient(app, raise_server_exceptions=False)
        app.dependency_overrides.clear()

    @pytest.mark.parametrize("value", [0, -5, 1001, "abc", 3.5])
    def test_bad_limits_rejected(self, client, value):
        r = client.put("/queues/shop/shop-001/max-size", json={"max_size": value})
        assert r.status_code == 422

    @pytest.mark.parametrize("value", [1, 12, 1000, None])
    def test_good_limits_accepted(self, client, value):
        with patch("app.routers.queues.queue_service.set_max_size", return_value={"max_queue_size": value}) as m:
            r = client.put("/queues/shop/shop-001/max-size", json={"max_size": value})
        assert r.status_code == 200
        m.assert_called_once()

    def test_unknown_action_rejected(self, client):
        r = client.post("/queues/shop/shop-001/limit-request", json={"action": "delete"})
        assert r.status_code == 422

    @pytest.mark.parametrize("action", ["skip", "close", "reset"])
    def test_known_actions_routed(self, client, action):
        with patch("app.routers.queues.queue_service.resolve_limit_request", return_value={"action": action}) as m:
            r = client.post("/queues/shop/shop-001/limit-request", json={"action": action})
        assert r.status_code == 200
        assert m.call_args[0][2] == action
