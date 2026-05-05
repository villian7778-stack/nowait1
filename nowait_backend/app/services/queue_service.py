import logging
from datetime import datetime, timedelta, timezone
from typing import Optional

from fastapi import HTTPException

from app.database import execute_one, supabase
from app.services.notification_service import create_notification
from app.services.staff_service import _is_owner

logger = logging.getLogger(__name__)


# ── helpers ──────────────────────────────────────────────────────────────────

def _compute_position(shop_id: str, token_number: int) -> int:
    result = (
        supabase.table("queue_entries")
        .select("id", count="exact")
        .eq("shop_id", shop_id)
        .eq("status", "waiting")
        .lt("token_number", token_number)
        .execute()
    )
    return (result.count or 0) + 1


def _get_now_serving_token(shop_id: str):
    result = execute_one(
        supabase.table("queue_entries")
        .select("token_number")
        .eq("shop_id", shop_id)
        .eq("status", "serving")
    )
    return result.data["token_number"] if result.data else None


def _get_display_status(status: str, position: int) -> str:
    if status == "serving":
        return "yourTurn"
    if status == "waiting":
        return "almostThere" if position <= 3 else "waiting"
    return status


def _get_avg_wait(shop_id: str) -> int:
    shop = execute_one(supabase.table("shops").select("avg_wait_minutes").eq("id", shop_id))
    return shop.data["avg_wait_minutes"] if shop.data else 10


def _fetch_services_by_ids(service_ids: list) -> list:
    """Batch-fetch services by ID list. Returns list of dicts."""
    if not service_ids:
        return []
    result = (
        supabase.table("services")
        .select("id, name, price, duration_minutes")
        .in_("id", service_ids)
        .execute()
    )
    return result.data or []


def _calculate_total_duration(service_ids: list, avg_wait: int) -> int:
    """Sum durations of selected services; fall back to avg_wait if none."""
    if not service_ids:
        return avg_wait
    services = _fetch_services_by_ids(service_ids)
    total = sum(s.get("duration_minutes") or 15 for s in services)
    return total if total > 0 else avg_wait


def _check_queue_ban(user_id: str) -> None:
    """Raise 403 if user is within the 2-hour cancellation cooldown period."""
    try:
        profile = execute_one(
            supabase.table("profiles").select("queue_ban_until").eq("id", user_id)
        )
        if not profile.data:
            return
        ban_until_str = profile.data.get("queue_ban_until")
        if not ban_until_str:
            return
        ban_until = datetime.fromisoformat(ban_until_str.replace("Z", "+00:00"))
        now = datetime.now(timezone.utc)
        if ban_until > now:
            remaining_mins = max(1, int((ban_until - now).total_seconds() / 60))
            unit = "minute" if remaining_mins == 1 else "minutes"
            raise HTTPException(
                status_code=403,
                detail=(
                    f"You cannot join any queue for another {remaining_mins} {unit} "
                    "due to a recent cancellation."
                ),
            )
    except HTTPException:
        raise
    except Exception:
        pass  # If column missing (pre-migration) or parse fails, allow join


def _check_existing_active_queue(user_id: str, current_shop_id: str) -> None:
    """Raise 409 if user is already active in a queue at a *different* shop.

    Same-shop duplicate detection is handled by the join_queue_v2 RPC and the
    per-(shop, user) unique index, so we exclude the current shop here to
    preserve the existing error message for that case.
    """
    existing = (
        supabase.table("queue_entries")
        .select("id, shop_id")
        .eq("user_id", user_id)
        .in_("status", ["waiting", "serving"])
        .neq("shop_id", current_shop_id)
        .limit(1)
        .execute()
    )
    if existing.data:
        raise HTTPException(
            status_code=409,
            detail=(
                "You are already in a queue at another shop. "
                "Please cancel or complete that queue first."
            ),
        )


def _build_entry_response(entry: dict, shop_name: str, avg_wait: int) -> dict:
    if entry["status"] == "serving":
        position = 1
    elif entry["status"] == "waiting":
        position = _compute_position(entry["shop_id"], entry["token_number"])
    else:
        position = 0
    now_serving = _get_now_serving_token(entry["shop_id"])
    display_status = _get_display_status(entry["status"], position)

    service_ids = list(entry.get("service_ids") or [])
    # Backward compat: single service_id with no array
    if not service_ids and entry.get("service_id"):
        service_ids = [entry["service_id"]]

    selected_services = _fetch_services_by_ids(service_ids)
    total_duration = entry.get("total_duration_minutes")
    if total_duration is None and selected_services:
        total_duration = sum(s.get("duration_minutes") or 15 for s in selected_services)

    est_wait = max(0, (position - 1) * avg_wait) if not total_duration else max(0, position - 1) * (total_duration or avg_wait)

    return {
        **entry,
        "shop_name": shop_name,
        "display_status": display_status,
        "position": position,
        "people_ahead": max(0, position - 1),
        "estimated_wait_minutes": max(0, (position - 1) * avg_wait),
        "now_serving_token": now_serving,
        "service_ids": service_ids,
        "selected_services": selected_services,
        "total_duration_minutes": total_duration,
    }


