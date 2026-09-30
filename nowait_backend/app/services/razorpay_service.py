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
            logger.error("Razorpay credentials NOT configured: RAZORPAY_KEY_ID set=%s, RAZORPAY_KEY_SECRET set=%s",
                         bool(settings.RAZORPAY_KEY_ID), bool(settings.RAZORPAY_KEY_SECRET))
            raise HTTPException(status_code=500, detail="Razorpay credentials are not configured")
        _client = razorpay.Client(auth=(settings.RAZORPAY_KEY_ID, settings.RAZORPAY_KEY_SECRET))
    return _client


def key_mode() -> str:
    key = settings.RAZORPAY_KEY_ID or ""
    if key.startswith("rzp_live_"):
        return "live"
    if key.startswith("rzp_test_"):
        return "test"
    return "unknown(key not set or malformed)"


def describe_error(e: Exception) -> str:
    """Everything useful from a Razorpay SDK exception: class, message, HTTP status, field, raw args."""
    parts = [f"type={type(e).__name__}", f"message={str(e) or '<empty>'}"]
    for attr in ("http_status", "status_code", "field", "code", "reason"):
        val = getattr(e, attr, None)
        if val:
            parts.append(f"{attr}={val}")
    if e.args:
        parts.append(f"args={e.args!r}")
    return " ".join(parts)


def _request_ctx(amount_paise: int, currency: str, receipt: str) -> str:
    key = settings.RAZORPAY_KEY_ID or ""
    masked = f"{key[:12]}..." if key else "<not set>"
    return (f"mode={key_mode()} key_id={masked} secret_set={bool(settings.RAZORPAY_KEY_SECRET)} "
            f"amount={amount_paise} currency={currency} receipt={receipt!r} (len={len(receipt)})")


def create_order(amount_paise: int, receipt: str, currency: str = "INR") -> dict:
    """Creates a Razorpay order. amount_paise must be >= 100 (i.e. >= Rs. 1)."""
    if amount_paise < 100:
        raise HTTPException(status_code=400, detail="Amount must be at least 100 paise (Rs. 1)")

    client = _get_client()
    try:
        order = client.order.create({
            "amount": amount_paise,
            "currency": currency,
            "receipt": receipt[:40],   # Razorpay hard limit
            "payment_capture": 1,
        })
    except razorpay.errors.BadRequestError as e:
        # Most commonly a misconfigured API key/secret, or an invalid request param —
        # never surface the raw SDK message to the client, only to logs.
        logger.error("Razorpay REJECTED order-create (BadRequestError): %s | %s", describe_error(e), _request_ctx(amount_paise, currency, receipt))
        raise HTTPException(
            status_code=502,
            detail="Payment provider rejected the request. Please try again, or contact support if this keeps happening.",
        )
    except (razorpay.errors.ServerError, razorpay.errors.GatewayError) as e:
        logger.error("Razorpay UNAVAILABLE (%s): %s | %s", type(e).__name__, describe_error(e), _request_ctx(amount_paise, currency, receipt))
        raise HTTPException(
            status_code=503,
            detail="Payment provider is temporarily unavailable. Please try again in a few minutes.",
        )
    except Exception as e:
        # Also covers auth failures / network errors (e.g. wrong key => "Authentication failed").
        logger.exception("Razorpay order creation FAILED (%s): %s | %s", type(e).__name__, describe_error(e), _request_ctx(amount_paise, currency, receipt))
        raise HTTPException(status_code=500, detail="Failed to create payment order. Please try again.")

    # Which mode the server is in (rzp_test_ / rzp_live_) — handy when checkout shows
    # Razorpay's generic "payment could not be completed" page. Key id is public; no secret logged.
    logger.info("Razorpay order %s created (%s mode, Rs %.2f)", order["id"],
                "live" if settings.RAZORPAY_KEY_ID.startswith("rzp_live_") else "test", order["amount"] / 100)
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
