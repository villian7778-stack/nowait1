from typing import List, Optional
from pydantic import BaseModel, Field


class ServiceCreate(BaseModel):
    name: str = Field(min_length=1, max_length=100)
    description: str = Field(default="", max_length=500)
    price: float = Field(ge=0)


class ServiceResponse(BaseModel):
    id: str
    shop_id: str
    name: str
    description: str
    price: float


class ShopCreate(BaseModel):
    name: str = Field(min_length=1, max_length=100)
    category: str = Field(min_length=1, max_length=50)
    address: str = Field(min_length=1, max_length=300)
    city: str = Field(min_length=1, max_length=100)
    avg_wait_minutes: int = Field(default=10, ge=1, le=240)
    images: List[str] = Field(default=[], max_length=10)
    description: str = Field(default="", max_length=1000)
    services: List[ServiceCreate] = []


class ShopUpdate(BaseModel):
    name: Optional[str] = Field(default=None, max_length=100)
    category: Optional[str] = Field(default=None, max_length=50)
    address: Optional[str] = Field(default=None, max_length=300)
    city: Optional[str] = Field(default=None, max_length=100)
    avg_wait_minutes: Optional[int] = Field(default=None, ge=1, le=240)
    images: Optional[List[str]] = Field(default=None, max_length=10)
    description: Optional[str] = Field(default=None, max_length=1000)


class PromotionInShop(BaseModel):
    id: str
    title: str
    description: str
    valid_until: str
    is_active: bool


class ShopSummary(BaseModel):
    id: str
    name: str
    category: str
    address: str
    city: str
    is_open: bool
    has_active_subscription: bool
    can_accept_queue: bool
    avg_wait_minutes: int
    rating: float
    images: List[str]
    queue_count: int
    now_serving_token: Optional[int]
    description: str
    is_promoted: bool = False
    active_promotions: List[PromotionInShop] = []


class ShopDetail(ShopSummary):
    owner_id: str
    services: List[ServiceResponse]


class ShopListResponse(BaseModel):
    shops: List[ShopSummary]
    total: int


class ToggleOpenResponse(BaseModel):
    shop_id: str
    is_open: bool
    message: str


class DeleteImageRequest(BaseModel):
    image_url: str


class ImageUploadResponse(BaseModel):
    url: str
    images: List[str]


class DeleteImageResponse(BaseModel):
    images: List[str]
