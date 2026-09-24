"""
Integration tests for all API endpoints using FastAPI TestClient.
Auth is bypassed via dependency overrides. Service calls are mocked.
"""
from unittest.mock import MagicMock, patch
import pytest
from fastapi.testclient import TestClient

from tests.conftest import make_shop, make_customer_user, make_owner_user, make_staff_member


# ── Auth fixtures ─────────────────────────────────────────────────────────────

@pytest.fixture(scope="module")
def _app():
    from app.main import app
    return app


@pytest.fixture
def customer_client(_app):
    from app.dependencies import get_current_user, get_current_owner
    from fastapi import HTTPException

    customer = make_customer_user()

    def _deny_owner():
        raise HTTPException(status_code=403, detail="Owner access required")

    _app.dependency_overrides[get_current_user] = lambda: customer
    _app.dependency_overrides[get_current_owner] = _deny_owner
    client = TestClient(_app, raise_server_exceptions=False)
    yield client
    _app.dependency_overrides.clear()


@pytest.fixture
def owner_client(_app):
    from app.dependencies import get_current_user, get_current_owner

    owner = make_owner_user()
    _app.dependency_overrides[get_current_user] = lambda: owner
    _app.dependency_overrides[get_current_owner] = lambda: owner
    client = TestClient(_app, raise_server_exceptions=False)
    yield client
    _app.dependency_overrides.clear()


@pytest.fixture
def anon_client(_app):
    client = TestClient(_app, raise_server_exceptions=False)
    yield client
    _app.dependency_overrides.clear()


# ── Health ────────────────────────────────────────────────────────────────────

class TestHealth:
    def test_root_returns_ok(self, anon_client):
        resp = anon_client.get("/")
        assert resp.status_code == 200
        assert resp.json()["status"] == "ok"

    def test_health_returns_healthy(self, anon_client):
        resp = anon_client.get("/health")
        assert resp.status_code == 200
        assert resp.json()["status"] == "healthy"


# ── Auth ──────────────────────────────────────────────────────────────────────

class TestAuthEndpoints:
    def test_register(self, anon_client):
        register_resp = {
            "access_token": "fake.jwt",
            "token_type": "bearer",
            "expires_in": 3600,
            "refresh_token": "fake-refresh",
            "profile": {
                "id": "u1", "name": "Rahul", "phone": "+911234567890",
                "email": "rahul@example.com", "state": "Maharashtra", "city": "Mumbai",
                "role": "customer", "created_at": "2026-01-01T00:00:00Z",
            },
            "email_confirmation_required": False,
        }
        with patch("app.routers.auth.auth_service.register", return_value=register_resp):
            resp = anon_client.post("/auth/register", json={
                "name": "Rahul", "phone": "+911234567890", "email": "rahul@example.com",
                "password": "Str0ngPass!", "state": "Maharashtra", "city": "Mumbai",
                "role": "customer",
            })
        assert resp.status_code == 200
        assert resp.json()["email_confirmation_required"] is False

    def test_login(self, anon_client):
        auth_resp = {
            "access_token": "fake.jwt",
            "token_type": "bearer",
            "expires_in": 3600,
            "refresh_token": "fake-refresh",
            "profile": None,
            "profile_required": True,
        }
        with patch("app.routers.auth.auth_service.login", return_value=auth_resp):
            resp = anon_client.post("/auth/login",
                                    json={"email": "rahul@example.com", "password": "Str0ngPass!"})
        assert resp.status_code == 200
        assert resp.json()["profile_required"] is True

    def test_forgot_password(self, anon_client):
        with patch("app.routers.auth.auth_service.forgot_password",
                   return_value={"message": "If an account exists for this email, a password reset link has been sent."}):
            resp = anon_client.post("/auth/forgot-password", json={"email": "rahul@example.com"})
        assert resp.status_code == 200

    def test_get_me_as_customer(self, customer_client):
        resp = customer_client.get("/auth/me")
        assert resp.status_code == 200
        assert resp.json()["role"] == "customer"


