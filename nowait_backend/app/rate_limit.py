import time
from collections import defaultdict, deque

from fastapi import Depends, HTTPException, Request
from slowapi import Limiter
from slowapi.util import get_remote_address

from app.config import settings
from app.dependencies import get_current_owner, get_current_user


def client_ip(request: Request) -> str:
    """The visitor's IP for per-IP rate limits. Behind Cloudflare (CLOUDFLARE_ORIGIN_SECRET set,
    so main.py has already refused anything that didn't come through Cloudflare) it is
    CF-Connecting-IP, which Cloudflare always overwrites. Otherwise uvicorn's view of it."""
    if settings.CLOUDFLARE_ORIGIN_SECRET:
        cf_ip = request.headers.get("cf-connecting-ip", "").strip()
        if cf_ip:
            return cf_ip
    return get_remote_address(request)


# Shared limiter instance — imported by main.py (to register the handler) and by
# any router that needs to rate-limit a specific endpoint (auth, admin login).
limiter = Limiter(key_func=client_ip)


# ── Per-owner limits for the payment endpoints ──────────────────────────────────────────
# Keyed by the signed-in owner rather than IP, so owners behind the same mobile-carrier address
# don't throttle each other. In-memory is enough: the Dockerfile runs a single worker.
_owner_calls: dict[tuple[str, str], deque] = defaultdict(deque)


def per_owner_limit(bucket: str, calls: int, per_seconds: int = 60):
    """FastAPI dependency: at most `calls` requests per `per_seconds` for each owner in `bucket`."""

    def dependency(current_user: dict = Depends(get_current_owner)) -> None:
        now = time.monotonic()
        q = _owner_calls[(bucket, current_user["id"])]
        while q and now - q[0] > per_seconds:
            q.popleft()
        if len(q) >= calls:
            retry = max(1, int(per_seconds - (now - q[0])))
            raise HTTPException(
                status_code=429,
                detail="Too many requests. Please wait a moment and try again.",
                headers={"Retry-After": str(retry)},
            )
        q.append(now)

    return dependency


def per_user_limit(bucket: str, calls: int, per_seconds: int = 60):
    """Like per_owner_limit, for endpoints any signed-in user (customer or owner) can call."""

    def dependency(current_user: dict = Depends(get_current_user)) -> None:
        now = time.monotonic()
        q = _owner_calls[(bucket, current_user["id"])]
        while q and now - q[0] > per_seconds:
            q.popleft()
        if len(q) >= calls:
            raise HTTPException(
                status_code=429,
                detail="Too many requests. Please wait a moment and try again.",
                headers={"Retry-After": str(max(1, int(per_seconds - (now - q[0]))))},
            )
        q.append(now)

    return dependency
