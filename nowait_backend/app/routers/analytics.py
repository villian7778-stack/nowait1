from typing import Optional

from fastapi import APIRouter, Depends, Query

from app.dependencies import get_current_owner, get_current_user
from app.services import analytics_service

router = APIRouter(prefix="/analytics", tags=["Analytics"])


@router.get("/shops/{shop_id}/summary", summary="Dashboard summary stats (owner or staff)")
def summary(
    shop_id: str,
    period: str = Query("today", description="today | week | month"),
    from_date: Optional[str] = Query(None, description="YYYY-MM-DD (inclusive); overrides period"),
    to_date: Optional[str] = Query(None, description="YYYY-MM-DD (inclusive); overrides period"),
    current_user: dict = Depends(get_current_user),
):
    return analytics_service.get_summary(shop_id, current_user["id"], period, from_date, to_date)


@router.get("/shops/{shop_id}/hourly", summary="Hourly customer count (owner or staff)")
def hourly(
    shop_id: str,
    days: int = Query(7, ge=1, le=30),
    from_date: Optional[str] = Query(None, description="YYYY-MM-DD (inclusive); overrides days"),
    to_date: Optional[str] = Query(None, description="YYYY-MM-DD (inclusive); overrides days"),
    current_user: dict = Depends(get_current_user),
):
    return analytics_service.get_hourly_stats(shop_id, current_user["id"], days, from_date, to_date)


@router.get("/shops/{shop_id}/staff", summary="Per-staff performance (owner only)")
def staff_perf(shop_id: str, current_user: dict = Depends(get_current_owner)):
    return analytics_service.get_staff_performance(shop_id, current_user["id"])
