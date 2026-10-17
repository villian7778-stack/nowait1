from typing import Optional

from pydantic import BaseModel, Field


class CreateOrderResponse(BaseModel):
    order_id: str
    amount: int
    currency: str
    key_id: str


class CheckoutFailureReport(BaseModel):
    razorpay_order_id: Optional[str] = Field(default=None, max_length=64)
    purpose: Optional[str] = Field(default=None, max_length=20)       # 'subscription' | 'promotion'
    step: Optional[str] = Field(default=None, max_length=40)          # 'create_order' | 'checkout' | 'verify'
    source: Optional[str] = Field(default=None, max_length=100)        # e.g. 'razorpay_checkout'
    code: Optional[str] = Field(default=None, max_length=100)
    reason: Optional[str] = Field(default=None, max_length=200)
    description: Optional[str] = Field(default=None, max_length=500)
    message: Optional[str] = Field(default=None, max_length=1000)
    raw: Optional[str] = Field(default=None, max_length=4000)


class SubscriptionOrderRequest(BaseModel):
    plan: str  # 'basic'
    duration_days: int = 30
    # Must be true to buy while a subscription is still active (extends it).
    extend: bool = False


class SubscriptionVerifyRequest(BaseModel):
    # plan/duration_days are accepted for older app versions but ignored: the server
    # uses what was stored when the order was created.
    plan: Optional[str] = None
    duration_days: Optional[int] = None
    razorpay_order_id: str = Field(max_length=64)
    razorpay_payment_id: str = Field(max_length=64)
    razorpay_signature: str = Field(max_length=128)


class PromotionOrderRequest(BaseModel):
    # Featured Promotion length in days (3, 7 or 15). The title, description,
    # end date and price are all worked out by the server from this.
    days: int


class PromotionVerifyRequest(BaseModel):
    # Ignored (kept for older app versions): the stored order metadata is used.
    title: Optional[str] = None
    description: Optional[str] = None
    valid_until: Optional[str] = None
    razorpay_order_id: str = Field(max_length=64)
    razorpay_payment_id: str = Field(max_length=64)
    razorpay_signature: str = Field(max_length=128)
