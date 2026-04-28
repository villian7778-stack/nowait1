from fastapi import APIRouter, Depends

from app.dependencies import get_current_user, get_token_claims
from app.schemas.auth import (
    AuthResponse,
    CompleteProfileRequest,
    ProfileResponse,
    RefreshTokenRequest,
    SendOTPRequest,
    VerifyOTPRequest,
)
from app.services import auth_service

router = APIRouter(prefix="/auth", tags=["Authentication"])


@router.post("/send-otp", summary="Send OTP to phone number")
def send_otp(body: SendOTPRequest):
    """
    Send an OTP SMS to the given phone number via Supabase Auth.
    Phone must be in E.164 format (e.g., +911234567890).

    **Sample Request:**
    ```json
    {"phone": "+911234567890"}
    ```
    **Sample Response:**
    ```json
    {"message": "OTP sent to +911234567890"}
    ```
    """
    return auth_service.send_otp(body.phone)


@router.post("/verify-otp", response_model=AuthResponse, summary="Verify OTP and get access token")
def verify_otp(body: VerifyOTPRequest):
    """
    Verify the OTP and receive a JWT access token.
    If `profile_required` is true, call `POST /auth/complete-profile` next.

    **Sample Request:**
    ```json
    {"phone": "+911234567890", "token": "123456"}
    ```
    **Sample Response:**
    ```json
    {
      "access_token": "eyJ...",
      "token_type": "bearer",
      "expires_in": 3600,
      "refresh_token": "...",
      "profile": null,
      "profile_required": true
    }
    ```
    """
    return auth_service.verify_otp(body.phone, body.token)


@router.post("/complete-profile", response_model=ProfileResponse, summary="Complete user profile after first login")
def complete_profile(body: CompleteProfileRequest, claims: dict = Depends(get_token_claims)):
    """
    Called once after first OTP verification. Sets name, city, and role.
    The phone number is extracted from the JWT payload (phone claim).

    **Sample Request:**
    ```json
    {"name": "Rahul Sharma", "city": "Mumbai", "role": "customer"}
    ```
    """
    user_id = claims.get("sub")
    phone = claims.get("phone") or body.phone or ""
    if not user_id:
        from fastapi import HTTPException, status
        raise HTTPException(status_code=status.HTTP_401_UNAUTHORIZED, detail="Invalid token payload")
    return auth_service.complete_profile(user_id, phone, body)


@router.get("/me", response_model=ProfileResponse, summary="Get current user profile")
def get_me(current_user: dict = Depends(get_current_user)):
    """Returns the authenticated user's profile."""
    return current_user


@router.post("/refresh", summary="Refresh access token")
def refresh_token(body: RefreshTokenRequest):
    """Exchange a refresh token for a new access token."""
    return auth_service.refresh_session(body.refresh_token)


@router.delete("/account", summary="Permanently delete user account and all associated data")
def delete_account(current_user: dict = Depends(get_current_user)):
    """
    Permanently delete the authenticated user's account.
    For shop owners, all shop images are removed from storage first.
    Deleting the auth user cascades to: profiles → shops → services, subscriptions,
    promotions, queue_entries, notifications, shop_staff.
    """
    return auth_service.delete_account(current_user["id"])


@router.post("/fcm-token", summary="Save FCM push token for this user")
def save_fcm_token(body: dict, current_user: dict = Depends(get_current_user)):
    """Save or update the Firebase Cloud Messaging token for push notifications."""
    from app.database import supabase
    token = body.get("fcm_token", "")
    if not token:
        from fastapi import HTTPException
        raise HTTPException(status_code=400, detail="fcm_token is required")
    supabase.table("profiles").update({"fcm_token": token}).eq("id", current_user["id"]).execute()
    return {"message": "FCM token saved"}
