# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Overview

**NOWAIT** is a queue-management mobile app with two user personas:
- **Customers** — browse salons/shops, join queues, track wait status
- **Shop Owners** — manage their shop, monitor queues, handle subscriptions

This repository contains two layers:
1. **Flutter mobile app** (`nowait_app/`) — the client, talks to the backend via REST
2. **FastAPI backend** (`nowait_backend/`) — REST API backed by Supabase (PostgreSQL + Auth)

## Flutter App (`nowait_app/`)

```bash
cd nowait_app
flutter pub get      # Install dependencies (first time or after pubspec changes)
flutter run          # Run on connected device/emulator
flutter run -d chrome  # Run as web app
flutter analyze      # Lint
flutter test         # Run all widget tests
flutter test test/widget_test.dart              # Run a single test file
flutter test --name "description text"          # Run tests matching a name
```

Flutter widget tests only — no backend tests exist in `nowait_app/`.

**Flutter SDK requirement:** `^3.11.4` (see `pubspec.yaml`). Runtime dependencies are intentionally minimal: `google_fonts`, `http`, `shared_preferences`, `image_picker` — no state management library, no DI framework.

**To set the backend URL** (defaults to `http://localhost:8000`):
```bash
flutter run --dart-define=BASE_URL=http://192.168.1.x:8000
# Android emulator default: http://10.0.2.2:8000
```

**Root data:** `india_state_city.json` at the repo root provides the state→city mapping loaded by `searchable_picker_sheet.dart` for address fields. It is bundled into the Flutter app via `assets/data/`.

**Architecture:**
- `lib/main.dart` — entry point; loads `AuthService` and `LocaleService` from storage in parallel, routes to login/home/dashboard based on auth state; forces portrait; listens to `LocaleService` to rebuild the widget tree on language change
- `lib/config/app_config.dart` — reads `BASE_URL` dart-define
- `lib/theme/app_theme.dart` — single source of truth for `AppColors` and `AppTheme`; never hardcode colors in screens
- `lib/theme/category_theme.dart` — per-category color/icon mappings used by category chips and list screens
- `lib/models/models.dart` — all data models (`UserModel`, `ShopModel`, `ServiceModel`, `QueueEntry`, `NotificationModel`, `SchemeModel`, `StaffMember`, `StaffQueueGroup`, `AnalyticsSummary`, `VisitHistory`) and enums. `ShopModel.canAcceptQueue` (`isOpen && hasActiveSubscription && !queuePaused`) is the canonical gate before joining a queue. `SchemeModel` is populated from `active_promotions` in the shop JSON response.
- `lib/data/mock_data.dart` — static `CategoryProduct` lists (salon, beauty, hospital, etc.) used only by the category chip row at the top of each category screen; not a fallback for API calls
- `lib/services/` — all singletons; call the backend via `ApiClient`:
  - `api_client.dart` — singleton HTTP client (`ApiClient.instance`), attaches Bearer token, throws `ApiException` on non-2xx
  - `auth_service.dart` — OTP flow, session persistence via `shared_preferences`, role detection
  - `locale_service.dart` — i18n singleton; supports `en`/`hi`/`mr`; `LocaleService.instance.tr('key', params: {'name': 'value'})` for all user-facing strings; placeholders in string table use `{name}` syntax; persists choice via `shared_preferences`; extends `ChangeNotifier` so the app rebuilds on language switch
  - `shop_service.dart` — CRUD + toggle-open
  - `queue_service.dart` — join, status, cancel, coming, history
  - `notification_service.dart` — fetch, mark read
  - `promotion_service.dart` — create/edit schemes and featured promotions
  - `subscription_service.dart` — subscribe, renew, cancel
  - `staff_service.dart` — add/remove staff, view assignments
  - `analytics_service.dart` — summary, hourly, and per-staff stats
- `lib/widgets/` — reusable components:
  - `gradient_button.dart` — `GradientButton` (gradient fill, `AnimatedScale` press feedback) and `GhostButton` (10% primary opacity bg, no gradient) — use instead of `ElevatedButton`
  - `shop_card.dart` — `ShopCard`
  - `status_badge.dart` — `StatusBadge`
  - `searchable_picker_sheet.dart` — bottom-sheet picker with search input; used for state/city selection
  - `ping_dot.dart` — animated pulsing dot indicator (live/active status)
  - `dashed_circle_painter.dart` — custom painter for dashed-circle decorations on token/queue screens
