from typing import Optional
from pydantic import BaseModel, EmailStr, Field, field_validator


class RegisterRequest(BaseModel):
    name: str = Field(min_length=2, max_length=100)
    phone: str  # E.164 format: +911234567890
    email: EmailStr
    password: str = Field(min_length=8, max_length=72)
    state: str = Field(min_length=1, max_length=100)
    city: str = Field(min_length=1, max_length=100)
    role: str

    @field_validator("name")
    @classmethod
    def validate_name(cls, v: str) -> str:
        return v.strip()

    @field_validator("phone")
    @classmethod
    def validate_phone(cls, v: str) -> str:
        v = v.strip()
        if not v.startswith("+"):
            raise ValueError("Phone must be in E.164 format starting with '+'")
        if len(v) < 8 or len(v) > 16:
            raise ValueError("Invalid phone number length")
        return v

    @field_validator("role")
    @classmethod
    def validate_role(cls, v: str) -> str:
        if v not in ("customer", "owner"):
            raise ValueError("Role must be 'customer' or 'owner'")
        return v


class LoginRequest(BaseModel):
    email: EmailStr
    password: str


class ForgotPasswordRequest(BaseModel):
    email: EmailStr


class CompleteProfileRequest(BaseModel):
    name: str = Field(min_length=2, max_length=100)
    phone: str
    state: str = Field(min_length=1, max_length=100)
    city: str = Field(min_length=1, max_length=100)
    role: str

    @field_validator("phone")
    @classmethod
    def validate_phone(cls, v: str) -> str:
        v = v.strip()
        if not v.startswith("+"):
            raise ValueError("Phone must be in E.164 format starting with '+'")
        if len(v) < 8 or len(v) > 16:
            raise ValueError("Invalid phone number length")
        return v

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
    email: str = ""
    state: str = ""
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


class RegisterResponse(BaseModel):
    access_token: Optional[str] = None
    token_type: str = "bearer"
    expires_in: Optional[int] = None
    refresh_token: Optional[str] = None
    profile: Optional[ProfileResponse] = None
    email_confirmation_required: bool = False
    message: Optional[str] = None


class RefreshTokenRequest(BaseModel):
    refresh_token: str
