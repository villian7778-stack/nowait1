# NOWAITT — Production launch guide

Everything you need to do **outside the code** to launch: Supabase, the server, Razorpay live payments,
Google Cloud and the Google Play Console. The code itself is ready; follow these steps in order.

---

## 0. Decide this first — Google Play's payments rule (can block approval)

Shop owners pay **inside the Android app** (Razorpay) for subscriptions and Featured Promotions.
Google Play's *Payments* policy generally requires **Google Play Billing** for purchases of digital
features inside an app. Using only Razorpay for these is the most likely reason the app could be
**rejected or removed**. Customers use the app for free, so they are not affected.

Your options — check the current rules in Play Console Help ("Payments policy", and the
"alternative / user choice billing" programme for India) before you pay for anything:

| Option | What it means | Code change needed |
|---|---|---|
| **A. Google Play Billing** | Owners on Android pay through Google; Google takes a service fee. | New: Play Billing purchase flow + server-side receipt check |
| **B. User choice billing** (if available to you in India) | Offer Google Play Billing *and* Razorpay side by side; reduced Google fee. | New: Play Billing flow + choice screen; keep Razorpay |
| **C. Sell outside the app** | Owners subscribe on your website; the Android app only *uses* the plan and shows no prices, buy buttons or links to pay. | Hide the Android pay screens; add a small web checkout page |

Tell your developer which option you choose — the rest of this guide applies to all three.

---

## 1. What the code already does (no action needed)

- Payments: real prices charged by the server (₹49 / 1 month, ₹130 / 3 months, ₹10 per day promotions);
  signature checks, replay protection, recovery of paid-but-not-activated orders, Razorpay webhook,
  per-owner rate limits, and a lock that refuses live keys until you turn it on.
- 3-month free trial, once per email / mobile number.
- Public policy pages served by your backend (Play and Razorpay need these):
  `/legal/privacy`, `/legal/terms`, `/legal/refund-policy`, `/legal/contact`, `/legal/delete-account`.
