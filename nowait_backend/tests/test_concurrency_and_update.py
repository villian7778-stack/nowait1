"""Double taps, slow-network retries and several people doing the same thing at once must never
charge twice, lose paid days, create duplicates or move the queue twice; and an out-of-date app
build must be told to update."""
import threading
import time
from datetime import datetime, timedelta, timezone
from unittest.mock import MagicMock, patch

import pytest
from fastapi import HTTPException
from fastapi.testclient import TestClient

from app.config import settings


def _together(n, fn):
    """Runs fn() in n threads released at the same moment; returns results / exceptions."""
    start = threading.Barrier(n)
    out = [None] * n

    def run(i):
        start.wait()
        try:
            out[i] = fn()
        except Exception as e:  # noqa: BLE001 - the test inspects it
            out[i] = e

    threads = [threading.Thread(target=run, args=(i,)) for i in range(n)]
    for t in threads:
        t.start()
    for t in threads:
        t.join()
    return out


# ── Payments: one order per purchase ───────────────────────────────────────────────────

class FakeLedger:
    def __init__(self):
        self.rows = []

    def find_open_order(self, shop_id, owner_id, purpose, amount, metadata):
        for row in reversed(self.rows):
            if (row["owner_id"], row["purpose"], row["amount_paise"]) == (owner_id, purpose, amount) and \
                    all(row["metadata"].get(k) == v for k, v in metadata.items()):
                return row
        return None

    def record_order(self, shop_id, owner_id, purpose, order_id, amount, metadata):
        self.rows.append({"shop_id": shop_id, "owner_id": owner_id, "purpose": purpose,
                          "razorpay_order_id": order_id, "amount_paise": amount, "metadata": metadata})


@pytest.fixture
def ledger():
    from app.routers import payments
    fake = FakeLedger()
    made = []

    def create_order(amount, receipt):
        time.sleep(0.05)  # a slow Razorpay call, so racing requests overlap
        made.append(amount)
        return {"order_id": f"order_{len(made)}", "amount": amount, "currency": "INR", "key_id": "k"}

    with patch.object(payments, "_require_shop_owner"), \
         patch.object(payments.subscription_service, "active_expiry", return_value=None), \
         patch.object(payments.payment_transaction_service, "find_open_order", side_effect=fake.find_open_order), \
         patch.object(payments.payment_transaction_service, "record_order", side_effect=fake.record_order), \
         patch.object(payments.razorpay_service, "create_order", side_effect=create_order):
        yield payments, made


class TestOneOrderPerPurchase:
    def _buy(self, payments, days=30):
        from app.schemas.payment import SubscriptionOrderRequest
        return payments.create_subscription_order(
            "shop-1", SubscriptionOrderRequest(plan="basic", duration_days=days), {"id": "owner-1"})

    def test_double_tap_gets_the_same_order(self, ledger):
        payments, made = ledger
        results = _together(5, lambda: self._buy(payments))
        assert {r["order_id"] for r in results} == {"order_1"}
        assert made == [4900]   # Razorpay was asked once: the owner can only pay once

    def test_retry_after_a_timeout_reuses_the_order(self, ledger):
        payments, made = ledger
        assert self._buy(payments)["order_id"] == self._buy(payments)["order_id"]
        assert len(made) == 1

    def test_a_different_plan_is_a_new_order(self, ledger):
        payments, made = ledger
        assert self._buy(payments, 30)["order_id"] != self._buy(payments, 90)["order_id"]
        assert made == [4900, 13000]

    def test_orders_made_with_other_razorpay_keys_are_not_reused(self, ledger):
        payments, made = ledger
        with patch.object(settings, "RAZORPAY_KEY_ID", "rzp_test_old"):
            self._buy(payments)
        with patch.object(settings, "RAZORPAY_KEY_ID", "rzp_live_new"):
            self._buy(payments)
        assert len(made) == 2


def test_find_open_order_only_matches_the_same_purchase():
    from app.services import payment_transaction_service as pts
    rows = [{"razorpay_order_id": "o1", "metadata": {"plan": "basic", "duration_days": 90, "key_id": "k"}}]
    with patch.object(pts, "supabase") as db:
        db.table.return_value.select.return_value.eq.return_value.eq.return_value.eq.return_value \
            .eq.return_value.eq.return_value.gte.return_value.order.return_value.limit.return_value \
            .execute.return_value = MagicMock(data=rows)
        assert pts.find_open_order("s", "o", "subscription", 13000, {"plan": "basic", "duration_days": 90, "key_id": "k"})
        assert pts.find_open_order("s", "o", "subscription", 13000, {"plan": "basic", "duration_days": 30, "key_id": "k"}) is None