# ── Shops ─────────────────────────────────────────────────────────────────────

class TestShopEndpoints:
    def test_list_shops(self, anon_client):
        with patch("app.routers.shops.shop_service.list_shops",
                   return_value={"shops": [], "total": 0}):
            resp = anon_client.get("/shops")
        assert resp.status_code == 200
        assert resp.json()["total"] == 0

    def test_list_shops_city_param_forwarded(self, anon_client):
        with patch("app.routers.shops.shop_service.list_shops",
                   return_value={"shops": [], "total": 0}) as mock_ls:
            anon_client.get("/shops?city=Pune")
        mock_ls.assert_called_once_with(city="Pune", category=None, open_only=False)

    def test_get_categories(self, anon_client):
        with patch("app.routers.shops.shop_service.get_categories",
                   return_value=["Salon", "Hospital"]):
            resp = anon_client.get("/shops/categories")
        assert resp.status_code == 200
        assert "Salon" in resp.json()

    def test_get_cities(self, anon_client):
        with patch("app.routers.shops.shop_service.get_cities",
                   return_value=["Mumbai", "Pune"]):
            resp = anon_client.get("/shops/cities")
        assert resp.status_code == 200
        assert "Pune" in resp.json()

    def test_create_shop_requires_owner_role(self, customer_client):
        resp = customer_client.post("/shops", json={
            "name": "Test", "category": "Salon",
            "address": "123", "city": "Pune",
        })
        assert resp.status_code == 403

    def test_create_shop_as_owner(self, owner_client):
        shop = {**make_shop(), "services": [], "owner_id": "owner-uid-001",
                "has_active_subscription": False, "can_accept_queue": False,
                "is_promoted": False, "active_promotions": [],
                "queue_count": 0, "now_serving_token": None, "rating": 4.0}
        with patch("app.routers.shops.shop_service.create_shop", return_value=shop):
            resp = owner_client.post("/shops", json={
                "name": "Raj Hair Salon", "category": "Salon",
                "address": "123 MG Road", "city": "Pune",
            })
        assert resp.status_code == 201
        assert resp.json()["name"] == "Raj Hair Salon"

    def test_toggle_open_requires_owner(self, customer_client):
        resp = customer_client.post("/shops/shop-001/toggle-open")
        assert resp.status_code == 403

    def test_toggle_open_as_owner(self, owner_client):
        with patch("app.routers.shops.shop_service.toggle_open",
                   return_value={"shop_id": "shop-001", "is_open": True,
                                 "message": "Shop is now open"}):
            resp = owner_client.post("/shops/shop-001/toggle-open")
        assert resp.status_code == 200
        assert resp.json()["is_open"] is True


# ── Queues ────────────────────────────────────────────────────────────────────

