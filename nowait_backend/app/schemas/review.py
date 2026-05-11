from typing import Optional
from pydantic import BaseModel, Field


class ReviewCreate(BaseModel):
    rating: int = Field(..., ge=1, le=5, description="Star rating 1–5")
    review: Optional[str] = Field(None, max_length=1000, description="Optional text review")
    queue_entry_id: str = Field(..., description="The completed queue entry ID this review is for")


class ReviewResponse(BaseModel):
    id: str
    shop_id: str
    user_id: str
    queue_entry_id: Optional[str]
    rating: int
    review: Optional[str]
    user_name: str
    created_at: str


class ReviewSummary(BaseModel):
    average_rating: float
    total_reviews: int
    rating_distribution: dict  # {"1": count, "2": count, ...}


class ReviewListResponse(BaseModel):
    reviews: list[ReviewResponse]
    total: int
    page: int
    has_more: bool
