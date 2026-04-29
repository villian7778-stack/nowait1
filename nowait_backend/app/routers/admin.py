"""
NOWAIT Admin Panel — /nowaitt_778admin
Credentials: 778Admin / Admin@nowait778
"""
import secrets
from datetime import datetime, timezone

from fastapi import APIRouter, Cookie, Form, Request
from fastapi.responses import HTMLResponse, JSONResponse, RedirectResponse

from app.database import supabase

router = APIRouter(prefix="/nowaitt_778admin", tags=["Admin"])

_ADMIN_USERNAME = "778Admin"
_ADMIN_PASSWORD = "Admin@nowait778"
_VALID_SESSIONS: set[str] = set()


# ── Auth helpers ──────────────────────────────────────────────────────────────

def _is_authed(session: str | None) -> bool:
    return bool(session and session in _VALID_SESSIONS)


def _auth_required(session: str | None):
    if not _is_authed(session):
        return RedirectResponse("/nowaitt_778admin/login", status_code=302)
    return None


# ── Login / logout ────────────────────────────────────────────────────────────

@router.get("/login", response_class=HTMLResponse)
def login_page(admin_session: str | None = Cookie(default=None)):
    if _is_authed(admin_session):
        return RedirectResponse("/nowaitt_778admin/dashboard", status_code=302)
    return HTMLResponse(_LOGIN_HTML)


@router.post("/login")
def do_login(username: str = Form(...), password: str = Form(...)):
    if username == _ADMIN_USERNAME and password == _ADMIN_PASSWORD:
        token = secrets.token_hex(32)
        _VALID_SESSIONS.add(token)
        resp = RedirectResponse("/nowaitt_778admin/dashboard", status_code=302)
        resp.set_cookie("admin_session", token, httponly=True, samesite="lax", max_age=86400)
        return resp
    resp = RedirectResponse("/nowaitt_778admin/login?error=1", status_code=302)
    return resp


@router.get("/logout")
def do_logout(admin_session: str | None = Cookie(default=None)):
    _VALID_SESSIONS.discard(admin_session or "")
    resp = RedirectResponse("/nowaitt_778admin/login", status_code=302)
    resp.delete_cookie("admin_session")
    return resp


@router.get("", response_class=HTMLResponse)
def root_redirect(admin_session: str | None = Cookie(default=None)):
    if _is_authed(admin_session):
        return RedirectResponse("/nowaitt_778admin/dashboard", status_code=302)
    return RedirectResponse("/nowaitt_778admin/login", status_code=302)


# ── Main dashboard HTML ───────────────────────────────────────────────────────

@router.get("/dashboard", response_class=HTMLResponse)
def dashboard(admin_session: str | None = Cookie(default=None)):
    redir = _auth_required(admin_session)
    if redir:
        return redir
    return HTMLResponse(_DASHBOARD_HTML)


# ── Admin API — Stats ─────────────────────────────────────────────────────────

@router.get("/api/stats")
def api_stats(admin_session: str | None = Cookie(default=None)):
    redir = _auth_required(admin_session)
    if redir:
        return JSONResponse({"error": "Unauthorized"}, status_code=401)

    users_r = supabase.table("profiles").select("id", count="exact").execute()
    shops_r = supabase.table("shops").select("id", count="exact").execute()
    open_shops_r = supabase.table("shops").select("id", count="exact").eq("is_open", True).execute()
    queue_r = supabase.table("queue_entries").select("id", count="exact").in_("status", ["waiting", "serving"]).execute()
    subs_r = supabase.table("subscriptions").select("id", count="exact").eq("status", "active").gt("expires_at", datetime.now(timezone.utc).isoformat()).execute()
    today_start = datetime.now(timezone.utc).replace(hour=0, minute=0, second=0, microsecond=0).isoformat()
    today_joins = supabase.table("queue_entries").select("id", count="exact").gte("created_at", today_start).execute()
    promos_r = supabase.table("promotions").select("id", count="exact").eq("is_active", True).execute()
    owners_r = supabase.table("profiles").select("id", count="exact").eq("role", "owner").execute()

    return {
        "total_users": users_r.count or 0,
        "total_shops": shops_r.count or 0,
        "open_shops": open_shops_r.count or 0,
        "active_queue": queue_r.count or 0,
        "active_subscriptions": subs_r.count or 0,
        "joins_today": today_joins.count or 0,
        "active_promotions": promos_r.count or 0,
        "total_owners": owners_r.count or 0,
    }


# ── Admin API — Users ─────────────────────────────────────────────────────────

@router.get("/api/users")
def api_users(admin_session: str | None = Cookie(default=None), page: int = 1, q: str = ""):
    if not _is_authed(admin_session):
        return JSONResponse({"error": "Unauthorized"}, status_code=401)
    limit, offset = 20, (page - 1) * 20
    query = supabase.table("profiles").select("*").order("created_at", desc=True)
    if q:
        query = query.ilike("name", f"%{q}%")
    total_r = supabase.table("profiles").select("id", count="exact").execute()
    result = query.range(offset, offset + limit - 1).execute()
    return {"users": result.data or [], "total": total_r.count or 0, "page": page}


@router.delete("/api/users/{user_id}")
def api_delete_user(user_id: str, admin_session: str | None = Cookie(default=None)):
    if not _is_authed(admin_session):
        return JSONResponse({"error": "Unauthorized"}, status_code=401)
    supabase.table("queue_entries").delete().eq("user_id", user_id).execute()
    supabase.table("notifications").delete().eq("user_id", user_id).execute()
    supabase.table("profiles").delete().eq("id", user_id).execute()
    return {"success": True}


# ── Admin API — Shops ─────────────────────────────────────────────────────────

@router.get("/api/shops")
def api_shops(admin_session: str | None = Cookie(default=None), page: int = 1, q: str = ""):
    if not _is_authed(admin_session):
        return JSONResponse({"error": "Unauthorized"}, status_code=401)
    limit, offset = 20, (page - 1) * 20
    query = supabase.table("shops").select("id, name, category, city, state, is_open, queue_paused, queue_count, avg_wait_minutes, rating, owner_id, created_at").order("created_at", desc=True)
    if q:
        query = query.ilike("name", f"%{q}%")
    total_r = supabase.table("shops").select("id", count="exact").execute()
    result = query.range(offset, offset + limit - 1).execute()
    shops = result.data or []
    if shops:
        owner_ids = list({s["owner_id"] for s in shops if s.get("owner_id")})
        profiles_r = supabase.table("profiles").select("id, name, phone").in_("id", owner_ids).execute()
        profiles_map = {p["id"]: p for p in (profiles_r.data or [])}
        for s in shops:
            owner = profiles_map.get(s.get("owner_id", ""), {})
            s["owner_name"] = owner.get("name", "Unknown")
            s["owner_phone"] = owner.get("phone", "")
    return {"shops": shops, "total": total_r.count or 0, "page": page}


