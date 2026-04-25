from typing import Optional
from pydantic import BaseModel, Field, field_validator


class SendOTPRequest(BaseModel):
    phone: str  # E.164 format: +911234567890

    @field_validator("phone")
    @classmethod
    def validate_phone(cls, v: str) -> str:
        v = v.strip()
        if not v.startswith("+"):
            raise ValueError("Phone must be in E.164 format starting with '+'")
        if len(v) < 8 or len(v) > 16:
            raise ValueError("Invalid phone number length")
        return v


class VerifyOTPRequest(BaseModel):
    phone: str
    token: str


class CompleteProfileRequest(BaseModel):
    name: str = Field(min_length=2, max_length=100)
    state: str = Field(min_length=1, max_length=100)
    city: str = Field(min_length=1, max_length=100)
    role: str
    phone: Optional[str] = None  # used in demo mode when JWT has no phone claim

    @field_validator("role")
    @classmethod
    def validate_role(cls, v: str) -> str:
        if v not in ("customer", "owner"):
            raise ValueError("Role must be 'customer' or 'owner'")
        return v

    @field_validator("name")
    @classmethod
    def validate_name(cls, v: str) -> str:
        return v.strip()


class ProfileResponse(BaseModel):
    id: str
    name: str
    phone: str
    state: str = ''
    city: str
    role: str
    created_at: str


class AuthResponse(BaseModel):
    access_token: str
    token_type: str = "bearer"
    expires_in: int
    refresh_token: str
    profile: Optional[ProfileResponse] = None
    profile_required: bool = False


class RefreshTokenRequest(BaseModel):
    refresh_token: str
