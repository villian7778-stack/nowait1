"""Rules the app also follows, enforced again on the server so a modified app or a direct API call
can't get around them."""
from unittest.mock import MagicMock, patch

import pytest
from fastapi import HTTPException

from app.schemas.shop import ShopCreate, ShopUpdate
from app.services import queue_service, shop_service
from tests.conftest import make_chain, ok, ok_list


class TestJoinOnlyWithTheShopsOwnServices:
    """The owner's estimated income and the wait estimate come from the services picked when
    joining, so they must be this shop's own."""

    def _join(self, offered_ids, picked_ids):
        sb = MagicMock()
        sb.table.side_effect = lambda name: make_chain(ok_list([{"id": i} for i in offered_ids]))
        sb.rpc.return_value = make_chain(ok({"id": "q1"}))
        with patch.object(queue_service, "supabase", sb), \
             patch.object(queue_service, "execute_one", return_value=ok({"avg_wait_minutes": 10, "category": "Salon"})), \
             patch.object(queue_service, "_check_queue_ban"), \
             patch.object(queue_service, "_check_existing_active_queue"), \
             patch.object(queue_service, "_calculate_total_duration", return_value=30):
            try:
                queue_service.join_queue("shop-1", "cust-1", service_ids=picked_ids)
            except HTTPException as e:
                return e, sb
            except Exception:
                pass  # the rest of join (after the RPC) isn't what this test is about
        return None, sb

    def test_another_shops_service_is_refused_before_joining(self):
        err, sb = self._join(offered_ids=["s-own"], picked_ids=["s-own", "s-other-shop"])
        assert err is not None and err.status_code == 400
        sb.rpc.assert_not_called()  # never reached the queue

    def test_made_up_service_is_refused(self):
        err, sb = self._join(offered_ids=[], picked_ids=["not-a-real-service"])
        assert err is not None and err.status_code == 400
        sb.rpc.assert_not_called()

    def test_own_services_join_normally(self):
        err, sb = self._join(offered_ids=["s1", "s2"], picked_ids=["s1", "s2"])
        assert err is None
        sb.rpc.assert_called_once()

    def test_joining_without_services_still_works(self):
        err, sb = self._join(offered_ids=[], picked_ids=[])
        assert err is None
        sb.rpc.assert_called_once()


class TestShopPhotosOnlyByUpload:
    def test_create_ignores_photo_addresses_sent_with_the_form(self):
        inserted = {}

        def table(name):
            chain = make_chain(ok_list([{"id": "shop-1"}]))
            chain.insert.side_effect = lambda row: (inserted.update(row), chain)[1]
            return chain

        sb = MagicMock()
        sb.table.side_effect = table
        data = ShopCreate(name="Shop", category="Salon", address="Road", city="Pune",
                          images=["https://example.com/anything.jpg"])
        with patch.object(shop_service, "supabase", sb), \
             patch.object(shop_service, "execute_one", return_value=ok(None)), \
             patch.object(shop_service, "get_shop", return_value={"id": "shop-1"}):
            try:
                shop_service._create_shop_locked("owner-1", data)
            except Exception:
                pass
        assert inserted.get("images") == []

    def _update(self, current, new):
        sb = MagicMock()
        sb.table.side_effect = lambda name: make_chain(ok_list([{"id": "shop-1"}]))
        with patch.object(shop_service, "supabase", sb), \
             patch.object(shop_service, "execute_one", return_value=ok({"id": "shop-1", "images": current})), \
             patch.object(shop_service, "get_shop", return_value={"id": "shop-1"}):
            return shop_service.update_shop("shop-1", "owner-1", ShopUpdate(images=new))

    def test_update_cannot_add_an_outside_photo(self):
        with pytest.raises(HTTPException) as e:
            self._update(["https://store/shop-1/a.jpg"], ["https://store/shop-1/a.jpg", "https://evil.example/x.jpg"])
        assert e.value.status_code == 400

    def test_update_can_remove_and_reorder_existing_photos(self):
        current = ["https://store/shop-1/a.jpg", "https://store/shop-1/b.jpg"]
        assert self._update(current, [current[1]]) == {"id": "shop-1"}
        assert self._update(current, list(reversed(current))) == {"id": "shop-1"}
