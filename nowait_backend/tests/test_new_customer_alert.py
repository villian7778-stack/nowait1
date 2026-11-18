"""Owner "New customer joined": in-app notification + push with the shop bell, mutable by the owner."""
from unittest.mock import MagicMock, patch

import pytest
from fastapi.testclient import TestClient

from app.services import push_service, queue_service
from tests.conftest import make_chain, ok, ok_list
from tests.test_push import B64, FakeGoogle

ENTRY = {"id": "q42", "shop_id": "shop-1", "token_number": 42, "status": "waiting", "position": 3, "user_id": "cust-1"}


def _join(shop=None, profile=None, notify_error=None):
    """join_queue for cust-1 at shop-1, succeeding; returns (response, create_notification mock, push mock)."""
    shop = shop if shop is not None else {"name": "Jai Salon", "avg_wait_minutes": 10, "owner_id": "owner-1", "category": "Salon"}

    def one(query):
        if query.table_name == "queue_entries":  # nobody being served yet
            return MagicMock(data=None)
        if query.table_name == "profiles":
            return MagicMock(data=profile if profile is not None else {"name": "Asha"})
        return MagicMock(data=shop)

    def table(name):
        chain = make_chain(ok_list([]))
        chain.table_name = name
        return chain

    sup = MagicMock()
    sup.table.side_effect = table
    sup.rpc.return_value = make_chain(ok(ENTRY))
    with patch.object(queue_service, "supabase", sup), \
         patch.object(queue_service, "execute_one", side_effect=one), \
         patch.object(queue_service, "_check_queue_ban"), \
         patch.object(queue_service, "_check_existing_active_queue"), \
         patch.object(queue_service, "_require_shop_services"), \
         patch.object(queue_service, "create_notification", side_effect=notify_error) as notify, \
         patch.object(queue_service.push_service, "notify_user") as push:
        out = queue_service.join_queue("shop-1", "cust-1")
    return out, notify, push


class TestOwnerIsTold:
    def test_online_join_notifies_the_owner(self):
        out, notify, push = _join()
        assert out["token_number"] == 42
        notify.assert_called_once()
        args, kwargs = notify.call_args
        assert args[:2] == ("owner-1", "new_customer")
        assert args[2] == "New customer joined"
        assert args[3] == "Token #42 · Asha joined your queue"
        assert args[4:] == ("Jai Salon", "shop-1")
        assert kwargs["push_data"] == {"queue_entry_id": "q42"}  # lets the open app avoid a double bell
        push.assert_not_called()  # create_notification pushes it

    def test_customer_without_a_name(self):
        _, notify, _ = _join(profile={"name": "  "})
        assert notify.call_args[0][3] == "Token #42 · A customer joined your queue"

    def test_owner_joining_their_own_shop_is_not_notified(self):
        _, notify, push = _join(shop={"name": "S", "avg_wait_minutes": 10, "owner_id": "cust-1"})
        notify.assert_not_called()
        push.assert_not_called()

    def test_before_the_migration_the_push_still_goes_and_the_join_works(self):
        out, notify, push = _join(notify_error=Exception('violates check constraint "notifications_type_check"'))
        assert out["token_number"] == 42
        push.assert_called_once_with("owner-1", "new_customer", "New customer joined",
                                     "Token #42 · Asha joined your queue", {"shop_id": "shop-1", "queue_entry_id": "q42"})

    def test_any_trouble_never_fails_the_join(self):
        with patch.object(queue_service.push_service, "notify_user", side_effect=RuntimeError("boom")):
            out, _, _ = _join(notify_error=Exception("db down"))
        assert out["token_number"] == 42

    def test_walk_ins_added_by_the_owner_do_not_notify(self):
        sb = MagicMock()
        sb.table.side_effect = lambda name: make_chain(ok_list([]))
        sb.rpc.return_value = make_chain(ok({"id": "w1", "token_number": 7, "status": "waiting", "is_walk_in": True}))
        with patch.object(queue_service, "supabase", sb), \
             patch.object(queue_service, "_is_owner", return_value=True), \
             patch.object(queue_service, "execute_one", return_value=MagicMock(data={"avg_wait_minutes": 10})), \
             patch.object(queue_service, "create_notification") as notify, \
             patch.object(queue_service.push_service, "notify_user") as push:
            queue_service.add_walk_in("shop-1", "owner-1", [])
        notify.assert_not_called()
        push.assert_not_called()