- `lib/screens/auth/` — login, create account, OTP verification
- `lib/screens/customer/` — `home_screen.dart`, `category_screen.dart` (category grid), `category_list_screen.dart` (shops within a category), `salon_list_screen.dart`, `shop_details_screen.dart`, `join_queue_sheet.dart` (bottom sheet), `queue_status_screen.dart`, `token_screen.dart` (large token number display after joining), `notifications_screen.dart`, `history_screen.dart` (past visits using `VisitHistory`)
- `lib/screens/owner/` — `owner_dashboard_screen.dart`, `manage_shop_screen.dart`, `edit_shop_screen.dart`, `create_shop_screen.dart`, `subscription_screen.dart`, `promotion_screen.dart` (paid "Featured Promotion" visibility boosts), `scheme_screen.dart` (create/edit customer-facing offer/scheme via `PromotionService`), `staff_management_screen.dart` (add/remove staff by phone, view staff queue groups)

**Key conventions:**
- `AuthService.instance`, `ApiClient.instance`, and all domain services are singletons — never instantiate with `new`
- `GradientButton` wraps `GestureDetector` + `AnimatedScale` — use it for primary CTAs; `GhostButton` for secondary actions
- Shadows use `AppColors.shadowPrimary` (`rgba(31,76,221,0.08)`), never `Colors.black`
- Phone numbers use a hardcoded `+91` prefix (India)
- No state management library — screens are `StatefulWidget`; call services directly in `initState`/handlers
- Navigation uses `Navigator.push`/`pop` directly — no named routes
- `AuthService.pendingPhone` stores the phone number during OTP flow because in demo mode the JWT doesn't contain a phone claim; it's passed explicitly to `complete-profile`
- All user-facing strings go through `LocaleService.instance.tr('key')` — never hardcode display text in widgets

## Design System

Key rules (matching the HTML prototypes the app was built from):

### Colors
- **Primary gradient**: `#1f4cdd` → `#5b3cdd` at 135° (used sparingly — max 2 elements per screen)
- **Surface base**: `#faf8ff`; cards use `surface-container-lowest` (`#ffffff`) to "pop"
- **Success**: `tertiary` `#006b2d`; **Error**: `#ba1a1a`
- Shadows: `rgba(31, 76, 221, 0.08)` — never pure black

### The "No-Line" Rule
**Never use 1px solid borders to separate content.** Use background-color shifts between surface tiers or whitespace instead.

### Typography
Both **Plus Jakarta Sans** and **Inter** are loaded via the `google_fonts` Flutter package — no font assets bundled.
- `display-lg`: Plus Jakarta Sans Bold, 3.5rem, −0.02em tracking
- `headline-sm`: Plus Jakarta Sans SemiBold, 1.5rem
- `title-md`: Inter Medium, 1.125rem
- `body-md`: Inter Regular, 0.875rem
- `label-md`: Inter SemiBold, 0.75rem, +0.02em tracking

### Components
- **Buttons**: 52px height, 1.5rem border-radius, gradient fill
- **Inputs**: `outline-variant` at 40% opacity, 12px radius; focus = 2px `primary` border
- **Cards**: 16px radius, no divider lines, 16–24px spacing to group items
- **Bottom Sheets**: Glassmorphic (60% opacity + heavy blur), `xl` top-corner radius, no handle bar
- **Badges**: Open = `tertiary-fixed` bg; Closed = `error-container` bg; Promoted = primary/secondary micro-gradient

## Backend API (`nowait_backend/`)

FastAPI + Supabase. No ORM — all data access via the Supabase Python SDK.

```bash
cd nowait_backend
# Create .env with required variables (no .env.example committed)
source venv/bin/activate       # venv/ already exists; use venv\Scripts\activate on Windows
pip install -r requirements.txt
uvicorn app.main:app --reload  # http://localhost:8000
```

Required `.env` variables: `SUPABASE_URL`, `SUPABASE_SERVICE_KEY`, `SUPABASE_ANON_KEY`, `SUPABASE_JWT_SECRET`. Optional: `DEMO_MODE` (default `True`), `DEMO_OTP` (default `123456`), `DEMO_PASSWORD` (default `NowaitDemo#2024` — used by demo auth flow). **No `.env.example` is committed** — create `.env` from scratch using the variable names above.

