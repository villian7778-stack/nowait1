import logging
import math
from concurrent.futures import ThreadPoolExecutor
from datetime import datetime, timedelta, timezone

from fastapi import HTTPException

from app.database import execute_one, supabase
from app.locks import lock_for
from app.schemas.promotion import PromotionCreate, PromotionUpdate
from app.services import push_service, subscription_service

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


SUBSCRIPTION_REQUIRED = (
    "Schemes and Featured Promotions need an active subscription or free trial. "
    "Activate one from the Subscription screen first."
)


def require_active_subscription(shop_id: str) -> datetime:
    """End of the shop's running subscription / free trial. 403 when there is none: an
    unsubscribed shop is hidden from customers, so a scheme or a paid boost would reach nobody."""
    expires_at = subscription_service.active_expiry(shop_id)
    if not expires_at:
        raise HTTPException(status_code=403, detail=SUBSCRIPTION_REQUIRED)
    return expires_at


def _running_featured_end(shop_id: str) -> datetime | None:
    now = datetime.now(timezone.utc)
    row = (
        supabase.table("promotions")
        .select("valid_until")
        .eq("shop_id", shop_id)
        .eq("title", FEATURED_TITLE)
        .eq("is_active", True)
        .gt("valid_until", now.isoformat())
        .order("valid_until", desc=True)
        .limit(1)
        .execute()
    ).data
    return _parse_dt(row[0]["valid_until"]) if row else None


def check_promotion_fits_subscription(shop_id: str, days: int) -> None:
    """Before taking money for a Featured Promotion: the shop must be subscribed, and the paid
    days (added after a promotion that is still running) must end before the subscription does.
    After that the shop is hidden, so those days would be paid for and never seen - and payments
    are not refunded."""
    expires_at = require_active_subscription(shop_id)
    now = datetime.now(timezone.utc)
    start = max(_running_featured_end(shop_id) or now, now)
    if start + timedelta(days=days) <= expires_at + timedelta(hours=1):
        return
    fits = [d for d in sorted(PROMOTION_DAYS) if start + timedelta(days=d) <= expires_at + timedelta(hours=1)]
    raise HTTPException(status_code=409, detail=promotion_too_long_message(days, expires_at, fits[-1] if fits else None))


def promotion_too_long_message(days: int, expires_at: datetime, longest_fitting: int | None) -> str:
    """e.g. "You're trying to get a 7-day promotion, but your subscription ends in 3 days (on
    12 Nov 2026). Extend your subscription, or choose 3 days or fewer."""
    left = max(0, math.ceil((expires_at - datetime.now(timezone.utc)).total_seconds() / 86400))
    left_text = "today" if left == 0 else f"in {left} day{'' if left == 1 else 's'}"
    text = (f"You're trying to get a {days}-day promotion, but your subscription ends {left_text} "
            f"(on {expires_at.strftime('%d %b %Y')}). ")
    if longest_fitting:
        return text + f"Extend your subscription, or choose {longest_fitting} days or fewer."
    return text + "Extend your subscription first, then promote your shop."


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

    # A paid Featured Promotion (paid=True) is always granted: the money was taken already.
    if not paid:
        require_active_subscription(shop_id)

    shop_name = shop.data.get("name", "A shop")
    shop_city = shop.data.get("city", "")

    # Only one scheme can be active at a time: a new scheme replaces the previous one. The lock
    # keeps a double tap from leaving two schemes (both deletes run before both inserts).
    with lock_for(f"promotions:{shop_id}"):
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

    # No notification here: schemes never notify, and a paid Featured Promotion is announced
    # once by announce_elite_promotion() after the payment is activated (payments.py).
    return result.data[0]


# ── "Elite Promotion" announcement: once per paid promotion ──────────────────

OFFER_ACTIVE_PREFIX = "🎁 Offer active: "  # the app shows an "Offer active" tag for this
ANNOUNCE_CALL_TO_ACTION = "Open NoWaitt to explore the shop and get your service."
_ANNOUNCE_BATCH = 500
_announce_pool = ThreadPoolExecutor(max_workers=1, thread_name_prefix="elite-announce")


def announce_elite_promotion(shop_id: str) -> None:
    """After a Featured Promotion payment is activated - a new one or an extension, whatever the
    days (3 / 7 / 15) - tell the customers in the shop's city, once for that payment (in-app +
    phone). payments._activate runs once per paid order, so a payment is never announced twice. Runs in the background so the owner's payment screen isn't held up,
    and never raises - the payment is already done."""
    _announce_pool.submit(_announce_now, shop_id)


def _announce_now(shop_id: str) -> int:
    """Sends the announcement; returns how many customers got it (0 = skipped)."""
    try:
        shop = execute_one(supabase.table("shops").select("id, name, city, owner_id").eq("id", shop_id)).data
        if not shop or not (shop.get("city") or "").strip():
            return 0
        now = datetime.now(timezone.utc)
        name = shop.get("name") or "A shop"
        city = shop["city"].strip()
        scheme = (
            supabase.table("promotions").select("title")
            .eq("shop_id", shop_id).eq("is_active", True).neq("title", FEATURED_TITLE)
            .gt("valid_until", now.isoformat())
            .order("created_at", desc=True).limit(1).execute()
        ).data
        title = f"⭐ Elite Promotion · {name}"[:100]
        if scheme:
            body = f"{OFFER_ACTIVE_PREFIX}{scheme[0]['title']}. {ANNOUNCE_CALL_TO_ACTION}"
        else:
            body = f"Now featured in {city}. {ANNOUNCE_CALL_TO_ACTION}"

        # Customers of that city (same city name, any capitals), never the owner
        pattern = city.replace("\\", "\\\\").replace("%", "\\%").replace("_", "\\_")
        customers = (
            supabase.table("profiles").select("id")
            .ilike("city", pattern).eq("role", "customer").neq("id", shop["owner_id"])
            .execute()
        ).data or []
        user_ids = [c["id"] for c in customers]
        for i in range(0, len(user_ids), _ANNOUNCE_BATCH):
            supabase.table("notifications").insert([
                {"user_id": uid, "type": "promotion", "title": title, "body": body,
                 "shop_name": name, "shop_id": shop_id}
                for uid in user_ids[i:i + _ANNOUNCE_BATCH]
            ]).execute()
        push_service.notify_users(user_ids, "promotion", title, body, {"shop_id": shop_id})
        logger.info("Elite announcement for shop %s sent to %d customers in %s", shop_id, len(user_ids), city)
        return len(user_ids)
    except Exception as e:
        logger.error("Elite announcement for shop %s failed: %s", shop_id, e)
        return 0


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

    require_active_subscription(promo.data["shop_id"])
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
