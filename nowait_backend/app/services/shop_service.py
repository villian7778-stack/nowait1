import uuid
from datetime import datetime, timezone
from typing import List, Optional

from fastapi import HTTPException

from app.database import execute_one, supabase
from app.schemas.shop import ShopCreate, ShopUpdate

MAX_SHOP_IMAGES = 10
_STORAGE_BUCKET = "shop-images"


def _has_active_subscription(shop_id: str) -> bool:
    result = execute_one(
        supabase.table("subscriptions")
        .select("id")
        .eq("shop_id", shop_id)
        .eq("status", "active")
        .gt("expires_at", datetime.now(timezone.utc).isoformat())
    )
    return result.data is not None


_PROMOTION_BOOST_TITLE = "Featured Promotion"


def _get_active_promotions(shop_id: str) -> list:
    """Return all active (non-expired) promotions for the shop."""
    result = (
        supabase.table("promotions")
        .select("*")
        .eq("shop_id", shop_id)
        .eq("is_active", True)
        .gt("valid_until", datetime.now(timezone.utc).isoformat())
        .execute()
    )
    return result.data or []


def _get_queue_stats(shop_id: str) -> dict:
    result = (
        supabase.table("queue_entries")
        .select("token_number, status")
        .eq("shop_id", shop_id)
        .in_("status", ["waiting", "serving"])
        .execute()
    )
    entries = result.data or []
    total = len(entries)
    serving = next((e["token_number"] for e in entries if e["status"] == "serving"), None)
    return {"queue_count": total, "now_serving_token": serving}


def _enrich_shop(shop: dict) -> dict:
    has_sub = _has_active_subscription(shop["id"])
    active_promotions = _get_active_promotions(shop["id"])
    # is_promoted = shop paid for a visibility boost (title == "Featured Promotion")
    is_promoted = any(p.get("title") == _PROMOTION_BOOST_TITLE for p in active_promotions)
    stats = _get_queue_stats(shop["id"])
    return {
        **shop,
        "has_active_subscription": has_sub,
        "can_accept_queue": shop["is_open"] and has_sub and not shop.get("queue_paused", False),
        "is_promoted": is_promoted,
        "active_promotions": active_promotions,
        **stats,
    }


def list_shops(city: Optional[str] = None, category: Optional[str] = None, open_only: bool = False) -> dict:
    query = supabase.table("shops").select("*")
    if city:
        query = query.ilike("city", f"%{city}%")
    if category:
        query = query.ilike("category", f"%{category}%")
    if open_only:
        query = query.eq("is_open", True)

    result = query.order("created_at", desc=True).execute()
    raw_shops = result.data or []
    if not raw_shops:
        return {"shops": [], "total": 0}

    shop_ids = [s["id"] for s in raw_shops]
    now_iso = datetime.now(timezone.utc).isoformat()

    # Batch query 1: active subscriptions
    sub_result = (
        supabase.table("subscriptions")
        .select("shop_id")
        .in_("shop_id", shop_ids)
        .eq("status", "active")
        .gt("expires_at", now_iso)
        .execute()
    )
    shops_with_sub = {r["shop_id"] for r in (sub_result.data or [])}

    # Batch query 2: active promotions
    promo_result = (
        supabase.table("promotions")
        .select("*")
        .in_("shop_id", shop_ids)
        .eq("is_active", True)
        .gt("valid_until", now_iso)
        .execute()
    )
    promos_by_shop: dict = {}
    for p in (promo_result.data or []):
        promos_by_shop.setdefault(p["shop_id"], []).append(p)

    # Batch query 3: queue stats
    queue_result = (
        supabase.table("queue_entries")
        .select("shop_id, token_number, status")
        .in_("shop_id", shop_ids)
        .in_("status", ["waiting", "serving"])
        .execute()
    )
    queue_by_shop: dict = {}
    for e in (queue_result.data or []):
        queue_by_shop.setdefault(e["shop_id"], []).append(e)

    shops = []
    for shop in raw_shops:
        sid = shop["id"]
        has_sub = sid in shops_with_sub
        active_promotions = promos_by_shop.get(sid, [])
        is_promoted = any(p.get("title") == _PROMOTION_BOOST_TITLE for p in active_promotions)
        entries = queue_by_shop.get(sid, [])
        total = len(entries)
        serving = next((e["token_number"] for e in entries if e["status"] == "serving"), None)
        shops.append({
            **shop,
            "has_active_subscription": has_sub,
            "can_accept_queue": shop["is_open"] and has_sub and not shop.get("queue_paused", False),
            "is_promoted": is_promoted,
            "active_promotions": active_promotions,
            "queue_count": total,
            "now_serving_token": serving,
        })

    return {"shops": shops, "total": len(shops)}


def get_shop(shop_id: str) -> dict:
    result = execute_one(supabase.table("shops").select("*").eq("id", shop_id))
    if not result.data:
        raise HTTPException(status_code=404, detail="Shop not found")
    shop = _enrich_shop(result.data)  # already includes active_promotions

    # Get services
    svc_result = supabase.table("services").select("*").eq("shop_id", shop_id).execute()
    shop["services"] = svc_result.data or []
    return shop


def get_owner_shop(owner_id: str) -> dict:
    result = execute_one(supabase.table("shops").select("*").eq("owner_id", owner_id))
    if not result.data:
        raise HTTPException(status_code=404, detail="No shop found for this owner")
    return get_shop(result.data["id"])


