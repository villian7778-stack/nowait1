import logging

from app.database import supabase

logger = logging.getLogger(__name__)


def record_order(shop_id: str, owner_id: str, purpose: str, order_id: str, amount_paise: int, metadata: dict) -> None:
    """Logs a Razorpay order as 'created' immediately after it's issued."""
    try:
        supabase.table("payment_transactions").insert({
            "shop_id": shop_id,
            "owner_id": owner_id,
            "purpose": purpose,
            "razorpay_order_id": order_id,
            "amount_paise": amount_paise,
            "status": "created",
            "metadata": metadata,
        }).execute()
    except Exception as e:
        # Ledger write is best-effort — never blocks the actual checkout flow.
        logger.warning("Failed to record payment_transactions row for order %s: %s", order_id, e)


def finalize(order_id: str, payment_id: str, signature: str, status: str) -> None:
    """Updates the order's transaction row with the final payment_id/signature/status."""
    try:
        supabase.table("payment_transactions").update({
            "razorpay_payment_id": payment_id,
            "razorpay_signature": signature,
            "status": status,
        }).eq("razorpay_order_id", order_id).execute()
    except Exception as e:
        logger.warning("Failed to finalize payment_transactions row for order %s: %s", order_id, e)