# ── Two payments activating together both count ─────────────────────────────────────────

def test_two_activations_at_once_both_add_their_days():
    from app.routers import payments
    state = {"expires": datetime(2027, 1, 1, tzinfo=timezone.utc)}

    def slow_renew(shop_id, owner_id, data):   # read ... think ... write, like the real one
        current = state["expires"]
        time.sleep(0.05)
        state["expires"] = current + timedelta(days=data.duration_days)

    txn = {"shop_id": "shop-1", "owner_id": "o", "purpose": "subscription",
           "metadata": {"plan": "basic", "duration_days": 30}}
    with patch.object(payments.subscription_service, "create_or_renew_subscription", side_effect=slow_renew):
        _together(2, lambda: payments._activate(txn))
    assert state["expires"] == datetime(2027, 1, 1, tzinfo=timezone.utc) + timedelta(days=60)


def test_subscription_created_by_a_parallel_payment_is_extended_not_lost():
    from app.schemas.subscription import SubscriptionCreate
    from app.services import subscription_service as ss
    end = (datetime.now(timezone.utc) + timedelta(days=10)).isoformat()
    lookups = iter([MagicMock(data={"id": "s"}), MagicMock(data=None),          # shop, no subscription yet
                    MagicMock(data={"status": "active", "expires_at": end})])   # ... now there is one
    with patch.object(ss, "execute_one", side_effect=lambda q: next(lookups)), patch.object(ss, "supabase") as db:
        db.table.return_value.insert.return_value.execute.side_effect = Exception("duplicate key value (23505)")
        db.table.return_value.update.return_value.eq.return_value.eq.return_value.execute.return_value = \
            MagicMock(data=[{"shop_id": "shop-1"}])
        out = ss.create_or_renew_subscription("shop-1", "o", SubscriptionCreate(plan="basic", duration_days=30))
    written = db.table.return_value.update.call_args[0][0]
    assert out["has_active_subscription"]
    assert datetime.fromisoformat(written["expires_at"]) > datetime.fromisoformat(end) + timedelta(days=29)


# ── One shop per owner, even with a double tap ───────────────────────────────────────────

def test_double_tap_on_create_shop_makes_one_shop():
    from app.schemas.shop import ShopCreate
    from app.services import shop_service
    shops = []

    def lookup(query):
        time.sleep(0.02)
        return MagicMock(data=shops[0] if shops else None)

    def insert(row):
        time.sleep(0.05)
        shops.append({**row, "id": f"shop-{len(shops) + 1}"})
        return MagicMock(execute=MagicMock(return_value=MagicMock(data=[shops[-1]])))

    body = ShopCreate(name="Cut", category="Salon", address="A", city="Akola", state="Maharashtra")
    with patch.object(shop_service, "execute_one", side_effect=lookup), \
         patch.object(shop_service, "supabase") as db, \
         patch.object(shop_service, "get_shop", side_effect=lambda sid: {"id": sid}):
        db.table.return_value.insert.side_effect = insert
        results = _together(3, lambda: shop_service.create_shop("owner-1", body))
    assert len(shops) == 1
    assert sum(isinstance(r, HTTPException) and r.status_code == 400 for r in results) == 2


def test_database_duplicate_is_reported_as_already_have_a_shop():
    from app.schemas.shop import ShopCreate
    from app.services import shop_service
    body = ShopCreate(name="Cut", category="Salon", address="A", city="Akola", state="Maharashtra")
    with patch.object(shop_service, "execute_one", return_value=MagicMock(data=None)), \
         patch.object(shop_service, "supabase") as db:
        db.table.return_value.insert.return_value.execute.side_effect = Exception('duplicate key value violates "idx_one_shop_per_owner"')
        with pytest.raises(HTTPException) as e:
            shop_service.create_shop("owner-1", body)
    assert e.value.status_code == 400 and "already have a shop" in e.value.detail


# ── "Next" pressed twice moves the queue once ────────────────────────────────────────────

