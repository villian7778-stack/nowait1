import logging
from collections import Counter

from fastapi import HTTPException
from postgrest.exceptions import APIError

from app.database import execute_one, supabase
from app.schemas.review import ReviewCreate

logger = logging.getLogger(__name__)

# Google Play's user-generated-content policy: users must be able to report objectionable
# reviews, and reported content must be removable. A review reported by this many different
# people is hidden from everyone until an admin looks at it (admin panel → Reported Reviews).
AUTO_HIDE_REPORTS = 3


def _visible_only(build):
    """Runs build(True) - the query restricted to reviews that are not hidden. If the database
    has not been migrated yet (no shop_reviews.is_hidden column), runs build(False) instead so
    reviews keep working, and logs loudly that sql/final_consolidated.sql needs to be run."""
    try:
        return build(True).execute()
    except APIError as e:
        if "is_hidden" in str(e):
            logger.error("shop_reviews.is_hidden is missing - run sql/final_consolidated.sql. Showing all reviews.")
            return build(False).execute()
        raise


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

    def count_query(visible):
        q = supabase.table("shop_reviews").select("id", count="exact").eq("shop_id", shop_id)
        return q.eq("is_hidden", False) if visible else q

    def page_query(visible):
        q = supabase.table("shop_reviews").select("*").eq("shop_id", shop_id)
        if visible:
            q = q.eq("is_hidden", False)
        return q.order("created_at", desc=True).range(offset, offset + limit - 1)

    total = _visible_only(count_query).count or 0
    reviews = _visible_only(page_query).data or []

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
    def query(visible):
        q = supabase.table("shop_reviews").select("rating").eq("shop_id", shop_id)
        return q.eq("is_hidden", False) if visible else q

    result = _visible_only(query)
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

    def query(visible):
        q = supabase.table("shop_reviews").select("shop_id, rating").in_("shop_id", shop_ids)
        return q.eq("is_hidden", False) if visible else q

    result = _visible_only(query)
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


# ── Reporting (Google Play user-generated-content policy) ────────────────────────────────

def report_review(review_id: str, reporter_id: str, reason: str, details: str | None = None) -> dict:
    """Records that a signed-in user finds a review objectionable. Each person can report a
    review once; once AUTO_HIDE_REPORTS different people have, it is hidden from everyone."""
    review = execute_one(supabase.table("shop_reviews").select("id, user_id, is_hidden").eq("id", review_id)).data
    if not review:
        raise HTTPException(status_code=404, detail="Review not found")
    if review["user_id"] == reporter_id:
        raise HTTPException(status_code=400, detail="You can't report your own review.")

    try:
        supabase.table("review_reports").insert({
            "review_id": review_id,
            "reporter_id": reporter_id,
            "reason": reason,
            "details": (details or "").strip()[:300] or None,
        }).execute()
    except Exception as e:
        if "23505" in str(e) or "duplicate key" in str(e).lower():
            return {"reported": True, "already_reported": True}
        logger.error("Could not save report for review %s: %s", review_id, e)
        raise HTTPException(status_code=500, detail="Could not send the report. Please try again.")

    count = (
        supabase.table("review_reports").select("id", count="exact").eq("review_id", review_id).execute().count or 0
    )
    logger.info("Review %s reported (%s) - %d report(s) so far", review_id, reason, count)
    if count >= AUTO_HIDE_REPORTS and not review.get("is_hidden"):
        supabase.table("shop_reviews").update({"is_hidden": True}).eq("id", review_id).execute()
        logger.warning("Review %s hidden automatically after %d reports - check the admin panel", review_id, count)
    return {"reported": True, "already_reported": False}


def admin_list_reported(page: int = 1, limit: int = 20) -> dict:
    """Reviews that have at least one report, most recently reported first."""
    reports = (
        supabase.table("review_reports").select("review_id, reason, details, created_at")
        .order("created_at", desc=True).execute().data or []
    )
    grouped: dict[str, dict] = {}
    for r in reports:
        g = grouped.setdefault(r["review_id"], {"count": 0, "reasons": Counter(), "details": [], "last_reported": r["created_at"]})
        g["count"] += 1
        g["reasons"][r.get("reason") or "other"] += 1
        if r.get("details"):
            g["details"].append(r["details"])

    ids = list(grouped)  # already newest-first
    page_ids = ids[(page - 1) * limit: page * limit]
    rows = []
    if page_ids:
        reviews = {r["id"]: r for r in (supabase.table("shop_reviews").select("*").in_("id", page_ids).execute().data or [])}
        shop_ids = list({r["shop_id"] for r in reviews.values()})
        user_ids = list({r["user_id"] for r in reviews.values()})
        shops = {s["id"]: s["name"] for s in (supabase.table("shops").select("id, name").in_("id", shop_ids).execute().data or [])} if shop_ids else {}
        users = {u["id"]: u["name"] for u in (supabase.table("profiles").select("id, name").in_("id", user_ids).execute().data or [])} if user_ids else {}
        for rid in page_ids:
            rv = reviews.get(rid)
            if not rv:
                continue
            g = grouped[rid]
            rows.append({
                **rv,
                "shop_name": shops.get(rv["shop_id"], "Unknown"),
                "user_name": users.get(rv["user_id"], "Customer"),
                "report_count": g["count"],
                "reasons": dict(g["reasons"]),
                "report_details": g["details"][:5],
                "last_reported": g["last_reported"],
            })
    return {"reviews": rows, "total": len(ids), "page": page}


def admin_set_hidden(review_id: str, hidden: bool) -> None:
    """Hide a review, or make it visible again. Making it visible also dismisses its reports,
    so it is not hidden again straight away by the reports that were already looked at."""
    supabase.table("shop_reviews").update({"is_hidden": hidden}).eq("id", review_id).execute()
    if not hidden:
        supabase.table("review_reports").delete().eq("review_id", review_id).execute()


def admin_delete_review(review_id: str) -> None:
    supabase.table("shop_reviews").delete().eq("id", review_id).execute()  # its reports go with it (FK cascade)