Run `sql/schema.sql` once in Supabase's SQL Editor to create all tables, indexes, RLS policies, and the atomic `join_queue` function. Incremental migration scripts (`sql/migrate_*.sql`) and `sql/storage_setup.sql` (Supabase Storage bucket/policy setup) are applied separately as needed. Interactive docs at `/docs`.

**Backend tests** (unit tests with mocked Supabase — no real DB needed):
```bash
cd nowait_backend
source venv/bin/activate  # or venv\Scripts\activate on Windows
pytest tests/                          # Run all backend tests
pytest tests/test_queue_service.py     # Run a single test file
pytest tests/ -k "test_join_queue"     # Run tests matching a name
```
Test files: `test_api_endpoints.py`, `test_queue_service.py`, `test_shop_service.py`, `test_subscription_service.py`, `test_staff_service.py`, `test_notification_service.py`.

The `conftest.py` patches `supabase.create_client` before any imports, so no real Supabase credentials are needed. Each test module must patch its own local `supabase` binding (e.g. `patch("app.services.queue_service.supabase", ...)`), not just `app.database.supabase`.

```bash
docker build -t nowait-backend .
docker run -p 8000:8000 --env-file .env nowait-backend
```

**Architecture:**
```
app/
  main.py          — FastAPI app, CORS, router registration
  config.py        — Settings (pydantic-settings, reads .env); DEMO_MODE bypasses real OTP
  database.py      — Two Supabase clients: supabase (service_role) and supabase_auth (anon, for OTP)
  dependencies.py  — FastAPI Depends: get_current_user, get_current_owner, get_token_user_id
  routers/         — One file per domain: auth, shops, queues, notifications, promotions, subscriptions, staff, analytics
  schemas/         — Pydantic request/response models
  services/        — Business logic; routers are thin HTTP adapters only
```

**Auth:** Supabase JWTs are decoded in `dependencies.py` — it tries HS256 first (legacy projects), then falls back to ES256/RS256 via cached JWKS (newer projects). Audience must be `authenticated`. Four `Depends` helpers exist: `get_current_user` (full profile lookup), `get_current_owner` (enforces `role == 'owner'`), `get_token_user_id` (ID only, no profile needed), `get_token_claims` (full JWT payload including `phone` claim — used for profile creation).

**Demo mode:** `DEMO_MODE=True` (default) accepts OTP `123456` without Twilio. For production, set `DEMO_MODE=False` and enable the Phone provider in Supabase (Authentication > Providers) with Twilio credentials.

**`execute_one(query)`** (`database.py`) — wrapper around `.maybe_single().execute()` that normalises supabase-py 2.9+ behaviour where a missing row may return `None` or raise `APIError(code=204)`. All single-row lookups in services should use this instead of `.single()`.

**No real-time push** — the API has no WebSocket or SSE endpoints. Flutter clients poll `GET /queues/status` to track queue position updates.

### Key Domain Rules

- **One shop per owner** — enforced in `shop_service.py`
- **Subscription required to open shop** — `toggle-open` checks for active subscription
- **Atomic queue join** — `POST /queues/join` calls the `join_queue` PG function: locks shop row, validates open + subscription, prevents duplicate joins, assigns next token
- **Token numbers never reset** — monotonically increasing per shop
- **Queue advance** (`POST /queues/shop/{id}/next`) — completes current `serving` entry, promotes next `waiting`, creates `your_turn`/`almost_there` notifications
- **Queue pause/resume** — `POST /queues/shop/{id}/pause` and `/resume` set `queue_paused` on the shop; paused shops still appear but `canAcceptQueue` returns `false`
- **Staff queues** — customers can join a specific staff member's queue by passing `staff_id` to `/queues/join`; owners view staff-grouped queues via `GET /queues/shop/{id}/by-staff`
- **`active_promotions` parsing** — entries with `title == 'Featured Promotion'` are paid visibility boosts (`isPromoted` flag on `ShopModel`); all other entries become the `SchemeModel` (customer-facing offer/scheme)

### Queue `display_status` Values

| Value | Meaning |
|---|---|
| `waiting` | In queue, position 4 or later |
| `almostThere` | In queue, position 1–3 |
| `yourTurn` | Currently being served (`status = serving`) |
| `completed` | Service completed |
| `skipped` | Skipped by owner |
| `cancelled` | Cancelled by customer |