# ── join queue ────────────────────────────────────────────────────────────────

def join_queue(shop_id: str, user_id: str, service_id: Optional[str] = None, service_ids: Optional[list] = None) -> dict:
    ids = service_ids or ([service_id] if service_id else [])
    # Deduplicate preserving order
    seen = set()
    unique_ids = []
    for sid in ids:
        if sid and sid not in seen:
            seen.add(sid)
            unique_ids.append(sid)

    avg_wait = _get_avg_wait(shop_id)
    total_duration = _calculate_total_duration(unique_ids, avg_wait) if unique_ids else None

    # Enforce cancellation cooldown before hitting the DB
    _check_queue_ban(user_id)
    # Enforce one active queue per user across all shops
    _check_existing_active_queue(user_id, shop_id)

    try:
        result = supabase.rpc("join_queue_v2", {
            "p_shop_id": shop_id,
            "p_user_id": user_id,
            "p_service_id": unique_ids[0] if unique_ids else service_id,
            "p_service_ids": unique_ids,
            "p_total_duration_minutes": total_duration,
        }).execute()
    except Exception as e:
        error_msg = str(e)
        if "SHOP_NOT_FOUND" in error_msg:
            raise HTTPException(status_code=404, detail="Shop not found")
        if "SHOP_CLOSED" in error_msg:
            raise HTTPException(status_code=400, detail="Shop is currently closed")
        if "QUEUE_PAUSED" in error_msg:
            raise HTTPException(status_code=400, detail="Queue is currently paused")
        if "QUEUE_FULL" in error_msg:
            raise HTTPException(status_code=400, detail="Queue has reached its maximum capacity")
        if "NO_SUBSCRIPTION" in error_msg:
            raise HTTPException(status_code=400, detail="Shop does not have an active subscription")
        if "ALREADY_IN_QUEUE" in error_msg:
            raise HTTPException(status_code=409, detail="You are already in this shop's queue")
        logger.error("join_queue RPC unexpected error (shop=%s user=%s): %s", shop_id, user_id, e)
        raise HTTPException(status_code=400, detail="Failed to join queue")

    if not result.data:
        raise HTTPException(status_code=500, detail="Failed to join queue")

    entry = result.data if isinstance(result.data, dict) else result.data[0]
    shop = execute_one(supabase.table("shops").select("name, avg_wait_minutes").eq("id", shop_id))
    shop_data = shop.data or {"name": "Unknown", "avg_wait_minutes": 10}
    return _build_entry_response(entry, shop_data["name"], avg_wait)


# ── customer status ───────────────────────────────────────────────────────────

def get_my_queue_status(user_id: str, shop_id: Optional[str] = None) -> list:
    query = (
        supabase.table("queue_entries")
        .select("*")
        .eq("user_id", user_id)
        .in_("status", ["waiting", "serving"])
        .order("joined_at", desc=True)
    )
    if shop_id:
        query = query.eq("shop_id", shop_id)

    result = query.execute()
    enriched = []
    for entry in result.data or []:
        shop = execute_one(supabase.table("shops").select("name, avg_wait_minutes, latitude, longitude").eq("id", entry["shop_id"]))
        shop_data = shop.data or {"name": "Unknown", "avg_wait_minutes": 10}
        avg = shop_data["avg_wait_minutes"]
        response = _build_entry_response(entry, shop_data["name"], avg)
        response["shop_latitude"] = shop_data.get("latitude")
        response["shop_longitude"] = shop_data.get("longitude")
        enriched.append(response)
    return enriched


