"""Push notifications through Firebase Cloud Messaging (HTTP v1 API).

Called after a notification row is saved (notification_service.create_notification), for the
queue alerts only (PUSH_TYPES). Sending happens on a small background pool, so "Next" / "Skip"
never wait for Google, and a failed push never fails the request: the in-app notification is
already saved.

The Firebase service-account key comes from FIREBASE_CREDENTIALS_BASE64 (the key file, base64
encoded on one line - easiest in a Docker --env-file) or FIREBASE_CREDENTIALS_FILE (a path). With
neither set, push is simply off. The OAuth access token is made by signing a JWT with the key
(PyJWT, already a dependency) - no firebase-admin package needed.
"""
import base64
import json
import logging
import threading
import time
from concurrent.futures import ThreadPoolExecutor

import httpx
import jwt

from app.config import settings
from app.database import supabase

logger = logging.getLogger(__name__)

# Alerts that are worth a push. Schemes are never announced; "promotion" is the one-time
# "Elite Promotion" announcement after an owner pays for one (promotion_service), at most once
# per shop per day.
PUSH_TYPES = {"your_turn", "almost_there", "skipped", "coming", "new_customer", "promotion"}

# Must match the channels the app creates (lib/services/push_service.dart).
ANDROID_CHANNEL_ID = "nowait_alerts"
# Owner "New customer joined": own channel with the shop bell (res/raw/new_customer.mp3).
NEW_CUSTOMER_CHANNEL_ID = "nowait_new_customer"
_ANDROID_SOUND = {NEW_CUSTOMER_CHANNEL_ID: "new_customer"}

_TOKEN_URL = "https://oauth2.googleapis.com/token"
_SCOPE = "https://www.googleapis.com/auth/firebase.messaging"

_pool = ThreadPoolExecutor(max_workers=2, thread_name_prefix="push")
_lock = threading.Lock()
_access_token: tuple[str, float] | None = None  # (token, expires_at)
_warned_off = False


def _credentials() -> dict | None:
    try:
        if settings.FIREBASE_CREDENTIALS_BASE64.strip():
            return json.loads(base64.b64decode(settings.FIREBASE_CREDENTIALS_BASE64.strip()))
        if settings.FIREBASE_CREDENTIALS_FILE.strip():
            with open(settings.FIREBASE_CREDENTIALS_FILE.strip(), encoding="utf-8") as f:
                return json.load(f)
    except Exception as e:
        logger.error("Firebase credentials could not be read (push is off): %s", type(e).__name__)
    return None


def enabled() -> bool:
    return _credentials() is not None


def _get_access_token(creds: dict) -> str:
    """OAuth token for FCM, cached until a minute before it expires (they last 1 hour)."""
    global _access_token
    with _lock:
        if _access_token and _access_token[1] - 60 > time.time():
            return _access_token[0]
        now = int(time.time())
        assertion = jwt.encode(
            {"iss": creds["client_email"], "scope": _SCOPE, "aud": _TOKEN_URL, "iat": now, "exp": now + 3600},
            creds["private_key"],
            algorithm="RS256",
        )
        res = httpx.post(
            _TOKEN_URL,
            data={"grant_type": "urn:ietf:params:oauth:grant-type:jwt-bearer", "assertion": assertion},
            timeout=10,
        )
        res.raise_for_status()
        body = res.json()
        _access_token = (body["access_token"], now + int(body.get("expires_in", 3600)))
        return _access_token[0]


def _forget_token(fcm_token: str) -> None:
    """The phone uninstalled the app or the token expired: stop sending to it."""
    try:
        supabase.table("profiles").update({"fcm_token": None}).eq("fcm_token", fcm_token).execute()
    except Exception as e:
        logger.warning("Could not clear a dead push token: %s", e)


def send_now(fcm_token: str, title: str, body: str, data: dict | None = None) -> bool:
    """Sends one push (blocking). Returns True when FCM accepted it."""
    creds = _credentials()
    if not creds or not fcm_token:
        return False
    channel = NEW_CUSTOMER_CHANNEL_ID if (data or {}).get("type") == "new_customer" else ANDROID_CHANNEL_ID
    message = {
        "message": {
            "token": fcm_token,
            "notification": {"title": title[:100], "body": body[:240]},
            "data": {k: str(v) for k, v in (data or {}).items() if v is not None},
            "android": {
                "priority": "HIGH",
                "notification": {"channel_id": channel, "sound": _ANDROID_SOUND.get(channel, "default")},
            },
        }
    }
    try:
        res = httpx.post(
            f"https://fcm.googleapis.com/v1/projects/{creds['project_id']}/messages:send",
            json=message,
            headers={"Authorization": f"Bearer {_get_access_token(creds)}"},
            timeout=10,
        )
    except Exception as e:
        logger.warning("Push not sent (network): %s", type(e).__name__)
        return False
    if res.status_code == 200:
        return True
    text = res.text[:300]
    if res.status_code == 404 or "UNREGISTERED" in text or ("INVALID_ARGUMENT" in text and "token" in text.lower()):
        _forget_token(fcm_token)
    logger.warning("Push rejected by FCM: HTTP %s %s", res.status_code, text)
    return False


def _owner_alert_row(user_id: str) -> list:
    """fcm_token + the owner's mute choice; before migrate_new_customer_alerts.sql has run the
    column is missing, so fall back to the token alone (alerts on)."""
    try:
        return supabase.table("profiles").select("fcm_token, new_customer_alerts").eq("id", user_id).limit(1).execute().data
    except Exception:
        return supabase.table("profiles").select("fcm_token").eq("id", user_id).limit(1).execute().data


def notify_users(user_ids: list, kind: str, title: str, body: str, data: dict | None = None) -> None:
    """The same push to many users (announcements): phone codes are looked up 200 at a time,
    and the messages go out on the background pool. Never raises."""
    if not user_ids or kind not in PUSH_TYPES or not enabled():
        return
    payload = {"type": kind, **(data or {})}
    for i in range(0, len(user_ids), 200):
        try:
            rows = supabase.table("profiles").select("fcm_token").in_("id", user_ids[i:i + 200]).execute().data
        except Exception as e:
            logger.warning("Push announcement: phone codes not loaded: %s", e.__class__.__name__)
            continue
        for token in {r.get("fcm_token") for r in rows or [] if r.get("fcm_token")}:
            _pool.submit(send_now, token, title, body, payload)


def notify_user(user_id: str | None, kind: str, title: str, body: str, data: dict | None = None) -> None:
    """Queue a push for this user's phone, if this alert type is pushed, push is configured and
    the user allowed notifications. Never raises, never blocks the caller."""
    global _warned_off
    if not user_id or kind not in PUSH_TYPES:
        return
    if not enabled():
        if not _warned_off:
            logger.info("Push notifications are off (no FIREBASE_CREDENTIALS_* set)")
            _warned_off = True
        return

    def work():
        try:
            row = (_owner_alert_row(user_id) if kind == "new_customer" else
                   supabase.table("profiles").select("fcm_token").eq("id", user_id).limit(1).execute().data)
            profile = (row or [{}])[0]
            if kind == "new_customer" and profile.get("new_customer_alerts") is False:
                return  # the owner muted it (Profile tab)
            token = profile.get("fcm_token")
            if token:
                send_now(token, title, body, {"type": kind, **(data or {})})
        except Exception as e:  # background work must never crash the pool
            logger.warning("Push for user %s failed: %s", user_id, e.__class__.__name__)

    _pool.submit(work)
