"""Public policy pages: privacy, terms, refund & cancellation, contact and account deletion.

Google Play needs a public Privacy Policy URL and an account-deletion URL; Razorpay needs
Terms, Privacy, Refund/Cancellation and Contact pages before it activates live payments.
Business details come from settings (LEGAL_* / SUPPORT_* in .env) and prices from the code
that actually charges them, so these pages can't drift from what the app does.

These are sensible starting texts written from what the app really does - have them reviewed
by someone qualified before launch.
"""
from html import escape

from fastapi import APIRouter
from fastapi.responses import HTMLResponse

from app.config import settings
from app.services import promotion_service, subscription_service, trial_service

router = APIRouter(prefix="/legal", tags=["Legal"])

LAST_UPDATED = "16 October 2026"


def _e(value) -> str:
    return escape(str(value or ""))


def _business() -> str:
    return _e(settings.LEGAL_BUSINESS_NAME or "NOWAITT")


def _contact_block() -> str:
    lines = [f"<li>Email: <a href=\"mailto:{_e(settings.SUPPORT_EMAIL)}\">{_e(settings.SUPPORT_EMAIL)}</a></li>"]
    if settings.SUPPORT_PHONE:
        lines.append(f"<li>Phone: {_e(settings.SUPPORT_PHONE)}</li>")
    if settings.LEGAL_ADDRESS:
        lines.append(f"<li>Address: {_e(settings.LEGAL_ADDRESS)}</li>")
    return "<ul>" + "".join(lines) + "</ul>"


def _prices() -> dict:
    p = subscription_service.DURATION_PRICES
    return {
        "month": p.get(30), "quarter": p.get(90),
        "trial_months": trial_service.TRIAL_DAYS // 30,
        "promo_per_day": promotion_service.PROMOTION_PRICE_PER_DAY,
        "promo_days": ", ".join(str(d) for d in promotion_service.PROMOTION_DAYS),
    }


def _page(title: str, body: str) -> HTMLResponse:
    nav = " · ".join(
        f'<a href="/legal/{slug}">{name}</a>'
        for slug, name in (("privacy", "Privacy"), ("terms", "Terms"), ("refund-policy", "Refunds"),
                           ("contact", "Contact"), ("delete-account", "Delete account"))
    )
    html = f"""<!DOCTYPE html>
<html lang="en"><head><meta charset="utf-8"><meta name="viewport" content="width=device-width,initial-scale=1">
<title>{_e(title)} · {_business()}</title>
<style>
  body{{margin:0;font-family:-apple-system,Segoe UI,Roboto,Helvetica,Arial,sans-serif;background:#faf8ff;color:#1b1b21;line-height:1.6}}
  main{{max-width:760px;margin:0 auto;padding:28px 20px 60px}}
  header{{background:linear-gradient(135deg,#1f4cdd,#5b3cdd);color:#fff;padding:22px 20px}}
  header .in{{max-width:760px;margin:0 auto}} header a{{color:#fff;text-decoration:none;font-weight:700;font-size:18px}}
  h1{{font-size:26px;margin:0 0 4px}} h2{{font-size:18px;margin:28px 0 8px}}
  .muted{{color:#5c5f71;font-size:14px}} a{{color:#1f4cdd}} nav{{font-size:14px;margin-top:36px;color:#5c5f71}}
  .card{{background:#fff;border-radius:16px;padding:18px 20px;box-shadow:0 2px 12px rgba(31,76,221,.08)}}
</style></head>
<body><header><div class="in"><a href="/legal">{_business()}</a></div></header>
<main><h1>{_e(title)}</h1><p class="muted">Last updated: {LAST_UPDATED}</p>{body}<nav>{nav}</nav></main></body></html>"""
    return HTMLResponse(html)


@router.get("", response_class=HTMLResponse, include_in_schema=False)
def index():
    body = """<div class="card"><ul>
<li><a href="/legal/privacy">Privacy Policy</a></li>
<li><a href="/legal/terms">Terms of Service</a></li>
<li><a href="/legal/refund-policy">Refund &amp; Cancellation Policy</a></li>
<li><a href="/legal/contact">Contact Us</a></li>
<li><a href="/legal/delete-account">Delete your account</a></li></ul></div>
<h2>Contact</h2>""" + _contact_block()
    return _page("Policies", body)


