import logging
from datetime import datetime, timedelta, timezone

from fastapi import HTTPException

from app.database import execute_one, supabase
from app.schemas.promotion import PromotionCreate, PromotionUpdate
from app.services.notification_service import create_notification

logger = logging.getLogger(__name__)


def get_shop_promotions(shop_id: str, active_only: bool = False) -> dict:
    query = supabase.table("promotions").select("*").eq("shop_id", shop_id)
    if active_only:
        query = query.eq("is_active", True).gt("valid_until", datetime.now(timezone.utc).isoformat())
    result = query.order("created_at", desc=True).execute()
    return {"promotions": result.data or []}


FEATURED_TITLE = "Featured Promotion"


# Featured Promotion: bought for a fixed number of days at a fixed daily rate. The server
# works out the price from the days, never from anything the client sends.
PROMOTION_DAYS = (3, 7, 15)
PROMOTION_PRICE_PER_DAY = 10  # rupees

# Customer-facing schemes run for at most 15 days (the app offers 3/7/15). A day of
# slack covers clock/timezone differences between phone and server.
SCHEME_MAX_DAYS = 15


def validate_promotion_days(days: int) -> None:
    if days not in PROMOTION_DAYS:
        raise HTTPException(status_code=400, detail="Choose 3, 7 or 15 days.")


def promotion_price_paise(days: int) -> int:
    return days * PROMOTION_PRICE_PER_DAY * 100


def _check_scheme_length(valid_until: str | None) -> None:
    if not valid_until:
        return
    try:
        end = datetime.fromisoformat(valid_until.replace("Z", "+00:00"))
        if end.tzinfo is None:
            end = end.replace(tzinfo=timezone.utc)
    except ValueError:
        return
    if end > datetime.now(timezone.utc) + timedelta(days=SCHEME_MAX_DAYS + 1):
        raise HTTPException(status_code=400, detail="A scheme can run for at most 15 days.")


def create_promotion(shop_id: str, owner_id: str, data: PromotionCreate, paid: bool = False) -> dict:
    # "Featured Promotion" is the paid visibility boost; only the payment-verify flow
    # (paid=True) may create one. Free callers can only create schemes/offers.
    if data.title.strip() == FEATURED_TITLE and not paid:
        raise HTTPException(status_code=403, detail="Featured Promotions can only be created through payment.")
    if data.title.strip() != FEATURED_TITLE:
        _check_scheme_length(data.valid_until)
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

    # Only one scheme can be active at a time: a new scheme replaces the previous one.
    if data.title.strip() != FEATURED_TITLE:
        supabase.table("promotions").delete().eq("shop_id", shop_id).neq("title", FEATURED_TITLE).execute()

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


def _parse_dt(value: str) -> datetime:
    dt = datetime.fromisoformat(value.replace("Z", "+00:00"))
    return dt if dt.tzinfo else dt.replace(tzinfo=timezone.utc)


def activate_featured(shop_id: str, owner_id: str, days: int) -> dict:
    """Grants a paid Featured Promotion. If one is still running, its end date is pushed out by
    the paid days (nothing already paid for is lost); otherwise a new one starts now."""
    now = datetime.now(timezone.utc)
    current = (
        supabase.table("promotions")
        .select("*")
        .eq("shop_id", shop_id)
        .eq("title", FEATURED_TITLE)
        .eq("is_active", True)
        .gt("valid_until", now.isoformat())
        .order("valid_until", desc=True)
        .limit(1)
        .execute()
    )
    if current.data:
        row = current.data[0]
        new_end = _parse_dt(row["valid_until"]) + timedelta(days=days)
        total = max(1, round((new_end - _parse_dt(row["created_at"])).total_seconds() / 86400))
        plural = "" if days == 1 else "s"
        result = (
            supabase.table("promotions")
            .update({
                "valid_until": new_end.isoformat(),
                "description": f"Shop promoted for {total} days in total (extended by {days} day{plural})",
            })
            .eq("id", row["id"])
            .execute()
        )
        if not result.data:
            raise HTTPException(status_code=500, detail="Failed to extend promotion")
        return result.data[0]
    plural = "" if days == 1 else "s"
    return create_promotion(
        shop_id, owner_id,
        PromotionCreate(
            title=FEATURED_TITLE,
            description=f"Shop promoted for {days} day{plural}",
            valid_until=(now + timedelta(days=days)).isoformat(),
        ),
        paid=True,
    )


def update_promotion(promotion_id: str, owner_id: str, data: PromotionUpdate) -> dict:
    promo = execute_one(
        supabase.table("promotions")
        .select("shop_id, title")
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

    # Paid boosts can't be edited (e.g. extending valid_until for free), and a free
    # scheme can't be renamed into one.
    new_title = (data.title or "").strip() if getattr(data, "title", None) else ""
    if promo.data.get("title") == FEATURED_TITLE or new_title == FEATURED_TITLE:
        raise HTTPException(status_code=403, detail="Featured Promotions can't be edited. Create a new one through payment.")

    _check_scheme_length(data.valid_until)
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
