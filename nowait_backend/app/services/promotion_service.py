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
        .select("id, name, city")
        .eq("id", shop_id)
        .eq("owner_id", owner_id)
    )
    if not shop.data:
        raise HTTPException(status_code=403, detail="Not authorized or shop not found")

    shop_name = shop.data.get("name", "A shop")
    shop_city = shop.data.get("city", "")

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

    # Notify ALL customers in the same city as the shop.
    # scheme type for customer-facing offers; promotion type for featured boosts.
    try:
        city_users_res = (
            supabase.table("profiles")
            .select("id")
            .eq("city", shop_city)
            .eq("role", "customer")
            .neq("id", owner_id)
            .execute()
        )
        notif_type = "scheme" if is_scheme else "promotion"
        title_label = "New Scheme" if is_scheme else "Featured Promotion"
        body_text = f"{data.title}: {data.description[:120]}"

        for row in city_users_res.data or []:
            uid = row["id"]
            try:
                create_notification(
                    user_id=uid,
                    type=notif_type,
                    title=f"{title_label} at {shop_name}",
                    body=body_text,
                    shop_name=shop_name,
                    shop_id=shop_id,
                )
            except Exception as e:
                logger.warning("Failed to notify user %s: %s", uid, e)
    except Exception as e:
        logger.warning("Failed to fetch city customers for notifications: %s", e)

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