def cancel_queue(entry_id: str, user_id: str) -> dict:
    entry = execute_one(
        supabase.table("queue_entries").select("*").eq("id", entry_id).eq("user_id", user_id)
    )
    if not entry.data:
        raise HTTPException(status_code=404, detail="Queue entry not found")
    if entry.data["status"] not in ("waiting",):
        raise HTTPException(status_code=400, detail=f"Cannot cancel entry with status '{entry.data['status']}'")

    supabase.table("queue_entries").update({"status": "cancelled"}).eq("id", entry_id).execute()
    supabase.table("queue_events").insert({
        "shop_id": entry.data["shop_id"],
        "entry_id": entry_id,
        "event_type": "cancelled",
    }).execute()

    # Apply 2-hour cooldown: user cannot join any queue until ban_until
    try:
        ban_until = (datetime.now(timezone.utc) + timedelta(hours=2)).isoformat()
        supabase.table("profiles").update({"queue_ban_until": ban_until}).eq("id", user_id).execute()
    except Exception as ban_err:
        logger.warning("Failed to apply queue ban for user %s: %s", user_id, ban_err)

    return {"message": "Queue entry cancelled successfully", "entry_id": entry_id}


# ── "I am coming" notification ────────────────────────────────────────────────

def notify_coming(entry_id: str, user_id: str) -> dict:
    entry = execute_one(
        supabase.table("queue_entries").select("*").eq("id", entry_id).eq("user_id", user_id)
    )
    if not entry.data:
        raise HTTPException(status_code=404, detail="Queue entry not found")
    if entry.data["status"] not in ("waiting", "serving"):
        raise HTTPException(status_code=400, detail="Can only notify when in queue")

    e = entry.data
    shop = execute_one(supabase.table("shops").select("name, owner_id").eq("id", e["shop_id"]))
    if not shop.data:
        raise HTTPException(status_code=404, detail="Shop not found")

    profile = execute_one(supabase.table("profiles").select("name").eq("id", user_id))
    customer_name = profile.data["name"] if profile.data else "A customer"

    supabase.table("queue_entries").update({"coming_at": datetime.now(timezone.utc).isoformat()}).eq("id", entry_id).execute()

    create_notification(
        user_id=shop.data["owner_id"],
        type="coming",
        title="Customer On The Way",
        body=f"{customer_name} (Token #{e['token_number']}) is on their way to {shop.data['name']}.",
        shop_name=shop.data["name"],
        shop_id=e["shop_id"],
    )

    return {"message": "Shop notified", "entry_id": entry_id}


# ── owner queue view ──────────────────────────────────────────────────────────

def get_shop_queue(shop_id: str, owner_id: str) -> dict:
    if not _is_owner(shop_id, owner_id):
        raise HTTPException(status_code=403, detail="Not authorized")

    shop = execute_one(supabase.table("shops").select("id, name, is_open, queue_paused, max_queue_size").eq("id", shop_id))
    if not shop.data:
        raise HTTPException(status_code=404, detail="Shop not found")

    result = (
        supabase.table("queue_entries")
        .select("*")
        .eq("shop_id", shop_id)
        .in_("status", ["waiting", "serving"])
        .order("token_number")
        .execute()
    )
    entries = result.data or []

    # Collect all service IDs for a single batch fetch
    all_service_ids = []
    for entry in entries:
        ids = list(entry.get("service_ids") or [])
        if not ids and entry.get("service_id"):
            ids = [entry["service_id"]]
        all_service_ids.extend(ids)

    services_map = {}
    if all_service_ids:
        svcs = _fetch_services_by_ids(list(set(all_service_ids)))
        services_map = {s["id"]: s for s in svcs}

    # Batch-fetch all customer profiles in one query (avoids N+1)
    user_ids = list({entry["user_id"] for entry in entries})
    profiles_result = supabase.table("profiles").select("id, name, phone").in_("id", user_ids).execute()
    profiles_map = {p["id"]: p for p in (profiles_result.data or [])}

    queue_items = []
    for i, entry in enumerate(entries, 1):
        customer = profiles_map.get(entry["user_id"], {"name": "Unknown", "phone": ""})

        ids = list(entry.get("service_ids") or [])
        if not ids and entry.get("service_id"):
            ids = [entry["service_id"]]
        selected_services = [services_map[sid] for sid in ids if sid in services_map]
        service_names = [s["name"] for s in selected_services]
        total_dur = entry.get("total_duration_minutes")
        if total_dur is None and selected_services:
            total_dur = sum(s.get("duration_minutes") or 15 for s in selected_services)

        queue_items.append({
            **entry,
            "customer_name": customer["name"],
            "customer_phone": customer["phone"],
            "position": i,
            "service_ids": ids,
            "service_names": service_names,
            "selected_services": selected_services,
            "total_duration_minutes": total_dur,
        })

    serving = next((e["token_number"] for e in entries if e["status"] == "serving"), None)
    waiting_count = sum(1 for e in entries if e["status"] == "waiting")

    return {
        "shop_id": shop_id,
        "shop_name": shop.data["name"],
        "is_open": shop.data["is_open"],
        "queue_paused": shop.data.get("queue_paused", False),
        "max_queue_size": shop.data.get("max_queue_size"),
        "total_waiting": waiting_count,
        "now_serving_token": serving,
        "queue": queue_items,
    }


