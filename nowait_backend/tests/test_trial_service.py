"""Tests for trial_service.py — the one-free-month-per-owner rule."""
from datetime import datetime
from unittest.mock import MagicMock, patch

import pytest
from fastapi import HTTPException

from app.services import trial_service


def test_hashes_are_keyed_and_stable():
    a = trial_service._digest("email", "a@b.com")
    assert a == trial_service._digest("email", "a@b.com")
    assert a != trial_service._digest("phone", "a@b.com")      # kind is part of the hash
    assert "a@b.com" not in a                                    # no readable value stored
    assert trial_service._digest("email", None) is None
    assert trial_service._digest("phone", "  ") is None


class TestExactMatchOnly:
    """Only identical emails / mobile numbers count as the same person — no alias tricks."""

    def test_email_is_case_and_space_insensitive_only(self):
        d = trial_service._digest
        assert d("email", "Owner@Example.com ") == d("email", "owner@example.com")

    @pytest.mark.parametrize("other", ["owner+1@example.com", "o.wner@example.com", "owner@example.co"])
    def test_other_emails_are_different_people(self, other):
        assert trial_service._digest("email", other) != trial_service._digest("email", "owner@example.com")

    def test_gmail_dots_and_plus_are_not_collapsed(self):
        d = trial_service._digest
        assert d("email", "a.b@gmail.com") != d("email", "ab@gmail.com")
        assert d("email", "ab+1@gmail.com") != d("email", "ab@gmail.com")

    def test_mobile_numbers_are_compared_as_stored(self):
        d = trial_service._digest
        assert d("phone", "+919834086519") == d("phone", " +919834086519 ")
        assert d("phone", "+919834086519") != d("phone", "09834086519")


class FakeDb:
    """Just enough of the supabase client for trial_service: remembers claims and subscriptions."""

    def __init__(self, profile, claimed_hashes=(), fail_subscription=False):
        self.profile = profile
        self.claimed = set(claimed_hashes)
        self.claims, self.subscriptions, self.deleted_claims = [], [], []
        self.fail_subscription = fail_subscription

    def table(self, name):
        db = self
        t = MagicMock()
        if name == "trial_claims":
            def insert(row):
                def execute():
                    hashes = {h for h in (row["email_hash"], row["phone_hash"]) if h}
                    if hashes & db.claimed:
                        raise Exception("duplicate key value violates unique constraint (code 23505)")
                    db.claimed |= hashes
                    db.claims.append(row)
                    return MagicMock(data=[{"id": "claim-1", **row}])
                return MagicMock(execute=execute)
            t.insert.side_effect = insert

            def or_(expr):
                wanted = {part.split(".eq.", 1)[1] for part in expr.split(",")}
                hit = bool(wanted & db.claimed)
                return MagicMock(limit=lambda n: MagicMock(execute=lambda: MagicMock(data=[{"id": "x"}] if hit else [])))
            t.select.return_value.or_.side_effect = or_
            t.delete.return_value.eq.side_effect = lambda c, v: (db.deleted_claims.append(v), MagicMock(execute=MagicMock()))[1]
        elif name == "subscriptions":
            def insert(row):
                def execute():
                    if db.fail_subscription:
                        raise Exception("db down")
                    db.subscriptions.append(row)
                    return MagicMock(data=[row])
                return MagicMock(execute=execute)
            t.insert.side_effect = insert
        return t


def _run(fn, db, *args):
    with patch.object(trial_service, "supabase", db), \
         patch.object(trial_service, "execute_one", return_value=MagicMock(data=db.profile)):
        return fn(*args)


PROFILE = {"email": "Owner@Example.com", "phone": "+919834086519"}


