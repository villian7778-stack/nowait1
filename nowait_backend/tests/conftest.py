"""
Pytest configuration.

Two issues to solve:
1. supabase.create_client() validates the API key at import time — patch it BEFORE
   any app code is imported so database.py uses a MagicMock client.
2. Services bind `supabase` locally via `from app.database import supabase`.
   Patching app.database.supabase after that import does nothing.
   Tests must patch the local binding in each service module directly.
"""
import os
from unittest.mock import MagicMock, patch

# ── 1. Env vars (must precede app.config import) ─────────────────────────────
os.environ["SUPABASE_URL"] = "https://test.supabase.co"
os.environ["SUPABASE_SERVICE_KEY"] = "test-service-role-key"
os.environ["SUPABASE_ANON_KEY"] = "test-anon-key"
os.environ["SUPABASE_JWT_SECRET"] = "test-jwt-secret-at-least-32-chars-padding-xx"

# ── 2. Mock create_client BEFORE any app module is imported ───────────────────
# database.py calls create_client() at module level; patching here ensures the
# call succeeds with a MagicMock instead of raising "Invalid API key".
_mock_db_client = MagicMock(name="supabase_db")
_create_client_patcher = patch(
    "supabase.create_client",
    side_effect=[_mock_db_client],
)
_create_client_patcher.start()

import pytest  # noqa: E402 — must come after the patch is started


# ── Shared factory helpers ────────────────────────────────────────────────────

def make_owner_user(user_id: str = "owner-uid-001") -> dict:
    return {"id": user_id, "name": "Test Owner", "phone": "+911111111111", "city": "Pune",
            "role": "owner", "created_at": "2024-01-01T00:00:00+00:00"}


def make_customer_user(user_id: str = "cust-uid-001") -> dict:
    return {"id": user_id, "name": "Test Customer", "phone": "+912222222222", "city": "Pune",
            "role": "customer", "created_at": "2024-01-01T00:00:00+00:00"}


def make_shop(shop_id: str = "shop-001", owner_id: str = "owner-uid-001") -> dict:
    return {
        "id": shop_id,
        "name": "Raj Hair Salon",
        "category": "Salon",
        "address": "123 MG Road",
        "city": "Pune",
        "owner_id": owner_id,
        "is_open": True,
        "queue_paused": False,
        "max_queue_size": None,
        "avg_wait_minutes": 10,
        "rating": 4.2,
        "images": [],
        "description": "Test salon",
    }


def make_queue_entry(
    entry_id: str = "entry-001",
    shop_id: str = "shop-001",
    user_id: str = "cust-uid-001",
    token: int = 1,
    status: str = "waiting",
    staff_id=None,
) -> dict:
    return {
        "id": entry_id,
        "shop_id": shop_id,
        "user_id": user_id,
        "token_number": token,
        "status": status,
        "staff_id": staff_id,
        "service_id": None,
        "coming_at": None,
        "joined_at": "2024-01-01T10:00:00+00:00",
        "served_at": None,
        "actual_service_minutes": None,
    }


def make_staff_member(
    mid: str = "sm-001",
    shop_id: str = "shop-001",
    user_id: str = "staff-uid-001",
    name: str = "Rahul",
    is_owner_staff: bool = False,
) -> dict:
    return {
        "id": mid,
        "shop_id": shop_id,
        "user_id": user_id,
        "display_name": name,
        "is_owner_staff": is_owner_staff,
        "is_active": True,
        "avg_service_minutes": None,
        "added_by": "owner-uid-001",
        "created_at": "2024-01-01T09:00:00+00:00",
    }


# ── Chainable supabase mock builder ──────────────────────────────────────────

def make_chain(execute_return=None):
    """Build a MagicMock that supports fluent Supabase query chaining."""
    c = MagicMock()
    for attr in ("table", "select", "insert", "update", "delete", "upsert",
                 "eq", "neq", "in_", "is_", "ilike", "gt", "gte", "lt", "lte",
                 "order", "limit", "maybe_single", "rpc"):
        getattr(c, attr).return_value = c
    default_result = MagicMock(data=None, count=0)
    c.execute.return_value = execute_return if execute_return is not None else default_result
    return c


def ok(data):
    m = MagicMock()
    m.data = data
    return m


def ok_list(rows, count=None):
    m = MagicMock()
    m.data = rows
    m.count = count if count is not None else len(rows)
    return m
