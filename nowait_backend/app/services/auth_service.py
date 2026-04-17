# import httpx
# from fastapi import HTTPException

# from app.config import settings
# from app.database import execute_one, supabase, supabase_auth
# from app.schemas.auth import CompleteProfileRequest


# def _demo_email(phone: str) -> str:
#     clean = phone.replace("+", "").replace(" ", "").replace("-", "")
#     return f"demo{clean}@nowait.demo"


# def send_otp(phone: str) -> dict:
#     if settings.DEMO_MODE:
#         return {"message": f"OTP sent to {phone}"}

#     try:
#         supabase_auth.auth.sign_in_with_otp({"phone": phone})
#         return {"message": f"OTP sent to {phone}"}
#     except Exception as e:
#         error_msg = str(e)
#         if "rate" in error_msg.lower():
#             raise HTTPException(status_code=429, detail="Too many requests.")
#         raise HTTPException(status_code=400, detail=f"Failed to send OTP: {error_msg}")


# def verify_otp(phone: str, token: str) -> dict:
#     if settings.DEMO_MODE:
#         if token != settings.DEMO_OTP:
#             raise HTTPException(
#                 status_code=400,
#                 detail=f"Invalid OTP. Use {settings.DEMO_OTP} in demo mode.",
#             )
#         return _demo_sign_in(phone)

#     try:
#         result = supabase_auth.auth.verify_with_otp({
#             "phone": phone, "token": token, "type": "sms",
#         })
#         session = result.session
#         user = result.user
#         if not session or not user:
#             raise HTTPException(status_code=400, detail="OTP verification failed")
#         profile_result = execute_one(supabase.table("profiles").select("*").eq("id", user.id))
#         profile = profile_result.data
#         return {
#             "access_token": session.access_token,
#             "token_type": "bearer",
#             "expires_in": session.expires_in,
#             "refresh_token": session.refresh_token,
#             "profile": profile,
#             "profile_required": profile is None,
#         }
#     except HTTPException:
#         raise
#     except Exception as e:
#         raise HTTPException(status_code=400, detail=f"OTP verification failed: {str(e)}")


# def _demo_sign_in(phone: str) -> dict:
#     email = _demo_email(phone)
#     password = settings.DEMO_PASSWORD

#     # ── Step 1: Try sign-in (fast path if user already created) ──────────────
#     try:
#         result = supabase_auth.auth.sign_in_with_password({"email": email, "password": password})
#         if result.session and result.user:
#             print(f"[DEMO] Signed in existing user: {email}")
#             return _build_response(result.session, result.user)
#     except Exception as e:
#         print(f"[DEMO] Sign-in attempt 1 failed: {e}")

#     # ── Step 2a: Try Admin REST API to create user ────────────────────────────
#     admin_ok = _try_admin_create(email, password)

#     # ── Step 2b: Fallback — try sign_up (works if email confirm is off) ───────
#     if not admin_ok:
#         try:
#             supabase_auth.auth.sign_up({"email": email, "password": password})
#             print(f"[DEMO] sign_up succeeded for {email}")
#         except Exception as e:
#             print(f"[DEMO] sign_up also failed: {e}")

#     # ── Step 3: Sign-in after creation ───────────────────────────────────────
#     try:
#         result = supabase_auth.auth.sign_in_with_password({"email": email, "password": password})
#         if result.session and result.user:
#             print(f"[DEMO] Signed in after creation: {email}")
#             return _build_response(result.session, result.user)
#     except Exception as e:
#         print(f"[DEMO] Sign-in attempt 2 failed: {e}")
#         raise HTTPException(
#             status_code=500,
#             detail=(
#                 f"Demo login failed for {email}. "
#                 "In Supabase dashboard → Authentication → Providers → Email, "
#                 "disable 'Confirm email'. Error: " + str(e)
#             ),
#         )

#     raise HTTPException(status_code=500, detail="Demo sign-in returned no session.")


# def _try_admin_create(email: str, password: str) -> bool:
#     """Call Supabase Admin REST API. Returns True if user is ready."""
#     url = f"{settings.SUPABASE_URL}/auth/v1/admin/users"
#     headers = {
#         "apikey": settings.SUPABASE_SERVICE_KEY,
#         "Authorization": f"Bearer {settings.SUPABASE_SERVICE_KEY}",
#         "Content-Type": "application/json",
#     }
#     try:
#         resp = httpx.post(url, json={
#             "email": email,
#             "password": password,
#             "email_confirm": True,
#         }, headers=headers, timeout=10.0)
#         print(f"[DEMO] Admin API → HTTP {resp.status_code}: {resp.text[:300]}")
#         # 200/201 = created, 422 = already exists
#         return resp.status_code in (200, 201, 422)
#     except Exception as e:
#         print(f"[DEMO] Admin API exception: {e}")
#         return False


