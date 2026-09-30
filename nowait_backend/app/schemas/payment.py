from typing import Optional

from pydantic import BaseModel


class CreateOrderResponse(BaseModel):
    order_id: str
    amount: int
    currency: str
    key_id: str


class CheckoutFailureReport(BaseModel):
    razorpay_order_id: Optional[str] = None
    purpose: Optional[str] = None       # 'subscription' | 'promotion'
    step: Optional[str] = None          # 'create_order' | 'checkout' | 'verify'
    source: Optional[str] = None        # e.g. 'razorpay_checkout'
    code: Optional[str] = None
    reason: Optional[str] = None
    description: Optional[str] = None
    message: Optional[str] = None
    raw: Optional[str] = None


class SubscriptionOrderRequest(BaseModel):
    plan: str  # 'basic' or 'premium'
    duration_days: int = 30
    # Must be true to buy while a subscription is still active (extends it).
    extend: bool = False


class SubscriptionVerifyRequest(BaseModel):
    # plan/duration_days are accepted for older app versions but ignored: the server
    # uses what was stored when the order was created.
    plan: Optional[str] = None
    duration_days: Optional[int] = None
    razorpay_order_id: str
    razorpay_payment_id: str
    razorpay_signature: str


class PromotionOrderRequest(BaseModel):
    title: str
    description: str
    valid_until: str


class PromotionVerifyRequest(BaseModel):
    # Ignored (kept for older app versions): the stored order metadata is used.
    title: Optional[str] = None
    description: Optional[str] = None
    valid_until: Optional[str] = None
    razorpay_order_id: str
    razorpay_payment_id: str
    razorpay_signature: str
