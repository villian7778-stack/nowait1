from fastapi import APIRouter, Depends, HTTPException

from app.dependencies import get_current_owner, get_current_user
from app.schemas.staff import AddStaffByNameRequest
from app.services import staff_service

router = APIRouter(prefix="/staff", tags=["Staff"])


@router.get("/shops/{shop_id}/public", summary="List staff for shop (any authenticated user — customer info view)")
def get_staff_public(shop_id: str, current_user: dict = Depends(get_current_user)):
    return staff_service.get_staff_public(shop_id)


@router.get("/shops/{shop_id}", summary="List staff for shop with details (owner only)")
def get_staff(shop_id: str, current_user: dict = Depends(get_current_owner)):
    return staff_service.get_staff(shop_id, current_user["id"])


@router.post("/shops/{shop_id}/by-name", summary="Add staff by display name — no app account required (owner only)")
def add_staff_by_name(shop_id: str, body: AddStaffByNameRequest, current_user: dict = Depends(get_current_owner)):
    name = body.name.strip()
    if not name:
        raise HTTPException(status_code=400, detail="name is required")
    return staff_service.add_staff_by_name(shop_id, current_user["id"], name)


@router.post("/shops/{shop_id}", summary="Add staff by phone number (owner only)")
def add_staff(shop_id: str, body: dict, current_user: dict = Depends(get_current_owner)):
    phone = body.get("phone", "")
    if not phone:
        raise HTTPException(status_code=400, detail="phone is required")
    return staff_service.add_staff(shop_id, current_user["id"], phone)


@router.delete("/shops/{shop_id}/{staff_id}", summary="Remove staff member by staff record ID (owner only)")
def remove_staff(shop_id: str, staff_id: str, current_user: dict = Depends(get_current_owner)):
    return staff_service.remove_staff(shop_id, current_user["id"], staff_id)


@router.post("/self-register", summary="Owner registers themselves as a visible staff member")
def self_register(current_user: dict = Depends(get_current_owner)):
    return staff_service.self_register_as_staff(current_user["id"])


@router.get("/my-assignments", summary="Get shops where I am staff")
def my_assignments(current_user: dict = Depends(get_current_user)):
    return staff_service.get_my_staff_assignments(current_user["id"])
