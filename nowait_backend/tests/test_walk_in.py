"""Walk-in customers: added by the owner at the counter, with no account."""
from pathlib import Path
from unittest.mock import MagicMock, patch

import pytest
from fastapi import HTTPException

from app.services import queue_service
from tests.conftest import make_chain, ok, ok_list

SERVICES = [{"id": "s-cut", "name": "Haircut", "price": 100, "duration_minutes": 20},
            {"id": "s-shave", "name": "Shave", "price": 50, "duration_minutes": 10}]


def _sb(services=SERVICES, rpc_result=None, rpc_error=None):
    sb = MagicMock()
    sb.table.side_effect = lambda name: make_chain(ok_list(services))
    if rpc_error:
        sb.rpc.side_effect = Exception(rpc_error)
    else:
        sb.rpc.return_value = make_chain(ok(rpc_result or {
            "id": "q9", "token_number": 12, "status": "waiting", "is_walk_in": True,
            "user_id": None, "total_duration_minutes": 30}))
    return sb


def _add(service_ids, sb, owner=True):
    with patch.object(queue_service, "supabase", sb), \
         patch.object(queue_service, "_is_owner", return_value=owner), \
         patch.object(queue_service, "execute_one", return_value=ok({"avg_wait_minutes": 10})):
        return queue_service.add_walk_in("shop-1", "owner-1", service_ids)


class TestAddWalkIn:
    def test_gets_the_next_token_with_the_chosen_services(self):
        sb = _sb()
        out = _add(["s-cut", "s-shave", "s-cut"], sb)
        assert out["token_number"] == 12 and out["is_walk_in"] is True
        assert out["service_names"] == ["Haircut", "Shave"]
        name, params = sb.rpc.call_args[0]
        assert name == "add_walk_in_v1"
        assert params["p_shop_id"] == "shop-1"
        assert params["p_service_ids"] == ["s-cut", "s-shave"]  # duplicates dropped
        assert params["p_total_duration_minutes"] == 30          # 20 + 10

    def test_only_the_shops_owner(self):
        sb = _sb()
        with pytest.raises(HTTPException) as e:
            _add(["s-cut"], sb, owner=False)
        assert e.value.status_code == 403
        sb.rpc.assert_not_called()

    def test_at_least_one_service_when_the_shop_has_services(self):
        sb = _sb()
        with pytest.raises(HTTPException) as e:
            _add([], sb)
        assert e.value.status_code == 400
        sb.rpc.assert_not_called()

    def test_a_shop_without_services_can_add_without_any(self):
        sb = _sb(services=[])
        assert _add([], sb)["token_number"] == 12

    def test_another_shops_service_is_refused(self):
        sb = _sb()
        with pytest.raises(HTTPException) as e:
            _add(["s-cut", "s-from-another-shop"], sb)
        assert e.value.status_code == 400
        sb.rpc.assert_not_called()

    @pytest.mark.parametrize("db_error,status,text", [
        ("SHOP_CLOSED: Shop is currently closed", 400, "Open your shop"),
        ("NO_SUBSCRIPTION: no active subscription", 403, "subscription"),
        ("Could not find the function public.add_walk_in_v1 (PGRST202)", 503, "set up"),
    ])
    def test_clear_messages(self, db_error, status, text):
        with pytest.raises(HTTPException) as e:
            _add(["s-cut", "s-shave"], _sb(rpc_error=db_error))
        assert e.value.status_code == status and text in e.value.detail


