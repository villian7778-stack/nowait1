"""Estimated income in the analytics summary: sum of the services customers picked, on completed visits."""
from datetime import datetime, timedelta, timezone
from unittest.mock import MagicMock, patch

import pytest
from fastapi import HTTPException

from app.services import analytics_service as an


class FakeTable:
    """Every query-builder call returns itself; execute() returns the rows for that table."""

    def __init__(self, rows):
        self.rows = rows

    def __getattr__(self, name):
        return lambda *a, **k: self

    def execute(self):
        return MagicMock(data=self.rows)


class FakeDb:
    def __init__(self, entries, services):
        self.tables = {"queue_entries": entries, "services": services}

    def table(self, name):
        return FakeTable(self.tables[name])


NOW = datetime.now(timezone.utc).isoformat()
SERVICES = [
    {"id": "haircut", "price": 150},
    {"id": "beard", "price": 80},
    {"id": "colour", "price": "500.00"},   # PostgREST may send DECIMAL as a string-like number
]


def entry(status, ids=None, single=None):
    return {"status": status, "joined_at": NOW, "service_ids": ids or [], "service_id": single}


def summary(entries, services=SERVICES, **kw):
    with patch.object(an, "supabase", FakeDb(entries, services)), patch.object(an, "_is_owner", return_value=True):
        return an.get_summary("shop-1", "owner-1", **kw)


class TestEstimatedIncome:
    def test_adds_up_every_service_of_every_completed_visit(self):
        s = summary([
            entry("completed", ["haircut"]),                     # 150
            entry("completed", ["haircut", "beard"]),            # 230
            entry("completed", ["colour"]),                      # 500
        ])
        assert s["estimated_income"] == 880
        assert s["total_served"] == 3

    def test_only_completed_visits_count(self):
        s = summary([
            entry("completed", ["haircut"]),
            entry("cancelled", ["colour"]),
            entry("skipped", ["colour"]),
            entry("waiting", ["colour"]),
            entry("serving", ["colour"]),
        ])
        assert s["estimated_income"] == 150
        assert (s["total_served"], s["total_cancelled"], s["total_skipped"]) == (1, 1, 1)

    def test_older_entries_with_a_single_service_id_are_counted(self):
        assert summary([entry("completed", [], single="beard")])["estimated_income"] == 80

    def test_a_visit_with_no_service_adds_nothing(self):
        assert summary([entry("completed", [])])["estimated_income"] == 0

    def test_a_deleted_service_cannot_be_priced_and_counts_as_zero(self):
        assert summary([entry("completed", ["haircut", "gone-service"])])["estimated_income"] == 150

    def test_no_visits_at_all(self):
        s = summary([])
        assert s["estimated_income"] == 0 and s["total_served"] == 0

    def test_decimal_prices_add_up_to_paise(self):
        s = summary([entry("completed", ["x"])] * 3, services=[{"id": "x", "price": 33.33}])
        assert s["estimated_income"] == 99.99

    def test_works_with_a_custom_date_range(self):
        today = datetime.now(timezone.utc).strftime("%Y-%m-%d")
        s = summary([entry("completed", ["haircut"])], from_date=today, to_date=today)
        assert s["period"] == "custom" and s["estimated_income"] == 150

    def test_the_services_table_is_not_read_when_nobody_was_served(self):
        db = FakeDb([entry("cancelled", ["haircut"])], services=[])
        db.table = MagicMock(side_effect=lambda name: FakeTable(db.tables[name]))
        with patch.object(an, "supabase", db), patch.object(an, "_is_owner", return_value=True):
            an.get_summary("shop-1", "owner-1")
        assert [c.args[0] for c in db.table.call_args_list] == ["queue_entries"]

    def test_only_the_owner_can_see_income(self):
        with patch.object(an, "supabase", FakeDb([], [])), patch.object(an, "_is_owner", return_value=False):
            with pytest.raises(HTTPException) as e:
                an.get_summary("shop-1", "someone-else")
        assert e.value.status_code == 403
