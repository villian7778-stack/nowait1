import time
from collections import defaultdict, deque

from fastapi import Depends, HTTPException
from slowapi import Limiter
from slowapi.util import get_remote_address

from app.dependencies import get_current_owner

# Shared limiter instance — imported by main.py (to register the handler) and by
# any router that needs to rate-limit a specific endpoint (auth, admin login).
limiter = Limiter(key_func=get_remote_address)


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
