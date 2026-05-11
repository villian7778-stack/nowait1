from fastapi import FastAPI
from fastapi.middleware.cors import CORSMiddleware

from app.config import settings
from app.routers import admin, analytics, auth, maps, notifications, promotions, queues, reviews, shops, staff, subscriptions

app = FastAPI(
    title="NOWAIT API",
    description="""
## NOWAIT Queue Management Backend

A REST API for the NOWAIT app — queue management for salons and shops.

### Authentication
All protected endpoints require a Bearer token obtained via `POST /auth/verify-otp`.

### Queue Flow (Customer)
1. `POST /auth/send-otp` — receive OTP on phone
2. `POST /auth/verify-otp` — get `access_token`
3. `POST /auth/complete-profile` — first login only
4. `GET /shops` — browse shops
5. `POST /queues/join` — join queue, receive token number
6. `GET /queues/status` — track position in real-time

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


@app.get("/", tags=["Health"])
def root():
    return {"status": "ok", "service": "NOWAIT API", "version": "1.0.0"}


@app.get("/health", tags=["Health"])
def health():
    return {"status": "healthy"}
