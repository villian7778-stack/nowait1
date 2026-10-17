from fastapi import APIRouter, Depends, Query

from app.dependencies import get_current_user, get_token_user_id
from app.rate_limit import per_user_limit
from app.schemas.review import (
    ReviewCreate,
    ReviewListResponse,
    ReviewReportRequest,
    ReviewReportResponse,
    ReviewResponse,
    ReviewSummary,
)
from app.services import review_service

router = APIRouter(prefix="/reviews", tags=["Reviews"])


@router.post(
    "/shops/{shop_id}",
    response_model=ReviewResponse,
    status_code=201,
    summary="Submit a star rating and optional review for a completed visit",
)
def submit_review(
    shop_id: str,
    body: ReviewCreate,
    user_id: str = Depends(get_token_user_id),
):
    """
    Submit a 1–5 star rating (and optional text review) for a completed queue visit.
    Requires a `queue_entry_id` of a `completed` entry belonging to the authenticated user.
    Re-submitting for the same entry overwrites the previous rating.
    """
    return review_service.submit_review(shop_id, user_id, body)


@router.get(
    "/shops/{shop_id}",
    response_model=ReviewListResponse,
    summary="Get paginated reviews for a shop",
)
def get_reviews(
    shop_id: str,
    page: int = Query(1, ge=1),
    limit: int = Query(20, ge=1, le=50),
):
    """Returns paginated customer reviews for a shop, newest first."""
    return review_service.get_shop_reviews(shop_id, page=page, limit=limit)


@router.get(
    "/shops/{shop_id}/summary",
    response_model=ReviewSummary,
    summary="Get rating summary for a shop",
)
def get_summary(shop_id: str):
    """Returns average rating, total review count, and per-star distribution."""
    return review_service.get_review_summary(shop_id)


@router.post(
    "/{review_id}/report",
    response_model=ReviewReportResponse,
    summary="Report a review as spam, offensive or fake",
    dependencies=[Depends(per_user_limit("report-review", 10))],
)
def report_review(review_id: str, body: ReviewReportRequest, current_user: dict = Depends(get_current_user)):
    """Any signed-in user can report a review (not their own) once. After
    review_service.AUTO_HIDE_REPORTS different people report it, it is hidden from everyone
    until an admin restores or deletes it (admin panel -> Reported Reviews)."""
    return review_service.report_review(review_id, current_user["id"], body.reason, body.details)
