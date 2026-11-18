"""Speed: independent database queries run at the same time, and the connections stay warm.

Each fake query below takes 0.1 s (about one round trip from the Mumbai server to Supabase in
Singapore), so a screen's time shows whether its queries ran side by side or one after another.
"""
import threading
import time
from unittest.mock import MagicMock, patch

import pytest

from app import database
from app.services import queue_service, shop_service
from tests.conftest import make_chain, ok, ok_list

TRIP = 0.1

SHOP = {"id": "s1", "name": "Jai Salon", "owner_id": "o1", "is_open": True, "queue_paused": False,
        "city": "Pune", "category": "Salon", "avg_wait_minutes": 10, "max_queue_size": None}
ROWS = {
    "shops": [SHOP],
    "subscriptions": [{"id": "sub1", "shop_id": "s1"}],
    "promotions": [{"shop_id": "s1", "title": "Featured Promotion"}],
    "queue_entries": [{"id": "q1", "shop_id": "s1", "user_id": "c1", "token_number": 4, "status": "serving",
                       "service_ids": ["svc1"], "service_id": None, "total_duration_minutes": None}],
    "services": [{"id": "svc1", "shop_id": "s1", "name": "Haircut", "price": 100, "duration_minutes": 20}],
    "profiles": [{"id": "c1", "name": "Asha", "phone": "+919800000000"}],
    "queue_events": [],
}


class SlowDb:
    """Answers like Supabase, but every query takes one round trip. Counts how many run at once."""
    def __init__(self):
        self.running = self.most_at_once = self.queries = 0
        self._lock = threading.Lock()

    def table(self, name):
        chain = make_chain()
        def execute():
            with self._lock:
                self.running += 1
                self.queries += 1
                self.most_at_once = max(self.most_at_once, self.running)
            time.sleep(TRIP)
            with self._lock:
                self.running -= 1
            rows = ROWS.get(name, [])
            return ok(rows[0]) if chain.maybe_single.called else ok_list(rows)
        chain.execute.side_effect = execute
        return chain


@pytest.fixture
def db():
    fake = SlowDb()
    def slow_reviews(*a, **k):
        time.sleep(TRIP)
        return {}
    with patch.object(database, "supabase", fake), \
         patch.object(shop_service, "supabase", fake), \
         patch.object(queue_service, "supabase", fake), \
         patch("app.services.staff_service.supabase", fake), \
         patch.object(shop_service.review_service, "get_batch_review_summaries", side_effect=slow_reviews), \
         patch.object(shop_service.review_service, "get_review_summary",
                      side_effect=lambda sid: (time.sleep(TRIP), {"average_rating": 4.5, "total_reviews": 2})[1]):
        yield fake


def timed(fn):
    start = time.perf_counter()
    out = fn()
    return out, time.perf_counter() - start


class TestRunParallel:
    def test_runs_at_the_same_time_and_keeps_the_order(self):
        out, took = timed(lambda: database.run_parallel(
            lambda: (time.sleep(0.2), "a")[1], lambda: (time.sleep(0.2), "b")[1], lambda: "c"))
        assert out == ["a", "b", "c"]
        assert took < 0.35  # one after another would be 0.4 s

    def test_an_error_is_raised_like_before(self):
        def boom():
            raise ValueError("db down")
        with pytest.raises(ValueError, match="db down"):
            database.run_parallel(lambda: 1, boom)

    def test_single_call_runs_directly(self):
        assert database.run_parallel(lambda: 7) == [7]


class TestScreensAreFaster:
    def test_shop_list_waits_two_trips_not_six(self, db):
        out, took = timed(lambda: shop_service.list_shops(city="Pune"))
        shop = out["shops"][0]
        assert shop["has_active_subscription"] and shop["is_promoted"] and shop["queue_count"] == 1
        assert shop["now_serving_token"] == 4 and shop["min_service_price"] == 100.0
        assert db.most_at_once >= 4
        assert took < 3.5 * TRIP  # was 6 trips one after another

    def test_shop_page_waits_two_trips_not_six(self, db):
        out, took = timed(lambda: shop_service.get_shop("s1"))
        assert out["services"][0]["name"] == "Haircut"
        assert out["avg_review_rating"] == 4.5 and out["review_count"] == 2 and out["rating"] == 4.5
        assert out["has_active_subscription"] and out["is_promoted"] and out["queue_count"] == 1
        assert took < 3.5 * TRIP

    def test_owner_shop_reuses_the_row_it_already_has(self, db):
        out, took = timed(lambda: shop_service.get_owner_shop("o1"))
        assert out["id"] == "s1" and out["services"]
        assert took < 4 * TRIP  # owner lookup + one parallel round (was 7 trips)

    def test_owner_live_queue(self, db):
        out, took = timed(lambda: queue_service.get_shop_queue("s1", "o1"))
        item = out["queue"][0]
        assert item["customer_name"] == "Asha" and item["service_names"] == ["Haircut"]
        assert out["now_serving_token"] == 4
        assert took < 3.5 * TRIP  # was 5 trips one after another

    def test_owner_live_queue_still_checks_the_owner_first(self, db):
        from fastapi import HTTPException
        with patch.object(queue_service, "_is_owner", return_value=False):
            with pytest.raises(HTTPException) as e:
                queue_service.get_shop_queue("s1", "someone-else")
        assert e.value.status_code == 403

    def test_customer_queue_view(self, db):
        out, took = timed(lambda: queue_service.get_public_shop_queue("s1"))
        assert out["queue"][0]["service_names"] == ["Haircut"]
        assert took < 2.5 * TRIP


class TestKeepWarm:
    def test_pings_several_connections_at_once(self):
        fake = SlowDb()
        with patch.object(database, "supabase", fake):
            _, took = timed(database.keep_warm_once)
        assert fake.queries == database.KEEP_WARM_CONNECTIONS
        assert fake.most_at_once > 1 and took < 2 * TRIP

    def test_a_failed_ping_never_raises(self):
        sb = MagicMock()
        sb.table.side_effect = RuntimeError("network down")
        with patch.object(database, "supabase", sb):
            database.keep_warm_once()  # no exception

    def test_connections_are_kept_for_a_minute(self):
        session = database._create_session(None, "https://x.supabase.co/rest/v1", {}, 10)
        assert session._transport._pool._keepalive_expiry == 60
        session.close()
