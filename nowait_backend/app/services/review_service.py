from fastapi import HTTPException

from app.database import execute_one, supabase
from app.schemas.review import ReviewCreate


def submit_review(shop_id: str, user_id: str, data: ReviewCreate) -> dict:
    # Verify the queue entry belongs to this user and is completed
    entry = execute_one(
        supabase.table("queue_entries")
        .select("id, shop_id, status, user_id")
        .eq("id", data.queue_entry_id)
        .eq("user_id", user_id)
    )
    if not entry.data:
        raise HTTPException(status_code=404, detail="Queue entry not found")
    if entry.data["shop_id"] != shop_id:
        raise HTTPException(status_code=400, detail="Queue entry does not belong to this shop")
    if entry.data["status"] != "completed":
        raise HTTPException(status_code=400, detail="Can only review completed visits")

    # Upsert so re-submission replaces previous rating for same visit
    result = (
        supabase.table("shop_reviews")
        .upsert(
            {
                "shop_id": shop_id,
                "user_id": user_id,
                "queue_entry_id": data.queue_entry_id,
                "rating": data.rating,
                "review": data.review,
            },
            on_conflict="user_id,queue_entry_id",
        )
        .execute()
    )
    if not result.data:
        raise HTTPException(status_code=500, detail="Failed to save review")

    review = result.data[0]
    # Fetch reviewer name
    profile = execute_one(supabase.table("profiles").select("name").eq("id", user_id))
    review["user_name"] = profile.data["name"] if profile.data else "Customer"
    return review


def get_shop_reviews(shop_id: str, page: int = 1, limit: int = 20) -> dict:
    offset = (page - 1) * limit

    count_result = (
        supabase.table("shop_reviews")
        .select("id", count="exact")
        .eq("shop_id", shop_id)
        .execute()
    )
    total = count_result.count or 0

    result = (
        supabase.table("shop_reviews")
        .select("*")
        .eq("shop_id", shop_id)
        .order("created_at", desc=True)
        .range(offset, offset + limit - 1)
        .execute()
    )
    reviews = result.data or []

    if reviews:
        user_ids = list({r["user_id"] for r in reviews})
        profiles_result = (
            supabase.table("profiles")
            .select("id, name")
            .in_("id", user_ids)
            .execute()
        )
        name_map = {p["id"]: p["name"] for p in (profiles_result.data or [])}
        for r in reviews:
            r["user_name"] = name_map.get(r["user_id"], "Customer")

    # Compute average from all reviews (not just this page)
    summary = get_review_summary(shop_id)

    return {
        "reviews": reviews,
        "total": total,
        "page": page,
        "has_more": offset + limit < total,
        "avg_rating": summary["average_rating"],
    }


def get_review_summary(shop_id: str) -> dict:
    result = (
        supabase.table("shop_reviews")
        .select("rating")
        .eq("shop_id", shop_id)
        .execute()
    )
    # Filter out None/null ratings to avoid sum() errors
    ratings = [int(r["rating"]) for r in (result.data or []) if r.get("rating") is not None]

    if not ratings:
        return {
            "average_rating": 0.0,
            "total_reviews": 0,
            "rating_distribution": {"1": 0, "2": 0, "3": 0, "4": 0, "5": 0},
        }

    distribution = {str(i): 0 for i in range(1, 6)}
    for r in ratings:
        key = str(r)
        if key in distribution:
            distribution[key] += 1

    avg = round(sum(ratings) / len(ratings), 1)
    return {
        "average_rating": avg,
        "total_reviews": len(ratings),
        "rating_distribution": distribution,
    }


def get_batch_review_summaries(shop_ids: list[str]) -> dict[str, dict]:
    """Batch-fetch review summaries for a list of shop IDs (used in list_shops)."""
    if not shop_ids:
        return {}
    result = (
        supabase.table("shop_reviews")
        .select("shop_id, rating")
        .in_("shop_id", shop_ids)
        .execute()
    )
    by_shop: dict[str, list[int]] = {}
    for r in (result.data or []):
        if r.get("rating") is not None:
            by_shop.setdefault(r["shop_id"], []).append(int(r["rating"]))

    summaries: dict[str, dict] = {}
    for sid in shop_ids:
        ratings = by_shop.get(sid, [])
        if ratings:
            summaries[sid] = {
                "avg_review_rating": round(sum(ratings) / len(ratings), 1),
                "review_count": len(ratings),
            }
        else:
            summaries[sid] = {"avg_review_rating": 0.0, "review_count": 0}
    return summaries
