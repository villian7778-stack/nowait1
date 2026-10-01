from typing import Optional
from pydantic import BaseModel


class SubscriptionCreate(BaseModel):
    plan: str  # 'basic' (paid). 'trial' is granted by the server only.
    duration_days: int = 30  # 30 (Rs. 49) or 90 (Rs. 130)


class SubscriptionResponse(BaseModel):
    id: str
    shop_id: str
    plan: str
    status: str
    started_at: str
    expires_at: str
    days_remaining: int
    created_at: str


class SubscriptionStatus(BaseModel):
    has_active_subscription: bool
    subscription: Optional[SubscriptionResponse] = None
    # True while this shop has never had a plan and its owner's email / mobile number
    # have not had a free month yet - the app then offers "Activate free trial".
    trial_available: bool = False
