import logging

import httpx
from fastapi import HTTPException

logger = logging.getLogger(__name__)

from app.config import settings
from app.database import execute_one, supabase, supabase_auth
from app.schemas.auth import CompleteProfileRequest


def _demo_email(phone: str) -> str:
    clean = phone.replace("+", "").replace(" ", "").replace("-", "")
    return f"demo{clean}@nowait.demo"


def send_otp(phone: str) -> dict:
    if settings.DEMO_MODE:
        return {"message": f"OTP sent to {phone}"}

    try:
        supabase_auth.auth.sign_in_with_otp({"phone": phone})
        return {"message": f"OTP sent to {phone}"}
    except Exception as e:
        error_msg = str(e).lower()
        logger.error("OTP send error: %s", e)
        if "rate" in error_msg:
            raise HTTPException(status_code=429, detail="Too many requests. Please wait before trying again.")
        raise HTTPException(status_code=400, detail="Failed to send OTP. Please check the phone number and try again.")


def verify_otp(phone: str, token: str) -> dict:
    if settings.DEMO_MODE:
        if token != settings.DEMO_OTP:
            raise HTTPException(
                status_code=400,
                detail=f"Invalid OTP. Use {settings.DEMO_OTP} in demo mode.",
            )
        return _demo_sign_in(phone)

    try:
        result = supabase_auth.auth.verify_with_otp({
            "phone": phone, "token": token, "type": "sms",
        })
        session = result.session
        user = result.user
        if not session or not user:
            raise HTTPException(status_code=400, detail="OTP verification failed")
        profile_result = execute_one(supabase.table("profiles").select("*").eq("id", user.id))
        profile = profile_result.data
        return {
            "access_token": session.access_token,
            "token_type": "bearer",
            "expires_in": session.expires_in,
            "refresh_token": session.refresh_token,
            "profile": profile,
            "profile_required": profile is None,
        }
    except HTTPException:
        raise
    except Exception as e:
        logger.error("OTP verification error: %s", e)
        raise HTTPException(status_code=400, detail="OTP verification failed. Please try again.")


def _demo_sign_in(phone: str) -> dict:
    email = _demo_email(phone)
    password = settings.DEMO_PASSWORD

    # ── Step 1: Try direct REST sign-in (bypasses supabase-py client quirks) ──
    data = _direct_sign_in(email, password)
    if data:
        print(f"[DEMO] Signed in existing user: {email}")
        return _build_response_from_dict(data)

    # ── Step 2: Create user via Admin API with email pre-confirmed ────────────
    user_id = _try_admin_create(email, password)
    if user_id:
        _admin_confirm_user(user_id)

    # ── Step 3: Sign-in after creation ───────────────────────────────────────
    data = _direct_sign_in(email, password)
    if data:
        print(f"[DEMO] Signed in after creation: {email}")
        return _build_response_from_dict(data)

    raise HTTPException(status_code=500, detail=f"Demo login failed for {email}. Check Supabase Email provider is enabled.")


def _direct_sign_in(email: str, password: str) -> dict | None:
    """Sign in via direct REST call — more reliable than supabase-py client."""
    url = f"{settings.SUPABASE_URL}/auth/v1/token?grant_type=password"
    headers = {
        "apikey": settings.SUPABASE_ANON_KEY,
        "Content-Type": "application/json",
    }
    try:
        resp = httpx.post(url, json={"email": email, "password": password}, headers=headers, timeout=10.0)
        print(f"[DEMO] Direct sign-in -> HTTP {resp.status_code}")
        if resp.status_code == 200:
            return resp.json()
        return None
    except Exception as e:
        print(f"[DEMO] Direct sign-in exception: {e}")
        return None


def _try_admin_create(email: str, password: str) -> str | None:
    """Create user via Admin API with email pre-confirmed. Returns user ID or None."""
    url = f"{settings.SUPABASE_URL}/auth/v1/admin/users"
    headers = {
        "apikey": settings.SUPABASE_SERVICE_KEY,
        "Authorization": f"Bearer {settings.SUPABASE_SERVICE_KEY}",
        "Content-Type": "application/json",
    }
    try:
        resp = httpx.post(url, json={
            "email": email,
            "password": password,
            "email_confirm": True,
        }, headers=headers, timeout=10.0)
        print(f"[DEMO] Admin create -> HTTP {resp.status_code}: {resp.text[:300]}")
        data = resp.json()
        if resp.status_code in (200, 201):
            return data.get("id")
        if resp.status_code == 422:
            # User already exists — get their ID
            return _get_user_id_by_email(email)
        return None
    except Exception as e:
        print(f"[DEMO] Admin create exception: {e}")
        return None


def _get_user_id_by_email(email: str) -> str | None:
    """Look up existing user ID by email via Admin API."""
    url = f"{settings.SUPABASE_URL}/auth/v1/admin/users"
    headers = {
        "apikey": settings.SUPABASE_SERVICE_KEY,
        "Authorization": f"Bearer {settings.SUPABASE_SERVICE_KEY}",
    }
    try:
        resp = httpx.get(url, params={"email": email}, headers=headers, timeout=10.0)
        data = resp.json()
        users = data.get("users", [])
        for u in users:
            if u.get("email") == email:
                return u.get("id")
    except Exception as e:
        print(f"[DEMO] Get user ID exception: {e}")
    return None


def _admin_confirm_user(user_id: str) -> None:
    """Force-confirm email and reset password via Admin API."""
    url = f"{settings.SUPABASE_URL}/auth/v1/admin/users/{user_id}"
    headers = {
        "apikey": settings.SUPABASE_SERVICE_KEY,
        "Authorization": f"Bearer {settings.SUPABASE_SERVICE_KEY}",
        "Content-Type": "application/json",
    }
    try:
        resp = httpx.put(url, json={"email_confirm": True, "password": settings.DEMO_PASSWORD}, headers=headers, timeout=10.0)
        print(f"[DEMO] Force-confirm+reset -> HTTP {resp.status_code}")
    except Exception as e:
        print(f"[DEMO] Force-confirm exception: {e}")


def _build_response(session, user) -> dict:
    profile_result = execute_one(supabase.table("profiles").select("*").eq("id", user.id))
    profile = profile_result.data
    return {
        "access_token": session.access_token,
        "token_type": "bearer",
        "expires_in": session.expires_in,
        "refresh_token": session.refresh_token,
        "profile": profile,
        "profile_required": profile is None,
    }


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


def complete_profile(user_id: str, phone: str, data: CompleteProfileRequest) -> dict:
    profile_data = {
        "id": user_id,
        "phone": phone,
        "name": data.name,
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


def refresh_session(refresh_token: str) -> dict:
    try:
        result = supabase_auth.auth.refresh_session(refresh_token)
        session = result.session
        return {
            "access_token": session.access_token,
            "token_type": "bearer",
            "expires_in": session.expires_in,
            "refresh_token": session.refresh_token,
        }
    except Exception as e:
        logger.error("Session refresh error: %s", e)
        raise HTTPException(status_code=401, detail="Session expired. Please log in again.")