@router.put("/api/shops/{shop_id}")
async def api_update_shop(shop_id: str, request: Request, admin_session: str | None = Cookie(default=None)):
    if not _is_authed(admin_session):
        return JSONResponse({"error": "Unauthorized"}, status_code=401)
    body = await request.json()
    allowed = {k: body[k] for k in ("name", "category", "city", "state", "address", "is_open", "avg_wait_minutes", "rating") if k in body}
    supabase.table("shops").update(allowed).eq("id", shop_id).execute()
    return {"success": True}


@router.delete("/api/shops/{shop_id}")
def api_delete_shop(shop_id: str, admin_session: str | None = Cookie(default=None)):
    if not _is_authed(admin_session):
        return JSONResponse({"error": "Unauthorized"}, status_code=401)
    supabase.table("queue_entries").delete().eq("shop_id", shop_id).execute()
    supabase.table("subscriptions").delete().eq("shop_id", shop_id).execute()
    supabase.table("promotions").delete().eq("shop_id", shop_id).execute()
    supabase.table("services").delete().eq("shop_id", shop_id).execute()
    supabase.table("shop_staff").delete().eq("shop_id", shop_id).execute()
    supabase.table("notifications").delete().eq("shop_id", shop_id).execute()
    supabase.table("shops").delete().eq("id", shop_id).execute()
    return {"success": True}


# ── Admin API — Queue Entries ─────────────────────────────────────────────────

@router.get("/api/queues")
def api_queues(admin_session: str | None = Cookie(default=None), page: int = 1, shop_id: str = ""):
    if not _is_authed(admin_session):
        return JSONResponse({"error": "Unauthorized"}, status_code=401)
    limit, offset = 30, (page - 1) * 30
    query = supabase.table("queue_entries").select("id, shop_id, user_id, token_number, status, position, created_at, service_ids").in_("status", ["waiting", "serving"]).order("created_at", desc=True)
    if shop_id:
        query = query.eq("shop_id", shop_id)
    total_r = supabase.table("queue_entries").select("id", count="exact").in_("status", ["waiting", "serving"]).execute()
    result = query.range(offset, offset + limit - 1).execute()
    entries = result.data or []
    if entries:
        uids = list({e["user_id"] for e in entries if e.get("user_id")})
        sids = list({e["shop_id"] for e in entries if e.get("shop_id")})
        pr = supabase.table("profiles").select("id, name, phone").in_("id", uids).execute()
        sr = supabase.table("shops").select("id, name").in_("id", sids).execute()
        pm = {p["id"]: p for p in (pr.data or [])}
        sm = {s["id"]: s for s in (sr.data or [])}
        for e in entries:
            u = pm.get(e.get("user_id", ""), {})
            e["customer_name"] = u.get("name", "Unknown")
            e["customer_phone"] = u.get("phone", "")
            sh = sm.get(e.get("shop_id", ""), {})
            e["shop_name"] = sh.get("name", "Unknown")
    return {"entries": entries, "total": total_r.count or 0, "page": page}


@router.delete("/api/queues/{entry_id}")
def api_cancel_queue(entry_id: str, admin_session: str | None = Cookie(default=None)):
    if not _is_authed(admin_session):
        return JSONResponse({"error": "Unauthorized"}, status_code=401)
    supabase.table("queue_entries").update({"status": "cancelled"}).eq("id", entry_id).execute()
    return {"success": True}


# ── Admin API — Subscriptions ─────────────────────────────────────────────────

@router.get("/api/subscriptions")
def api_subscriptions(admin_session: str | None = Cookie(default=None), page: int = 1):
    if not _is_authed(admin_session):
        return JSONResponse({"error": "Unauthorized"}, status_code=401)
    limit, offset = 20, (page - 1) * 20
    result = supabase.table("subscriptions").select("*").order("created_at", desc=True).range(offset, offset + limit - 1).execute()
    total_r = supabase.table("subscriptions").select("id", count="exact").execute()
    subs = result.data or []
    if subs:
        sids = list({s["shop_id"] for s in subs if s.get("shop_id")})
        sr = supabase.table("shops").select("id, name, city").in_("id", sids).execute()
        sm = {s["id"]: s for s in (sr.data or [])}
        for s in subs:
            sh = sm.get(s.get("shop_id", ""), {})
            s["shop_name"] = sh.get("name", "Unknown")
            s["shop_city"] = sh.get("city", "")
    return {"subscriptions": subs, "total": total_r.count or 0, "page": page}


@router.post("/api/subscriptions")
async def api_create_subscription(request: Request, admin_session: str | None = Cookie(default=None)):
    if not _is_authed(admin_session):
        return JSONResponse({"error": "Unauthorized"}, status_code=401)
    body = await request.json()
    shop_id = body.get("shop_id")
    days = int(body.get("days", 30))
    if not shop_id:
        return JSONResponse({"error": "shop_id required"}, status_code=400)
    from datetime import timedelta
    expires = (datetime.now(timezone.utc) + timedelta(days=days)).isoformat()
    supabase.table("subscriptions").upsert({"shop_id": shop_id, "status": "active", "expires_at": expires, "plan": "admin_grant"}, on_conflict="shop_id").execute()
    supabase.table("shops").update({"has_active_subscription": True}).eq("id", shop_id).execute()
    return {"success": True}


@router.delete("/api/subscriptions/{sub_id}")
def api_cancel_subscription(sub_id: str, admin_session: str | None = Cookie(default=None)):
    if not _is_authed(admin_session):
        return JSONResponse({"error": "Unauthorized"}, status_code=401)
    row = supabase.table("subscriptions").select("shop_id").eq("id", sub_id).single().execute()
    supabase.table("subscriptions").update({"status": "cancelled"}).eq("id", sub_id).execute()
    if row.data:
        supabase.table("shops").update({"has_active_subscription": False, "is_open": False}).eq("id", row.data["shop_id"]).execute()
    return {"success": True}


# ── Admin API — Promotions ────────────────────────────────────────────────────

@router.get("/api/promotions")
def api_promotions(admin_session: str | None = Cookie(default=None), page: int = 1):
    if not _is_authed(admin_session):
        return JSONResponse({"error": "Unauthorized"}, status_code=401)
    limit, offset = 20, (page - 1) * 20
    result = supabase.table("promotions").select("*").order("created_at", desc=True).range(offset, offset + limit - 1).execute()
    total_r = supabase.table("promotions").select("id", count="exact").execute()
    promos = result.data or []
    if promos:
        sids = list({p["shop_id"] for p in promos if p.get("shop_id")})
        sr = supabase.table("shops").select("id, name").in_("id", sids).execute()
        sm = {s["id"]: s for s in (sr.data or [])}
        for p in promos:
            p["shop_name"] = sm.get(p.get("shop_id", ""), {}).get("name", "Unknown")
    return {"promotions": promos, "total": total_r.count or 0, "page": page}


