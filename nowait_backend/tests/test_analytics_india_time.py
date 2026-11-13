"""Owner analytics are in India time (times are stored in UTC)."""
from datetime import datetime, timedelta
from unittest.mock import MagicMock, patch

from app.services import analytics_service as an
from tests.conftest import make_chain, ok_list

# 13:30 UTC = 7:00 PM in India, 03:00 UTC = 8:30 AM in India
EVENING_RUSH = ["2026-11-12T13:30:00+00:00", "2026-11-12T13:45:00+00:00", "2026-11-12T14:10:00Z"]
MORNING = ["2026-11-12T03:00:00+00:00"]


def _run(fn, rows, **kw):
    sb = MagicMock()
    sb.table.side_effect = lambda name: make_chain(ok_list(rows if name == "queue_entries" else []))
    with patch.object(an, "supabase", sb), patch.object(an, "_is_owner", return_value=True):
        return fn("shop-1", "owner-1", **kw)


def test_peak_hour_is_the_india_hour():
    rows = [{"status": "completed", "joined_at": t, "service_id": None, "service_ids": []} for t in EVENING_RUSH + MORNING]
    summary = _run(an.get_summary, rows, period="today")
    assert summary["peak_hour"] == 19  # 7 PM in India - not 13 (1 PM, the UTC hour)


def test_hourly_chart_counts_india_hours():
    rows = [{"status": "completed", "joined_at": t} for t in EVENING_RUSH + MORNING]
    hourly = {h["hour"]: h["count"] for h in _run(an.get_hourly_stats, rows, days=7)}
    assert hourly[19] == 3 and hourly[8] == 1
    assert hourly[13] == 0 and hourly[3] == 0  # nothing left on the UTC hours


def test_today_week_month_start_at_india_midnight():
    now_ist = datetime.now(an.IST)
    midnight = now_ist.replace(hour=0, minute=0, second=0, microsecond=0)
    for period, days_back in (("today", 0), ("week", 6), ("month", 29)):
        start = datetime.fromisoformat(an._period_start(period))
        assert start.utcoffset() == timedelta(hours=5, minutes=30)
        assert start == midnight - timedelta(days=days_back), period


def test_custom_dates_are_india_days():
    start, end = an._range_bounds("2026-11-12", "2026-11-12")
    assert start == "2026-11-12T00:00:00+05:30"
    assert end == "2026-11-13T00:00:00+05:30"  # the whole India day, end exclusive