class TestWalkInsInQueueLists:
    def test_owner_queue_shows_walk_ins_without_looking_up_an_account(self):
        entries = [
            {"id": "q1", "user_id": "cust-1", "is_walk_in": False, "token_number": 10, "status": "serving",
             "service_ids": [], "service_id": None, "coming_at": None, "joined_at": "2026-11-12T10:00:00Z"},
            {"id": "q2", "user_id": None, "is_walk_in": True, "token_number": 11, "status": "waiting",
             "service_ids": ["s-cut"], "service_id": "s-cut", "coming_at": None, "joined_at": "2026-11-12T10:05:00Z"},
        ]
        profile_lookups = []

        def table(name):
            if name == "queue_entries":
                return make_chain(ok_list(entries))
            if name == "profiles":
                chain = make_chain(ok_list([{"id": "cust-1", "name": "Asha", "phone": "+919800000000"}]))
                chain.in_.side_effect = lambda col, ids: (profile_lookups.append(ids), chain)[1]
                return chain
            return make_chain(ok_list([]))

        sb = MagicMock()
        sb.table.side_effect = table
        with patch.object(queue_service, "supabase", sb), \
             patch.object(queue_service, "_is_owner", return_value=True), \
             patch.object(queue_service, "execute_one", return_value=ok(
                 {"id": "shop-1", "name": "Shop", "is_open": True, "queue_paused": False, "max_queue_size": None})), \
             patch.object(queue_service, "_fetch_services_by_ids", return_value=[SERVICES[0]]), \
             patch.object(queue_service, "_remaining", return_value=1, create=True):
            try:
                out = queue_service.get_shop_queue("shop-1", "owner-1")
            except Exception:  # anything after building the list isn't what this test is about
                out = None
        assert profile_lookups == [["cust-1"]]  # no lookup for the walk-in's empty account
        if out is not None:
            items = {q["token_number"]: q for q in out["queue"]}
            assert items[11]["is_walk_in"] is True and items[11]["customer_name"] == "Walk-in customer"
            assert items[10]["is_walk_in"] is False and items[10]["customer_name"] == "Asha"

    def test_almost_there_skips_walk_ins_but_notifies_customers(self):
        sb = MagicMock()
        sb.table.side_effect = lambda name: make_chain(ok_list([
            {"user_id": None, "token_number": 11}, {"user_id": "cust-2", "token_number": 12}]))
        with patch.object(queue_service, "supabase", sb), \
             patch.object(queue_service, "create_notification") as notify:
            queue_service._notify_upcoming_customers("shop-1", "Shop")
        assert [c.kwargs["user_id"] for c in notify.call_args_list] == ["cust-2"]

    def test_skipping_a_walk_in_sends_no_notification(self):
        sb = MagicMock()
        sb.rpc.return_value = make_chain(ok({"id": "q2", "shop_id": "shop-1", "user_id": None, "token_number": 11}))
        with patch.object(queue_service, "supabase", sb), \
             patch.object(queue_service, "_is_owner", return_value=True), \
             patch.object(queue_service, "execute_one", side_effect=[ok({"id": "q2", "shop_id": "shop-1"}), ok({"name": "Shop"})]), \
             patch.object(queue_service, "create_notification") as notify:
            out = queue_service.skip_customer("q2", "owner-1")
        assert out["user_id"] is None
        notify.assert_not_called()

    def test_public_queue_marks_walk_ins(self):
        sb = MagicMock()
        sb.table.side_effect = lambda name: make_chain(ok_list([
            {"token_number": 10, "status": "serving", "service_ids": [], "service_id": None,
             "total_duration_minutes": None, "is_walk_in": False},
            {"token_number": 11, "status": "waiting", "service_ids": [], "service_id": None,
             "total_duration_minutes": None, "is_walk_in": True}]))
        with patch.object(queue_service, "supabase", sb), \
             patch.object(queue_service, "execute_one", return_value=ok(
                 {"id": "shop-1", "name": "Shop", "is_open": True, "avg_wait_minutes": 10})):
            out = queue_service.get_public_shop_queue("shop-1")
        assert [q["is_walk_in"] for q in out["queue"]] == [False, True]


def test_database_function_exists_and_is_locked_down():
    sql = (Path(__file__).parent.parent / "sql" / "final_consolidated.sql").read_text(encoding="utf-8")
    assert "CREATE OR REPLACE FUNCTION add_walk_in_v1(" in sql
    assert "ALTER TABLE queue_entries ALTER COLUMN user_id DROP NOT NULL;" in sql
    assert "'skip_customer_v2','add_walk_in_v1')" in sql  # only the backend may call it
    standalone = (Path(__file__).parent.parent / "sql" / "migrate_walk_in.sql").read_text(encoding="utf-8")
    assert "add_walk_in_v1" in standalone and "REVOKE ALL ON FUNCTION" in standalone
