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


def _require_shop_owner(shop_id: str, owner_id: str) -> None:
    shop = execute_one(
        supabase.table("shops").select("id").eq("id", shop_id).eq("owner_id", owner_id)
    )
    if not shop.data:
        raise HTTPException(status_code=403, detail="Not authorized or shop not found")


def _activate_or_explain(activate_fn, payment_id: str):
    """Runs the post-payment activation step (grant subscription / create promotion).
    By this point Razorpay has already captured the payment, so a failure here must
    never look like "payment failed" to the client — it's a distinct, actionable
    "we owe you this" state that needs a support reference, not a retry."""
    try:
        return activate_fn()
    except HTTPException as e:
        logger.error("Activation rejected after payment %s was captured: %s", payment_id, e.detail)
        raise HTTPException(
            status_code=e.status_code,
            detail=(
                f"Your payment was received (reference: {payment_id}), but activating it failed: {e.detail}. "
                "Please contact support with this reference — do not pay again."
            ),
        )
    except Exception as e:
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
    receipt = f"sub_{shop_id}_{uuid.uuid4().hex[:12]}"
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
    valid = razorpay_service.verify_signature(
        body.razorpay_order_id, body.razorpay_payment_id, body.razorpay_signature
    )
    payment_transaction_service.finalize(
        body.razorpay_order_id, body.razorpay_payment_id, body.razorpay_signature,
        "paid" if valid else "failed",
    )
    if not valid:
        raise HTTPException(
            status_code=400,
            detail=(
                "We couldn't verify this payment. If Razorpay showed you a success screen, "
                f"please contact support with reference {body.razorpay_payment_id} before trying again."
            ),
        )

    sub_data = SubscriptionCreate(plan=body.plan, duration_days=body.duration_days)
    return _activate_or_explain(
        lambda: subscription_service.create_or_renew_subscription(shop_id, current_user["id"], sub_data),
        body.razorpay_payment_id,
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
    receipt = f"promo_{shop_id}_{uuid.uuid4().hex[:12]}"
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
    valid = razorpay_service.verify_signature(
        body.razorpay_order_id, body.razorpay_payment_id, body.razorpay_signature
    )
    payment_transaction_service.finalize(
        body.razorpay_order_id, body.razorpay_payment_id, body.razorpay_signature,
        "paid" if valid else "failed",
    )
    if not valid:
        raise HTTPException(
            status_code=400,
            detail=(
                "We couldn't verify this payment. If Razorpay showed you a success screen, "
                f"please contact support with reference {body.razorpay_payment_id} before trying again."
            ),
        )

    promo_data = PromotionCreate(
        title=body.title, description=body.description, valid_until=body.valid_until
    )
    return _activate_or_explain(
        lambda: promotion_service.create_promotion(shop_id, current_user["id"], promo_data),
        body.razorpay_payment_id,
    )
