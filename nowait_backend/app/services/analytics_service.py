from datetime import datetime, timedelta, timezone
from typing import Optional

from fastapi import HTTPException

from app.database import supabase
from app.services.staff_service import _is_owner


def _period_start(period: str) -> str:
    now = datetime.now(timezone.utc)
    if period == "today":
        start = now.replace(hour=0, minute=0, second=0, microsecond=0)
    elif period == "week":
        start = now - timedelta(days=7)
    elif period == "month":
        start = now - timedelta(days=30)
    else:
        start = now.replace(hour=0, minute=0, second=0, microsecond=0)
    return start.isoformat()


def get_summary(shop_id: str, actor_id: str, period: str = "today") -> dict:
    if not _is_owner(shop_id, actor_id):
        raise HTTPException(status_code=403, detail="Not authorized")

    since = _period_start(period)

    result = (
        supabase.table("queue_entries")
        .select("status, joined_at")
        .eq("shop_id", shop_id)
        .gte("joined_at", since)
        .execute()
    )
    entries = result.data or []

    total_joined = len(entries)
    total_served = sum(1 for e in entries if e["status"] == "completed")
    total_cancelled = sum(1 for e in entries if e["status"] == "cancelled")
    total_skipped = sum(1 for e in entries if e["status"] == "skipped")

    # actual_service_minutes column does not exist in schema; avg derived from shop settings instead
    avg_service = None

    cancel_rate = round(total_cancelled / total_joined * 100, 1) if total_joined else 0
    skip_rate = round(total_skipped / total_joined * 100, 1) if total_joined else 0

    # Peak hour: hour with most joins
    hour_counts: dict[int, int] = {}
    for e in entries:
        try:
            hour = datetime.fromisoformat(e["joined_at"].replace("Z", "+00:00")).hour
            hour_counts[hour] = hour_counts.get(hour, 0) + 1
        except Exception:
            pass
    peak_hour = max(hour_counts, key=hour_counts.get) if hour_counts else None

    return {
        "period": period,
        "total_joined": total_joined,
        "total_served": total_served,
        "total_cancelled": total_cancelled,
        "total_skipped": total_skipped,
        "avg_service_minutes": avg_service,
        "cancel_rate_pct": cancel_rate,
        "skip_rate_pct": skip_rate,
        "peak_hour": peak_hour,
    }


def get_hourly_stats(shop_id: str, actor_id: str, days: int = 7) -> list:
    if not _is_owner(shop_id, actor_id):
        raise HTTPException(status_code=403, detail="Not authorized")

    since = (datetime.now(timezone.utc) - timedelta(days=days)).isoformat()
    result = (
        supabase.table("queue_entries")
        .select("joined_at, status")
        .eq("shop_id", shop_id)
        .gte("joined_at", since)
        .execute()
    )

    # Build hour → count dict (0-23)
    hourly: dict[int, int] = {h: 0 for h in range(24)}
    for e in result.data or []:
        try:
            hour = datetime.fromisoformat(e["joined_at"].replace("Z", "+00:00")).hour
            hourly[hour] = hourly.get(hour, 0) + 1
        except Exception:
            pass

    return [{"hour": h, "count": hourly[h]} for h in range(24)]


def get_staff_performance(shop_id: str, owner_id: str) -> list:
    """Returns staff member list. Staff are informational only — no per-staff queue stats."""
    if not _is_owner(shop_id, owner_id):
        raise HTTPException(status_code=403, detail="Not authorized")

    staff_result = (
        supabase.table("staff_members")
        .select("id, user_id, display_name, is_owner_staff, is_active")
        .eq("shop_id", shop_id)
        .eq("is_active", True)
        .execute()
    )

    return [
        {
            "staff_id": sm.get("user_id") or sm["id"],
            "staff_name": sm["display_name"],
            "is_owner_staff": sm.get("is_owner_staff", False),
        }
        for sm in (staff_result.data or [])
    ]