class TestQueueEndpoints:
    def _entry_resp(self, staff_id=None, display_status="waiting", position=5):
        return {
            "id": "entry-001",
            "shop_id": "shop-001",
            "shop_name": "Raj Salon",
            "user_id": "cust-uid-001",
            "token_number": 5,
            "status": "waiting",
            "display_status": display_status,
            "position": position,
            "people_ahead": position - 1,
            "estimated_wait_minutes": (position - 1) * 10,
            "now_serving_token": None,
            "staff_id": staff_id,
            "joined_at": "2024-01-01T10:00:00+00:00",
        }

    def test_join_queue(self, customer_client):
        with patch("app.routers.queues.queue_service.join_queue",
                   return_value=self._entry_resp()):
            resp = customer_client.post("/queues/join", json={"shop_id": "shop-001"})
        assert resp.status_code == 201
        assert resp.json()["token_number"] == 5

    def test_join_queue_passes_staff_id(self, customer_client):
        with patch("app.routers.queues.queue_service.join_queue",
                   return_value=self._entry_resp(staff_id="staff-001")) as mock_join:
            customer_client.post("/queues/join",
                                 json={"shop_id": "shop-001", "staff_id": "staff-001"})
        mock_join.assert_called_once_with(
            "shop-001", "cust-uid-001", staff_id="staff-001", service_id=None
        )

    def test_get_queue_status(self, customer_client):
        with patch("app.routers.queues.queue_service.get_my_queue_status", return_value=[]):
            resp = customer_client.get("/queues/status")
        assert resp.status_code == 200

    def test_cancel_queue(self, customer_client):
        with patch("app.routers.queues.queue_service.cancel_queue",
                   return_value={"message": "Cancelled", "entry_id": "entry-001"}):
            resp = customer_client.delete("/queues/entry-001/cancel")
        assert resp.status_code == 200

    def test_coming_notification(self, customer_client):
        with patch("app.routers.queues.queue_service.notify_coming",
                   return_value={"message": "Shop notified", "entry_id": "entry-001"}):
            resp = customer_client.post("/queues/entry-001/coming")
        assert resp.status_code == 200
        assert resp.json()["message"] == "Shop notified"

    def test_get_shop_queue(self, owner_client):
        queue_resp = {
            "shop_id": "shop-001", "shop_name": "Raj Salon", "is_open": True,
            "queue_paused": False, "max_queue_size": None,
            "total_waiting": 2, "now_serving_token": 1, "queue": [],
        }
        with patch("app.routers.queues.queue_service.get_shop_queue", return_value=queue_resp):
            resp = owner_client.get("/queues/shop/shop-001")
        assert resp.status_code == 200
        assert resp.json()["queue_paused"] is False

    def test_advance_queue(self, owner_client):
        with patch("app.routers.queues.queue_service.advance_queue",
                   return_value={"message": "Queue advanced",
                                 "completed_token": 1, "now_serving_token": 2, "total_remaining": 3}):
            resp = owner_client.post("/queues/shop/shop-001/next")
        assert resp.status_code == 200
        assert resp.json()["now_serving_token"] == 2

    def test_pause_queue(self, owner_client):
        with patch("app.routers.queues.queue_service.pause_queue",
                   return_value={"shop_id": "shop-001", "queue_paused": True, "message": "Paused"}):
            resp = owner_client.post("/queues/shop/shop-001/pause")
        assert resp.status_code == 200
        assert resp.json()["queue_paused"] is True

    def test_resume_queue(self, owner_client):
        with patch("app.routers.queues.queue_service.resume_queue",
                   return_value={"shop_id": "shop-001", "queue_paused": False, "message": "Resumed"}):
            resp = owner_client.post("/queues/shop/shop-001/resume")
        assert resp.status_code == 200
        assert resp.json()["queue_paused"] is False

    def test_history(self, customer_client):
        with patch("app.routers.queues.queue_service.get_customer_history", return_value=[]):
            resp = customer_client.get("/queues/history")
        assert resp.status_code == 200


# ── Staff ─────────────────────────────────────────────────────────────────────

