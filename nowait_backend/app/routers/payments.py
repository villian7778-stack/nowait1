import logging
import uuid
from datetime import datetime, timedelta, timezone

from fastapi import APIRouter, Depends, HTTPException

from app.config import settings
from app.database import execute_one, supabase
from app.dependencies import get_current_owner
from app.schemas.payment import (
    CheckoutFailureReport,
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

# Orders are charged at their real price - subscriptions from subscription_service.DURATION_PRICES,
# Featured Promotions at promotion_service.PROMOTION_PRICE_PER_DAY per day. With Razorpay *test*
# keys no real money moves.


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
        # Bad signature usually = KEY_SECRET on the server doesn't match the KEY_ID that created the order
        # (e.g. test key id with a live secret, or a stale secret after regenerating keys).
        logger.error(
            "SIGNATURE MISMATCH order=%s payment=%s mode=%s secret_set=%s sig_len=%d",
            body.razorpay_order_id, body.razorpay_payment_id, razorpay_service.key_mode(),
            bool(settings.RAZORPAY_KEY_SECRET), len(body.razorpay_signature or ""),
        )
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
        logger.warning("Order %s already claimed as paid; rejecting duplicate verify (payment %s)",
                       body.razorpay_order_id, body.razorpay_payment_id)
        raise HTTPException(status_code=409, detail="This payment has already been processed.")
    logger.info("Payment VERIFIED order=%s payment=%s — activating", body.razorpay_order_id, body.razorpay_payment_id)


@router.post("/report-failure", summary="App reports a checkout failure so it appears in server logs")
def report_checkout_failure(body: CheckoutFailureReport, current_user: dict = Depends(get_current_owner)):
    """Checkout runs on the phone, so Razorpay's failure reason never reaches the server on its own.
    The app posts it here; we log it and mark the order failed (never touches an already-paid order)."""
    logger.error(
        "CHECKOUT FAILED (reported by app) owner=%s order=%s purpose=%s mode=%s | code=%s reason=%s source=%s step=%s | "
        "description=%s | message=%s | raw=%s",
        current_user["id"], body.razorpay_order_id, body.purpose, razorpay_service.key_mode(),
        body.code, body.reason, body.source, body.step, body.description, body.message, (body.raw or "")[:1000],
    )
    if body.razorpay_order_id:
        payment_transaction_service.mark_failed(body.razorpay_order_id, None, None)
    return {"logged": True}


def _activate(txn: dict):
    """Grants what a paid order bought, using only what was stored when the order was
    created. Built inside the activation step so any problem releases the claim instead
    of leaving a paid-but-never-activated order that can't be retried."""
    meta = txn.get("metadata") or {}
    if txn["purpose"] == "subscription":
        sub_data = SubscriptionCreate(plan=meta.get("plan"), duration_days=meta.get("duration_days"))
        return subscription_service.create_or_renew_subscription(txn["shop_id"], txn["owner_id"], sub_data)
    # The promotion runs for the paid number of days from when it is activated (orders made by
    # older app builds stored a fixed end date instead).
    days = meta.get("days")
    valid_until = (datetime.now(timezone.utc) + timedelta(days=days)).isoformat() if days else meta.get("valid_until")
    promo_data = PromotionCreate(title=meta.get("title"), description=meta.get("description"), valid_until=valid_until)
    return promotion_service.create_promotion(txn["shop_id"], txn["owner_id"], promo_data, paid=True)


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
    order = razorpay_service.create_order(subscription_service.price_paise(body.duration_days), receipt)
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

    # Plan and duration come from the stored order, never from the request body.
    return _activate_or_explain(
        lambda: _activate(txn),
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
    promotion_service.validate_promotion_days(body.days)
    receipt = _receipt("promo", shop_id)
    order = razorpay_service.create_order(promotion_service.promotion_price_paise(body.days), receipt)
    plural = "" if body.days == 1 else "s"
    payment_transaction_service.record_order(
        shop_id, current_user["id"], "promotion", order["order_id"], order["amount"],
        {
            "title": promotion_service.FEATURED_TITLE,
            "description": f"Shop promoted for {body.days} day{plural}",
            "days": body.days,
        },
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

    return _activate_or_explain(
        lambda: _activate(txn),
        body.razorpay_payment_id,
        body.razorpay_order_id,
    )


@router.get("/order/{order_id}/status", summary="Whether Razorpay has taken payment for this order")
def order_status(order_id: str, current_user: dict = Depends(get_current_owner)):
    """Polled by the app while Razorpay's checkout is open. With UPI, the checkout can
    capture the payment and then sit on its own "order is already paid" screen without
    ever calling back, so the app watches the order here and closes the checkout itself."""
    row = execute_one(
        supabase.table("payment_transactions").select("owner_id").eq("razorpay_order_id", order_id)
    ).data
    if not row or row["owner_id"] != current_user["id"]:
        raise HTTPException(status_code=404, detail="Unknown payment order.")
    return {"paid": razorpay_service.order_is_paid(order_id)}


@router.post("/reconcile/shop/{shop_id}", summary="Activate orders Razorpay captured but the app never verified")
def reconcile_payments(shop_id: str, current_user: dict = Depends(get_current_owner)):
    """Safety net for "Razorpay shows the payment captured but nothing was activated":
    checkout succeeded, but the app's verify call never reached us (app closed, network
    drop, server error). We ask Razorpay directly, so no checkout signature is needed."""
    _require_shop_owner(shop_id, current_user["id"])
    since = (datetime.now(timezone.utc) - timedelta(days=7)).isoformat()
    activated = []
    for txn in payment_transaction_service.unfinished_orders(shop_id, current_user["id"], since):
        order_id = txn["razorpay_order_id"]
        payment = razorpay_service.captured_payment_for_order(order_id)
        if not payment:
            continue
        if payment.get("amount") != txn["amount_paise"]:
            logger.error("RECONCILE amount mismatch order=%s paid=%s expected=%s — not activating",
                         order_id, payment.get("amount"), txn["amount_paise"])
            continue
        if not payment_transaction_service.claim_paid(order_id, payment["id"], None):
            continue
        try:
            _activate(txn)
        except Exception as e:
            payment_transaction_service.release_claim(order_id)
            logger.error("RECONCILE activation failed order=%s payment=%s: %s", order_id, payment["id"], e)
            continue
        logger.info("RECONCILED order=%s payment=%s purpose=%s — activated", order_id, payment["id"], txn["purpose"])
        activated.append({"order_id": order_id, "payment_id": payment["id"], "purpose": txn["purpose"]})
    return {"activated": activated}
