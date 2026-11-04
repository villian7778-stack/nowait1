import hashlib
import hmac
import logging
from typing import NamedTuple

import razorpay
from fastapi import HTTPException

from app.config import settings

logger = logging.getLogger(__name__)

_client: razorpay.Client | None = None
_client_key: str | None = None  # key id the cached client was built with


class Credentials(NamedTuple):
    mode: str            # "test" or "live": what the switch asks for
    key_id: str
    key_secret: str
    webhook_secret: str
    other_webhook_secret: str  # the other mode's, to recognise (and ignore) its webhooks
    legacy: bool = False       # from the older single RAZORPAY_KEY_ID set


def credentials() -> Credentials:
    """The Razorpay key set in use. RAZORPAY_LIVE picks RAZORPAY_LIVE_* (true) or RAZORPAY_TEST_*
    (false); if that set is empty, the older single RAZORPAY_KEY_ID / _SECRET / _WEBHOOK_SECRET
    set is used instead, its mode read from the key prefix."""
    s = settings
    live = (s.RAZORPAY_LIVE_KEY_ID, s.RAZORPAY_LIVE_KEY_SECRET, s.RAZORPAY_LIVE_WEBHOOK_SECRET)
    test = (s.RAZORPAY_TEST_KEY_ID, s.RAZORPAY_TEST_KEY_SECRET, s.RAZORPAY_TEST_WEBHOOK_SECRET)
    chosen, other = (live, test) if s.RAZORPAY_LIVE else (test, live)
    if chosen[0]:
        return Credentials("live" if s.RAZORPAY_LIVE else "test", *chosen, other_webhook_secret=other[2])
    key = s.RAZORPAY_KEY_ID or ""
    return Credentials("live" if key.startswith("rzp_live_") else "test", key, s.RAZORPAY_KEY_SECRET,
                       s.RAZORPAY_WEBHOOK_SECRET, other_webhook_secret="", legacy=True)


def active_key_id() -> str:
    return credentials().key_id


def _refusal(c: Credentials) -> str | None:
    """Why these keys must not be used, or None. Checked on every call, so it can't be bypassed.
    Real money only ever moves when it was asked for explicitly."""
    live_key = c.key_id.startswith("rzp_live_")
    if c.legacy:
        if live_key and not (settings.RAZORPAY_ALLOW_LIVE or settings.RAZORPAY_LIVE):
            return "payments are test-mode only (set RAZORPAY_LIVE=true to take real payments)"
        return None
    if c.mode == "test" and live_key:
        return "a LIVE key (rzp_live_) is in RAZORPAY_TEST_KEY_ID while RAZORPAY_LIVE=false"
    if c.mode == "live" and c.key_id.startswith("rzp_test_"):
        return "RAZORPAY_LIVE=true but RAZORPAY_LIVE_KEY_ID is a test key (rzp_test_)"
    return None


def _get_client() -> razorpay.Client:
    global _client, _client_key
    c = credentials()
    reason = _refusal(c)
    if reason:
        logger.error("REFUSING to use Razorpay keys: %s", reason)
        raise HTTPException(status_code=503, detail="Payments are not configured correctly right now."
                            if c.mode == "live" and not c.legacy else "Payments are in test mode only right now.")
    if _client is None or (_client_key is not None and _client_key != c.key_id):
        if not c.key_id or not c.key_secret:
            logger.error("Razorpay credentials NOT configured for %s mode: key id set=%s, secret set=%s",
                         c.mode, bool(c.key_id), bool(c.key_secret))
            raise HTTPException(status_code=500, detail="Razorpay credentials are not configured")
        _client = razorpay.Client(auth=(c.key_id, c.key_secret))
        _client_key = c.key_id
    return _client


def key_mode() -> str:
    key = credentials().key_id or ""
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
    c = credentials()
    key = c.key_id or ""
    masked = f"{key[:12]}..." if key else "<not set>"
    return (f"mode={key_mode()} key_id={masked} secret_set={bool(c.key_secret)} "
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
                key_mode(), order["amount"] / 100)
    return {
        "order_id": order["id"],
        "amount": order["amount"],
        "currency": order["currency"],
        "key_id": active_key_id(),
    }


def verify_signature(order_id: str, payment_id: str, signature: str) -> bool:
    """Recomputes HMAC-SHA256(order_id|payment_id, KEY_SECRET) and compares to the signature returned by checkout."""
    # With no secret configured an HMAC with an empty key is trivially forgeable - never accept.
    secret = credentials().key_secret
    if not secret or not order_id or not payment_id or not signature:
        return False
    generated = hmac.new(
        secret.encode(),
        f"{order_id}|{payment_id}".encode(),
        hashlib.sha256,
    ).hexdigest()
    return hmac.compare_digest(generated, signature)


def _signed_with(secret: str, raw_body: bytes, signature: str | None) -> bool:
    if not secret or not signature:
        return False
    expected = hmac.new(secret.encode(), raw_body, hashlib.sha256).hexdigest()
    return hmac.compare_digest(expected, signature.strip())


def verify_webhook_signature(raw_body: bytes, signature: str | None) -> bool:
    """Razorpay signs the exact bytes of a webhook with HMAC-SHA256 using the webhook secret
    chosen in the dashboard, and sends the hex digest in the X-Razorpay-Signature header.
    True only for the mode in use."""
    return _signed_with(credentials().webhook_secret, raw_body, signature)


def is_other_mode_webhook(raw_body: bytes, signature: str | None) -> bool:
    """A genuine webhook from the mode NOT in use (e.g. a test-mode event while live, when both
    webhooks point at this server). Answered 200 and ignored, so Razorpay doesn't keep retrying
    and switch that webhook off."""
    return _signed_with(credentials().other_webhook_secret, raw_body, signature)


def captured_payment_for_order(order_id: str) -> dict | None:
    """Asks Razorpay (authenticated with our secret, so this is trustworthy without a
    checkout signature) whether the order has a captured payment. Returns it, or None."""
    try:
        items = _get_client().order.payments(order_id).get("items", [])
    except Exception as e:
        logger.error("Could not fetch payments for order %s from Razorpay: %s", order_id, describe_error(e))
        return None
    return next((p for p in items if p.get("status") == "captured"), None)


def order_is_paid(order_id: str) -> bool:
    """True once Razorpay has captured the full amount for this order."""
    try:
        return _get_client().order.fetch(order_id).get("status") == "paid"
    except Exception as e:
        logger.warning("Could not fetch order %s from Razorpay: %s", order_id, describe_error(e))
        return False
