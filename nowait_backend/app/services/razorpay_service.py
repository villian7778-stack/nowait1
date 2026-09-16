import hashlib
import hmac
import logging

import razorpay
from fastapi import HTTPException

from app.config import settings

logger = logging.getLogger(__name__)

_client: razorpay.Client | None = None


def _get_client() -> razorpay.Client:
    global _client
    if _client is None:
        if not settings.RAZORPAY_KEY_ID or not settings.RAZORPAY_KEY_SECRET:
            raise HTTPException(status_code=500, detail="Razorpay credentials are not configured")
        _client = razorpay.Client(auth=(settings.RAZORPAY_KEY_ID, settings.RAZORPAY_KEY_SECRET))
    return _client


def create_order(amount_paise: int, receipt: str, currency: str = "INR") -> dict:
    """Creates a Razorpay order. amount_paise must be >= 100 (i.e. >= Rs. 1)."""
    if amount_paise < 100:
        raise HTTPException(status_code=400, detail="Amount must be at least 100 paise (Rs. 1)")

    client = _get_client()
    try:
        order = client.order.create({
            "amount": amount_paise,
            "currency": currency,
            "receipt": receipt,
            "payment_capture": 1,
        })
    except razorpay.errors.BadRequestError as e:
        raise HTTPException(status_code=401, detail=f"Razorpay authentication/request error: {e}")
    except Exception as e:
        logger.error("Razorpay order creation failed: %s", e)
        raise HTTPException(status_code=500, detail="Failed to create Razorpay order")

    return {
        "order_id": order["id"],
        "amount": order["amount"],
        "currency": order["currency"],
        "key_id": settings.RAZORPAY_KEY_ID,
    }


def verify_signature(order_id: str, payment_id: str, signature: str) -> bool:
    """Recomputes HMAC-SHA256(order_id|payment_id, KEY_SECRET) and compares to the signature returned by checkout."""
    if not order_id or not payment_id or not signature:
        return False
    generated = hmac.new(
        settings.RAZORPAY_KEY_SECRET.encode(),
        f"{order_id}|{payment_id}".encode(),
        hashlib.sha256,
    ).hexdigest()
    return hmac.compare_digest(generated, signature)
