"""One free month for each new shop owner, started by the owner from the Subscription screen.

A free month is claimed against the owner's email AND mobile number: if either one has
already had a free month, no second one is given. Only keyed hashes of the two are stored,
in `trial_claims`, which has no link to `profiles`/`auth.users` — so the record survives
account deletion (deleting the account and registering again with the same email or mobile
number does not give another free month) while no readable personal data is kept.

Matching is on the exact value: an email is compared case-insensitively, a mobile number as
stored on the profile. Nothing cleverer than that.
"""
import hashlib
import hmac
import logging
from datetime import datetime, timedelta, timezone

from fastapi import HTTPException

from app.config import settings
from app.database import execute_one, supabase

logger = logging.getLogger(__name__)

TRIAL_DAYS = 30


def _digest(kind: str, value: str | None) -> str | None:
    value = (value or "").strip()
    if kind == "email":
        value = value.lower()
    if not value:
        return None
    return hmac.new(settings.TRIAL_HASH_KEY.encode(), f"{kind}:{value}".encode(), hashlib.sha256).hexdigest()


def _owner_hashes(owner_id: str) -> tuple[str | None, str | None]:
    profile = execute_one(supabase.table("profiles").select("email, phone").eq("id", owner_id)).data or {}
    return _digest("email", profile.get("email")), _digest("phone", profile.get("phone"))


def is_eligible(owner_id: str) -> bool:
    """True if neither this owner's email nor mobile number has had a free month yet."""
    try:
        email_hash, phone_hash = _owner_hashes(owner_id)
        conditions = []
        if email_hash:
            conditions.append(f"email_hash.eq.{email_hash}")
        if phone_hash:
            conditions.append(f"phone_hash.eq.{phone_hash}")
        if not conditions:
            return False
        used = supabase.table("trial_claims").select("id").or_(",".join(conditions)).limit(1).execute()
        return not used.data
    except Exception as e:
        logger.error("Could not check free-trial eligibility for owner %s: %s", owner_id, e)
        return False


def start_trial(shop_id: str, owner_id: str) -> None:
    """Gives the shop its free month. Raises HTTPException if the owner has already had one
    (or on a server problem) — the caller is the owner pressing "Activate free trial"."""
    email_hash, phone_hash = _owner_hashes(owner_id)
    if email_hash is None and phone_hash is None:
        raise HTTPException(status_code=400, detail="Add an email or mobile number to your profile first.")

    already_used = HTTPException(
        status_code=409,
        detail="The free trial has already been used with this email or mobile number.",
    )

    # The UNIQUE constraints on both hash columns make this atomic: if either has been
    # claimed (even a moment ago, by a parallel request) the insert fails and nothing is granted.
    try:
        claim = supabase.table("trial_claims").insert({"email_hash": email_hash, "phone_hash": phone_hash}).execute()
    except Exception as e:
        if "23505" in str(e) or "duplicate key" in str(e).lower():
            logger.info("Trial refused for owner %s: email or mobile number already used a free month", owner_id)
            raise already_used
        logger.error("Trial claim failed for owner %s: %s", owner_id, e)
        raise HTTPException(status_code=500, detail="Could not start the free trial. Please try again.")
    claim_id = (claim.data or [{}])[0].get("id")

    now = datetime.now(timezone.utc)
    try:
        supabase.table("subscriptions").insert({
            "shop_id": shop_id,
            "plan": "trial",
            "status": "active",
            "started_at": now.isoformat(),
            "expires_at": (now + timedelta(days=TRIAL_DAYS)).isoformat(),
        }).execute()
    except Exception as e:
        # The owner got nothing, so don't use up their one free month.
        logger.error("Trial subscription insert failed for shop %s: %s", shop_id, e)
        if claim_id:
            try:
                supabase.table("trial_claims").delete().eq("id", claim_id).execute()
            except Exception as e2:
                logger.error("Could not release trial claim %s: %s", claim_id, e2)
        raise HTTPException(status_code=500, detail="Could not start the free trial. Please try again.")
    logger.info("Free trial started: shop=%s owner=%s", shop_id, owner_id)