def create_shop(owner_id: str, data: ShopCreate) -> dict:
    # Prevent owner from having multiple shops
    existing = execute_one(supabase.table("shops").select("id").eq("owner_id", owner_id))
    if existing.data:
        raise HTTPException(status_code=400, detail="You already have a shop. Use update to modify it.")

    shop_data = {
        "owner_id": owner_id,
        "name": data.name,
        "category": data.category,
        "address": data.address,
        "city": data.city,
        "state": data.state,
        "avg_wait_minutes": data.avg_wait_minutes,
        "images": data.images,
        "description": data.description,
        **({"opening_hours": data.opening_hours} if data.opening_hours else {}),
    }
    result = supabase.table("shops").insert(shop_data).execute()
    if not result.data:
        raise HTTPException(status_code=500, detail="Failed to create shop")
    shop = result.data[0]

    # Create services
    if data.services:
        services_data = [
            {"shop_id": shop["id"], "name": s.name, "description": s.description, "price": s.price}
            for s in data.services
        ]
        supabase.table("services").insert(services_data).execute()

    return get_shop(shop["id"])


def update_shop(shop_id: str, owner_id: str, data: ShopUpdate) -> dict:
    # Verify ownership
    existing = execute_one(
        supabase.table("shops")
        .select("id")
        .eq("id", shop_id)
        .eq("owner_id", owner_id)
    )
    if not existing.data:
        raise HTTPException(status_code=403, detail="Not authorized to update this shop")

    update_data = {k: v for k, v in data.model_dump().items() if v is not None}
    if not update_data:
        raise HTTPException(status_code=400, detail="No fields to update")

    supabase.table("shops").update(update_data).eq("id", shop_id).execute()
    return get_shop(shop_id)


def toggle_open(shop_id: str, owner_id: str) -> dict:
    existing = execute_one(
        supabase.table("shops")
        .select("id, is_open")
        .eq("id", shop_id)
        .eq("owner_id", owner_id)
    )
    if not existing.data:
        raise HTTPException(status_code=403, detail="Not authorized or shop not found")

    new_state = not existing.data["is_open"]
    supabase.table("shops").update({"is_open": new_state}).eq("id", shop_id).execute()
    return {
        "shop_id": shop_id,
        "is_open": new_state,
        "message": f"Shop is now {'open' if new_state else 'closed'}",
    }


def get_categories() -> List[str]:
    result = supabase.table("shops").select("category").execute()
    categories = list({s["category"] for s in (result.data or []) if s.get("category")})
    return sorted(categories)


def get_cities() -> List[str]:
    result = supabase.table("shops").select("city").execute()
    seen: dict = {}
    for s in (result.data or []):
        city = (s.get("city") or "").strip()
        if city:
            key = city.lower()
            if key not in seen:
                seen[key] = city
    return sorted(seen.values())


def add_service(shop_id: str, owner_id: str, name: str, description: str, price: float) -> dict:
    existing = execute_one(
        supabase.table("shops")
        .select("id")
        .eq("id", shop_id)
        .eq("owner_id", owner_id)
    )
    if not existing.data:
        raise HTTPException(status_code=403, detail="Not authorized")
    result = supabase.table("services").insert({
        "shop_id": shop_id,
        "name": name,
        "description": description,
        "price": price,
    }).execute()
    return result.data[0]


def upload_shop_image(shop_id: str, owner_id: str, file_data: bytes, original_filename: str, content_type: str) -> dict:
    existing = execute_one(
        supabase.table("shops").select("id, images").eq("id", shop_id).eq("owner_id", owner_id)
    )
    if not existing.data:
        raise HTTPException(status_code=403, detail="Not authorized or shop not found")

    current_images: list = existing.data.get("images") or []
    if len(current_images) >= MAX_SHOP_IMAGES:
        raise HTTPException(status_code=400, detail=f"Maximum {MAX_SHOP_IMAGES} images allowed per shop")

    ext = original_filename.rsplit(".", 1)[-1].lower() if "." in original_filename else "jpg"
    storage_path = f"{shop_id}/{uuid.uuid4()}.{ext}"

    supabase.storage.from_(_STORAGE_BUCKET).upload(
        path=storage_path,
        file=file_data,
        file_options={"content-type": content_type, "upsert": "true"},
    )

    public_url: str = supabase.storage.from_(_STORAGE_BUCKET).get_public_url(storage_path)

    new_images = current_images + [public_url]
    supabase.table("shops").update({"images": new_images}).eq("id", shop_id).execute()
    return {"url": public_url, "images": new_images}


def delete_shop_image(shop_id: str, owner_id: str, image_url: str) -> dict:
    existing = execute_one(
        supabase.table("shops").select("id, images").eq("id", shop_id).eq("owner_id", owner_id)
    )
    if not existing.data:
        raise HTTPException(status_code=403, detail="Not authorized or shop not found")

    current_images: list = existing.data.get("images") or []
    if image_url not in current_images:
        raise HTTPException(status_code=404, detail="Image not found in this shop")

    bucket_prefix = f"/storage/v1/object/public/{_STORAGE_BUCKET}/"
    idx = image_url.find(bucket_prefix)
    if idx != -1:
        storage_path = image_url[idx + len(bucket_prefix):]
        try:
            supabase.storage.from_(_STORAGE_BUCKET).remove([storage_path])
        except Exception:
            pass

    new_images = [u for u in current_images if u != image_url]
    supabase.table("shops").update({"images": new_images}).eq("id", shop_id).execute()
    return {"images": new_images}


def delete_service(service_id: str, owner_id: str) -> bool:
    svc = execute_one(supabase.table("services").select("shop_id").eq("id", service_id))
    if not svc.data:
        raise HTTPException(status_code=404, detail="Service not found")
    shop = execute_one(
        supabase.table("shops")
        .select("id")
        .eq("id", svc.data["shop_id"])
        .eq("owner_id", owner_id)
    )
    if not shop.data:
        raise HTTPException(status_code=403, detail="Not authorized")
    supabase.table("services").delete().eq("id", service_id).execute()
    return True
