from typing import List, Optional

from fastapi import APIRouter, Depends, File, Query, UploadFile

from app.dependencies import get_current_owner, get_current_user
from app.schemas.shop import (
    DeleteImageRequest,
    DeleteImageResponse,
    ImageUploadResponse,
    ServiceCreate,
    ServiceResponse,
    ShopCreate,
    ShopDetail,
    ShopListResponse,
    ShopUpdate,
    ToggleOpenResponse,
)
from app.services import shop_service

router = APIRouter(prefix="/shops", tags=["Shops"])


@router.get("/cities", summary="List distinct cities with shops")
def list_cities():
    """Returns distinct city names that have at least one shop."""
    return shop_service.get_cities()


@router.get("", response_model=ShopListResponse, summary="List all shops")
def list_shops(
    city: Optional[str] = Query(None, description="Filter by city"),
    category: Optional[str] = Query(None, description="Filter by category"),
    open_only: bool = Query(False, description="Only return open shops"),
):
    """
    Returns a list of shops with live queue counts and subscription status.

    **Sample Response:**
    ```json
    {
      "shops": [{
        "id": "uuid",
        "name": "Raj Hair Salon",
        "category": "Salon",
        "is_open": true,
        "queue_count": 5,
        "now_serving_token": 12,
        "can_accept_queue": true
      }],
      "total": 1
    }
    ```
    """
    return shop_service.list_shops(city=city, category=category, open_only=open_only)


@router.get("/categories", response_model=List[str], summary="Get all shop categories")
def get_categories():
    """Returns a sorted list of all unique shop categories."""
    return shop_service.get_categories()


@router.get("/my", summary="Get owner's shop (owner only)")
def get_my_shop(current_user: dict = Depends(get_current_owner)):
    """Returns the authenticated owner's shop with full details."""
    return shop_service.get_owner_shop(current_user["id"])


@router.get("/{shop_id}", response_model=ShopDetail, summary="Get shop details")
def get_shop(shop_id: str):
    """
    Returns full shop details with services, queue stats, and active promotions.
    """
    return shop_service.get_shop(shop_id)


@router.post("", response_model=ShopDetail, status_code=201, summary="Create a new shop (owner only)")
def create_shop(body: ShopCreate, current_user: dict = Depends(get_current_owner)):
    """
    Create a new shop. Each owner can have only one shop.

    **Sample Request:**
    ```json
    {
      "name": "Raj Hair Salon",
      "category": "Salon",
      "address": "123 MG Road",
      "city": "Mumbai",
      "avg_wait_minutes": 15,
      "services": [{"name": "Haircut", "description": "Classic cut", "price": 150}]
    }
    ```
    """
    return shop_service.create_shop(current_user["id"], body)


@router.put("/{shop_id}", response_model=ShopDetail, summary="Update shop details (owner only)")
def update_shop(shop_id: str, body: ShopUpdate, current_user: dict = Depends(get_current_owner)):
    """Update shop name, category, address, city, wait time, images, or description."""
    return shop_service.update_shop(shop_id, current_user["id"], body)


@router.post("/{shop_id}/toggle-open", response_model=ToggleOpenResponse, summary="Toggle shop open/closed (owner only)")
def toggle_open(shop_id: str, current_user: dict = Depends(get_current_owner)):
    """
    Toggles the shop between open and closed.
    Closed shops do not accept new queue entries.
    """
    return shop_service.toggle_open(shop_id, current_user["id"])


_ALLOWED_IMAGE_TYPES = {"image/jpeg", "image/png", "image/webp", "image/gif"}
_MAX_IMAGE_BYTES = 5 * 1024 * 1024  # 5 MB


@router.post("/{shop_id}/images", response_model=ImageUploadResponse, status_code=201, summary="Upload a shop image (owner only)")
async def upload_shop_image(
    shop_id: str,
    file: UploadFile = File(...),
    current_user: dict = Depends(get_current_owner),
):
    """Upload one image for the shop. Max 10 images, 5 MB each, JPEG/PNG/WebP/GIF only."""
    content_type = (file.content_type or "").lower()
    if content_type not in _ALLOWED_IMAGE_TYPES:
        raise HTTPException(status_code=415, detail="Only JPEG, PNG, WebP, or GIF images are allowed.")

    file_data = await file.read()
    if len(file_data) > _MAX_IMAGE_BYTES:
        raise HTTPException(status_code=413, detail="Image must be 5 MB or smaller.")

    return shop_service.upload_shop_image(
        shop_id,
        current_user["id"],
        file_data,
        file.filename or "image.jpg",
        content_type,
    )


@router.delete("/{shop_id}/images", response_model=DeleteImageResponse, summary="Delete a shop image (owner only)")
def delete_shop_image(
    shop_id: str,
    body: DeleteImageRequest,
    current_user: dict = Depends(get_current_owner),
):
    """Remove an image from the shop by its URL. Also deletes the file from storage."""
    return shop_service.delete_shop_image(shop_id, current_user["id"], body.image_url)


@router.post("/{shop_id}/services", response_model=ServiceResponse, status_code=201, summary="Add a service to the shop")
def add_service(shop_id: str, body: ServiceCreate, current_user: dict = Depends(get_current_owner)):
    """Add a new service (e.g. Haircut, Shave) to the owner's shop."""
    return shop_service.add_service(shop_id, current_user["id"], body.name, body.description, body.price)


@router.delete("/services/{service_id}", status_code=204, summary="Delete a service")
def delete_service(service_id: str, current_user: dict = Depends(get_current_owner)):
    """Permanently delete a service from the shop."""
    shop_service.delete_service(service_id, current_user["id"])
