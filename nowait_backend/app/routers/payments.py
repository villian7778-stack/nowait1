import logging
import uuid

from fastapi import APIRouter, Depends, HTTPException

from app.database import execute_one, supabase
from app.dependencies import get_current_owner
from app.schemas.payment import (
    CreateOrderResponse,
    PromotionOrderRequest,
    PromotionVerifyRequest,
    SubscriptionOrderRequest,
    SubscriptionVerifyRequest,
)
from app.schemas.promotion import PromotionCreate, PromotionResponse
from app.schemas.subscription import SubscriptionCreate, SubscriptionStatus
from app.services import payment_transaction_service, promotion_service, razorpay_service, subscription_service

router = APIRouter(prefix="/payments", tags=["Payments"])

logger = logging.getLogger(__name__)

# Razorpay test-mode integration: every order is fixed at Rs. 1 regardless of the
# selected plan/duration so the checkout flow can be verified end-to-end without
# moving real money. Swap this for real plan/promotion pricing before going live.
TEST_AMOUNT_PAISE = 100


def _receipt(prefix: str, shop_id: str) -> str:
    """Razorpay rejects receipts longer than 40 characters; the old "<prefix>_<uuid>_<12 hex>"
    form was 53-55. This keeps the shop reference (16 hex) plus a unique suffix, <= 35 chars."""
    return f"{prefix}_{shop_id.replace('-', '')[:16]}_{uuid.uuid4().hex[:12]}"


def _require_shop_owner(shop_id: str, owner_id: str) -> None:
    shop = execute_one(
        supabase.table("shops").select("id").eq("id", shop_id).eq("owner_id", owner_id)
    )
    if not shop.data:
        raise HTTPException(status_code=403, detail="Not authorized or shop not found")


def _check_signature_and_claim(body) -> None:
    """Verifies Razorpay's signature, then atomically marks the order paid so the same
    payment can never be applied twice."""
    valid = razorpay_service.verify_signature(
        body.razorpay_order_id, body.razorpay_payment_id, body.razorpay_signature
    )
    if not valid:
        payment_transaction_service.mark_failed(
            body.razorpay_order_id, body.razorpay_payment_id, body.razorpay_signature
        )
        raise HTTPException(
            status_code=400,
            detail=(
                "We couldn't verify this payment. If Razorpay showed you a success screen, "
                f"please contact support with reference {body.razorpay_payment_id} before trying again."
            ),
        )
    if not payment_transaction_service.claim_paid(
        body.razorpay_order_id, body.razorpay_payment_id, body.razorpay_signature
    ):
        raise HTTPException(status_code=409, detail="This payment has already been processed.")


def _activate_or_explain(activate_fn, payment_id: str, order_id: str):
    """Runs the post-payment activation step (grant subscription / create promotion).
    By this point Razorpay has already captured the payment, so a failure here must
    never look like "payment failed" to the client — it's a distinct, actionable
    "we owe you this" state that needs a support reference, not a retry."""
    try:
        return activate_fn()
    except HTTPException as e:
        payment_transaction_service.release_claim(order_id)
        logger.error("Activation rejected after payment %s was captured: %s", payment_id, e.detail)
        raise HTTPException(
            status_code=e.status_code,
            detail=(
                f"Your payment was received (reference: {payment_id}), but activating it failed: {e.detail}. "
                "Please contact support with this reference — do not pay again."
            ),
        )
    except Exception as e:
        payment_transaction_service.release_claim(order_id)
        logger.error("Activation failed after payment %s was captured: %s", payment_id, e)
        raise HTTPException(
            status_code=500,
            detail=(
                f"Your payment was received (reference: {payment_id}), but activating it failed on our end. "
                "Please contact support with this reference — do not pay again."
            ),
        )


@router.post(
    "/subscription/shop/{shop_id}/create-order",
    response_model=CreateOrderResponse,
    summary="Create a Razorpay order for a subscription payment",
)
def create_subscription_order(
    shop_id: str, body: SubscriptionOrderRequest, current_user: dict = Depends(get_current_owner)
):
    _require_shop_owner(shop_id, current_user["id"])
    subscription_service.validate_plan(body.plan, body.duration_days)
    expires_at = subscription_service.active_expiry(shop_id)
    if expires_at and not body.extend:
        # 409 + message: the app shows this and asks whether to extend.
        raise HTTPException(
            status_code=409,
            detail=subscription_service.already_active_message(expires_at, body.duration_days),
        )
    receipt = _receipt("sub", shop_id)
    order = razorpay_service.create_order(TEST_AMOUNT_PAISE, receipt)
    payment_transaction_service.record_order(
        shop_id, current_user["id"], "subscription", order["order_id"], order["amount"],
        {"plan": body.plan, "duration_days": body.duration_days},
    )
    return order


@router.post(
    "/subscription/shop/{shop_id}/verify",
    response_model=SubscriptionStatus,
    summary="Verify a subscription payment and activate the subscription",
)
def verify_subscription_payment(
    shop_id: str, body: SubscriptionVerifyRequest, current_user: dict = Depends(get_current_owner)
):
    txn = payment_transaction_service.get_order_for_verify(
        body.razorpay_order_id, shop_id, current_user["id"], "subscription"
    )
    _check_signature_and_claim(body)

    meta = txn.get("metadata") or {}

    # Plan and duration come from the stored order, never from the request body. Built
    # inside the activation step so any problem releases the claim instead of leaving
    # a paid-but-never-activated order that can't be retried.
    def activate():
        sub_data = SubscriptionCreate(plan=meta.get("plan"), duration_days=meta.get("duration_days"))
        return subscription_service.create_or_renew_subscription(shop_id, current_user["id"], sub_data)

    return _activate_or_explain(
        activate,
        body.razorpay_payment_id,
        body.razorpay_order_id,
    )


@router.post(
    "/promotion/shop/{shop_id}/create-order",
    response_model=CreateOrderResponse,
    summary="Create a Razorpay order for a Featured Promotion payment",
)
def create_promotion_order(
    shop_id: str, body: PromotionOrderRequest, current_user: dict = Depends(get_current_owner)
):
    _require_shop_owner(shop_id, current_user["id"])
    receipt = _receipt("promo", shop_id)
    order = razorpay_service.create_order(TEST_AMOUNT_PAISE, receipt)
    payment_transaction_service.record_order(
        shop_id, current_user["id"], "promotion", order["order_id"], order["amount"],
        {"title": body.title, "description": body.description, "valid_until": body.valid_until},
    )
    return order


@router.post(
    "/promotion/shop/{shop_id}/verify",
    response_model=PromotionResponse,
    summary="Verify a promotion payment and create the Featured Promotion",
)
def verify_promotion_payment(
    shop_id: str, body: PromotionVerifyRequest, current_user: dict = Depends(get_current_owner)
):
    txn = payment_transaction_service.get_order_for_verify(
        body.razorpay_order_id, shop_id, current_user["id"], "promotion"
    )
    _check_signature_and_claim(body)

    meta = txn.get("metadata") or {}

    def activate():
        promo_data = PromotionCreate(
            title=meta.get("title"), description=meta.get("description"), valid_until=meta.get("valid_until")
        )
        return promotion_service.create_promotion(shop_id, current_user["id"], promo_data, paid=True)

    return _activate_or_explain(
        activate,
        body.razorpay_payment_id,
        body.razorpay_order_id,
    )
