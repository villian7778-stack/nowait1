from typing import List, Optional
from pydantic import BaseModel, Field


class PromotionCreate(BaseModel):
    title: str = Field(min_length=1, max_length=100)
    description: str = Field(min_length=1, max_length=500)
    valid_until: str = Field(max_length=40)  # ISO datetime string


class PromotionUpdate(BaseModel):
    title: Optional[str] = Field(default=None, min_length=1, max_length=100)
    description: Optional[str] = Field(default=None, min_length=1, max_length=500)
    valid_until: Optional[str] = Field(default=None, max_length=40)
    is_active: Optional[bool] = None


class PromotionResponse(BaseModel):
    id: str
    shop_id: str
    title: str
    description: str
    valid_until: str
    is_active: bool
    created_at: str


class PromotionListResponse(BaseModel):
    promotions: List[PromotionResponse]
