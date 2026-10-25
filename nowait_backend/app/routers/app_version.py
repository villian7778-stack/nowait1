from typing import Literal, Optional

from fastapi import APIRouter, Query

from app.config import settings

router = APIRouter(prefix="/app", tags=["App"])


def min_build(platform: str) -> int:
    return settings.APP_MIN_BUILD_IOS if platform == "ios" else settings.APP_MIN_BUILD_ANDROID


def store_url(platform: str) -> str:
    return settings.APP_STORE_URL_IOS if platform == "ios" else settings.APP_STORE_URL_ANDROID


def update_required(platform: Optional[str], build: Optional[int]) -> bool:
    """True when this app build is older than the minimum set for its platform."""
    if platform not in ("android", "ios") or build is None:
        return False
    return build < min_build(platform)


@router.get("/version", summary="Whether this app build must be updated before it can be used")
def app_version(
    platform: Literal["android", "ios"] = Query(...),
    build: int = Query(..., ge=0, le=1_000_000_000),
):
    return {
        "platform": platform,
        "min_build": min_build(platform),
        "update_required": update_required(platform, build),
        "store_url": store_url(platform),
    }
