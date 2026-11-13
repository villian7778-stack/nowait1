from typing import Optional

from fastapi import HTTPException

from app.database import execute_one, supabase
from app.services import push_service


def create_notification(
    user_id: str,
    type: str,
    title: str,
    body: str,
    shop_name: str,
    shop_id: Optional[str] = None,
) -> dict:
    data = {
        "user_id": user_id,
        "type": type,
        "title": title,
        "body": body,
        "shop_name": shop_name,
        "shop_id": shop_id,
    }
    result = supabase.table("notifications").insert(data).execute()
    # Also to the phone, for the queue alerts (background, never fails this call)
    push_service.notify_user(user_id, type, title, body, {"shop_id": shop_id})
    return result.data[0] if result.data else {}


def get_notifications(user_id: str) -> dict:
    result = (
        supabase.table("notifications")
        .select("*")
        .eq("user_id", user_id)
        .order("created_at", desc=True)
        .limit(50)
        .execute()
    )
    notifications = result.data or []
    unread = sum(1 for n in notifications if not n["is_read"])
    return {"notifications": notifications, "unread_count": unread}


def mark_read(notification_id: str, user_id: str) -> dict:
    existing = execute_one(
        supabase.table("notifications")
        .select("id")
        .eq("id", notification_id)
        .eq("user_id", user_id)
    )
    if not existing.data:
        raise HTTPException(status_code=404, detail="Notification not found")
    supabase.table("notifications").update({"is_read": True}).eq("id", notification_id).execute()
    return {"message": "Notification marked as read", "updated_count": 1}


def mark_all_read(user_id: str) -> dict:
    result = (
        supabase.table("notifications")
        .update({"is_read": True})
        .eq("user_id", user_id)
        .eq("is_read", False)
        .execute()
    )
    count = len(result.data) if result.data else 0
    return {"message": f"Marked {count} notifications as read", "updated_count": count}
