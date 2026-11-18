"""Elite Promotion announcement: once per paid Featured Promotion (new or extension, 3 / 7 / 15
days), after the payment, to the shop's city only. Schemes never notify anyone."""
from datetime import datetime, timedelta, timezone
from unittest.mock import MagicMock, patch

import pytest

from app.routers import payments
from app.schemas.promotion import PromotionCreate
from app.services import promotion_service, push_service
from tests.conftest import make_chain, ok, ok_list

SHOP = {"id": "s1", "name": "Jai Salon", "city": "Pune", "owner_id": "o1"}


class FakeDb:
    """Records every table call; answers per table."""
    def __init__(self, scheme=None, customers=("c1", "c2")):
        self.calls = []  # (table, method, args)
        self.inserts = []
        self.answers = {
            "shops": SHOP,
            "promotions": [{"title": scheme}] if scheme else [],
            "profiles": [{"id": c} for c in customers],
        }

    def table(self, name):
        chain = make_chain()
        def record(method):
            def fn(*args, **kwargs):
                self.calls.append((name, method, args))
                if method == "insert":
                    self.inserts.append((name, args[0]))
                return chain
            return fn
        for m in ("select", "eq", "neq", "gt", "ilike", "insert", "order", "limit", "delete"):
            getattr(chain, m).side_effect = record(m)
        def execute():
            data = self.answers.get(name)
            return ok(data) if chain.maybe_single.called else ok_list(data if isinstance(data, list) else [data])
        chain.execute.side_effect = execute
        return chain


def _announce(db):
    with patch.object(promotion_service, "supabase", db), \
         patch("app.database.supabase", db), \
         patch.object(push_service, "notify_users") as push:
        sent = promotion_service._announce_now("s1")
    return sent, push


class TestAnnouncement:
    def test_city_customers_get_it_in_app_and_on_the_phone(self):
        db = FakeDb()
        sent, push = _announce(db)
        assert sent == 2
        (table, rows), = db.inserts
        assert table == "notifications" and [r["user_id"] for r in rows] == ["c1", "c2"]
        row = rows[0]
        assert row["type"] == "promotion" and row["shop_id"] == "s1" and row["shop_name"] == "Jai Salon"
        assert row["title"] == "⭐ Elite Promotion · Jai Salon"
        assert row["body"] == "Now featured in Pune. Open NoWaitt to explore the shop and get your service."
        push.assert_called_once_with(["c1", "c2"], "promotion", row["title"], row["body"], {"shop_id": "s1"})

    def test_only_customers_of_that_city_never_the_owner(self):
        db = FakeDb()
        _announce(db)
        profile_calls = [(m, a) for t, m, a in db.calls if t == "profiles"]
        assert ("ilike", ("city", "Pune")) in profile_calls
        assert ("eq", ("role", "customer")) in profile_calls
        assert ("neq", ("id", "o1")) in profile_calls

    def test_a_running_scheme_shows_offer_active(self):
        db = FakeDb(scheme="20% off haircut")
        _announce(db)
        body = db.inserts[0][1][0]["body"]
        assert body.startswith(promotion_service.OFFER_ACTIVE_PREFIX)
        assert body == "🎁 Offer active: 20% off haircut. Open NoWaitt to explore the shop and get your service."

    def test_no_daily_limit_the_next_payment_is_announced_too(self):
        # e.g. an extension paid an hour later: that payment is announced as well
        for _ in range(2):
            sent, push = _announce(FakeDb())
            assert sent == 2
            push.assert_called_once()

    def test_a_city_name_cannot_act_as_a_wildcard(self):
        db = FakeDb()
        db.answers["shops"] = {**SHOP, "city": "Pu%e_"}
        _announce(db)
        assert ("profiles", "ilike", ("city", "Pu\\%e\\_")) in db.calls

    def test_trouble_never_raises(self):
        db = MagicMock()
        db.table.side_effect = RuntimeError("db down")
        with patch.object(promotion_service, "supabase", db), patch("app.database.supabase", db):
            assert promotion_service._announce_now("s1") == 0

    def test_many_customers_are_saved_in_batches(self):
        db = FakeDb(customers=[f"c{i}" for i in range(1203)])
        sent, _ = _announce(db)
        assert sent == 1203
        assert [len(rows) for _, rows in db.inserts] == [500, 500, 203]