@router.delete("/api/promotions/{promo_id}")
def api_delete_promotion(promo_id: str, admin_session: str | None = Cookie(default=None)):
    if not _is_authed(admin_session):
        return JSONResponse({"error": "Unauthorized"}, status_code=401)
    supabase.table("promotions").delete().eq("id", promo_id).execute()
    return {"success": True}


# ── HTML ──────────────────────────────────────────────────────────────────────

_LOGIN_HTML = """<!DOCTYPE html>
<html lang="en">
<head>
<meta charset="UTF-8">
<meta name="viewport" content="width=device-width, initial-scale=1.0">
<title>NOWAIT Admin</title>
<style>
  *{margin:0;padding:0;box-sizing:border-box}
  body{min-height:100vh;display:flex;align-items:center;justify-content:center;
    background:#0d0d14;font-family:'Segoe UI',system-ui,sans-serif;color:#e2e8f0}
  .card{background:#1a1a2e;border:1px solid #2a2a45;border-radius:20px;
    padding:48px 40px;width:100%;max-width:400px;box-shadow:0 24px 64px rgba(0,0,0,.5)}
  .logo{text-align:center;margin-bottom:32px}
  .logo-mark{display:inline-flex;align-items:center;justify-content:center;
    width:64px;height:64px;border-radius:18px;
    background:linear-gradient(135deg,#6c5ce7,#a29bfe);
    font-size:28px;margin-bottom:12px}
  h1{font-size:24px;font-weight:700;color:#fff;margin-bottom:4px;text-align:center}
  .subtitle{font-size:13px;color:#6b7280;text-align:center}
  .error{background:#3b1a1a;border:1px solid #7f1d1d;border-radius:10px;
    padding:10px 14px;font-size:13px;color:#fca5a5;margin-bottom:18px;display:none}
  .error.show{display:block}
  label{display:block;font-size:12px;font-weight:600;color:#9ca3af;
    text-transform:uppercase;letter-spacing:.06em;margin-bottom:6px;margin-top:20px}
  input{width:100%;padding:12px 16px;background:#0d0d1a;border:1.5px solid #2a2a45;
    border-radius:10px;color:#e2e8f0;font-size:14px;outline:none;transition:.2s}
  input:focus{border-color:#6c5ce7;box-shadow:0 0 0 3px rgba(108,92,231,.15)}
  button{width:100%;margin-top:28px;padding:14px;
    background:linear-gradient(135deg,#6c5ce7,#a29bfe);border:none;
    border-radius:12px;color:#fff;font-size:15px;font-weight:700;
    cursor:pointer;transition:.15s;letter-spacing:.02em}
  button:hover{opacity:.9;transform:translateY(-1px)}
  .badge{text-align:center;margin-top:24px;font-size:11px;color:#4b5563}
</style>
</head>
<body>
<div class="card">
  <div class="logo">
    <div class="logo-mark">⚡</div>
    <h1>NOWAIT Admin</h1>
    <p class="subtitle">Restricted access — authorised personnel only</p>
  </div>
  <div class="error" id="err">Invalid credentials. Please try again.</div>
  <form method="POST" action="/nowaitt_778admin/login">
    <label>Admin ID</label>
    <input type="text" name="username" placeholder="Enter admin ID" required autofocus>
    <label>Password</label>
    <input type="password" name="password" placeholder="Enter password" required>
    <button type="submit">Sign In</button>
  </form>
  <p class="badge">NOWAIT v1.0 &nbsp;·&nbsp; Admin Console</p>
</div>
<script>
  if(location.search.includes('error=1'))
    document.getElementById('err').classList.add('show');
</script>
</body>
</html>"""