- In-app account deletion (Profile → Delete Account) and a deletion web page.
- Reporting of abusive reviews (Play's user-content rule): auto-hidden after 3 reports; moderate in the
  admin panel → **Reported Reviews**.
- Database locked so only your server can read/write it; the SQL also creates the photo bucket.
- A release build refuses to start if it was built without the production server address.

---

## 2. What to buy / sign up for (in this order)

1. **A domain** (recommended), e.g. `nowaitt.in`. Gives you `https://api.nowaitt.in` for the server and
   stable policy-page addresses. Razorpay and Google both prefer a real domain.
2. **Supabase Pro** — projects on the free plan pause after a week without use, which breaks the app.
3. **A server** for the backend (Render paid plan is simplest — the project already deploys there).
4. **Razorpay account activation** (KYC) — free, but takes a few days; start early.
5. **Google Play developer account** (one-time fee). A *personal* account must run a **closed test with
   at least 12 testers for 14 days** before you can publish; an *organisation* account (needs a
   D-U-N-S number) does not.

---

## 3. Supabase (production project)

1. Create a **new** project (region: **Mumbai / ap-south-1**). Don't reuse the test project.
2. **SQL Editor** → paste all of `nowait_backend/sql/final_consolidated.sql` → **Run**. This creates every
   table, the queue functions, the security lock-down and the `shop-images` photo bucket.
3. **Authentication → Providers**
   - Email: keep enabled. Decide whether users must confirm their email (the app handles both).
   - Google: enable, paste the Google OAuth client ID/secret (see section 6).
4. **Authentication → URL Configuration** → add Redirect URL: `io.nowait.app://auth-callback`.
5. **Authentication → SMTP**: connect a real email sender (e.g. Brevo, Resend, ZeptoMail). Supabase's
   built-in email is limited to a few emails per hour — password-reset emails would stop working.
6. **Project Settings → API**: note the **URL**, **anon key** (goes in the app), **service_role key**
   and **JWT secret** (go on the server only).
7. **Storage**: check the `shop-images` bucket exists and is **Public**.

---

## 4. Server (backend)

**Render (simplest):** New Web Service → connect the GitHub repo → Root directory `nowait_backend` →
it uses the `Dockerfile`. Pick a paid instance (free instances sleep). Health check path: `/health`.
Add your domain (e.g. `api.nowaitt.in`) under *Custom Domains* — HTTPS is automatic.

**Own server (VPS):** run the Docker image behind Caddy or nginx with HTTPS, and set
`FORWARDED_ALLOW_IPS=127.0.0.1` (the proxy's address) so users can't fake their IP. Set `ENVIRONMENT=production`.

**Environment variables** (full list with notes in `nowait_backend/.env.example`):

| Variable | Value |
|---|---|
| `SUPABASE_URL`, `SUPABASE_ANON_KEY` | from the new Supabase project |
| `SUPABASE_SERVICE_KEY`, `SUPABASE_JWT_SECRET` | from Supabase — **secret** |
| `ENVIRONMENT` | `production` (hides `/docs`) |
| `ADMIN_USERNAME`, `ADMIN_PASSWORD` | choose a long random password |
| `GOOGLE_MAP_KEY` | your restricted Maps key (section 6) |
| `RAZORPAY_KEY_ID`, `RAZORPAY_KEY_SECRET` | **live** keys (section 5) |
| `RAZORPAY_ALLOW_LIVE` | `true` (only on the server that takes real payments) |
| `RAZORPAY_WEBHOOK_SECRET` | the secret you type in Razorpay's **live** webhook |
| `TRIAL_HASH_KEY` | new long random value; save it forever, never change it |
| `LEGAL_BUSINESS_NAME`, `SUPPORT_EMAIL`, `SUPPORT_PHONE`, `LEGAL_ADDRESS`, `LEGAL_JURISDICTION` | shown on the policy pages; Razorpay checks name + address |
| `CLOUDFLARE_ORIGIN_SECRET` | only once Cloudflare is set up (section 4b) — **secret** |
| `APP_MIN_BUILD_ANDROID`, `APP_MIN_BUILD_IOS` | `0` (off) — raise only to force an update (section 10) |
| `APP_STORE_URL_IOS` | your App Store link, once the iPhone app is published |

**After deploying, open:** `/health` (should say healthy), `/legal/privacy` (should show your
business name), and `/docs` (should be *Not Found* in production).

### 4b. Cloudflare in front of the server (free plan)

Cloudflare blocks floods and bad traffic before they reach the server. Needs your own domain
(e.g. bought on Hostinger — you keep it there, only its DNS moves to Cloudflare). Works with Render's free plan.

1. **Cloudflare account** — cloudflare.com → sign up → *Add a domain* → enter `nowaitt.in` → **Free** plan.
2. **Check the imported DNS records** — if the domain has Hostinger email or a website, make sure its
   MX / A / CNAME records are in the list, or they stop working.
3. **Hostinger → Domains → your domain → Nameservers → Change nameservers** → paste the 2 Cloudflare
   nameservers. Wait until Cloudflare emails "your domain is active" (minutes to a few hours).
4. **Render → your service → Settings → Custom Domains → Add** `api.nowaitt.in`. Render shows a target
   like `your-service.onrender.com`.
5. **Cloudflare → DNS → Add record:** Type `CNAME`, Name `api`, Target `your-service.onrender.com`,
   Proxy **off (grey cloud, "DNS only")**. Back in Render press *Verify* and wait for the certificate.
6. **Cloudflare → the record → turn Proxy on (orange cloud).** Then **SSL/TLS → Overview → Full (strict)**.
   Check `https://api.nowaitt.in/health` says healthy.
7. **Lock the back door** (so nobody can skip Cloudflare by using the `onrender.com` address):
   - make a long random value: `python -c "import secrets; print(secrets.token_urlsafe(32))"`
   - Cloudflare → **Rules → Transform Rules → Modify Request Header → Create rule**: name `origin secret`,
     *Custom filter* Hostname equals `api.nowaitt.in`, then **Set static** header `X-Origin-Secret` = that value → Deploy.
   - Render → Environment → add `CLOUDFLARE_ORIGIN_SECRET` = the same value → save (it redeploys).
   - Check: `https://api.nowaitt.in/health` and `https://api.nowaitt.in/` work;
     `https://your-service.onrender.com/` now says `Forbidden`.
   With this set, rate limits also use Cloudflare's real visitor IP (it cannot be faked).
8. **Move everything to the new address** (the old `onrender.com` address is refused after step 7):
   - app: `BASE_URL=https://api.nowaitt.in` in `nowait_app/release.env` → rebuild and upload the app;
   - Razorpay → Settings → Webhooks → edit the URL to `https://api.nowaitt.in/payments/webhook`;
   - Play Console / Razorpay website field: policy links `https://api.nowaitt.in/legal/...`;
   - admin panel: `https://api.nowaitt.in/nowaitt_778admin`.
   If people already use an app build with the old address, do step 7 only after they have updated.
9. **Don't turn on** *Bot Fight Mode* or *I'm Under Attack* for `api.` — they show a browser challenge
   page that the app and Razorpay's webhook can't pass. The default free protection is enough.

Render free plan note: the server sleeps after ~15 minutes without traffic and the first request then
takes up to a minute (Razorpay retries webhooks, and the app reconciles payments, so nothing is lost —
it is just slow). A paid Render instance removes this.

---

## 5. Razorpay — going live

1. Dashboard → **Activate account**: business details, PAN, bank account. For "website / app", give your
   domain or the Play listing. Policy links to give them:
   `https://api.nowaitt.in/legal/terms`, `/legal/privacy`, `/legal/refund-policy`, `/legal/contact`.
2. Switch the dashboard to **Live mode** → *Account & Settings → API Keys* → **Generate Live Key**.
   Copy the secret immediately (shown once) → put both on the server, and set `RAZORPAY_ALLOW_LIVE=true`.
3. Live mode → *Settings → Webhooks* → **Add New Webhook**
   - URL: `https://api.nowaitt.in/payments/webhook`
   - Secret: a new random value → also set as `RAZORPAY_WEBHOOK_SECRET` on the server
   - Events: `payment.captured`, `order.paid`, `payment.failed`
4. Enable the payment methods you want (UPI, cards, netbanking).
5. **Test with real money once**: pay ₹49 for a 1-month plan from a test shop, check it activates, then
   refund yourself from the Razorpay dashboard.
6. Ask an accountant whether your prices include GST and whether you must issue invoices.

---

## 6. Google Cloud

- **Maps key** (`GOOGLE_MAP_KEY`): *APIs & Services → Credentials* → restrict the key to
  **Geocoding API** and **Places API**. If your server has a fixed IP, also restrict it to that IP.
- **Google sign-in**: *OAuth consent screen* → app name, support email, logo, **privacy policy URL**
  (`/legal/privacy`), authorised domain (your domain) → **Publish app** (move it out of "Testing").
  Create an OAuth client of type *Web application* with the redirect URL Supabase shows you
  (Authentication → Providers → Google) and paste its ID/secret into Supabase.

---

## 7. Build the Android app for Play

One-time setup (keep these files **out of git** — they already are ignored):

1. Create the upload key (keep the file and passwords forever — losing them means you can never update the app):
   ```powershell
   keytool -genkey -v -keystore C:\keys\nowait-upload.jks -keyalg RSA -keysize 2048 -validity 10000 -alias upload
   ```
2. Copy `nowait_app/android/key.properties.example` → `nowait_app/android/key.properties`, fill in the passwords and path.
3. Copy `nowait_app/release.env.example` → `nowait_app/release.env`, fill in your server address and Supabase URL + anon key.

Every release:

```powershell
cd nowait_app
.\build_release.ps1        # -> build\app\outputs\bundle\release\app-release.aab  (upload to Play)
.\build_release.ps1 -Apk   # also builds an APK to try on your phone first
```

Before each new upload, raise the version in `nowait_app/pubspec.yaml` (e.g. `1.0.0+1` → `1.0.1+2`;
the number after `+` must always go up).

---

## 8. Google Play Console

**Create the app** (free app; say whether it contains in-app purchases according to your choice in section 0).

**Store listing:** app name (NOWAITT), short and full description, 512×512 icon, 1024×500 feature
graphic, at least 2 phone screenshots.

**App content** (left menu → *Policy → App content*):

| Item | What to enter |
|---|---|
| Privacy policy | `https://api.nowaitt.in/legal/privacy` |
| App access | "Some functionality is restricted" → give reviewers one **customer** and one **shop owner** login on the production server |
| Ads | No ads |
| Content rating | Fill in the questionnaire (no violence, user reviews are visible → answer "users can interact / share content": yes, with reporting) |
| Target audience | 13+ (or 18+); not designed for children |
| Data safety | see table below |
| Account deletion | In-app: yes. Web link: `https://api.nowaitt.in/legal/delete-account` |
| Health apps | The app manages queues for clinics but has no health features — answer accordingly |
| Financial features / Government / News | None |

**Data safety answers** (what the app actually does):

| Data type | Collected | Shared | Required? | Purpose |
|---|---|---|---|---|
| Name, Email address, Phone number | Yes | No¹ | Required | Account management, App functionality |
| Approximate & precise location | Yes | No | Optional | App functionality (pick shop location / nearby shops) |
| Photos (shop photos by owners) | Yes | No | Optional | App functionality |
| Other user-generated content (reviews) | Yes | No | Optional | App functionality |
| App activity: app interactions (queue joins, visit history) | Yes | No | Required | App functionality, Analytics (owner's own stats) |
| Purchase history (owner payments) | Yes | No | Optional | App functionality |
| Financial info: payment info | Collected by the Razorpay SDK | No | Optional | Payments, Fraud prevention |
| Device or other IDs | Collected by the Razorpay SDK² | No | Optional | Fraud prevention |

Data is **encrypted in transit**; users **can request deletion**.
¹ Service providers (hosting, Supabase, Razorpay, Google) don't count as "sharing" in Play's definition.
² Check Razorpay's own Play data-safety guidance for its SDK and match it.

**Testing → release:** Internal testing (you) → Closed testing (≥12 testers for 14 days if your account
is personal) → Production. Read the *Pre-launch report* Play generates for crashes.

---

## 9. Final checklist before going live

- [ ] Section 0 decision made and implemented
- [ ] **Rotate every secret** that was ever shared in chat or email (Supabase service key + JWT secret,
      Razorpay keys, Google Maps key, webhook secret) — create new ones for production
- [ ] Production `.env` / server variables set from section 4; `RAZORPAY_ALLOW_LIVE=true` only there
- [ ] Policy pages show your real business name, address and phone
- [ ] Supabase: SQL run, Google provider + redirect URL set, SMTP connected, bucket public
- [ ] Release build made with `build_release.ps1` and tried on a real phone:
      register (email and Google) · create shop · free trial · pay ₹49 (real) · customer joins queue ·
      owner Next/Skip · customer leaves a review · report a review · delete an account
- [ ] Unused `DEMO_*` lines removed from `.env`

## 10. After launch

- **Logs** (server): search `WEBHOOK`, `CHECKOUT FAILED`, `RECONCILED`, `LEDGER`, `SIGNATURE` for payments.
- **Moderation**: admin panel (`/nowaitt_778admin`) → *Reported Reviews* — hide, restore or delete.
- **Backups**: Supabase Pro takes daily backups; download one occasionally.
- **Scaling later**: the server runs one worker on purpose (admin logins, rate limits and the
  "one at a time" locks that stop double payments / double shops are kept in memory). If you ever add
  more workers or servers, those need a shared store (e.g. Redis) first.

### Forcing everyone onto a new app version

The app sends its **build number** (the number after `+` in `nowait_app/pubspec.yaml`, e.g.
`version: 1.0.1+2` → build **2**) with every request. A build older than the minimum you set sees only
an **"Update required"** screen whose button opens the Play Store (Android) or App Store (iPhone).

1. Raise the version in `pubspec.yaml` for every release, e.g. `1.0.0+1` → `1.0.1+2` (Play needs a higher
   build number for each upload anyway). Build and upload it to Play.
2. **Wait until the new version is live on the Play Store** (review can take hours or days).
3. Render → Environment → `APP_MIN_BUILD_ANDROID` = the new build number (e.g. `2`) → save.
   Every older app shows the update screen immediately, even if it was left open.
4. iPhone (once on the App Store): same with `APP_MIN_BUILD_IOS`, and set `APP_STORE_URL_IOS`
   (e.g. `https://apps.apple.com/app/id1234567890`).

Never set the minimum higher than the build that is live on the store — nobody could use the app.
Made a mistake? Set it back (or to `0` = off) and the app unlocks again the next time it is opened.
Payments already in progress always finish, even for an old build.
