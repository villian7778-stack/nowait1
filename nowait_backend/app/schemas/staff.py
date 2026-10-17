from pydantic import BaseModel, Field
from typing import Optional


class AddStaffRequest(BaseModel):
    phone: str = Field(min_length=10, max_length=16)  # Find user by phone number


class StaffMemberResponse(BaseModel):
    id: str
    shop_id: str
    user_id: str
    display_name: str
    is_owner_staff: bool
    is_active: bool
    avg_service_minutes: Optional[float]
    created_at: str


class AddStaffByNameRequest(BaseModel):
    name: str = Field(min_length=1, max_length=60)