# ── public queue view (no auth — customers polling) ───────────────────────────

def get_public_shop_queue(shop_id: str) -> dict:
    shop = execute_one(
        supabase.table("shops").select("id, name, is_open, avg_wait_minutes").eq("id", shop_id)
    )
    if not shop.data:
        raise HTTPException(status_code=404, detail="Shop not found")

    result = (
        supabase.table("queue_entries")
        .select("token_number, status, service_ids, service_id, total_duration_minutes")
        .eq("shop_id", shop_id)
        .in_("status", ["waiting", "serving"])
        .order("token_number")
        .execute()
    )
    entries = result.data or []

    all_service_ids = []
    for entry in entries:
        ids = list(entry.get("service_ids") or [])
        if not ids and entry.get("service_id"):
            ids = [entry["service_id"]]
        all_service_ids.extend(ids)

    services_map = {}
    if all_service_ids:
        svcs = _fetch_services_by_ids(list(set(all_service_ids)))
        services_map = {s["id"]: s for s in svcs}

    avg_wait = shop.data["avg_wait_minutes"]
    queue_items = []
    for i, entry in enumerate(entries, 1):
        ids = list(entry.get("service_ids") or [])
        if not ids and entry.get("service_id"):
            ids = [entry["service_id"]]
        service_names = [services_map[sid]["name"] for sid in ids if sid in services_map]
        total_dur = entry.get("total_duration_minutes")
        if total_dur is None and ids:
            total_dur = sum(services_map[sid].get("duration_minutes") or 15 for sid in ids if sid in services_map)

        queue_items.append({
            "token_number": entry["token_number"],
            "status": entry["status"],
            "service_names": service_names,
            "total_duration_minutes": total_dur or avg_wait,
            "position": i,
        })

    serving = next((e["token_number"] for e in entries if e["status"] == "serving"), None)
    waiting_count = sum(1 for e in entries if e["status"] == "waiting")

    return {
        "shop_id": shop_id,
        "shop_name": shop.data["name"],
        "total_waiting": waiting_count,
        "now_serving_token": serving,
        "avg_wait_minutes": avg_wait,
        "queue": queue_items,
    }


# ── advance / skip ────────────────────────────────────────────────────────────

def advance_queue(shop_id: str, owner_id: str) -> dict:
    if not _is_owner(shop_id, owner_id):
        raise HTTPException(status_code=403, detail="Not authorized")

    try:
        result = supabase.rpc("advance_queue_v2", {
            "p_shop_id": shop_id,
        }).execute()
    except Exception as e:
        logger.error("advance_queue RPC error (shop=%s owner=%s): %s", shop_id, owner_id, e)
        raise HTTPException(status_code=400, detail="Failed to advance queue")

    data = result.data or []
    completed_token = None
    next_serving_token = None

    if data:
        row = data[0]
        completed_entry = row.get("completed_entry")
        next_entry = row.get("next_entry")

        if completed_entry and isinstance(completed_entry, dict):
            completed_token = completed_entry.get("token_number")

        if next_entry and isinstance(next_entry, dict):
            next_serving_token = next_entry.get("token_number")
            next_user_id = next_entry.get("user_id")
            if next_user_id:
                shop_r = execute_one(supabase.table("shops").select("name").eq("id", shop_id))
                shop_name = shop_r.data["name"] if shop_r.data else "Shop"
                create_notification(
                    user_id=next_user_id,
                    type="your_turn",
                    title="It's Your Turn!",
                    body=f"Token #{next_serving_token} — please proceed to {shop_name} now.",
                    shop_name=shop_name,
                    shop_id=shop_id,
                )
                _notify_upcoming_customers(shop_id, shop_name)

    remaining = (
        supabase.table("queue_entries")
        .select("id", count="exact")
        .eq("shop_id", shop_id)
        .in_("status", ["waiting", "serving"])
        .execute()
    )

    return {
        "message": "Queue advanced" if next_serving_token else "Queue advanced — no more customers waiting",
        "completed_token": completed_token,
        "now_serving_token": next_serving_token,
        "total_remaining": remaining.count or 0,
    }


