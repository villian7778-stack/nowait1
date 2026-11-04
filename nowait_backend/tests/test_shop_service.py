"""Tests for shop_service.py — list_shops batching, can_accept_queue, enrich."""
from unittest.mock import MagicMock, patch
import pytest

from tests.conftest import make_shop, make_chain, ok, ok_list


def _make_list_chain(results: list):
    """Return a chain whose execute() calls go through results in order; calls past the end
    (e.g. the service-price query, when a test doesn't care about it) return no rows."""
    idx = [0]

    def _exec():
        r = results[idx[0]] if idx[0] < len(results) else ok_list([])
        idx[0] += 1
        return r

    chain = make_chain()
    chain.execute.side_effect = _exec
    return chain


class TestListShops:
    def test_returns_empty_when_no_shops(self):
        from app.services import shop_service

        chain = _make_list_chain([ok_list([])])
        with patch("app.services.shop_service.supabase") as mock_sup:
            mock_sup.table = chain.table
            result = shop_service.list_shops(city="Pune")
        assert result == {"shops": [], "total": 0}

    def test_uses_exactly_five_db_queries(self):
        """list_shops should fire exactly 5 queries however many shops there are:
        shops + subs + promos + queue + service prices (reviews go through review_service)."""
        from app.services import shop_service
        shop = make_shop()

        results = [ok_list([shop]), ok_list([]), ok_list([]), ok_list([]), ok_list([])]
        chain = _make_list_chain(results)

        with patch("app.services.shop_service.supabase") as mock_sup, \
                patch.object(shop_service.review_service, "get_batch_review_summaries", return_value={}):
            mock_sup.table = chain.table
            shop_service.list_shops(city="Pune")

        assert chain.execute.call_count == 5

    def test_service_price_range_per_shop(self):
        """Cheapest and dearest service per shop, for the app's "Sort by price"; None without services."""
        from app.services import shop_service
        a = {**make_shop(), "id": "a"}
        b = {**make_shop(), "id": "b"}
        prices = [{"shop_id": "a", "price": 20}, {"shop_id": "a", "price": 10},
                  {"shop_id": "a", "price": 30.5}]
        chain = _make_list_chain([ok_list([a, b]), ok_list([]), ok_list([]), ok_list([]), ok_list(prices)])

        with patch("app.services.shop_service.supabase") as mock_sup, \
                patch.object(shop_service.review_service, "get_batch_review_summaries", return_value={}):
            mock_sup.table = chain.table
            out = {s["id"]: s for s in shop_service.list_shops()["shops"]}

        assert (out["a"]["min_service_price"], out["a"]["max_service_price"]) == (10.0, 30.5)
        assert out["b"]["min_service_price"] is None and out["b"]["max_service_price"] is None

    def test_can_accept_queue_false_when_paused(self):
        from app.services import shop_service
        shop = {**make_shop(), "is_open": True, "queue_paused": True}

        results = [
            ok_list([shop]),
            ok_list([{"shop_id": shop["id"]}]),  # active sub
            ok_list([]),
            ok_list([]),
        ]
        chain = _make_list_chain(results)

        with patch("app.services.shop_service.supabase") as mock_sup:
            mock_sup.table = chain.table
            result = shop_service.list_shops()

        assert result["shops"][0]["can_accept_queue"] is False

    def test_can_accept_queue_false_when_closed(self):
        from app.services import shop_service
        shop = {**make_shop(), "is_open": False}

        results = [ok_list([shop]), ok_list([{"shop_id": shop["id"]}]), ok_list([]), ok_list([])]
        chain = _make_list_chain(results)

        with patch("app.services.shop_service.supabase") as mock_sup:
            mock_sup.table = chain.table
            result = shop_service.list_shops()

        assert result["shops"][0]["can_accept_queue"] is False

    def test_can_accept_queue_true_when_open_subscribed_not_paused(self):
        from app.services import shop_service
        shop = {**make_shop(), "is_open": True, "queue_paused": False}

        results = [ok_list([shop]), ok_list([{"shop_id": shop["id"]}]), ok_list([]), ok_list([])]
        chain = _make_list_chain(results)

        with patch("app.services.shop_service.supabase") as mock_sup:
            mock_sup.table = chain.table
            result = shop_service.list_shops()

        assert result["shops"][0]["can_accept_queue"] is True

    def test_queue_count_aggregated_correctly(self):
        from app.services import shop_service
        shop = make_shop()
        queue_entries = [
            {"shop_id": shop["id"], "token_number": 1, "status": "serving"},
            {"shop_id": shop["id"], "token_number": 2, "status": "waiting"},
            {"shop_id": shop["id"], "token_number": 3, "status": "waiting"},
        ]

        results = [ok_list([shop]), ok_list([]), ok_list([]), ok_list(queue_entries)]
        chain = _make_list_chain(results)

        with patch("app.services.shop_service.supabase") as mock_sup:
            mock_sup.table = chain.table
            result = shop_service.list_shops()

        s = result["shops"][0]
        assert s["queue_count"] == 3
        assert s["now_serving_token"] == 1

    def test_is_promoted_from_featured_promotion(self):
        from app.services import shop_service
        shop = make_shop()
        promos = [{"shop_id": shop["id"], "title": "Featured Promotion"}]

        results = [ok_list([shop]), ok_list([]), ok_list(promos), ok_list([])]
        chain = _make_list_chain(results)

        with patch("app.services.shop_service.supabase") as mock_sup:
            mock_sup.table = chain.table
            result = shop_service.list_shops()

        assert result["shops"][0]["is_promoted"] is True


