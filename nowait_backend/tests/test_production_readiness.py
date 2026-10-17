"""Production-readiness features: review reporting (Play UGC policy), hidden reviews, public policy
pages (Play + Razorpay), shop responses carrying the fields the app reads, admin moderation."""
from unittest.mock import MagicMock, patch

import pytest
from fastapi import HTTPException
from fastapi.testclient import TestClient
from postgrest.exceptions import APIError

from app.services import review_service as rs


# ── helpers ──────────────────────────────────────────────────────────────────────────────

class Chain:
    """Query-builder stand-in that records the filters applied and returns fixed rows."""

    def __init__(self, rows=None, count=None, fail_on_hidden=False):
        self.rows, self.count, self.fail_on_hidden, self.calls = rows or [], count, fail_on_hidden, []

    def __getattr__(self, name):
        def call(*a, **k):
            self.calls.append((name, a))
            return self
        return call

    def execute(self):
        if self.fail_on_hidden and any(n == "eq" and a and a[0] == "is_hidden" for n, a in self.calls):
            self.calls.clear()
            raise APIError({"message": "column shop_reviews.is_hidden does not exist", "code": "42703"})
        return MagicMock(data=self.rows, count=self.count if self.count is not None else len(self.rows))


@pytest.fixture
def client():
    from app.main import app
    yield TestClient(app, raise_server_exceptions=False)
    app.dependency_overrides.clear()


# ── reporting ────────────────────────────────────────────────────────────────────────────

class TestReportReview:
    def _run(self, review, count_after=1, insert_error=None, **kw):
        inserted, updated = [], []
        db = MagicMock()

        def table(name):
            t = MagicMock()
            if name == "review_reports":
                def insert(row):
                    if insert_error:
                        raise insert_error
                    inserted.append(row)
                    return MagicMock(execute=MagicMock())
                t.insert.side_effect = insert
                t.select.return_value.eq.return_value.execute.return_value = MagicMock(count=count_after)
            elif name == "shop_reviews":
                t.update.side_effect = lambda d: (updated.append(d), MagicMock(eq=lambda *a: MagicMock(execute=MagicMock())))[1]
            return t

        db.table.side_effect = table
        with patch.object(rs, "supabase", db), patch.object(rs, "execute_one", return_value=MagicMock(data=review)):
            out = rs.report_review("rev-1", kw.get("reporter", "user-2"), kw.get("reason", "spam"), kw.get("details"))
        return out, inserted, updated

    REVIEW = {"id": "rev-1", "user_id": "author-1", "is_hidden": False}

    def test_first_report_is_recorded_and_review_stays_visible(self):
        out, inserted, updated = self._run(self.REVIEW, count_after=1, details="  rude words  ")
        assert out == {"reported": True, "already_reported": False}
        assert inserted[0]["reason"] == "spam" and inserted[0]["details"] == "rude words"
        assert updated == []

    def test_third_different_person_hides_it(self):
        _, _, updated = self._run(self.REVIEW, count_after=rs.AUTO_HIDE_REPORTS)
        assert updated == [{"is_hidden": True}]

    def test_same_person_twice_is_not_counted_again(self):
        out, _, updated = self._run(self.REVIEW, insert_error=Exception("duplicate key value (23505)"))
        assert out == {"reported": True, "already_reported": True} and updated == []

    def test_cannot_report_your_own_review(self):
        with pytest.raises(HTTPException) as e:
            self._run(self.REVIEW, reporter="author-1")
        assert e.value.status_code == 400

    def test_unknown_review(self):
        with pytest.raises(HTTPException) as e:
            self._run(None)
        assert e.value.status_code == 404


class TestHiddenReviewsAreLeftOut:
    def test_summary_only_counts_visible_reviews(self):
        chain = Chain(rows=[{"rating": 5}, {"rating": 3}])
        with patch.object(rs, "supabase", MagicMock(table=lambda n: chain)):
            s = rs.get_review_summary("shop-1")
        assert ("eq", ("is_hidden", False)) in chain.calls
        assert s["average_rating"] == 4.0 and s["total_reviews"] == 2

    def test_batch_summaries_used_by_the_shop_list_skip_hidden_ones(self):
        chain = Chain(rows=[{"shop_id": "s1", "rating": 4}])
        with patch.object(rs, "supabase", MagicMock(table=lambda n: chain)):
            out = rs.get_batch_review_summaries(["s1", "s2"])
        assert ("eq", ("is_hidden", False)) in chain.calls
        assert out == {"s1": {"avg_review_rating": 4.0, "review_count": 1}, "s2": {"avg_review_rating": 0.0, "review_count": 0}}

    def test_still_works_before_the_sql_migration_has_been_run(self):
        chain = Chain(rows=[{"rating": 4}], fail_on_hidden=True)
        with patch.object(rs, "supabase", MagicMock(table=lambda n: chain)):
            assert rs.get_review_summary("shop-1")["average_rating"] == 4.0


class TestReportEndpoint:
    def test_needs_a_signed_in_user(self, client):
        assert client.post("/reviews/rev-1/report", json={"reason": "spam"}).status_code in (401, 403)

    def test_passes_reason_and_reporter(self, client):
        from app.dependencies import get_current_user
        from app.main import app
        app.dependency_overrides[get_current_user] = lambda: {"id": "user-9", "role": "customer"}
        with patch("app.routers.reviews.review_service.report_review", return_value={"reported": True}) as rep:
            r = client.post("/reviews/rev-1/report", json={"reason": "offensive", "details": "abusive"})
        assert r.status_code == 200 and r.json()["reported"] is True
        rep.assert_called_once_with("rev-1", "user-9", "offensive", "abusive")

    def test_unknown_reason_is_rejected(self, client):
        from app.dependencies import get_current_user
        from app.main import app
        app.dependency_overrides[get_current_user] = lambda: {"id": "user-9", "role": "customer"}
        assert client.post("/reviews/rev-1/report", json={"reason": "i-dont-like-it"}).status_code == 422


