import logging

from fastapi import HTTPException

from app.database import execute_one, supabase

logger = logging.getLogger(__name__)


def record_order(shop_id: str, owner_id: str, purpose: str, order_id: str, amount_paise: int, metadata: dict) -> None:
    """Logs a Razorpay order as 'created' immediately after it's issued.

    The ledger row is what ties an order to its shop, owner and plan, so verification
    depends on it: if it can't be written the checkout must not start.
    """
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
        # Typical causes: table/column missing (run sql/final_consolidated.sql), or SUPABASE_SERVICE_KEY
        # is not the service_role key. The Supabase error text says which.
        logger.error("LEDGER WRITE FAILED for Razorpay order %s (shop=%s owner=%s purpose=%s): %s: %r",
                     order_id, shop_id, owner_id, purpose, type(e).__name__, e)
        raise HTTPException(status_code=500, detail="Could not start the payment. Please try again.")


def get_order(order_id: str) -> dict | None:
    """The ledger row for an order, or None."""
    return execute_one(
        supabase.table("payment_transactions").select("*").eq("razorpay_order_id", order_id)
    ).data


def owns_order(order_id: str, owner_id: str) -> bool:
    """True if this order was created by this owner."""
    row = execute_one(
        supabase.table("payment_transactions").select("owner_id").eq("razorpay_order_id", order_id)
    ).data
    return bool(row) and row["owner_id"] == owner_id


def get_order_for_verify(order_id: str, shop_id: str, owner_id: str, purpose: str) -> dict:
    """Loads the ledger row for an order and checks it belongs to this owner, shop and
    purpose and has not already been paid out. Returns the row (with its metadata)."""
    row = execute_one(supabase.table("payment_transactions").select("*").eq("razorpay_order_id", order_id)).data
    if not row:
        raise HTTPException(status_code=404, detail="Unknown payment order.")
    if row["owner_id"] != owner_id or row["shop_id"] != shop_id or row["purpose"] != purpose:
        logger.warning("Order %s verify attempted by owner %s for shop %s (purpose %s)", order_id, owner_id, shop_id, purpose)
        raise HTTPException(status_code=403, detail="This payment does not belong to this shop.")
    if row["status"] == "paid":
        raise HTTPException(status_code=409, detail="This payment has already been processed.")
    return row


def claim_paid(order_id: str, payment_id: str, signature: str) -> bool:
    """Atomically flips the order to 'paid'. Returns False if someone else already did,
    which is what stops the same payment being applied twice (even concurrently)."""
    result = (
        supabase.table("payment_transactions")
        .update({"razorpay_payment_id": payment_id, "razorpay_signature": signature, "status": "paid"})
        .eq("razorpay_order_id", order_id)
        .in_("status", ["created", "failed"])
        .execute()
    )
    return bool(result.data)


def mark_failed(order_id: str, payment_id: str | None, signature: str | None) -> None:
    """Records a failed attempt (bad signature or app-reported checkout failure).
    Never touches a row that is already paid."""
    try:
        update = {"status": "failed"}
        if payment_id:
            update["razorpay_payment_id"] = payment_id
        if signature:
            update["razorpay_signature"] = signature
        supabase.table("payment_transactions").update(update).eq(
            "razorpay_order_id", order_id
        ).eq("status", "created").execute()
    except Exception as e:
        logger.warning("Failed to mark payment_transactions row failed for order %s: %s", order_id, e)


def release_claim(order_id: str) -> None:
    """Puts a claimed order back to 'created' when activation failed after the claim,
    so the verify can be retried instead of being locked out as 'already processed'."""
    try:
        supabase.table("payment_transactions").update({"status": "created"}).eq(
            "razorpay_order_id", order_id
        ).eq("status", "paid").execute()
    except Exception as e:
        logger.error("Failed to release claim on order %s: %s", order_id, e)


def unfinished_orders(shop_id: str, owner_id: str, since_iso: str) -> list[dict]:
    """This owner's recent orders that were never activated — candidates for reconciling
    against Razorpay when checkout succeeded but the app's verify call never landed."""
    result = (
        supabase.table("payment_transactions")
        .select("*")
        .eq("shop_id", shop_id)
        .eq("owner_id", owner_id)
        .in_("status", ["created", "failed"])
        .gte("created_at", since_iso)
        .order("created_at", desc=True)
        .limit(10)
        .execute()
    )
    return result.data or []
