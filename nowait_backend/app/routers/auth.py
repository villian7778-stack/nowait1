from fastapi import APIRouter, Depends, Request

from app.dependencies import get_current_user, get_token_claims
from app.rate_limit import limiter
from app.schemas.auth import (
    AuthResponse,
    CompleteProfileRequest,
    ForgotPasswordRequest,
    LoginRequest,
    ProfileResponse,
    RefreshTokenRequest,
    RegisterRequest,
    RegisterResponse,
)
from app.services import auth_service

router = APIRouter(prefix="/auth", tags=["Authentication"])


@router.post("/register", response_model=RegisterResponse, summary="Register with email and password")
@limiter.limit("5/minute")
def register(request: Request, body: RegisterRequest):
    """
    Creates an account and profile in one step. The mobile number is stored on the
    profile but is never used for login or verified by OTP.

    **Sample Request:**
    ```json
    {
      "name": "Rahul Sharma",
      "phone": "+911234567890",
      "email": "rahul@example.com",
      "password": "Str0ngPass!",
      "state": "Maharashtra",
      "city": "Mumbai",
      "role": "customer"
    }
    ```
    If Supabase's "Confirm email" setting is enabled, no session is returned and
    `email_confirmation_required` is true — the user must confirm via email before
    calling `/auth/login`.
    """
    return auth_service.register(body)


@router.post("/login", response_model=AuthResponse, summary="Log in with email and password")
@limiter.limit("5/minute")
def login(request: Request, body: LoginRequest):
    """
    **Sample Request:**
    ```json
    {"email": "rahul@example.com", "password": "Str0ngPass!"}
    ```
    """
    return auth_service.login(body)


@router.post("/forgot-password", summary="Send a password reset link to the given email")
@limiter.limit("3/minute")
def forgot_password(request: Request, body: ForgotPasswordRequest):
    """Uses Supabase's built-in secure password reset flow. Always returns a generic
    success message regardless of whether the email exists, to avoid account enumeration."""
    return auth_service.forgot_password(body.email)


@router.post("/complete-profile", response_model=ProfileResponse, summary="Complete profile after Google sign-in")
def complete_profile(body: CompleteProfileRequest, claims: dict = Depends(get_token_claims)):
    """
    Called once after a new Google sign-in with no existing profile. Sets name,
    phone, state, city, and role. The email is taken from the JWT (Google-provided),
    never re-entered by the user.
    """
    user_id = claims.get("sub")
    email = claims.get("email") or ""
    from fastapi import HTTPException, status
    if not user_id:
        raise HTTPException(status_code=status.HTTP_401_UNAUTHORIZED, detail="Invalid token payload")
    return auth_service.complete_profile(user_id, email, body)


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