# ── shop responses carry what the app reads ───────────────────────────────────────────────

def test_shop_list_response_keeps_rating_pause_and_limit(client):
    shop = {"id": "s1", "name": "A", "category": "Salon", "address": "x", "city": "Akola", "is_open": True,
            "has_active_subscription": True, "can_accept_queue": False, "avg_wait_minutes": 10, "rating": 4.5,
            "images": [], "queue_count": 0, "now_serving_token": None, "description": "",
            "avg_review_rating": 4.5, "review_count": 12, "queue_paused": True, "max_queue_size": 8}
    with patch("app.routers.shops.shop_service.list_shops", return_value={"shops": [shop], "total": 1}):
        body = client.get("/shops").json()["shops"][0]
    assert (body["avg_review_rating"], body["review_count"], body["queue_paused"], body["max_queue_size"]) == (4.5, 12, True, 8)


def test_list_shops_rating_is_the_review_average_not_the_stale_column():
    from app.services import shop_service
    shop_row = {"id": "s1", "name": "A", "category": "Salon", "address": "x", "city": "Akola", "is_open": True,
                "rating": 0, "images": [], "description": "", "avg_wait_minutes": 10}
    tables = {"shops": Chain(rows=[shop_row]), "subscriptions": Chain(rows=[{"shop_id": "s1"}]),
              "promotions": Chain(rows=[]), "queue_entries": Chain(rows=[])}
    with patch.object(shop_service, "supabase", MagicMock(table=lambda n: tables[n])), \
         patch.object(shop_service.review_service, "get_batch_review_summaries",
                      return_value={"s1": {"avg_review_rating": 4.2, "review_count": 5}}):
        out = shop_service.list_shops()["shops"][0]
    assert out["rating"] == 4.2 and out["review_count"] == 5


# ── public policy pages ──────────────────────────────────────────────────────────────────

@pytest.mark.parametrize("path", ["/legal", "/legal/privacy", "/legal/terms", "/legal/refund-policy",
                                  "/legal/contact", "/legal/delete-account"])
def test_policy_pages_are_public_html(client, path):
    r = client.get(path)
    assert r.status_code == 200 and r.headers["content-type"].startswith("text/html")
    assert "nowaitt778@gmail.com" in r.text


def test_policy_prices_come_from_the_code_that_charges_them(client):
    from app.services import promotion_service, subscription_service, trial_service
    terms = client.get("/legal/terms").text
    refund = client.get("/legal/refund-policy").text
    for page in (terms, refund):
        assert f"₹{subscription_service.DURATION_PRICES[30]}" in page and f"₹{subscription_service.DURATION_PRICES[90]}" in page
        assert f"₹{promotion_service.PROMOTION_PRICE_PER_DAY}" in page
    assert f"{trial_service.TRIAL_DAYS // 30} months" in terms


def test_policy_pages_escape_configured_values(client):
    from app.config import settings
    with patch.object(settings, "LEGAL_BUSINESS_NAME", "<script>alert(1)</script>"), \
         patch.object(settings, "LEGAL_ADDRESS", "Shop 1 & 2 <b>"):
        r = client.get("/legal/contact")
    assert "<script>alert(1)</script>" not in r.text and "&lt;script&gt;" in r.text
    assert "Shop 1 &amp; 2 &lt;b&gt;" in r.text


def test_deletion_page_explains_in_app_and_email_routes(client):
    t = client.get("/legal/delete-account").text
    assert "Delete Account" in t and "mailto:" in t and "7 days" in t


# ── admin moderation ─────────────────────────────────────────────────────────────────────

class TestAdminModeration:
    def _authed(self, client):
        from app.routers import admin
        admin._VALID_SESSIONS.add("test-session")
        client.cookies.set("admin_session", "test-session")
        return client

    def test_needs_an_admin_session(self, client):
        assert client.get("/nowaitt_778admin/api/reviews").status_code == 401
        assert client.delete("/nowaitt_778admin/api/reviews/rev-1").status_code == 401

    def test_list_hide_restore_delete(self, client):
        c = self._authed(client)
        with patch("app.routers.admin.review_service") as svc:
            svc.admin_list_reported.return_value = {"reviews": [], "total": 0, "page": 1}
            assert c.get("/nowaitt_778admin/api/reviews").json()["total"] == 0
            assert c.post("/nowaitt_778admin/api/reviews/rev-1/hide").json() == {"success": True}
            svc.admin_set_hidden.assert_called_with("rev-1", True)
            c.post("/nowaitt_778admin/api/reviews/rev-1/unhide")
            svc.admin_set_hidden.assert_called_with("rev-1", False)
            c.delete("/nowaitt_778admin/api/reviews/rev-1")
            svc.admin_delete_review.assert_called_once_with("rev-1")

    def test_restoring_a_review_dismisses_its_reports(self):
        db = MagicMock()
        with patch.object(rs, "supabase", db):
            rs.admin_set_hidden("rev-1", False)
        assert [c.args[0] for c in db.table.call_args_list] == ["shop_reviews", "review_reports"]

    def test_dashboard_escapes_user_text(self, client):
        html = self._authed(client).get("/nowaitt_778admin/dashboard").text
        assert "function esc(" in html and "esc(p.title)" in html and "esc(u.name" in html
        assert "${u.name||'—'}" not in html