class TestPush:
    @pytest.fixture
    def push_on(self):
        with patch.object(push_service.settings, "FIREBASE_CREDENTIALS_BASE64", B64), \
             patch.object(push_service, "_access_token", None):
            yield

    def test_new_customer_rings_the_shop_bell_channel(self, push_on):
        g = FakeGoogle()
        with patch.object(push_service.httpx, "post", g.post):
            push_service.send_now("owner-phone", "New customer joined", "Token #42",
                                  {"type": "new_customer", "queue_entry_id": "q42"})
            push_service.send_now("cust-phone", "It's Your Turn!", "Token #12", {"type": "your_turn"})
        owner, cust = (s["json"]["message"]["android"]["notification"] for s in g.sends)
        assert owner == {"channel_id": "nowait_new_customer", "sound": "new_customer"}
        assert g.sends[0]["json"]["message"]["data"]["queue_entry_id"] == "q42"
        assert cust == {"channel_id": "nowait_alerts", "sound": "default"}  # customers: unchanged

    def _run(self, row, select_error=False):
        calls = []

        def table(name):
            chain = make_chain(ok_list(row))
            def select(cols):
                calls.append(cols)
                if select_error and "new_customer_alerts" in cols:
                    raise Exception("column profiles.new_customer_alerts does not exist")
                return chain
            chain.select.side_effect = select
            return chain
        sb = MagicMock()
        sb.table.side_effect = table
        jobs = []
        with patch.object(push_service, "supabase", sb), \
             patch.object(push_service, "_pool", MagicMock(submit=lambda fn: jobs.append(fn))), \
             patch.object(push_service, "send_now") as send:
            push_service.notify_user("owner-1", "new_customer", "New customer joined", "Token #42", {"shop_id": "s1"})
            jobs[0]()
        return send, calls

    def test_sent_when_on(self, push_on):
        send, _ = self._run([{"fcm_token": "owner-phone", "new_customer_alerts": True}])
        send.assert_called_once_with("owner-phone", "New customer joined", "Token #42",
                                     {"type": "new_customer", "shop_id": "s1"})

    def test_muted_owner_gets_no_push(self, push_on):
        send, _ = self._run([{"fcm_token": "owner-phone", "new_customer_alerts": False}])
        send.assert_not_called()

    def test_before_the_migration_alerts_stay_on(self, push_on):
        send, calls = self._run([{"fcm_token": "owner-phone"}], select_error=True)
        assert calls == ["fcm_token, new_customer_alerts", "fcm_token"]
        send.assert_called_once()


class TestMuteEndpoint:
    @pytest.fixture
    def client(self):
        from app.dependencies import get_current_user
        from app.main import app
        app.dependency_overrides[get_current_user] = lambda: {"id": "owner-1", "role": "owner"}
        yield TestClient(app, raise_server_exceptions=False)
        app.dependency_overrides.pop(get_current_user, None)

    def _sb(self, fail=False):
        calls = []
        def table(name):
            chain = make_chain(ok([]))
            def update(data):
                if fail:
                    raise Exception("column does not exist")
                calls.append(("update", data))
                return chain
            chain.update.side_effect = update
            chain.eq.side_effect = lambda col, val: (calls.append(("eq", col, val)), chain)[1]
            return chain
        sb = MagicMock()
        sb.table.side_effect = table
        return sb, calls

    def test_mute_and_unmute_change_only_your_row(self, client):
        for on in (False, True):
            sb, calls = self._sb()
            with patch("app.database.supabase", sb):
                r = client.put("/auth/new-customer-alerts", json={"enabled": on})
            assert r.status_code == 200 and r.json() == {"new_customer_alerts": on}
            assert calls == [("update", {"new_customer_alerts": on}), ("eq", "id", "owner-1")]

    @pytest.mark.parametrize("body", [{}, {"enabled": "no"}, {"enabled": 0}, {"enabled": None}])
    def test_only_true_or_false(self, client, body):
        sb, calls = self._sb()
        with patch("app.database.supabase", sb):
            r = client.put("/auth/new-customer-alerts", json=body)
        assert r.status_code == 400 and calls == []

    def test_before_the_migration(self, client):
        sb, _ = self._sb(fail=True)
        with patch("app.database.supabase", sb):
            assert client.put("/auth/new-customer-alerts", json={"enabled": False}).status_code == 503

    def test_needs_login(self):
        from app.main import app
        r = TestClient(app).put("/auth/new-customer-alerts", json={"enabled": False})
        assert r.status_code in (401, 403)