class TestStaffEndpoints:
    def test_get_staff_public_by_customer(self, customer_client):
        sm = {**make_staff_member(), "phone": ""}
        with patch("app.routers.staff.staff_service.get_staff_public", return_value=[sm]):
            resp = customer_client.get("/staff/shops/shop-001/public")
        assert resp.status_code == 200
        assert len(resp.json()) == 1

    def test_get_staff_owner_only(self, customer_client):
        resp = customer_client.get("/staff/shops/shop-001")
        assert resp.status_code == 403

    def test_add_staff_by_name(self, owner_client):
        sm = {**make_staff_member(name="Priya"), "phone": ""}
        with patch("app.routers.staff.staff_service.add_staff_by_name", return_value=sm):
            resp = owner_client.post("/staff/shops/shop-001/by-name", json={"name": "Priya"})
        assert resp.status_code == 200
        assert resp.json()["display_name"] == "Priya"

    def test_add_staff_by_name_requires_non_empty_name(self, owner_client):
        resp = owner_client.post("/staff/shops/shop-001/by-name", json={"name": "  "})
        assert resp.status_code == 400

    def test_remove_staff(self, owner_client):
        with patch("app.routers.staff.staff_service.remove_staff",
                   return_value={"message": "Removed", "user_id": "staff-uid-001"}):
            resp = owner_client.delete("/staff/shops/shop-001/staff-uid-001")
        assert resp.status_code == 200

    def test_self_register_as_staff(self, owner_client):
        with patch("app.routers.staff.staff_service.self_register_as_staff",
                   return_value={"message": "Registered as staff", "shop_id": "shop-001", "is_owner_staff": True}):
            resp = owner_client.post("/staff/self-register")
        assert resp.status_code == 200

    def test_my_assignments(self, customer_client):
        with patch("app.routers.staff.staff_service.get_my_staff_assignments", return_value=[]):
            resp = customer_client.get("/staff/my-assignments")
        assert resp.status_code == 200


# ── Notifications ─────────────────────────────────────────────────────────────

class TestNotificationEndpoints:
    def test_get_notifications(self, customer_client):
        with patch("app.routers.notifications.notification_service.get_notifications",
                   return_value={"notifications": [], "unread_count": 0}):
            resp = customer_client.get("/notifications")
        assert resp.status_code == 200
        assert resp.json()["unread_count"] == 0

    def test_mark_notification_read(self, customer_client):
        with patch("app.routers.notifications.notification_service.mark_read",
                   return_value={"message": "OK", "updated_count": 1}):
            resp = customer_client.patch("/notifications/notif-001/read")
        assert resp.status_code == 200

    def test_mark_all_read(self, customer_client):
        with patch("app.routers.notifications.notification_service.mark_all_read",
                   return_value={"message": "OK", "updated_count": 5}):
            resp = customer_client.patch("/notifications/read-all")
        assert resp.status_code == 200


# ── Analytics ─────────────────────────────────────────────────────────────────

class TestAnalyticsEndpoints:
    def test_get_summary_as_owner(self, owner_client):
        summary = {
            "period": "today", "total_joined": 10, "total_served": 8,
            "total_cancelled": 1, "total_skipped": 1,
            "avg_service_minutes": 12.5, "cancel_rate_pct": 10.0,
            "skip_rate_pct": 10.0, "peak_hour": 11,
        }
        with patch("app.routers.analytics.analytics_service.get_summary", return_value=summary):
            resp = owner_client.get("/analytics/shops/shop-001/summary")
        assert resp.status_code == 200
        assert resp.json()["total_joined"] == 10


# ── Subscriptions ─────────────────────────────────────────────────────────────

class TestSubscriptionEndpoints:
    _sub_resp = {
        "has_active_subscription": True,
        "subscription": {
            "id": "sub-001",
            "shop_id": "shop-001",
            "plan": "basic",
            "status": "active",
            "started_at": "2024-01-01T00:00:00+00:00",
            "expires_at": "2024-02-01T00:00:00+00:00",
            "days_remaining": 30,
            "created_at": "2024-01-01T00:00:00+00:00",
        },
    }

    def test_get_subscription(self, owner_client):
        with patch("app.routers.subscriptions.subscription_service.get_subscription",
                   return_value=self._sub_resp):
            resp = owner_client.get("/subscriptions/shop/shop-001")
        assert resp.status_code == 200
        assert resp.json()["has_active_subscription"] is True

    def test_create_subscription_returns_201(self, owner_client):
        with patch("app.routers.subscriptions.subscription_service.create_or_renew_subscription",
                   return_value=self._sub_resp):
            resp = owner_client.post("/subscriptions/shop/shop-001",
                                     json={"plan": "basic", "duration_days": 30})
        assert resp.status_code == 201