def _notify_upcoming_customers(shop_id: str, shop_name: str):
    upcoming = (
        supabase.table("queue_entries")
        .select("user_id, token_number")
        .eq("shop_id", shop_id)
        .eq("status", "waiting")
        .order("token_number")
        .limit(2)
        .execute()
    )

    for i, entry in enumerate(upcoming.data or [], 2):
        create_notification(
            user_id=entry["user_id"],
            type="almost_there",
            title="Almost Your Turn!",
            body=f"You are #{i} in line at {shop_name}. Token #{entry['token_number']} — get ready!",
            shop_name=shop_name,
            shop_id=shop_id,
        )


def skip_customer(entry_id: str, owner_id: str) -> dict:
    entry = execute_one(supabase.table("queue_entries").select("*").eq("id", entry_id))
    if not entry.data:
        raise HTTPException(status_code=404, detail="Queue entry not found")

    if not _is_owner(entry.data["shop_id"], owner_id):
        raise HTTPException(status_code=403, detail="Not authorized")

    try:
        result = supabase.rpc("skip_customer_v2", {
            "p_entry_id": entry_id,
        }).execute()
    except Exception as e:
        error_msg = str(e)
        if "NOT_FOUND" in error_msg:
            raise HTTPException(status_code=404, detail="Entry not found or not skippable")
        logger.error("skip_customer RPC unexpected error (entry=%s): %s", entry_id, e)
        raise HTTPException(status_code=400, detail="Failed to skip customer")

    if not result.data:
        raise HTTPException(status_code=404, detail="Entry not found")

    skipped = result.data if isinstance(result.data, dict) else result.data[0]
    shop_r = execute_one(supabase.table("shops").select("name").eq("id", skipped["shop_id"]))
    shop_name = shop_r.data["name"] if shop_r.data else "Shop"

    create_notification(
        user_id=skipped["user_id"],
        type="skipped",
        title="You Were Skipped",
        body=f"Token #{skipped['token_number']} was skipped at {shop_name}.",
        shop_name=shop_name,
        shop_id=skipped["shop_id"],
    )
    return skipped


# ── queue controls ────────────────────────────────────────────────────────────

def pause_queue(shop_id: str, owner_id: str) -> dict:
    if not _is_owner(shop_id, owner_id):
        raise HTTPException(status_code=403, detail="Not authorized")
    supabase.table("shops").update({"queue_paused": True}).eq("id", shop_id).execute()
    supabase.table("queue_events").insert({"shop_id": shop_id, "event_type": "paused"}).execute()
    return {"shop_id": shop_id, "queue_paused": True, "message": "Queue paused"}


def resume_queue(shop_id: str, owner_id: str) -> dict:
    if not _is_owner(shop_id, owner_id):
        raise HTTPException(status_code=403, detail="Not authorized")
    supabase.table("shops").update({"queue_paused": False}).eq("id", shop_id).execute()
    supabase.table("queue_events").insert({"shop_id": shop_id, "event_type": "resumed"}).execute()
    return {"shop_id": shop_id, "queue_paused": False, "message": "Queue resumed"}


def set_max_size(shop_id: str, owner_id: str, max_size: Optional[int]) -> dict:
    if not _is_owner(shop_id, owner_id):
        raise HTTPException(status_code=403, detail="Not authorized")
    supabase.table("shops").update({"max_queue_size": max_size}).eq("id", shop_id).execute()
    return {"shop_id": shop_id, "max_queue_size": max_size}


# ── customer history ──────────────────────────────────────────────────────────

def get_customer_history(user_id: str, limit: int = 30) -> list:
    result = (
        supabase.table("queue_entries")
        .select("*")
        .eq("user_id", user_id)
        .in_("status", ["completed", "skipped", "cancelled"])
        .order("joined_at", desc=True)
        .limit(limit)
        .execute()
    )
    enriched = []
    for entry in result.data or []:
        shop_r = execute_one(supabase.table("shops").select("name, category, city").eq("id", entry["shop_id"]))
        shop = shop_r.data or {"name": "Unknown", "category": "", "city": ""}

        service_name = None
        ids = list(entry.get("service_ids") or [])
        if not ids and entry.get("service_id"):
            ids = [entry["service_id"]]
        if ids:
            svcs = _fetch_services_by_ids(ids)
            service_name = ", ".join(s["name"] for s in svcs) if svcs else None

        enriched.append({
            **entry,
            "shop_name": shop["name"],
            "shop_category": shop["category"],
            "shop_city": shop["city"],
            "service_name": service_name,
        })
    return enriched