class TestEnrichShop:
    def test_can_accept_queue_false_when_paused(self):
        from app.services import shop_service
        shop = {**make_shop(), "is_open": True, "queue_paused": True}

        with patch("app.services.shop_service._has_active_subscription", return_value=True), \
             patch("app.services.shop_service._get_active_promotions", return_value=[]), \
             patch("app.services.shop_service._get_queue_stats", return_value={"queue_count": 0, "now_serving_token": None}):
            enriched = shop_service._enrich_shop(shop)

        assert enriched["can_accept_queue"] is False

    def test_can_accept_queue_true_when_all_conditions_met(self):
        from app.services import shop_service
        shop = {**make_shop(), "is_open": True, "queue_paused": False}

        with patch("app.services.shop_service._has_active_subscription", return_value=True), \
             patch("app.services.shop_service._get_active_promotions", return_value=[]), \
             patch("app.services.shop_service._get_queue_stats", return_value={"queue_count": 0, "now_serving_token": None}):
            enriched = shop_service._enrich_shop(shop)

        assert enriched["can_accept_queue"] is True


class TestCategoriesAndCities:
    def test_get_categories_deduplicates_and_sorts(self):
        from app.services import shop_service

        chain = make_chain(ok_list([
            {"category": "Salon"},
            {"category": "Hospital"},
            {"category": "Salon"},
            {"category": "Barbershop"},
        ]))
        with patch("app.services.shop_service.supabase") as mock_sup:
            mock_sup.table = chain.table
            cats = shop_service.get_categories()

        assert cats == ["Barbershop", "Hospital", "Salon"]

    def test_get_cities_strips_whitespace_and_sorts(self):
        from app.services import shop_service

        chain = make_chain(ok_list([
            {"city": " Mumbai "},
            {"city": "Pune"},
            {"city": "Mumbai"},
            {"city": ""},
        ]))
        with patch("app.services.shop_service.supabase") as mock_sup:
            mock_sup.table = chain.table
            cities = shop_service.get_cities()

        assert "Mumbai" in cities
        assert "Pune" in cities
        assert "" not in cities


class TestUnsubscribedShopsLookClosed:
    def _run(self, subscribed_ids, **kw):
        from app.services import shop_service

        shops = [{"id": "a", "is_open": True, "queue_paused": False}, {"id": "b", "is_open": True, "queue_paused": False}]
        results = {
            "shops": ok_list(shops),
            "subscriptions": ok_list([{"shop_id": i} for i in subscribed_ids]),
            "promotions": ok_list([]),
            "queue_entries": ok_list([]),
            "services": ok_list([]),
        }
        with patch.object(shop_service, "supabase") as sb, \
                patch.object(shop_service.review_service, "get_batch_review_summaries", return_value={}):
            sb.table.side_effect = lambda name: make_chain(results[name])
            return shop_service.list_shops(**kw)["shops"]

    def test_cancelled_or_expired_shop_is_reported_unsubscribed_and_closed(self):
        out = {s["id"]: s for s in self._run(["a"])}
        assert out["a"]["has_active_subscription"] and out["a"]["is_open"]
        assert not out["b"]["has_active_subscription"]
        assert out["b"]["is_open"] is False
        assert out["b"]["can_accept_queue"] is False

    def test_open_only_leaves_unsubscribed_shops_out(self):
        assert [s["id"] for s in self._run(["a"], open_only=True)] == ["a"]