class TestNextCustomer:
    def _run(self, serving_now, expected):
        from app.services import queue_service as qs
        with patch.object(qs, "_is_owner", return_value=True), \
             patch.object(qs, "_serving_token", return_value=serving_now), \
             patch.object(qs, "_remaining", return_value=4), \
             patch.object(qs, "supabase") as db:
            db.rpc.return_value.execute.return_value = MagicMock(data=[])
            out = qs.advance_queue("shop-1", "owner-1", expected)
        return out, db.rpc

    def test_screen_up_to_date_advances(self):
        out, rpc = self._run(serving_now=7, expected=7)
        rpc.assert_called_once()
        assert not out.get("already_moved")

    def test_second_tap_or_second_device_does_not_advance_again(self):
        out, rpc = self._run(serving_now=8, expected=7)   # someone already moved 7 -> 8
        rpc.assert_not_called()
        assert out["already_moved"] and out["now_serving_token"] == 8

    def test_older_app_without_the_token_still_works(self):
        _, rpc = self._run(serving_now=7, expected=None)
        rpc.assert_called_once()


def test_sql_next_and_skip_lock_before_changing_the_queue():
    sql = open("sql/final_consolidated.sql", encoding="utf-8").read()
    advance = sql[sql.index("CREATE OR REPLACE FUNCTION advance_queue_v2"):sql.index("CREATE OR REPLACE FUNCTION skip_customer_v2")]
    assert "FROM shops WHERE id = p_shop_id FOR UPDATE" in advance
    skip = sql[sql.index("CREATE OR REPLACE FUNCTION skip_customer_v2"):]
    assert "FOR UPDATE" in skip[:skip.index("END;")]
    assert "idx_one_shop_per_owner ON shops(owner_id)" in sql


# ── Staff and schemes ────────────────────────────────────────────────────────────────────

def test_same_staff_name_twice_is_refused():
    from app.services import staff_service
    with patch.object(staff_service, "_is_owner", return_value=True), patch.object(staff_service, "supabase") as db:
        db.table.return_value.select.return_value.eq.return_value.eq.return_value.ilike.return_value \
            .limit.return_value.execute.return_value = MagicMock(data=[{"id": "x"}])
        with pytest.raises(HTTPException) as e:
            staff_service.add_staff_by_name("shop-1", "owner-1", "Rahul")
    assert e.value.status_code == 409
    db.table.return_value.insert.assert_not_called()


# ── Forced app update ────────────────────────────────────────────────────────────────────

@pytest.fixture
def client():
    from app.main import app
    with patch.object(settings, "APP_MIN_BUILD_ANDROID", 5), patch.object(settings, "APP_MIN_BUILD_IOS", 3), \
         patch.object(settings, "APP_STORE_URL_IOS", "https://apps.apple.com/app/id1"):
        yield TestClient(app, raise_server_exceptions=False)


def _app(platform, build):
    return {"X-App-Platform": platform, "X-App-Build": str(build)}


class TestForcedUpdate:
    @pytest.mark.parametrize("platform,build,required", [
        ("android", 4, True), ("android", 5, False), ("android", 9, False), ("ios", 2, True), ("ios", 3, False)])
    def test_version_check(self, client, platform, build, required):
        r = client.get(f"/app/version?platform={platform}&build={build}")
        assert r.status_code == 200 and r.json()["update_required"] is required
        assert r.json()["store_url"].startswith("https://")

    def test_old_build_is_blocked_on_every_call(self, client):
        r = client.get("/shops", headers=_app("android", 4))
        assert r.status_code == 426
        assert r.json()["update_required"] and "play.google.com" in r.json()["store_url"]

    def test_current_build_passes(self, client):
        assert client.get("/", headers=_app("android", 5)).status_code == 200

    @pytest.mark.parametrize("headers", [{}, {"X-App-Platform": "android"}, {"X-App-Build": "1"},
                                         {"X-App-Platform": "android", "X-App-Build": "abc"},
                                         {"X-App-Platform": "web", "X-App-Build": "1"}])
    def test_requests_without_a_valid_app_build_are_not_affected(self, client, headers):
        # Older builds, browsers, Razorpay's webhook and the admin panel send no build header.
        assert client.get("/", headers=headers).status_code == 200

    def test_a_payment_already_in_progress_can_still_finish(self, client):
        r = client.post("/payments/webhook", headers=_app("android", 1), content=b"{}")
        assert r.status_code != 426

    def test_off_by_default(self):
        from app.routers import app_version
        assert settings.APP_MIN_BUILD_ANDROID == 0 and not app_version.update_required("android", 1)
