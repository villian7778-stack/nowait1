import math
from datetime import datetime, timedelta, timezone

from fastapi import HTTPException

from app.database import execute_one, supabase
from app.schemas.subscription import SubscriptionCreate
from app.services import trial_service

# Two paid plans, priced by length (rupees). New owners also get TRIAL_DAYS free - see
# trial_service. The plan label is 'basic' for both; 'premium' is only still accepted so
# older app builds and existing rows keep working, and 'trial' marks the free month.
PLAN_PRICES = {"basic": 49, "premium": 49}
DURATION_PRICES = {30: 49, 90: 130}
VALID_DURATIONS = tuple(DURATION_PRICES)


def price_paise(duration_days: int) -> int:
    """Amount to charge for a plan length, in paise. Server-side only - never from the client."""
    return DURATION_PRICES[duration_days] * 100


def _parse_dt(value: str) -> datetime:
    return datetime.fromisoformat(value.replace("Z", "+00:00"))


def _days_left(expires_at: datetime, now: datetime) -> int:
    """Whole days left, rounded up, so a fresh 30-day plan reads 30 (not 29)."""
    return max(0, math.ceil((expires_at - now).total_seconds() / 86400))


def active_expiry(shop_id: str) -> datetime | None:
    """expires_at of the shop's subscription if it is currently active, else None."""
    row = execute_one(supabase.table("subscriptions").select("*").eq("shop_id", shop_id)).data
    if not row or row.get("status") != "active" or not row.get("expires_at"):
        return None
    expires_at = _parse_dt(row["expires_at"])
    return expires_at if expires_at > datetime.now(timezone.utc) else None


def validate_plan(plan: str, duration_days: int) -> None:
    if plan not in PLAN_PRICES:
        raise HTTPException(status_code=400, detail=f"Invalid plan. Choose from: {list(PLAN_PRICES.keys())}")
    if duration_days not in VALID_DURATIONS:
        raise HTTPException(status_code=400, detail="Choose a 1-month or 3-month plan.")


def already_active_message(expires_at: datetime, duration_days: int) -> str:
    length = {30: "1 month", 90: "3 months"}.get(duration_days, f"{duration_days} days")
    new_end = expires_at + timedelta(days=duration_days)
    return (
        f"Your active subscription ends on {expires_at.strftime('%d %b %Y')}. "
        f"Do you want to extend it by {length}? The new end date will be {new_end.strftime('%d %b %Y')}."
    )


def get_subscription(shop_id: str, owner_id: str) -> dict:
    shop = execute_one(
        supabase.table("shops")
        .select("id")
        .eq("id", shop_id)
        .eq("owner_id", owner_id)
    )
    if not shop.data:
        raise HTTPException(status_code=403, detail="Not authorized or shop not found")

    result = execute_one(supabase.table("subscriptions").select("*").eq("shop_id", shop_id))
    if not result.data:
        # A shop that has never had a plan can start its owner's one free month.
        return {
            "has_active_subscription": False,
            "subscription": None,
            "trial_available": trial_service.is_eligible(owner_id),
        }

    sub = result.data
    now = datetime.now(timezone.utc)
    expires_at = _parse_dt(sub["expires_at"])
    days_remaining = _days_left(expires_at, now)

    is_active = sub["status"] == "active" and expires_at > now
    # A cancelled/expired plan has no days left, whatever its stored end date says.
    sub_response = {**sub, "days_remaining": days_remaining if is_active else 0}

    return {"has_active_subscription": is_active, "subscription": sub_response}


def start_free_trial(shop_id: str, owner_id: str) -> dict:
    """Owner presses "Activate free trial": gives the shop its one free month."""
    shop = execute_one(
        supabase.table("shops")
        .select("id")
        .eq("id", shop_id)
        .eq("owner_id", owner_id)
    )
    if not shop.data:
        raise HTTPException(status_code=403, detail="Not authorized or shop not found")

    if execute_one(supabase.table("subscriptions").select("id").eq("shop_id", shop_id)).data:
        raise HTTPException(status_code=400, detail="The free trial is only for shops that have not subscribed yet.")

    trial_service.start_trial(shop_id, owner_id)
    return get_subscription(shop_id, owner_id)


def create_or_renew_subscription(shop_id: str, owner_id: str, data: SubscriptionCreate) -> dict:
    shop = execute_one(
        supabase.table("shops")
        .select("id")
        .eq("id", shop_id)
        .eq("owner_id", owner_id)
    )
    if not shop.data:
        raise HTTPException(status_code=403, detail="Not authorized or shop not found")

    validate_plan(data.plan, data.duration_days)

    now = datetime.now(timezone.utc)

    existing = execute_one(
        supabase.table("subscriptions")
        .select("*")
        .eq("shop_id", shop_id)
    )

    # Extend from the current end date while the subscription is still active, so the
    # days already paid for are never lost; otherwise start counting from now.
    started_at = now
    base = now
    prev = existing.data or {}
    if prev.get("status") == "active" and prev.get("expires_at"):
        prev_expiry = _parse_dt(prev["expires_at"])
        if prev_expiry > now:
            base = prev_expiry
            if prev.get("started_at"):
                started_at = _parse_dt(prev["started_at"])
    expires_at = base + timedelta(days=data.duration_days)

    sub_data = {
        "shop_id": shop_id,
        "plan": data.plan,
        "status": "active",
        "started_at": started_at.isoformat(),
        "expires_at": expires_at.isoformat(),
    }

    if existing.data:
        result = supabase.table("subscriptions").update(sub_data).eq("shop_id", shop_id).execute()
    else:
        result = supabase.table("subscriptions").insert(sub_data).execute()

    if not result.data:
        raise HTTPException(status_code=500, detail="Failed to create/renew subscription")

    sub = result.data[0]
    days_remaining = _days_left(expires_at, now)
    return {"has_active_subscription": True, "subscription": {**sub, "days_remaining": days_remaining}}


def cancel_subscription(shop_id: str, owner_id: str) -> dict:
    shop = execute_one(
        supabase.table("shops")
        .select("id")
        .eq("id", shop_id)
        .eq("owner_id", owner_id)
    )
    if not shop.data:
        raise HTTPException(status_code=403, detail="Not authorized or shop not found")

    result = (
        supabase.table("subscriptions")
        .update({"status": "cancelled"})
        .eq("shop_id", shop_id)
        .execute()
    )
    if not result.data:
        raise HTTPException(status_code=404, detail="No subscription found to cancel")
    # No subscription = shop goes inactive: close it so it stops taking queues.
    supabase.table("shops").update({"is_open": False}).eq("id", shop_id).execute()
    # The response model requires days_remaining; a cancelled plan has none left.
    return {"has_active_subscription": False, "subscription": {**result.data[0], "days_remaining": 0}}
