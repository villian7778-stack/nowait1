import logging

import httpx
from fastapi import HTTPException

logger = logging.getLogger(__name__)

from app.config import settings
from app.database import execute_one, supabase
from app.schemas.auth import CompleteProfileRequest, LoginRequest, RegisterRequest


def _signup(email: str, password: str) -> tuple[dict | None, str | None]:
    """Creates a Supabase auth user via direct REST call. Returns (response, None) on
    success or (None, error_message) on failure."""
    url = f"{settings.SUPABASE_URL}/auth/v1/signup"
    headers = {"apikey": settings.SUPABASE_ANON_KEY, "Content-Type": "application/json"}
    try:
        resp = httpx.post(url, json={"email": email, "password": password}, headers=headers, timeout=10.0)
        if resp.status_code in (200, 201):
            return resp.json(), None
        try:
            err = resp.json()
            msg = err.get("error_description") or err.get("msg") or err.get("error") or "Registration failed"
        except Exception:
            msg = "Registration failed"
        return None, msg
    except Exception as e:
        logger.error("Signup request failed: %s", e)
        return None, "Registration failed. Please try again."


def _password_grant(email: str, password: str) -> tuple[dict | None, str | None]:
    """Signs in via direct REST call to Supabase's password grant. Returns (session, None)
    on success or (None, error_message) on failure."""
    url = f"{settings.SUPABASE_URL}/auth/v1/token?grant_type=password"
    headers = {"apikey": settings.SUPABASE_ANON_KEY, "Content-Type": "application/json"}
    try:
        resp = httpx.post(url, json={"email": email, "password": password}, headers=headers, timeout=10.0)
        if resp.status_code == 200:
            return resp.json(), None
        try:
            err = resp.json()
            msg = err.get("error_description") or err.get("msg") or err.get("error") or "Invalid email or password"
        except Exception:
            msg = "Invalid email or password"
        return None, msg
    except Exception as e:
        logger.error("Password grant request failed: %s", e)
        return None, "Login failed. Please try again."


def _build_response_from_dict(data: dict) -> dict:
    user_id = data.get("user", {}).get("id") or data.get("sub")
    profile_result = execute_one(supabase.table("profiles").select("*").eq("id", user_id))
    profile = profile_result.data
    return {
        "access_token": data["access_token"],
        "token_type": "bearer",
        "expires_in": data.get("expires_in", 3600),
        "refresh_token": data.get("refresh_token", ""),
        "profile": profile,
        "profile_required": profile is None,
    }


def register(data: RegisterRequest) -> dict:
    existing_phone = execute_one(supabase.table("profiles").select("id").eq("phone", data.phone))
    if existing_phone.data:
        raise HTTPException(status_code=400, detail="This mobile number is already registered.")

    result, error = _signup(data.email, data.password)
    if result is None:
        raise HTTPException(status_code=400, detail=error or "Registration failed")

    user = result.get("user") or result
    user_id = user.get("id")
    if not user_id:
        raise HTTPException(status_code=500, detail="Registration failed: no user id returned")

    # Supabase returns identities=[] (without erroring) for an email that's already
    # registered but unconfirmed, to avoid leaking which emails exist.
    if user.get("identities") == []:
        raise HTTPException(status_code=400, detail="An account with this email already exists.")

    profile_data = {
        "id": user_id,
        "name": data.name,
        "phone": data.phone,
        "email": data.email,
        "state": data.state,
        "city": data.city,
        "role": data.role,
    }
    try:
        profile_result = supabase.table("profiles").upsert(profile_data).execute()
    except Exception as e:
        logger.error("Profile creation failed for user %s: %s", user_id, e)
        raise HTTPException(status_code=500, detail="Failed to create profile")
    if not profile_result.data:
        raise HTTPException(status_code=500, detail="Failed to create profile")
    profile = profile_result.data[0]

    access_token = result.get("access_token")
    if access_token:
        return {
            "access_token": access_token,
            "token_type": "bearer",
            "expires_in": result.get("expires_in", 3600),
            "refresh_token": result.get("refresh_token", ""),
            "profile": profile,
            "email_confirmation_required": False,
        }

    return {
        "email_confirmation_required": True,
        "message": "Account created. Please check your email to confirm your address before logging in.",
        "profile": profile,
    }


