from pydantic import BaseModel


class CreateOrderResponse(BaseModel):
    order_id: str
    amount: int
    currency: str
    key_id: str


class SubscriptionOrderRequest(BaseModel):
    plan: str  # 'basic' or 'premium'
    duration_days: int = 30


class SubscriptionVerifyRequest(BaseModel):
    plan: str
    duration_days: int = 30
    razorpay_order_id: str
    razorpay_payment_id: str
    razorpay_signature: str


class PromotionOrderRequest(BaseModel):
    title: str
    description: str
    valid_until: str


class PromotionVerifyRequest(BaseModel):
    title: str
    description: str
    valid_until: str
    razorpay_order_id: str
    razorpay_payment_id: str
    razorpay_signature: str
