"""Tests for staff_service.py."""
from unittest.mock import MagicMock, patch
import pytest

from tests.conftest import make_staff_member, make_chain, ok, ok_list


class TestGetStaffPublic:
    def test_returns_active_staff_list(self):
        from app.services import staff_service

        sm = make_staff_member()
        chain = make_chain(ok_list([sm]))

        with patch("app.services.staff_service.supabase") as mock_sup:
            mock_sup.table = chain.table
            result = staff_service.get_staff_public("shop-001")

        assert len(result) == 1
        assert result[0]["display_name"] == "Rahul"

    def test_returns_empty_when_no_staff(self):
        from app.services import staff_service

        chain = make_chain(ok_list([]))

        with patch("app.services.staff_service.supabase") as mock_sup:
            mock_sup.table = chain.table
            result = staff_service.get_staff_public("shop-001")

        assert result == []


class TestAddStaffByName:
    def test_raises_403_if_not_owner(self):
        from app.services import staff_service
        from fastapi import HTTPException

        with patch("app.services.staff_service._is_owner", return_value=False):
            with pytest.raises(HTTPException) as exc:
                staff_service.add_staff_by_name("shop-001", "not-owner", "Rahul")
            assert exc.value.status_code == 403

    def test_raises_400_if_name_empty(self):
        from app.services import staff_service
        from fastapi import HTTPException

        with patch("app.services.staff_service._is_owner", return_value=True):
            with pytest.raises(HTTPException) as exc:
                staff_service.add_staff_by_name("shop-001", "owner-001", "   ")
            assert exc.value.status_code == 400

    def test_virtual_staff_has_none_user_id(self):
        """Virtual staff must use user_id=None to avoid FK violation on profiles(id)."""
        from app.services import staff_service

        inserted = []

        def fake_insert(data):
            inserted.append(data)
            chain = make_chain(ok_list([{**data, "id": "sm-new-001"}]))
            return chain

        chain = make_chain(ok_list([]))
        chain.insert.side_effect = fake_insert

        with patch("app.services.staff_service._is_owner", return_value=True), \
             patch("app.services.staff_service.supabase") as mock_sup:
            mock_sup.table = chain.table
            staff_service.add_staff_by_name("shop-001", "owner-001", "  Priya  ")

        assert len(inserted) == 1
        assert inserted[0]["display_name"] == "Priya"
        assert inserted[0]["is_owner_staff"] is False
        assert inserted[0]["is_active"] is True
        # user_id must be None — no FK to profiles table
        assert inserted[0].get("user_id") is None

    def test_result_has_display_name_and_empty_phone(self):
        from app.services import staff_service

        sm_row = make_staff_member(name="Priya")

        def fake_insert(data):
            chain = make_chain(ok_list([sm_row]))
            return chain

        chain = make_chain(ok_list([]))
        chain.insert.side_effect = fake_insert

        with patch("app.services.staff_service._is_owner", return_value=True), \
             patch("app.services.staff_service.supabase") as mock_sup:
            mock_sup.table = chain.table
            result = staff_service.add_staff_by_name("shop-001", "owner-001", "Priya")

        assert result["display_name"] == "Priya"
        assert result["phone"] == ""


class TestRemoveStaff:
    def test_raises_403_if_not_owner(self):
        from app.services import staff_service
        from fastapi import HTTPException

        with patch("app.services.staff_service._is_owner", return_value=False):
            with pytest.raises(HTTPException) as exc:
                staff_service.remove_staff("shop-001", "not-owner", "staff-uid")
            assert exc.value.status_code == 403

    def test_raises_400_if_removing_owner_staff(self):
        from app.services import staff_service
        from fastapi import HTTPException

        sm = {"id": "sm-001", "is_owner_staff": True}
        with patch("app.services.staff_service._is_owner", return_value=True), \
             patch("app.services.staff_service.execute_one", return_value=MagicMock(data=sm)):
            with pytest.raises(HTTPException) as exc:
                staff_service.remove_staff("shop-001", "owner-001", "owner-001")
            assert exc.value.status_code == 400

    def test_raises_404_if_staff_not_found(self):
        from app.services import staff_service
        from fastapi import HTTPException

        with patch("app.services.staff_service._is_owner", return_value=True), \
             patch("app.services.staff_service.execute_one", return_value=MagicMock(data=None)):
            with pytest.raises(HTTPException) as exc:
                staff_service.remove_staff("shop-001", "owner-001", "missing-uid")
            assert exc.value.status_code == 404

    def test_soft_deletes_staff(self):
        from app.services import staff_service

        sm = {"id": "sm-001", "is_owner_staff": False}
        updates = []
        chain = make_chain(ok_list([]))
        chain.update.side_effect = lambda data: updates.append(data) or chain

        with patch("app.services.staff_service._is_owner", return_value=True), \
             patch("app.services.staff_service.execute_one", return_value=MagicMock(data=sm)), \
             patch("app.services.staff_service.supabase") as mock_sup:
            mock_sup.table = chain.table
            result = staff_service.remove_staff("shop-001", "owner-001", "staff-uid")

        assert any(u.get("is_active") is False for u in updates)
        assert result["id"] == "staff-uid"   # removal is by staff_members.id


class TestSelfRegisterAsStaff:
    def test_raises_404_if_no_shop(self):
        from app.services import staff_service
        from fastapi import HTTPException

        with patch("app.services.staff_service.execute_one", return_value=MagicMock(data=None)):
            with pytest.raises(HTTPException) as exc:
                staff_service.self_register_as_staff("owner-001")
            assert exc.value.status_code == 404

    def test_returns_already_registered_if_active(self):
        from app.services import staff_service

        results = iter([
            MagicMock(data={"id": "shop-001", "name": "Raj Salon"}),
            MagicMock(data={"name": "Raj"}),
            MagicMock(data={"id": "sm-001", "is_active": True}),
        ])
        with patch("app.services.staff_service.execute_one", side_effect=lambda q: next(results)):
            result = staff_service.self_register_as_staff("owner-001")

        assert "Already registered" in result["message"]

    def test_inserts_owner_staff_entry(self):
        from app.services import staff_service

        inserted = []
        results = iter([
            MagicMock(data={"id": "shop-001", "name": "Raj Salon"}),
            MagicMock(data={"name": "Raj"}),
            MagicMock(data=None),  # not yet registered
        ])

        def fake_insert(data):
            inserted.append(data)
            return make_chain(ok_list([{"id": "sm-new"}]))

        chain = make_chain(ok_list([]))
        chain.insert.side_effect = fake_insert

        with patch("app.services.staff_service.execute_one", side_effect=lambda q: next(results)), \
             patch("app.services.staff_service.supabase") as mock_sup:
            mock_sup.table = chain.table
            result = staff_service.self_register_as_staff("owner-001")

        assert len(inserted) == 1
        assert inserted[0]["is_owner_staff"] is True
        assert result["message"] == "Registered as staff"


class TestIsOwner:
    """Staff are informational only; the single access check is "is this the shop's owner"."""

    def test_true_when_the_shop_belongs_to_the_user(self):
        from app.services import staff_service
        with patch("app.services.staff_service.execute_one", return_value=MagicMock(data={"id": "shop-001"})):
            assert staff_service._is_owner("shop-001", "owner-001") is True

    def test_false_for_anyone_else(self):
        from app.services import staff_service
        with patch("app.services.staff_service.execute_one", return_value=MagicMock(data=None)):
            assert staff_service._is_owner("shop-001", "random-uid") is False