_DASHBOARD_HTML = """<!DOCTYPE html>
<html lang="en">
<head>
<meta charset="UTF-8">
<meta name="viewport" content="width=device-width, initial-scale=1.0">
<title>NOWAIT Admin Console</title>
<style>
/* ── Reset ── */
*{margin:0;padding:0;box-sizing:border-box}
:root{
  --bg:#0d0d14;--surface:#13131f;--card:#1a1a2e;
  --border:#252540;--border2:#2e2e50;
  --primary:#6c5ce7;--primary2:#a29bfe;
  --text:#e2e8f0;--muted:#6b7280;--dim:#9ca3af;
  --success:#10b981;--warn:#f59e0b;--danger:#ef4444;--info:#3b82f6;
}
body{display:flex;min-height:100vh;background:var(--bg);
  font-family:'Segoe UI',system-ui,sans-serif;color:var(--text);font-size:14px}

/* ── Sidebar ── */
#sidebar{width:240px;background:var(--surface);border-right:1px solid var(--border);
  display:flex;flex-direction:column;position:fixed;top:0;left:0;height:100vh;z-index:100}
.sidebar-logo{padding:22px 20px;border-bottom:1px solid var(--border);display:flex;align-items:center;gap:12px}
.logo-icon{width:36px;height:36px;border-radius:10px;
  background:linear-gradient(135deg,var(--primary),var(--primary2));
  display:flex;align-items:center;justify-content:center;font-size:18px;flex-shrink:0}
.logo-text{font-size:16px;font-weight:700;color:#fff}
.logo-sub{font-size:10px;color:var(--muted);font-weight:400}
.nav{flex:1;padding:12px 10px;overflow-y:auto}
.nav-section{font-size:10px;font-weight:700;text-transform:uppercase;letter-spacing:.1em;
  color:var(--muted);padding:14px 10px 6px}
.nav-item{display:flex;align-items:center;gap:10px;padding:9px 12px;border-radius:10px;
  cursor:pointer;transition:.15s;color:var(--dim);margin-bottom:2px;user-select:none}
.nav-item:hover{background:rgba(108,92,231,.1);color:var(--text)}
.nav-item.active{background:rgba(108,92,231,.18);color:var(--primary2);font-weight:600}
.nav-item .icon{font-size:16px;width:20px;text-align:center;flex-shrink:0}
.nav-item .badge{margin-left:auto;background:var(--primary);color:#fff;
  border-radius:20px;padding:1px 7px;font-size:10px;font-weight:700}
.sidebar-footer{padding:14px 10px;border-top:1px solid var(--border)}
.logout-btn{display:flex;align-items:center;gap:10px;padding:9px 12px;border-radius:10px;
  cursor:pointer;color:var(--danger);transition:.15s;width:100%;background:none;border:none;font-size:14px}
.logout-btn:hover{background:rgba(239,68,68,.1)}

/* ── Main ── */
#main{margin-left:240px;flex:1;display:flex;flex-direction:column;min-height:100vh}

/* ── Header ── */
#header{background:var(--surface);border-bottom:1px solid var(--border);
  padding:0 24px;height:60px;display:flex;align-items:center;justify-content:space-between;
  position:sticky;top:0;z-index:50}
.header-title{font-size:18px;font-weight:700;color:#fff}
.header-right{display:flex;align-items:center;gap:12px}
.refresh-btn{background:rgba(108,92,231,.15);border:1px solid rgba(108,92,231,.3);
  color:var(--primary2);padding:7px 14px;border-radius:8px;cursor:pointer;
  font-size:12px;font-weight:600;transition:.15s}
.refresh-btn:hover{background:rgba(108,92,231,.25)}
.admin-chip{background:rgba(108,92,231,.12);border:1px solid var(--border2);
  color:var(--primary2);padding:6px 14px;border-radius:20px;font-size:12px;font-weight:600}

/* ── Content ── */
#content{flex:1;padding:24px}

/* ── Section ── */
.section{display:none}
.section.active{display:block}

/* ── Stat cards ── */
.stats-grid{display:grid;grid-template-columns:repeat(4,1fr);gap:16px;margin-bottom:24px}
.stat-card{background:var(--card);border:1px solid var(--border);border-radius:16px;padding:20px}
.stat-icon{font-size:22px;margin-bottom:12px}
.stat-value{font-size:32px;font-weight:800;color:#fff;line-height:1}
.stat-label{font-size:11px;color:var(--muted);margin-top:6px;font-weight:500;text-transform:uppercase;letter-spacing:.05em}
.stat-sub{font-size:11px;margin-top:4px}
.stat-up{color:var(--success)}
.stat-down{color:var(--danger)}

/* ── Cards row ── */
.row2{display:grid;grid-template-columns:1fr 1fr;gap:16px;margin-bottom:24px}

/* ── Table card ── */
.table-card{background:var(--card);border:1px solid var(--border);border-radius:16px;overflow:hidden}
.table-header{padding:16px 20px;display:flex;align-items:center;justify-content:space-between;border-bottom:1px solid var(--border)}
.table-title{font-size:15px;font-weight:700;color:#fff}
.table-controls{display:flex;gap:10px;align-items:center}
input.search{background:var(--bg);border:1.5px solid var(--border2);border-radius:8px;
  padding:7px 12px;color:var(--text);font-size:12px;outline:none;width:200px;transition:.2s}
input.search:focus{border-color:var(--primary)}
.btn{padding:7px 14px;border-radius:8px;border:none;cursor:pointer;font-size:12px;font-weight:600;transition:.15s}
.btn-primary{background:var(--primary);color:#fff}
.btn-primary:hover{background:#5b4dd4}
.btn-danger{background:rgba(239,68,68,.15);color:var(--danger);border:1px solid rgba(239,68,68,.3)}
.btn-danger:hover{background:rgba(239,68,68,.25)}
.btn-edit{background:rgba(59,130,246,.15);color:var(--info);border:1px solid rgba(59,130,246,.3)}
.btn-edit:hover{background:rgba(59,130,246,.25)}
.btn-sm{padding:4px 10px;font-size:11px}
.btn-grant{background:rgba(16,185,129,.15);color:var(--success);border:1px solid rgba(16,185,129,.3)}
.btn-grant:hover{background:rgba(16,185,129,.25)}

table{width:100%;border-collapse:collapse}
th{padding:10px 16px;text-align:left;font-size:11px;font-weight:700;
  text-transform:uppercase;letter-spacing:.06em;color:var(--muted);
  background:rgba(255,255,255,.02);border-bottom:1px solid var(--border)}
td{padding:11px 16px;border-bottom:1px solid rgba(255,255,255,.04);font-size:13px;vertical-align:middle}
tr:last-child td{border-bottom:none}
tr:hover td{background:rgba(255,255,255,.02)}
.ellipsis{max-width:160px;overflow:hidden;text-overflow:ellipsis;white-space:nowrap}

/* ── Badges ── */
.badge-pill{display:inline-block;padding:2px 9px;border-radius:20px;font-size:11px;font-weight:600}
.badge-open{background:rgba(16,185,129,.15);color:var(--success)}
.badge-closed{background:rgba(239,68,68,.12);color:var(--danger)}
.badge-active{background:rgba(108,92,231,.15);color:var(--primary2)}
.badge-waiting{background:rgba(245,158,11,.12);color:var(--warn)}
.badge-serving{background:rgba(16,185,129,.15);color:var(--success)}
.badge-cancelled{background:rgba(107,114,128,.12);color:var(--muted)}
.badge-owner{background:rgba(59,130,246,.12);color:var(--info)}
.badge-customer{background:rgba(156,163,175,.08);color:var(--dim)}

/* ── Pagination ── */
.pagination{padding:12px 20px;display:flex;align-items:center;gap:8px;
  border-top:1px solid var(--border);justify-content:flex-end}
.page-btn{padding:5px 11px;border-radius:7px;border:1px solid var(--border2);
  background:none;color:var(--dim);cursor:pointer;font-size:12px;transition:.15s}
.page-btn:hover{background:rgba(255,255,255,.06);color:var(--text)}
.page-btn.cur{background:var(--primary);border-color:var(--primary);color:#fff}
.page-info{font-size:12px;color:var(--muted);margin-right:auto}

/* ── Modal ── */
.modal-overlay{position:fixed;inset:0;background:rgba(0,0,0,.7);backdrop-filter:blur(4px);
  z-index:200;display:none;align-items:center;justify-content:center}
.modal-overlay.open{display:flex}
.modal{background:var(--card);border:1px solid var(--border2);border-radius:20px;
  padding:28px;width:100%;max-width:460px;box-shadow:0 32px 80px rgba(0,0,0,.6)}
.modal h2{font-size:18px;font-weight:700;margin-bottom:4px}
.modal .modal-sub{font-size:13px;color:var(--muted);margin-bottom:22px}
.modal label{display:block;font-size:11px;font-weight:600;text-transform:uppercase;
  letter-spacing:.06em;color:var(--muted);margin-bottom:5px;margin-top:14px}
.modal input,.modal select{width:100%;padding:10px 12px;background:var(--bg);
  border:1.5px solid var(--border2);border-radius:9px;color:var(--text);
  font-size:13px;outline:none;transition:.2s}
.modal input:focus,.modal select:focus{border-color:var(--primary)}
.modal-footer{display:flex;gap:10px;margin-top:24px;justify-content:flex-end}

/* ── Confirm modal ── */
.confirm-icon{font-size:40px;text-align:center;margin-bottom:12px}
.confirm-msg{font-size:14px;color:var(--dim);margin-bottom:6px}

/* ── Loading / empty ── */
.loading{text-align:center;padding:40px;color:var(--muted)}
.empty{text-align:center;padding:40px;color:var(--muted)}
.empty-icon{font-size:40px;margin-bottom:10px}
.spinner{display:inline-block;width:20px;height:20px;border:2px solid var(--border2);
  border-top-color:var(--primary);border-radius:50%;animation:spin .7s linear infinite}
@keyframes spin{to{transform:rotate(360deg)}}

/* ── Recent activity card ── */
.activity-list{padding:6px 0}
.activity-item{padding:11px 20px;display:flex;gap:14px;align-items:flex-start;
  border-bottom:1px solid rgba(255,255,255,.04)}
.activity-item:last-child{border-bottom:none}
.activity-dot{width:8px;height:8px;border-radius:50%;margin-top:4px;flex-shrink:0}
.a-join{background:var(--primary)}
.a-serve{background:var(--success)}
.a-skip{background:var(--warn)}
.a-cancel{background:var(--danger)}
.activity-body{flex:1}
.activity-title{font-size:13px;color:var(--text)}
.activity-time{font-size:11px;color:var(--muted);margin-top:1px}

/* ── Toast ── */
#toast{position:fixed;bottom:28px;right:28px;z-index:300;
  background:var(--card);border:1px solid var(--border2);border-radius:12px;
  padding:12px 18px;font-size:13px;font-weight:500;
  box-shadow:0 8px 32px rgba(0,0,0,.4);
  transform:translateY(20px);opacity:0;transition:.3s;pointer-events:none}
#toast.show{transform:translateY(0);opacity:1}
#toast.ok{border-left:3px solid var(--success);color:#6ee7b7}
#toast.err{border-left:3px solid var(--danger);color:#fca5a5}
</style>
</head>
<body>

<!-- Sidebar -->
<nav id="sidebar">
  <div class="sidebar-logo">
    <div class="logo-icon">⚡</div>
    <div>
      <div class="logo-text">NOWAIT</div>
      <div class="logo-sub">Admin Console</div>
    </div>
  </div>
  <div class="nav">
    <div class="nav-section">Overview</div>
    <div class="nav-item active" onclick="nav('dashboard',this)">
      <span class="icon">📊</span> Dashboard
    </div>
    <div class="nav-section">Data</div>
    <div class="nav-item" onclick="nav('users',this)">
      <span class="icon">👥</span> Users
    </div>
    <div class="nav-item" onclick="nav('shops',this)">
      <span class="icon">🏪</span> Shops
    </div>
    <div class="nav-item" onclick="nav('queues',this)">
      <span class="icon">🔢</span> Live Queues
    </div>
    <div class="nav-section">Business</div>
    <div class="nav-item" onclick="nav('subscriptions',this)">
      <span class="icon">💳</span> Subscriptions
    </div>
    <div class="nav-item" onclick="nav('promotions',this)">
      <span class="icon">🎯</span> Promotions
    </div>
  </div>
  <div class="sidebar-footer">
    <button class="logout-btn" onclick="location.href='/nowaitt_778admin/logout'">
      <span class="icon">🚪</span> Sign Out
    </button>
  </div>
</nav>

<!-- Main -->
<div id="main">
  <div id="header">
    <div class="header-title" id="page-title">Dashboard</div>
    <div class="header-right">
      <button class="refresh-btn" onclick="refreshCurrent()">↻ Refresh</button>
      <div class="admin-chip">🛡 778Admin</div>
    </div>
  </div>
  <div id="content">

    <!-- ── Dashboard ── -->
    <div id="sec-dashboard" class="section active">
      <div class="stats-grid" id="stats-grid">
        <div class="loading"><div class="spinner"></div></div>
      </div>
      <div class="row2">
        <div class="table-card" id="recent-queue-card">
          <div class="table-header">
            <span class="table-title">⚡ Live Queue Activity</span>
          </div>
          <div id="recent-queue"><div class="loading"><div class="spinner"></div></div></div>
        </div>
        <div class="table-card">
          <div class="table-header"><span class="table-title">🏪 Shops Overview</span></div>
          <div id="dash-shops"><div class="loading"><div class="spinner"></div></div></div>
        </div>
      </div>
    </div>

    <!-- ── Users ── -->
    <div id="sec-users" class="section">
      <div class="table-card">
        <div class="table-header">
          <span class="table-title">All Users</span>
          <div class="table-controls">
            <input class="search" id="user-search" placeholder="Search by name…" oninput="debouncedLoad('users')">
            <span id="user-count" style="font-size:12px;color:var(--muted)"></span>
          </div>
        </div>
        <div id="users-body"><div class="loading"><div class="spinner"></div></div></div>
        <div class="pagination" id="users-pager"></div>
      </div>
    </div>

    <!-- ── Shops ── -->
    <div id="sec-shops" class="section">
      <div class="table-card">
        <div class="table-header">
          <span class="table-title">All Shops</span>
          <div class="table-controls">
            <input class="search" id="shop-search" placeholder="Search by name…" oninput="debouncedLoad('shops')">
            <span id="shop-count" style="font-size:12px;color:var(--muted)"></span>
          </div>
        </div>
        <div id="shops-body"><div class="loading"><div class="spinner"></div></div></div>
        <div class="pagination" id="shops-pager"></div>
      </div>
    </div>

    <!-- ── Queues ── -->
    <div id="sec-queues" class="section">
      <div class="table-card">
        <div class="table-header">
          <span class="table-title">Live Queue Entries</span>
          <div class="table-controls">
            <span id="queue-count" style="font-size:12px;color:var(--muted)"></span>
          </div>
        </div>
        <div id="queues-body"><div class="loading"><div class="spinner"></div></div></div>
        <div class="pagination" id="queues-pager"></div>
      </div>
    </div>

    <!-- ── Subscriptions ── -->
    <div id="sec-subscriptions" class="section">
      <div class="table-card">
        <div class="table-header">
          <span class="table-title">Subscriptions</span>
          <div class="table-controls">
            <button class="btn btn-grant" onclick="openGrantSub()">+ Grant Subscription</button>
          </div>
        </div>
        <div id="subs-body"><div class="loading"><div class="spinner"></div></div></div>
        <div class="pagination" id="subs-pager"></div>
      </div>
    </div>

    <!-- ── Promotions ── -->
    <div id="sec-promotions" class="section">
      <div class="table-card">
        <div class="table-header">
          <span class="table-title">Promotions</span>
          <div class="table-controls">
            <span id="promo-count" style="font-size:12px;color:var(--muted)"></span>
          </div>
        </div>
        <div id="promos-body"><div class="loading"><div class="spinner"></div></div></div>
        <div class="pagination" id="promos-pager"></div>
      </div>
    </div>

  </div><!-- /content -->
</div><!-- /main -->

<!-- Edit Shop Modal -->
<div class="modal-overlay" id="modal-shop">
  <div class="modal">
    <h2>Edit Shop</h2>
    <p class="modal-sub">Update shop details</p>
    <input type="hidden" id="edit-shop-id">
    <label>Shop Name</label><input id="edit-name" type="text">
    <label>Category</label><input id="edit-category" type="text">
    <label>City</label><input id="edit-city" type="text">
    <label>Avg Wait (min)</label><input id="edit-wait" type="number" min="1" max="120">
    <label>Status</label>
    <select id="edit-open">
      <option value="true">Open</option>
      <option value="false">Closed</option>
    </select>
    <div class="modal-footer">
      <button class="btn" style="background:var(--bg);border:1px solid var(--border2);color:var(--dim)" onclick="closeModal('modal-shop')">Cancel</button>
      <button class="btn btn-primary" onclick="saveShop()">Save Changes</button>
    </div>
  </div>
</div>

<!-- Grant Subscription Modal -->
<div class="modal-overlay" id="modal-grant">
  <div class="modal">
    <h2>Grant Subscription</h2>
    <p class="modal-sub">Manually activate a subscription for a shop</p>
    <label>Shop ID</label><input id="grant-shop-id" type="text" placeholder="Paste shop UUID…">
    <label>Duration (days)</label><input id="grant-days" type="number" value="30" min="1" max="365">
    <div class="modal-footer">
      <button class="btn" style="background:var(--bg);border:1px solid var(--border2);color:var(--dim)" onclick="closeModal('modal-grant')">Cancel</button>
      <button class="btn btn-grant" onclick="grantSubscription()">Grant</button>
    </div>
  </div>
</div>

<!-- Confirm Delete Modal -->
<div class="modal-overlay" id="modal-confirm">
  <div class="modal" style="max-width:380px">
    <div class="confirm-icon" id="confirm-icon">⚠️</div>
    <h2 id="confirm-title" style="text-align:center"></h2>
    <p class="confirm-msg" id="confirm-msg" style="text-align:center"></p>
    <div class="modal-footer" style="justify-content:center">
      <button class="btn" style="background:var(--bg);border:1px solid var(--border2);color:var(--dim)" onclick="closeModal('modal-confirm')">Cancel</button>
      <button class="btn btn-danger" id="confirm-ok">Delete</button>
    </div>
  </div>
</div>

<div id="toast"></div>

<script>
const BASE = '/nowaitt_778admin';
let pages = {users:1,shops:1,queues:1,subscriptions:1,promotions:1};
let debounceTimer;

/* ── Navigation ── */
function nav(sec, el) {
  document.querySelectorAll('.nav-item').forEach(i=>i.classList.remove('active'));
  if(el) el.classList.add('active');
  document.querySelectorAll('.section').forEach(s=>s.classList.remove('active'));
  document.getElementById('sec-'+sec).classList.add('active');
  document.getElementById('page-title').textContent =
    {dashboard:'Dashboard',users:'Users',shops:'Shops',
     queues:'Live Queues',subscriptions:'Subscriptions',promotions:'Promotions'}[sec];
  loadSection(sec);
}

function refreshCurrent() {
  const active = document.querySelector('.section.active');
  if(!active) return;
  const sec = active.id.replace('sec-','');
  loadSection(sec);
}

function loadSection(sec) {
  if(sec==='dashboard') loadDashboard();
  else if(sec==='users') loadUsers();
  else if(sec==='shops') loadShops();
  else if(sec==='queues') loadQueues();
  else if(sec==='subscriptions') loadSubs();
  else if(sec==='promotions') loadPromos();
}

function debouncedLoad(sec) {
  clearTimeout(debounceTimer);
  pages[sec]=1;
  debounceTimer = setTimeout(()=>loadSection(sec), 350);
}

/* ── Fetch helper ── */
async function api(url, opts={}) {
  const r = await fetch(BASE+url, {credentials:'include',...opts});
  if(r.status===401) { location.href=BASE+'/login'; return null; }
  return r.json();
}

/* ── Toast ── */
function toast(msg, ok=true) {
  const t=document.getElementById('toast');
  t.textContent=msg; t.className='show '+(ok?'ok':'err');
  setTimeout(()=>t.className='',3000);
}

/* ── Format helpers ── */
function fDate(d) {
  if(!d) return '—';
  const dt=new Date(d);
  return dt.toLocaleDateString('en-IN',{day:'2-digit',month:'short',year:'numeric'});
}
function fTime(d) {
  if(!d) return '—';
  const dt=new Date(d);
  return dt.toLocaleTimeString('en-IN',{hour:'2-digit',minute:'2-digit'});
}
function ago(d) {
  if(!d) return '';
  const s=Math.floor((Date.now()-new Date(d))/1000);
  if(s<60) return s+'s ago';
  if(s<3600) return Math.floor(s/60)+'m ago';
  if(s<86400) return Math.floor(s/3600)+'h ago';
  return Math.floor(s/86400)+'d ago';
}
function pill(text,cls) { return `<span class="badge-pill ${cls}">${text}</span>`; }

/* ── Pagination ── */
function renderPager(containerId, sec, cur, total, perPage) {
  const pages_ = Math.ceil(total/perPage);
  const el = document.getElementById(containerId);
  if(!el) return;
  let html = `<span class="page-info">${total} records · Page ${cur}/${pages_||1}</span>`;
  if(pages_>1) {
    if(cur>1) html+=`<button class="page-btn" onclick="goPage('${sec}',${cur-1})">‹</button>`;
    for(let i=Math.max(1,cur-2);i<=Math.min(pages_,cur+2);i++)
      html+=`<button class="page-btn${i===cur?' cur':''}" onclick="goPage('${sec}',${i})">${i}</button>`;
    if(cur<pages_) html+=`<button class="page-btn" onclick="goPage('${sec}',${cur+1})">›</button>`;
  }
  el.innerHTML = html;
}
function goPage(sec,p){ pages[sec]=p; loadSection(sec); }

/* ── Dashboard ── */
async function loadDashboard() {
  const d = await api('/api/stats');
  if(!d) return;
  document.getElementById('stats-grid').innerHTML = `
    <div class="stat-card">
      <div class="stat-icon">👥</div>
      <div class="stat-value">${d.total_users}</div>
      <div class="stat-label">Total Users</div>
      <div class="stat-sub" style="color:var(--info)">${d.total_owners} owners · ${d.total_users-d.total_owners} customers</div>
    </div>
    <div class="stat-card">
      <div class="stat-icon">🏪</div>
      <div class="stat-value">${d.total_shops}</div>
      <div class="stat-label">Total Shops</div>
      <div class="stat-sub stat-up">▲ ${d.open_shops} currently open</div>
    </div>
    <div class="stat-card">
      <div class="stat-icon">🔢</div>
      <div class="stat-value">${d.active_queue}</div>
      <div class="stat-label">In Queue Now</div>
      <div class="stat-sub" style="color:var(--warn)">${d.joins_today} joins today</div>
    </div>
    <div class="stat-card">
      <div class="stat-icon">💳</div>
      <div class="stat-value">${d.active_subscriptions}</div>
      <div class="stat-label">Active Subscriptions</div>
      <div class="stat-sub stat-up">▲ ${d.active_promotions} active promos</div>
    </div>`;

  // Live queues
  const q = await api('/api/queues?page=1');
  if(!q) return;
  const entries = (q.entries||[]).slice(0,6);
  document.getElementById('recent-queue').innerHTML = entries.length
    ? '<div class="activity-list">'+entries.map(e=>`
        <div class="activity-item">
          <div class="activity-dot a-${e.status==='serving'?'serve':e.status}"></div>
          <div class="activity-body">
            <div class="activity-title">${e.customer_name} @ <strong>${e.shop_name}</strong>
              &nbsp;${pill('#'+e.token_number,(e.status==='serving'?'badge-serving':'badge-waiting'))}</div>
            <div class="activity-time">${ago(e.created_at)}</div>
          </div>
        </div>`).join('')+'</div>'
    : '<div class="empty"><div class="empty-icon">🎉</div>No active queue entries</div>';

  // Shops
  const s = await api('/api/shops?page=1');
  if(!s) return;
  const shops = (s.shops||[]).slice(0,6);
  document.getElementById('dash-shops').innerHTML = shops.length
    ? '<table><thead><tr><th>Shop</th><th>City</th><th>Status</th></tr></thead><tbody>'
      + shops.map(sh=>`<tr>
          <td><div class="ellipsis">${sh.name}</div><div style="font-size:11px;color:var(--muted)">${sh.category}</div></td>
          <td>${sh.city}</td>
          <td>${sh.is_open?pill('Open','badge-open'):pill('Closed','badge-closed')}</td>
        </tr>`).join('')+'</tbody></table>'
    : '<div class="empty">No shops yet</div>';
}

/* ── Users ── */
async function loadUsers() {
  document.getElementById('users-body').innerHTML='<div class="loading"><div class="spinner"></div></div>';
  const q=document.getElementById('user-search')?.value||'';
  const d = await api(`/api/users?page=${pages.users}&q=${encodeURIComponent(q)}`);
  if(!d) return;
  document.getElementById('user-count').textContent=d.total+' users';
  const rows = (d.users||[]).map(u=>`<tr>
    <td style="font-size:11px;color:var(--muted)">${u.id.slice(0,8)}…</td>
    <td><strong>${u.name||'—'}</strong></td>
    <td>${u.phone||'—'}</td>
    <td>${u.city||'—'}</td>
    <td>${pill(u.role==='owner'?'Owner':'Customer',u.role==='owner'?'badge-owner':'badge-customer')}</td>
    <td>${fDate(u.created_at)}</td>
    <td><button class="btn btn-danger btn-sm" onclick="confirmDelete('user','${u.id}','${(u.name||'').replace(/'/g,"\\'")}')">Delete</button></td>
  </tr>`).join('');
  document.getElementById('users-body').innerHTML = rows
    ? `<table><thead><tr><th>ID</th><th>Name</th><th>Phone</th><th>City</th><th>Role</th><th>Joined</th><th></th></tr></thead><tbody>${rows}</tbody></table>`
    : '<div class="empty"><div class="empty-icon">👤</div>No users found</div>';
  renderPager('users-pager','users',pages.users,d.total,20);
}

/* ── Shops ── */
async function loadShops() {
  document.getElementById('shops-body').innerHTML='<div class="loading"><div class="spinner"></div></div>';
  const q=document.getElementById('shop-search')?.value||'';
  const d = await api(`/api/shops?page=${pages.shops}&q=${encodeURIComponent(q)}`);
  if(!d) return;
  document.getElementById('shop-count').textContent=d.total+' shops';
  const rows=(d.shops||[]).map(s=>`<tr>
    <td><div class="ellipsis"><strong>${s.name}</strong></div></td>
    <td>${s.category}</td>
    <td>${s.city}${s.state?', '+s.state:''}</td>
    <td><div class="ellipsis" style="color:var(--dim)">${s.owner_name}</div></td>
    <td>${s.is_open?pill('Open','badge-open'):pill('Closed','badge-closed')}</td>
    <td>${s.queue_count||0}</td>
    <td style="font-size:11px;color:var(--muted)">${fDate(s.created_at)}</td>
    <td style="display:flex;gap:6px">
      <button class="btn btn-edit btn-sm" onclick="openEditShop(${JSON.stringify(s).replace(/"/g,'&quot;')})">Edit</button>
      <button class="btn btn-danger btn-sm" onclick="confirmDelete('shop','${s.id}','${s.name.replace(/'/g,"\\'")}')">Del</button>
    </td>
  </tr>`).join('');
  document.getElementById('shops-body').innerHTML = rows
    ? `<table><thead><tr><th>Name</th><th>Category</th><th>City</th><th>Owner</th><th>Status</th><th>Queue</th><th>Created</th><th></th></tr></thead><tbody>${rows}</tbody></table>`
    : '<div class="empty"><div class="empty-icon">🏪</div>No shops found</div>';
  renderPager('shops-pager','shops',pages.shops,d.total,20);
}

/* ── Queues ── */
async function loadQueues() {
  document.getElementById('queues-body').innerHTML='<div class="loading"><div class="spinner"></div></div>';
  const d = await api(`/api/queues?page=${pages.queues}`);
  if(!d) return;
  document.getElementById('queue-count').textContent=d.total+' active entries';
  const rows=(d.entries||[]).map(e=>`<tr>
    <td><span style="font-weight:700;color:var(--primary2)">#${e.token_number}</span></td>
    <td>${e.customer_name}</td>
    <td style="font-size:11px;color:var(--muted)">${e.customer_phone}</td>
    <td><div class="ellipsis">${e.shop_name}</div></td>
    <td>${e.status==='serving'?pill('Serving','badge-serving'):pill('Waiting','badge-waiting')}</td>
    <td>${fTime(e.created_at)}<br><span style="font-size:10px;color:var(--muted)">${ago(e.created_at)}</span></td>
    <td><button class="btn btn-danger btn-sm" onclick="confirmDelete('queue','${e.id}','${e.customer_name.replace(/'/g,"\\'")}')">Cancel</button></td>
  </tr>`).join('');
  document.getElementById('queues-body').innerHTML = rows
    ? `<table><thead><tr><th>Token</th><th>Customer</th><th>Phone</th><th>Shop</th><th>Status</th><th>Joined</th><th></th></tr></thead><tbody>${rows}</tbody></table>`
    : '<div class="empty"><div class="empty-icon">🎉</div>No active entries</div>';
  renderPager('queues-pager','queues',pages.queues,d.total,30);
}

/* ── Subscriptions ── */
async function loadSubs() {
  document.getElementById('subs-body').innerHTML='<div class="loading"><div class="spinner"></div></div>';
  const d = await api(`/api/subscriptions?page=${pages.subscriptions}`);
  if(!d) return;
  const rows=(d.subscriptions||[]).map(s=>{
    const exp=new Date(s.expires_at);
    const isActive=s.status==='active'&&exp>new Date();
    return `<tr>
      <td><div class="ellipsis"><strong>${s.shop_name}</strong></div>
        <div style="font-size:11px;color:var(--muted)">${s.shop_city}</div></td>
      <td>${isActive?pill('Active','badge-active'):pill(s.status,'badge-cancelled')}</td>
      <td>${s.plan||'standard'}</td>
      <td>${fDate(s.created_at)}</td>
      <td style="${exp<new Date()?'color:var(--danger)':''}">${fDate(s.expires_at)}</td>
      <td>${isActive?`<button class="btn btn-danger btn-sm" onclick="confirmDelete('sub','${s.id}','${s.shop_name.replace(/'/g,"\\'")}')">Cancel</button>`:''}</td>
    </tr>`;}).join('');
  document.getElementById('subs-body').innerHTML = rows
    ? `<table><thead><tr><th>Shop</th><th>Status</th><th>Plan</th><th>Started</th><th>Expires</th><th></th></tr></thead><tbody>${rows}</tbody></table>`
    : '<div class="empty"><div class="empty-icon">💳</div>No subscriptions</div>';
  renderPager('subs-pager','subscriptions',pages.subscriptions,d.total,20);
}

/* ── Promotions ── */
async function loadPromos() {
  document.getElementById('promos-body').innerHTML='<div class="loading"><div class="spinner"></div></div>';
  const d = await api(`/api/promotions?page=${pages.promotions}`);
  if(!d) return;
  document.getElementById('promo-count').textContent=d.total+' promotions';
  const rows=(d.promotions||[]).map(p=>`<tr>
    <td><div class="ellipsis"><strong>${p.shop_name}</strong></div></td>
    <td class="ellipsis">${p.title}</td>
    <td class="ellipsis" style="color:var(--muted)">${p.description||'—'}</td>
    <td>${p.is_active?pill('Active','badge-active'):pill('Inactive','badge-cancelled')}</td>
    <td>${fDate(p.valid_until)}</td>
    <td><button class="btn btn-danger btn-sm" onclick="confirmDelete('promo','${p.id}','${p.title.replace(/'/g,"\\'")}')">Delete</button></td>
  </tr>`).join('');
  document.getElementById('promos-body').innerHTML = rows
    ? `<table><thead><tr><th>Shop</th><th>Title</th><th>Description</th><th>Status</th><th>Valid Until</th><th></th></tr></thead><tbody>${rows}</tbody></table>`
    : '<div class="empty"><div class="empty-icon">🎯</div>No promotions</div>';
  renderPager('promos-pager','promotions',pages.promotions,d.total,20);
}

/* ── Edit Shop Modal ── */
function openEditShop(s) {
  document.getElementById('edit-shop-id').value=s.id;
  document.getElementById('edit-name').value=s.name||'';
  document.getElementById('edit-category').value=s.category||'';
  document.getElementById('edit-city').value=s.city||'';
  document.getElementById('edit-wait').value=s.avg_wait_minutes||10;
  document.getElementById('edit-open').value=s.is_open?'true':'false';
  document.getElementById('modal-shop').classList.add('open');
}
async function saveShop() {
  const id=document.getElementById('edit-shop-id').value;
  const body={
    name:document.getElementById('edit-name').value,
    category:document.getElementById('edit-category').value,
    city:document.getElementById('edit-city').value,
    avg_wait_minutes:parseInt(document.getElementById('edit-wait').value)||10,
    is_open:document.getElementById('edit-open').value==='true',
  };
  const r=await api(`/api/shops/${id}`,{method:'PUT',headers:{'Content-Type':'application/json'},body:JSON.stringify(body)});
  if(r?.success){ toast('Shop updated'); closeModal('modal-shop'); loadShops(); }
  else toast('Failed to update shop',false);
}

/* ── Grant Subscription ── */
function openGrantSub(){ document.getElementById('modal-grant').classList.add('open'); }
async function grantSubscription() {
  const shopId=document.getElementById('grant-shop-id').value.trim();
  const days=parseInt(document.getElementById('grant-days').value)||30;
  if(!shopId){ toast('Enter a shop ID',false); return; }
  const r=await api('/api/subscriptions',{method:'POST',headers:{'Content-Type':'application/json'},body:JSON.stringify({shop_id:shopId,days})});
  if(r?.success){ toast('Subscription granted ✓'); closeModal('modal-grant'); loadSubs(); }
  else toast('Failed to grant subscription',false);
}

/* ── Confirm Delete ── */
let _deleteHandler=null;
function confirmDelete(type, id, name) {
  const msgs={
    user:{icon:'👤',title:`Delete "${name}"?`,msg:'This will remove the user and all their queue history permanently.'},
    shop:{icon:'🏪',title:`Delete "${name}"?`,msg:'All queue entries, subscriptions, and promotions for this shop will be deleted.'},
    queue:{icon:'🔢',title:`Cancel entry for "${name}"?`,msg:'The customer will be removed from the queue.'},
    sub:{icon:'💳',title:`Cancel subscription for "${name}"?`,msg:'The shop will lose queue management access immediately.'},
    promo:{icon:'🎯',title:`Delete promotion "${name}"?`,msg:'This promotion will be permanently removed.'},
  }[type];
  document.getElementById('confirm-icon').textContent=msgs.icon;
  document.getElementById('confirm-title').textContent=msgs.title;
  document.getElementById('confirm-msg').textContent=msgs.msg;
  _deleteHandler=async()=>{
    const ep={user:'/api/users/'+id,shop:'/api/shops/'+id,queue:'/api/queues/'+id,sub:'/api/subscriptions/'+id,promo:'/api/promotions/'+id}[type];
    const r=await api(ep,{method:'DELETE'});
    if(r?.success){
      toast('Deleted successfully');
      closeModal('modal-confirm');
      const sec={user:'users',shop:'shops',queue:'queues',sub:'subscriptions',promo:'promotions'}[type];
      loadSection(sec);
    } else toast('Delete failed',false);
  };
  document.getElementById('confirm-ok').onclick=_deleteHandler;
  document.getElementById('modal-confirm').classList.add('open');
}

/* ── Modal helpers ── */
function closeModal(id){ document.getElementById(id).classList.remove('open'); }
document.querySelectorAll('.modal-overlay').forEach(m=>{
  m.addEventListener('click',e=>{ if(e.target===m) m.classList.remove('open'); });
});

/* ── Init ── */
loadDashboard();
</script>
</body>
</html>"""