# def _build_response(session, user) -> dict:
#     profile_result = execute_one(supabase.table("profiles").select("*").eq("id", user.id))
#     profile = profile_result.data
#     return {
#         "access_token": session.access_token,
#         "token_type": "bearer",
#         "expires_in": session.expires_in,
#         "refresh_token": session.refresh_token,
#         "profile": profile,
#         "profile_required": profile is None,
#     }


# def complete_profile(user_id: str, phone: str, data: CompleteProfileRequest) -> dict:
#     profile_data = {
#         "id": user_id,
#         "phone": phone,
#         "name": data.name,
#         "city": data.city,
#         "role": data.role,
#     }
#     result = supabase.table("profiles").upsert(profile_data).execute()
#     if not result.data:
#         raise HTTPException(status_code=500, detail="Failed to create profile")
#     return result.data[0]


# def get_profile(user_id: str) -> dict:
#     result = execute_one(supabase.table("profiles").select("*").eq("id", user_id))
#     if not result.data:
#         raise HTTPException(status_code=404, detail="Profile not found")
#     return result.data


# def refresh_session(refresh_token: str) -> dict:
#     try:
#         result = supabase_auth.auth.refresh_session(refresh_token)
#         session = result.session
#         return {
#             "access_token": session.access_token,
#             "token_type": "bearer",
#             "expires_in": session.expires_in,
#             "refresh_token": session.refresh_token,
#         }
#     except Exception as e:
#         raise HTTPException(status_code=401, detail=f"Failed to refresh session: {str(e)}")


import httpx
from fastapi import HTTPException

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
        error_msg = str(e)
        if "rate" in error_msg.lower():
            raise HTTPException(status_code=429, detail="Too many requests.")
        raise HTTPException(status_code=400, detail=f"Failed to send OTP: {error_msg}")


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
        raise HTTPException(status_code=400, detail=f"OTP verification failed: {str(e)}")


def _demo_sign_in(phone: str) -> dict:
    email = _demo_email(phone)
    password = settings.DEMO_PASSWORD

    # ── Step 1: Try sign-in (fast path if user already created) ──────────────
    try:
        result = supabase_auth.auth.sign_in_with_password({"email": email, "password": password})
        if result.session and result.user:
            print(f"[DEMO] Signed in existing user: {email}")
            return _build_response(result.session, result.user)
    except Exception as e:
        print(f"[DEMO] Sign-in attempt 1 failed: {e}")

    # ── Step 2: Create user via Admin API (sets email_confirm=true, bypasses email confirmation) ──
    user_id = _try_admin_create(email, password)

    # ── Step 3: Sign-in after creation ───────────────────────────────────────
    try:
        result = supabase_auth.auth.sign_in_with_password({"email": email, "password": password})
        if result.session and result.user:
            print(f"[DEMO] Signed in after creation: {email}")
            return _build_response(result.session, result.user)
    except Exception as e:
        print(f"[DEMO] Sign-in attempt 2 failed: {e}")
        # Last resort: confirm user via admin API then retry
        if user_id:
            _admin_confirm_user(user_id)
        try:
            result = supabase_auth.auth.sign_in_with_password({"email": email, "password": password})
            if result.session and result.user:
                print(f"[DEMO] Signed in after force-confirm: {email}")
                return _build_response(result.session, result.user)
        except Exception as e2:
            raise HTTPException(status_code=500, detail=f"Demo login failed for {email}. Error: {str(e2)}")

    raise HTTPException(status_code=500, detail="Demo sign-in returned no session.")


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
        print(f"[DEMO] Admin create → HTTP {resp.status_code}: {resp.text[:300]}")
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
    """Force-confirm a user's email via Admin API."""
    url = f"{settings.SUPABASE_URL}/auth/v1/admin/users/{user_id}"
    headers = {
        "apikey": settings.SUPABASE_SERVICE_KEY,
        "Authorization": f"Bearer {settings.SUPABASE_SERVICE_KEY}",
        "Content-Type": "application/json",
    }
    try:
        resp = httpx.put(url, json={"email_confirm": True}, headers=headers, timeout=10.0)
        print(f"[DEMO] Force-confirm → HTTP {resp.status_code}")
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


def complete_profile(user_id: str, phone: str, data: CompleteProfileRequest) -> dict:
    profile_data = {
        "id": user_id,
        "phone": phone,
        "name": data.name,
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
        raise HTTPException(status_code=401, detail=f"Failed to refresh session: {str(e)}")