@router.get("/privacy", response_class=HTMLResponse, include_in_schema=False)
def privacy():
    b = _business()
    body = f"""
<p>{b} ("we") runs the {b} app, which lets customers join a shop's queue from their phone and lets shop
owners manage their queue. This policy explains what information we collect, why, and the choices you have.</p>

<h2>Information we collect</h2>
<ul>
<li><b>Account details:</b> your name, email address, mobile number, city and state, and whether you are a customer or a shop owner. If you sign in with Google we receive your name and email address from Google.</li>
<li><b>Shop details (shop owners):</b> shop name, category, address and map location, opening hours, photos, services and prices, and the names of staff you add.</li>
<li><b>Queue activity:</b> the queues you join, your token number, the services you choose, visit times and status, and notifications we send you.</li>
<li><b>Reviews:</b> star ratings and comments you write about a visit, and reports you make about reviews.</li>
<li><b>Location:</b> only when you choose to use a location feature (for example picking your shop on the map or finding nearby shops). We do not track your location in the background.</li>
<li><b>Payments (shop owners):</b> payments are processed by Razorpay. We receive the payment reference, amount and status. We never see or store your card, UPI or bank details.</li>
</ul>

<h2>How we use it</h2>
<ul>
<li>To run the service: create your account, show shops, manage queues, notify you when your turn is near, and show reviews.</li>
<li>To process subscriptions and promotions, and to make sure each person gets the free trial only once.</li>
<li>To keep the service safe: preventing misuse, handling reports and answering support requests.</li>
</ul>

<h2>Who can see your information</h2>
<ul>
<li><b>The shop you queue at</b> sees your name and mobile number, so it can call you when it is your turn.</li>
<li><b>Other users</b> see a shop's public details and the first name shown with a review.</li>
<li><b>Service providers</b> that run parts of the service for us: our hosting and database provider, Razorpay (payments) and Google (sign-in and maps). They may use your information only to provide their service to us.</li>
<li>We share information with authorities only when the law requires it.</li>
</ul>
<p>We do not sell your personal information.</p>

<h2>How long we keep it</h2>
<p>We keep your information while your account exists. When you delete your account, your profile, shop, queue history,
reviews and notifications are deleted. To stop the free trial being claimed more than once, we keep a scrambled code made from
your email and mobile number; it cannot be turned back into your details. Payment records are also kept by Razorpay as the law requires.</p>

<h2>Your choices and rights</h2>
<ul>
<li><b>Delete your account</b> at any time in the app (Profile → Delete Account), or see <a href="/legal/delete-account">how to delete your account</a>.</li>
<li><b>Access or correct</b> your information by writing to us at the address below.</li>
<li>You can refuse location permission; the rest of the app keeps working.</li>
</ul>

<h2>Security</h2>
<p>Information is sent over an encrypted connection (HTTPS) and access to it is restricted to the systems that need it.
No system is perfectly secure, but we work to protect your information.</p>

<h2>Children</h2>
<p>The app is not meant for children under 13. Shop owners must be at least 18 years old.</p>

<h2>Changes</h2>
<p>We may update this policy. We will change the date at the top, and tell you in the app if the change is important.</p>

<h2>Contact and grievances</h2>
<p>For questions, requests or complaints about your personal information, contact us:</p>{_contact_block()}"""
    return _page("Privacy Policy", body)