Estimated wait: `(position - 1) * avg_wait_minutes` (shop owner sets `avg_wait_minutes`).

### Notification Types (server-side only)

- `your_turn` — sent when a customer is called to serve
- `almost_there` — sent to customers at positions 2 and 3 after each advance
- `skipped` — sent when the owner skips a customer
- `coming` — customer self-notifies the shop they're on their way (`POST /queues/{id}/coming`)
- `promotion` — reserved for future manual use

### API Endpoints Reference

| Method | Path | Auth | Description |
|---|---|---|---|
| GET | `/` | — | Service status |
| GET | `/health` | — | Health check |
| POST | `/auth/send-otp` | — | Send OTP (E.164 phone) |
| POST | `/auth/verify-otp` | — | Verify OTP, get JWTs |
| POST | `/auth/complete-profile` | Bearer | Set name, city, role (first login only) |
| GET | `/auth/me` | Bearer | Current user profile |
| POST | `/auth/refresh` | — | Refresh access token |
| GET | `/shops` | — | List shops (`city`, `category`, `open_only` filters) |
| GET | `/shops/categories` | — | All categories |
| GET | `/shops/my` | Owner | Owner's shop |
| GET | `/shops/{id}` | — | Shop detail with services and promotions |
| POST | `/shops` | Owner | Create shop |
| PUT | `/shops/{id}` | Owner | Update shop |
| POST | `/shops/{id}/toggle-open` | Owner | Toggle open/closed |
| POST | `/shops/{id}/services` | Owner | Add service |
| DELETE | `/shops/services/{id}` | Owner | Delete service |
| POST | `/queues/join` | Customer | Join queue (optional `staff_id`, `service_id`) |
| GET | `/queues/status` | Customer | Active queue entries |
| DELETE | `/queues/{id}/cancel` | Customer | Cancel waiting entry |
| POST | `/queues/{id}/coming` | Customer | Notify shop customer is on the way |
| GET | `/queues/history` | Customer | Past visit history |
| GET | `/queues/shop/{id}` | Owner/Staff | Full shop queue with customer details |
| POST | `/queues/shop/{id}/next` | Owner/Staff | Advance queue (optional `staff_id` query param) |
| POST | `/queues/{id}/skip` | Owner/Staff | Skip a customer |
| GET | `/queues/shop/{id}/by-staff` | Owner | Queue grouped by staff member |
| POST | `/queues/shop/{id}/pause` | Owner | Pause entire shop queue |
| POST | `/queues/shop/{id}/resume` | Owner | Resume shop queue |
| GET | `/notifications` | Customer | Last 50 notifications with unread count |
| PATCH | `/notifications/{id}/read` | Customer | Mark one read |
| PATCH | `/notifications/read-all` | Customer | Mark all read |
| GET | `/promotions/shop/{id}` | — | Shop promotions (`active_only` param) |
| POST | `/promotions/shop/{id}` | Owner | Create promotion |
| PUT | `/promotions/{id}` | Owner | Update promotion |
| DELETE | `/promotions/{id}` | Owner | Delete promotion |
| GET | `/subscriptions/shop/{id}` | Owner | Subscription status |
| POST | `/subscriptions/shop/{id}` | Owner | Create or renew subscription |
| DELETE | `/subscriptions/shop/{id}` | Owner | Cancel subscription |
| GET | `/staff/shops/{id}` | Owner | List shop staff |
| POST | `/staff/shops/{id}` | Owner | Add staff by phone number |
| DELETE | `/staff/shops/{id}/{user_id}` | Owner | Remove staff member |
| POST | `/staff/self-register` | Owner | Register self as staff |
| GET | `/staff/my-assignments` | User | Shops where current user is staff |
| GET | `/analytics/shops/{id}/summary` | Owner/Staff | Summary stats (`period`: today/week/month) |
| GET | `/analytics/shops/{id}/hourly` | Owner/Staff | Hourly customer counts (`days`: 1–30) |
| GET | `/analytics/shops/{id}/staff` | Owner | Per-staff performance metrics |

### Database Tables

`profiles`, `shops`, `services`, `subscriptions`, `promotions`, `queue_entries`, `notifications`, `shop_staff` — all RLS-enabled; service role key bypasses RLS server-side.