class TestWhenItIsSent:
    def _txn(self, purpose):
        return {"shop_id": "s1", "owner_id": "o1", "purpose": purpose, "metadata": {"days": 7, "plan": "basic", "duration_days": 30}}

    def test_after_a_promotion_payment_is_activated(self):
        with patch.object(payments, "_activate_unlocked", return_value={"id": "p1"}), \
             patch.object(promotion_service, "announce_elite_promotion") as announce:
            payments._activate(self._txn("promotion"))
        announce.assert_called_once_with("s1")

    @pytest.mark.parametrize("days", [3, 7, 15])
    def test_once_per_payment_for_every_length_and_again_for_an_extension(self, days):
        txn = {"shop_id": "s1", "owner_id": "o1", "purpose": "promotion", "metadata": {"days": days}}
        with patch.object(payments.promotion_service, "activate_featured", return_value={"id": "p1"}) as activate, \
             patch.object(promotion_service, "announce_elite_promotion") as announce:
            payments._activate(txn)  # the payment
            assert announce.call_count == 1
            activate.assert_called_with("s1", "o1", days)
            payments._activate(txn)  # owner pays again to extend
            assert announce.call_count == 2

    def test_one_payment_seen_three_times_is_announced_once(self):
        """verify, the webhook and reconcile can all see the same paid order: only the one that
        claims it activates - and so announces."""
        claims = iter([True, False, False])
        txn = {"shop_id": "s1", "owner_id": "o1", "purpose": "promotion", "metadata": {"days": 7},
               "amount_paise": 7000, "razorpay_order_id": "order1"}
        payment = {"id": "pay1", "amount": 7000, "currency": "INR"}
        with patch.object(payments.razorpay_service, "captured_payment_for_order", return_value=payment), \
             patch.object(payments.payment_transaction_service, "claim_paid", side_effect=lambda *a: next(claims)), \
             patch.object(payments.promotion_service, "activate_featured", return_value={"id": "p1"}), \
             patch.object(promotion_service, "announce_elite_promotion") as announce:
            results = [payments._activate_if_paid(txn, source) for source in ("verify", "webhook", "reconcile")]
        assert results[0] is not None and results[1:] == [None, None]
        announce.assert_called_once_with("s1")

    def test_not_for_a_subscription_payment(self):
        with patch.object(payments, "_activate_unlocked", return_value={"id": "sub"}), \
             patch.object(promotion_service, "announce_elite_promotion") as announce:
            payments._activate(self._txn("subscription"))
        announce.assert_not_called()

    def test_not_when_activation_failed(self):
        with patch.object(payments, "_activate_unlocked", side_effect=RuntimeError("boom")), \
             patch.object(promotion_service, "announce_elite_promotion") as announce:
            try:
                payments._activate(self._txn("promotion"))
            except RuntimeError:
                pass
        announce.assert_not_called()

    def test_runs_in_the_background(self):
        with patch.object(promotion_service, "_announce_pool") as pool:
            promotion_service.announce_elite_promotion("s1")
        pool.submit.assert_called_once_with(promotion_service._announce_now, "s1")


class TestSchemesNeverNotify:
    def test_creating_a_scheme_sends_nothing(self):
        db = FakeDb()
        db.answers["promotions"] = [{"id": "sch1", "title": "20% off"}]
        with patch.object(promotion_service, "supabase", db), \
             patch.object(promotion_service, "require_active_subscription"), \
             patch.object(push_service, "notify_users") as push_many, \
             patch.object(push_service, "notify_user") as push_one:
            promotion_service.create_promotion("s1", "o1", PromotionCreate(
                title="20% off", description="Haircuts",
                valid_until=(datetime.now(timezone.utc) + timedelta(days=7)).isoformat()))
        assert [t for t, _ in db.inserts] == ["promotions"]  # no notifications rows
        push_many.assert_not_called()
        push_one.assert_not_called()


class TestPushToMany:
    def test_one_lookup_per_200_and_each_phone_once(self):
        calls = []
        def table(name):
            chain = make_chain()
            def in_(col, ids):
                calls.append(len(ids))
                return chain
            chain.in_.side_effect = in_
            chain.execute.return_value = ok_list([{"fcm_token": "tok-a"}, {"fcm_token": "tok-a"}, {"fcm_token": None}])
            return chain
        sb = MagicMock()
        sb.table.side_effect = table
        jobs = []
        with patch.object(push_service, "enabled", return_value=True), \
             patch.object(push_service, "supabase", sb), \
             patch.object(push_service, "_pool", MagicMock(submit=lambda *a: jobs.append(a))):
            push_service.notify_users([f"u{i}" for i in range(450)], "promotion", "T", "B", {"shop_id": "s1"})
        assert calls == [200, 200, 50]
        assert len(jobs) == 3  # one phone per batch (duplicates and empty codes dropped)
        assert jobs[0][1:] == ("tok-a", "T", "B", {"type": "promotion", "shop_id": "s1"})

    def test_off_without_firebase(self):
        with patch.object(push_service, "_pool") as pool:
            push_service.notify_users(["u1"], "promotion", "T", "B")
        pool.submit.assert_not_called()