@router.get("/terms", response_class=HTMLResponse, include_in_schema=False)
def terms():
    b, p = _business(), _prices()
    jurisdiction = _e(settings.LEGAL_JURISDICTION or "India")
    body = f"""
<p>These terms apply when you use the {b} app. By creating an account you agree to them.</p>

<h2>The service</h2>
<p>{b} lets customers take a token in a shop's queue and follow their place in line, and lets shop owners manage that queue.
Waiting times shown in the app are estimates; the shop decides when to serve each customer.</p>

<h2>Your account</h2>
<ul>
<li>Give true details and keep your login safe. You are responsible for what happens in your account.</li>
<li>One account per person. You must be at least 13 to use the app, and at least 18 to register a shop.</li>
</ul>

<h2>Shop owners</h2>
<ul>
<li>You must run a genuine business and describe it honestly, including your services and prices.</li>
<li>A subscription is needed to open your shop to customers: ₹{p['month']} for 1 month or ₹{p['quarter']} for 3 months.
New shop owners can activate a free trial of {p['trial_months']} months once per person (per email and mobile number).</li>
<li>Featured Promotion costs ₹{p['promo_per_day']} per day and can be bought for {p['promo_days']} days.</li>
<li>All payments are final - see the <a href="/legal/refund-policy">Refund &amp; Cancellation Policy</a>.</li>
<li>Treat customers' names and mobile numbers only as needed to serve them.</li>
</ul>

<h2>Reviews and content</h2>
<ul>
<li>Reviews must be about a real visit. Do not post anything false, hateful, abusive, sexual, threatening, or that shares someone's private information.</li>
<li>Anyone can report a review in the app. We may hide or remove content that breaks these rules, and suspend accounts that repeatedly do.</li>
</ul>

<h2>Things you must not do</h2>
<ul>
<li>Misuse the queue (for example fake tokens), try to break or overload the service, or access other people's accounts.</li>
<li>Use the app for anything illegal.</li>
</ul>

<h2>Availability and liability</h2>
<p>We work to keep the service running but cannot promise it will always be available or free of errors. To the extent the law allows,
we are not responsible for indirect losses, or for the services a shop provides. Our total liability is limited to the amount you
paid us in the 3 months before the claim.</p>

<h2>Ending your use</h2>
<p>You can delete your account at any time. We may suspend or close accounts that break these terms.</p>

<h2>Law</h2>
<p>These terms are governed by the laws of India, and disputes are subject to the courts of {jurisdiction}.</p>

<h2>Contact</h2>{_contact_block()}"""
    return _page("Terms of Service", body)


@router.get("/refund-policy", response_class=HTMLResponse, include_in_schema=False)
def refund_policy():
    b, p = _business(), _prices()
    body = f"""
<h2>Payments are final</h2>
<p>Subscriptions (₹{p['month']} for 1 month, ₹{p['quarter']} for 3 months), renewals and extensions, and Featured Promotions
(₹{p['promo_per_day']} per day) are final and non-refundable. No refund is given for unused days, for cancelling a subscription
or promotion early, or for closing your shop.</p>

<h2>Cancellation</h2>
<p>You can cancel your subscription in the app (Manage Shop → Subscription). Cancelling closes your shop to new customers
straight away and is not refunded.</p>

<h2>If you were charged but nothing was activated</h2>
<p>The app checks with our payment provider and normally activates a paid plan automatically, even if the app was closed during
payment. If money was taken but your plan or promotion is still not active after a few minutes, write to us with the payment
reference shown by Razorpay, within 7 days. We will activate what you paid for, or, if that is not possible, refund the payment
to the original payment method within 5-7 working days.</p>

<h2>Delivery of the service</h2>
<p>{b} is a digital service. Subscriptions and promotions are activated in the app as soon as the payment is confirmed;
nothing is shipped.</p>

<h2>Contact</h2>{_contact_block()}"""
    return _page("Refund & Cancellation Policy", body)


@router.get("/contact", response_class=HTMLResponse, include_in_schema=False)
def contact():
    body = f"""<div class="card"><p>Questions, problems with a payment, or a complaint? Contact {_business()}:</p>
{_contact_block()}<p class="muted">We usually reply within 2 working days.</p></div>"""
    return _page("Contact Us", body)


@router.get("/delete-account", response_class=HTMLResponse, include_in_schema=False)
def delete_account():
    b = _business()
    email = _e(settings.SUPPORT_EMAIL)
    body = f"""
<h2>Delete it in the app (fastest)</h2>
<ol><li>Open the {b} app and sign in.</li><li>Go to <b>Profile</b>.</li><li>Tap <b>Delete Account</b> and confirm.</li></ol>
<p>Your account is deleted immediately.</p>

<h2>Can't use the app?</h2>
<p>Email <a href="mailto:{email}?subject=Delete%20my%20account">{email}</a> from the email address of your account, with the subject
"Delete my account". We will delete it within 7 days and confirm by email.</p>

<h2>What is deleted</h2>
<p>Your profile (name, email, mobile number, city and state), your shop and its photos, services, staff, subscriptions and promotions,
your queue history, reviews and notifications.</p>

<h2>What is kept</h2>
<p>A scrambled code made from your email and mobile number, so the free trial cannot be claimed again. It cannot be turned back into
your details. Payment records are kept by our payment provider, Razorpay, as the law requires.</p>"""
    return _page("Delete your account", body)
