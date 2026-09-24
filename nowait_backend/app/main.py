from fastapi import FastAPI
from fastapi.middleware.cors import CORSMiddleware
from slowapi import _rate_limit_exceeded_handler
from slowapi.errors import RateLimitExceeded

from app.config import settings
from app.rate_limit import limiter
from app.routers import admin, analytics, auth, maps, notifications, payments, promotions, queues, reviews, shops, staff, subscriptions

app = FastAPI(
    title="NOWAIT API",
    description="""
## NOWAIT Queue Management Backend

A REST API for the NOWAIT app — queue management for salons and shops.

### Authentication
All protected endpoints require a Bearer token obtained via `POST /auth/login` (or
`POST /auth/register` for a new account). Google sign-in is handled client-side via
Supabase Auth; the resulting token works against the same endpoints — a new Google
user without a profile calls `POST /auth/complete-profile` once.

### Queue Flow (Customer)
1. `POST /auth/register` — create account (email + password), or `POST /auth/login`
2. `GET /shops` — browse shops
3. `POST /queues/join` — join queue, receive token number
4. `GET /queues/status` — track position in real-time

### Queue Flow (Owner)
1. Authenticate (same as above, role = 'owner')
2. `POST /shops` — create shop
3. `POST /subscriptions/shop/{id}` — activate subscription
4. `POST /shops/{id}/toggle-open` — open shop
5. `GET /queues/shop/{id}` — view live queue
6. `POST /queues/shop/{id}/next` — serve next customer
    """,
    version="1.0.0",
    docs_url="/docs",
    redoc_url="/redoc",
)

app.state.limiter = limiter
app.add_exception_handler(RateLimitExceeded, _rate_limit_exceeded_handler)

app.add_middleware(
    CORSMiddleware,
    allow_origins=settings.cors_origins,
    allow_credentials=True,
    allow_methods=["*"],
    allow_headers=["*"],
)

app.include_router(admin.router)
app.include_router(auth.router)
app.include_router(reviews.router)
app.include_router(maps.router)
app.include_router(shops.router)
app.include_router(queues.router)
app.include_router(staff.router)
app.include_router(analytics.router)
app.include_router(notifications.router)
app.include_router(promotions.router)
app.include_router(subscriptions.router)
app.include_router(payments.router)


@app.get("/", tags=["Health"])
def root():
    return {"status": "ok", "service": "NOWAIT API", "version": "1.0.0"}


@app.get("/health", tags=["Health"])
def health():
    return {"status": "healthy"}
