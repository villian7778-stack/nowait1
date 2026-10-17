import time
from typing import Optional

import httpx
import jwt
from fastapi import Depends, HTTPException, status
from fastapi.security import HTTPAuthorizationCredentials, HTTPBearer
from jwt import ExpiredSignatureError, InvalidTokenError, PyJWK

from app.config import settings
from app.database import execute_one, supabase

security = HTTPBearer()

_JWKS_TTL = 1800  # 30 minutes — refresh after key rotation
_jwks_cache: Optional[list] = None
_jwks_fetched_at: float = 0.0

# Signing algorithms Supabase's asymmetric keys use. The algorithm in a token's header is chosen
# by whoever made the token, so it is only ever accepted from this list - never trusted as-is.
_ASYMMETRIC_ALGORITHMS = {"ES256", "RS256"}


def _get_jwks() -> list:
    """Fetch and cache Supabase JWKS with a 30-minute TTL."""
    global _jwks_cache, _jwks_fetched_at
    if _jwks_cache is None or (time.monotonic() - _jwks_fetched_at) > _JWKS_TTL:
        resp = httpx.get(
            f"{settings.SUPABASE_URL}/auth/v1/.well-known/jwks.json", timeout=5.0
        )
        resp.raise_for_status()
        _jwks_cache = resp.json().get("keys", [])
        _jwks_fetched_at = time.monotonic()
    return _jwks_cache


def decode_jwt(token: str) -> dict:
    # Legacy Supabase projects sign with the shared JWT secret (HS256).
    try:
        return jwt.decode(
            token,
            settings.SUPABASE_JWT_SECRET,
            algorithms=["HS256"],
            audience="authenticated",
        )
    except ExpiredSignatureError:
        raise HTTPException(status_code=status.HTTP_401_UNAUTHORIZED, detail="Token expired")
    except InvalidTokenError:
        pass

    # Newer projects sign with an asymmetric key published as JWKS (ES256 / RS256). Only a key
    # whose kid matches exactly is used, with the algorithm that key is allowed to use.
    try:
        header = jwt.get_unverified_header(token)
        alg, kid = header.get("alg"), header.get("kid")
        if alg in _ASYMMETRIC_ALGORITHMS and kid:
            jwk = next((k for k in _get_jwks() if k.get("kid") == kid), None)
            if jwk and jwk.get("alg", alg) == alg:
                key = PyJWK(jwk, algorithm=alg).key
                return jwt.decode(token, key, algorithms=[alg], audience="authenticated")
    except ExpiredSignatureError:
        raise HTTPException(status_code=status.HTTP_401_UNAUTHORIZED, detail="Token expired")
    except Exception:
        pass

    raise HTTPException(status_code=status.HTTP_401_UNAUTHORIZED, detail="Invalid token")


def get_current_user(credentials: HTTPAuthorizationCredentials = Depends(security)) -> dict:
    payload = decode_jwt(credentials.credentials)
    user_id = payload.get("sub")
    if not user_id:
        raise HTTPException(status_code=status.HTTP_401_UNAUTHORIZED, detail="Invalid token payload")

    result = execute_one(supabase.table("profiles").select("*").eq("id", user_id))
    if not result.data:
        raise HTTPException(
            status_code=status.HTTP_404_NOT_FOUND,
            detail="Profile not found. Please complete registration.",
        )
    return result.data


def get_current_owner(current_user: dict = Depends(get_current_user)) -> dict:
    if current_user.get("role") != "owner":
        raise HTTPException(status_code=status.HTTP_403_FORBIDDEN, detail="Owner access required")
    return current_user


def get_token_user_id(credentials: HTTPAuthorizationCredentials = Depends(security)) -> str:
    """Returns user ID from token without requiring a profile (used for profile creation)."""
    payload = decode_jwt(credentials.credentials)
    user_id = payload.get("sub")
    if not user_id:
        raise HTTPException(status_code=status.HTTP_401_UNAUTHORIZED, detail="Invalid token payload")
    return user_id


def get_token_claims(credentials: HTTPAuthorizationCredentials = Depends(security)) -> dict:
    """Returns full JWT payload including phone claim. Used for profile creation."""
    return decode_jwt(credentials.credentials)
