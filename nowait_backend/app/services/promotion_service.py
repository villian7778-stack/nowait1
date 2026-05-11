import logging

from fastapi import HTTPException

from app.database import execute_one, supabase
from app.schemas.promotion import PromotionCreate, PromotionUpdate
from app.services.notification_service import create_notification

logger = logging.getLogger(__name__)


def get_shop_promotions(shop_id: str, active_only: bool = False) -> dict:
    query = supabase.table("promotions").select("*").eq("shop_id", shop_id)
    if active_only:
        query = query.eq("is_active", True)
    result = query.order("created_at", desc=True).execute()
    return {"promotions": result.data or []}


def create_promotion(shop_id: str, owner_id: str, data: PromotionCreate) -> dict:
    shop = execute_one(
        supabase.table("shops")
        .select("id, name")
        .eq("id", shop_id)
        .eq("owner_id", owner_id)
    )
    if not shop.data:
        raise HTTPException(status_code=403, detail="Not authorized or shop not found")

    shop_name = shop.data.get("name", "A shop")

    result = supabase.table("promotions").insert({
        "shop_id": shop_id,
        "title": data.title,
        "description": data.description,
        "valid_until": data.valid_until,
        "is_active": True,
    }).execute()

    if not result.data:
        raise HTTPException(status_code=500, detail="Failed to create promotion")

    promotion = result.data[0]
    is_scheme = data.title != "Featured Promotion"

    # Notify all past visitors of this shop about the new scheme/promotion.
    # Past visitors = users with a completed queue entry at this shop.
    try:
        visitors_res = (
            supabase.table("queue_entries")
            .select("user_id")
            .eq("shop_id", shop_id)
            .eq("status", "completed")
            .execute()
        )
        # "scheme" type for customer-facing offers; "promotion" for featured boosts
        notif_type = "scheme" if is_scheme else "promotion"
        title_label = "New Scheme" if is_scheme else "Featured Offer"
        seen_users: set = set()
        for row in visitors_res.data or []:
            uid = row["user_id"]
            if uid in seen_users or uid == owner_id:
                continue
            seen_users.add(uid)
            try:
                create_notification(
                    user_id=uid,
                    type=notif_type,
                    title=f"{title_label} at {shop_name}",
                    body=f"{data.title}: {data.description[:120]}",
                    shop_name=shop_name,
                    shop_id=shop_id,
                )
            except Exception as e:
                logger.warning("Failed to notify user %s: %s", uid, e)
    except Exception as e:
        logger.warning("Failed to fetch past visitors for notifications: %s", e)

    return promotion


def update_promotion(promotion_id: str, owner_id: str, data: PromotionUpdate) -> dict:
    promo = execute_one(
        supabase.table("promotions")
        .select("shop_id")
        .eq("id", promotion_id)
    )
    if not promo.data:
        raise HTTPException(status_code=404, detail="Promotion not found")

    shop = execute_one(
        supabase.table("shops")
        .select("id")
        .eq("id", promo.data["shop_id"])
        .eq("owner_id", owner_id)
    )
    if not shop.data:
        raise HTTPException(status_code=403, detail="Not authorized")

    update_data = {k: v for k, v in data.model_dump().items() if v is not None}
    result = supabase.table("promotions").update(update_data).eq("id", promotion_id).execute()
    return result.data[0]


def delete_promotion(promotion_id: str, owner_id: str) -> bool:
    promo = execute_one(
        supabase.table("promotions")
        .select("shop_id")
        .eq("id", promotion_id)
    )
    if not promo.data:
        raise HTTPException(status_code=404, detail="Promotion not found")

    shop = execute_one(
        supabase.table("shops")
        .select("id")
        .eq("id", promo.data["shop_id"])
        .eq("owner_id", owner_id)
    )
    if not shop.data:
        raise HTTPException(status_code=403, detail="Not authorized")

    supabase.table("promotions").delete().eq("id", promotion_id).execute()
    return True