def login(data: LoginRequest) -> dict:
    session_data, error = _password_grant(data.email, data.password)
    if session_data is None:
        raise HTTPException(status_code=400, detail=error or "Invalid email or password")
    return _build_response_from_dict(session_data)


def forgot_password(email: str) -> dict:
    url = f"{settings.SUPABASE_URL}/auth/v1/recover"
    headers = {"apikey": settings.SUPABASE_ANON_KEY, "Content-Type": "application/json"}
    try:
        httpx.post(
            url,
            json={"email": email},
            params={"redirect_to": settings.PASSWORD_RESET_REDIRECT_URL},
            headers=headers,
            timeout=10.0,
        )
    except Exception as e:
        logger.warning("Password recovery request failed: %s", e)
    # Always return the same message regardless of outcome, to avoid leaking
    # whether an account exists for this email.
    return {"message": "If an account exists for this email, a password reset link has been sent."}


def complete_profile(user_id: str, email: str, data: CompleteProfileRequest) -> dict:
    existing_phone = execute_one(
        supabase.table("profiles").select("id").eq("phone", data.phone).neq("id", user_id)
    )
    if existing_phone.data:
        raise HTTPException(status_code=400, detail="This mobile number is already registered.")

    profile_data = {
        "id": user_id,
        "name": data.name,
        "phone": data.phone,
        "email": email,
        "state": data.state,
        "city": data.city,
        "role": data.role,
    }
    result = supabase.table("profiles").upsert(profile_data).execute()
    if not result.data:
        raise HTTPException(status_code=500, detail="Failed to create profile")
    return result.data[0]


def get_profile(user_id: str) -> dict:
    result = execute_one(supabase.table("profiles").select("*").eq("id", user_id))
    if not result.data:
        raise HTTPException(status_code=404, detail="Profile not found")
    return result.data


def delete_account(user_id: str) -> dict:
    """Delete user account: removes shop images from storage, then deletes auth user (cascades all DB data)."""
    _STORAGE_BUCKET = "shop-images"
    bucket_prefix = f"/storage/v1/object/public/{_STORAGE_BUCKET}/"

    try:
        shop_result = supabase.table("shops").select("id, images").eq("owner_id", user_id).execute()
        for shop in (shop_result.data or []):
            for image_url in (shop.get("images") or []):
                idx = image_url.find(bucket_prefix)
                if idx != -1:
                    storage_path = image_url[idx + len(bucket_prefix):]
                    try:
                        supabase.storage.from_(_STORAGE_BUCKET).remove([storage_path])
                    except Exception:
                        pass
    except Exception as e:
        logger.warning("Could not clean shop images for user %s: %s", user_id, e)

    url = f"{settings.SUPABASE_URL}/auth/v1/admin/users/{user_id}"
    headers = {
        "apikey": settings.SUPABASE_SERVICE_KEY,
        "Authorization": f"Bearer {settings.SUPABASE_SERVICE_KEY}",
    }
    try:
        resp = httpx.delete(url, headers=headers, timeout=10.0)
        logger.info("Delete auth user %s -> HTTP %s", user_id, resp.status_code)
        if resp.status_code not in (200, 204):
            raise HTTPException(status_code=500, detail="Failed to delete account. Please try again.")
    except HTTPException:
        raise
    except Exception as e:
        logger.error("Delete account error for %s: %s", user_id, e)
        raise HTTPException(status_code=500, detail="Failed to delete account. Please try again.")

    return {"message": "Account deleted successfully"}


def refresh_session(refresh_token: str) -> dict:
    url = f"{settings.SUPABASE_URL}/auth/v1/token?grant_type=refresh_token"
    headers = {"apikey": settings.SUPABASE_ANON_KEY, "Content-Type": "application/json"}
    try:
        resp = httpx.post(url, json={"refresh_token": refresh_token}, headers=headers, timeout=10.0)
        if resp.status_code != 200:
            raise HTTPException(status_code=401, detail="Session expired. Please log in again.")
        data = resp.json()
        return {
            "access_token": data["access_token"],
            "token_type": "bearer",
            "expires_in": data.get("expires_in", 3600),
            "refresh_token": data.get("refresh_token", ""),
        }
    except HTTPException:
        raise
    except Exception as e:
        logger.error("Session refresh error: %s", e)
        raise HTTPException(status_code=401, detail="Session expired. Please log in again.")
