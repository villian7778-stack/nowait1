from typing import Optional

from fastapi import APIRouter, Depends, Query

from app.dependencies import get_current_owner, get_current_user
from app.schemas.queue import (
    AdvanceQueueResponse,
    CancelQueueResponse,
    JoinQueueRequest,
    PublicQueueResponse,
    QueueEntryResponse,
    ShopQueueResponse,
)
from app.services import queue_service

router = APIRouter(prefix="/queues", tags=["Queue"])


@router.post("/join", response_model=QueueEntryResponse, status_code=201, summary="Join a shop's queue")
def join_queue(body: JoinQueueRequest, current_user: dict = Depends(get_current_user)):
    return queue_service.join_queue(
        body.shop_id,
        current_user["id"],
        service_id=body.service_id,
        service_ids=body.service_ids,
    )


@router.get("/status", summary="Get current user's active queue entries")
def get_my_status(
    shop_id: Optional[str] = Query(None),
    current_user: dict = Depends(get_current_user),
):
    return queue_service.get_my_queue_status(current_user["id"], shop_id)


@router.delete("/{entry_id}/cancel", response_model=CancelQueueResponse, summary="Cancel queue entry")
def cancel_queue(entry_id: str, current_user: dict = Depends(get_current_user)):
    return queue_service.cancel_queue(entry_id, current_user["id"])


@router.post("/{entry_id}/coming", summary="Notify shop that customer is on the way")
def notify_coming(entry_id: str, current_user: dict = Depends(get_current_user)):
    return queue_service.notify_coming(entry_id, current_user["id"])


@router.get("/shop/{shop_id}/public", response_model=PublicQueueResponse, summary="Public queue list (no auth)")
def get_public_queue(shop_id: str):
    return queue_service.get_public_shop_queue(shop_id)


@router.get("/shop/{shop_id}", response_model=ShopQueueResponse, summary="Get shop queue (owner only)")
def get_shop_queue(shop_id: str, current_user: dict = Depends(get_current_owner)):
    return queue_service.get_shop_queue(shop_id, current_user["id"])


@router.post("/shop/{shop_id}/next", response_model=AdvanceQueueResponse, summary="Serve next customer (owner only)")
def advance_queue(shop_id: str, current_user: dict = Depends(get_current_owner)):
    return queue_service.advance_queue(shop_id, current_user["id"])


@router.post("/{entry_id}/skip", summary="Skip a customer (owner only)")
def skip_customer(entry_id: str, current_user: dict = Depends(get_current_owner)):
    return queue_service.skip_customer(entry_id, current_user["id"])


@router.post("/shop/{shop_id}/pause", summary="Pause entire shop queue (owner only)")
def pause_queue(shop_id: str, current_user: dict = Depends(get_current_owner)):
    return queue_service.pause_queue(shop_id, current_user["id"])


@router.post("/shop/{shop_id}/resume", summary="Resume shop queue (owner only)")
def resume_queue(shop_id: str, current_user: dict = Depends(get_current_owner)):
    return queue_service.resume_queue(shop_id, current_user["id"])


@router.put("/shop/{shop_id}/max-size", summary="Set max queue size (owner only, null = unlimited)")
def set_max_size(shop_id: str, body: dict, current_user: dict = Depends(get_current_owner)):
    max_size = body.get("max_size")
    return queue_service.set_max_size(shop_id, current_user["id"], max_size)


@router.get("/history", summary="Customer's visit history")
def get_history(current_user: dict = Depends(get_current_user)):
    return queue_service.get_customer_history(current_user["id"])
