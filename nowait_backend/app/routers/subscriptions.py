from fastapi import APIRouter, Depends, HTTPException

from app.dependencies import get_current_owner
from app.schemas.subscription import SubscriptionCreate, SubscriptionStatus
from app.services import subscription_service

router = APIRouter(prefix="/subscriptions", tags=["Subscriptions"])


@router.get("/shop/{shop_id}", response_model=SubscriptionStatus, summary="Get shop subscription status")
def get_subscription(shop_id: str, current_user: dict = Depends(get_current_owner)):
    """Returns current subscription details and whether it's active."""
    return subscription_service.get_subscription(shop_id, current_user["id"])


@router.post(
    "/shop/{shop_id}/start-trial",
    response_model=SubscriptionStatus,
    status_code=201,
    summary="Activate the one-time free month",
)
def start_trial(shop_id: str, current_user: dict = Depends(get_current_owner)):
    """Starts the 30-day free trial. Allowed once per email / mobile number, and only for a
    shop that has never had a plan. `GET /subscriptions/shop/{id}` reports `trial_available`."""
    return subscription_service.start_free_trial(shop_id, current_user["id"])


@router.post("/shop/{shop_id}", response_model=SubscriptionStatus, status_code=201, summary="Create or renew subscription")
def create_or_renew(shop_id: str, body: SubscriptionCreate, current_user: dict = Depends(get_current_owner)):
    """
    Create a new subscription or renew existing one.
    Plans: 1 month (30 days, Rs. 49) or 3 months (90 days, Rs. 130). New owners can start
    one free month with `POST /subscriptions/shop/{id}/start-trial`.

    **Sample Request:**
    ```json
    {"plan": "basic", "duration_days": 30}
    ```
    **Sample Response:**
    ```json
    {
      "has_active_subscription": true,
      "subscription": {
        "plan": "basic",
        "status": "active",
        "days_remaining": 30
      }
    }
    ```
    """
    # Subscriptions are only granted after a verified payment (POST
    # /payments/subscription/shop/{id}/verify). Leaving this open let any owner
    # activate a plan for free.
    raise HTTPException(
        status_code=403,
        detail="Subscriptions can only be activated through payment.",
    )


@router.delete("/shop/{shop_id}", response_model=SubscriptionStatus, summary="Cancel subscription")
def cancel_subscription(shop_id: str, current_user: dict = Depends(get_current_owner)):
    """Cancels the active subscription. Shop will no longer accept queue entries."""
    return subscription_service.cancel_subscription(shop_id, current_user["id"])