class TestStartTrial:
    def test_new_owner_gets_30_free_days(self):
        db = FakeDb(PROFILE)
        _run(trial_service.start_trial, db, "shop-1", "owner-1")
        sub = db.subscriptions[0]
        assert sub["plan"] == "trial" and sub["status"] == "active" and sub["shop_id"] == "shop-1"
        days = (datetime.fromisoformat(sub["expires_at"]) - datetime.fromisoformat(sub["started_at"])).days
        assert days == 30

    def test_stores_only_hashes(self):
        db = FakeDb(PROFILE)
        _run(trial_service.start_trial, db, "shop-1", "owner-1")
        assert "example.com" not in str(db.claims[0]) and "9834086519" not in str(db.claims[0])

    def test_same_email_again_is_refused(self):
        first = FakeDb(PROFILE)
        _run(trial_service.start_trial, first, "shop-1", "owner-1")
        # Deleted the account, registered again: same email, different mobile number.
        again = FakeDb({"email": "owner@example.com", "phone": "+919000000001"}, claimed_hashes=first.claimed)
        with pytest.raises(HTTPException) as e:
            _run(trial_service.start_trial, again, "shop-2", "owner-2")
        assert e.value.status_code == 409
        assert again.subscriptions == []

    def test_same_mobile_again_is_refused(self):
        first = FakeDb(PROFILE)
        _run(trial_service.start_trial, first, "shop-1", "owner-1")
        again = FakeDb({"email": "other@example.com", "phone": "+919834086519"}, claimed_hashes=first.claimed)
        with pytest.raises(HTTPException) as e:
            _run(trial_service.start_trial, again, "shop-2", "owner-2")
        assert e.value.status_code == 409
        assert again.subscriptions == []

    def test_genuinely_new_person_still_gets_a_trial(self):
        first = FakeDb(PROFILE)
        _run(trial_service.start_trial, first, "shop-1", "owner-1")
        other = FakeDb({"email": "new@example.com", "phone": "+919111111111"}, claimed_hashes=first.claimed)
        _run(trial_service.start_trial, other, "shop-2", "owner-2")
        assert len(other.subscriptions) == 1

    def test_failed_grant_gives_the_free_month_back(self):
        db = FakeDb(PROFILE, fail_subscription=True)
        with pytest.raises(HTTPException) as e:
            _run(trial_service.start_trial, db, "shop-1", "owner-1")
        assert e.value.status_code == 500
        assert db.deleted_claims == ["claim-1"]         # claim released so they can still get it

    def test_profile_without_contact_details_is_refused(self):
        db = FakeDb({"email": None, "phone": None})
        with pytest.raises(HTTPException) as e:
            _run(trial_service.start_trial, db, "shop-1", "owner-1")
        assert e.value.status_code == 400
        assert db.claims == []


class TestIsEligible:
    def test_true_for_someone_new(self):
        assert _run(trial_service.is_eligible, FakeDb(PROFILE), "owner-1") is True

    def test_false_once_the_email_was_used(self):
        first = FakeDb(PROFILE)
        _run(trial_service.start_trial, first, "shop-1", "owner-1")
        again = FakeDb({"email": "owner@example.com", "phone": "+919000000001"}, claimed_hashes=first.claimed)
        assert _run(trial_service.is_eligible, again, "owner-2") is False

    def test_false_once_the_mobile_was_used(self):
        first = FakeDb(PROFILE)
        _run(trial_service.start_trial, first, "shop-1", "owner-1")
        again = FakeDb({"email": "other@example.com", "phone": "+919834086519"}, claimed_hashes=first.claimed)
        assert _run(trial_service.is_eligible, again, "owner-2") is False

    def test_false_when_the_check_itself_fails(self):
        db = FakeDb(PROFILE)
        with patch.object(trial_service, "supabase", db), \
             patch.object(trial_service, "execute_one", side_effect=Exception("db down")):
            assert trial_service.is_eligible("owner-1") is False


class TestStartFreeTrialEndpointLogic:
    """subscription_service.start_free_trial: ownership + 'never subscribed' guards."""

    def _call(self, shop_row, sub_row):
        from app.services import subscription_service as ss
        rows = iter([MagicMock(data=shop_row), MagicMock(data=sub_row)])
        with patch.object(ss, "execute_one", side_effect=lambda q: next(rows)), \
             patch.object(ss, "supabase", MagicMock()), \
             patch.object(ss.trial_service, "start_trial") as start, \
             patch.object(ss, "get_subscription", return_value={"has_active_subscription": True}) as get:
            return ss.start_free_trial("shop-1", "owner-1"), start, get

    def test_starts_for_a_shop_that_never_subscribed(self):
        res, start, _ = self._call({"id": "shop-1"}, None)
        start.assert_called_once_with("shop-1", "owner-1")
        assert res == {"has_active_subscription": True}

    def test_refuses_someone_elses_shop(self):
        with pytest.raises(HTTPException) as e:
            self._call(None, None)
        assert e.value.status_code == 403

    def test_refuses_a_shop_that_already_has_a_plan(self):
        with pytest.raises(HTTPException) as e:
            self._call({"id": "shop-1"}, {"id": "sub-1"})
        assert e.value.status_code == 400
