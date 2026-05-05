# NOWAIT — Comprehensive Testing Checklist

> Generated from full codebase analysis (Flutter app + FastAPI backend).
> Every test case maps to real code paths, validations, and known edge cases.

---

## 1. App Startup & Initialization

- [ ] Cold start with no stored session — app shows `LoginScreen` — expected: no crash, clean login UI
- [ ] Cold start with valid stored tokens — app navigates to `HomeScreen` (customer) or `OwnerDashboardScreen` (owner) without re-authenticating — expected: correct role-based routing
- [ ] Cold start with valid tokens but missing profile (`profileRequired = true`) — app routes to `CreateAccountScreen` in `isCompletingProfile` mode — expected: no dashboard access until profile completed
- [ ] Cold start with expired access token but valid refresh token — `ApiClient` auto-refreshes on first API call — expected: seamless session restoration
- [ ] Cold start with both tokens expired — app logs out and shows `LoginScreen` — expected: all SharedPreferences cleared
- [ ] `AuthService` and `LocaleService` are loaded in parallel on startup (`Future.wait`) — expected: app opens without sequential delay
- [ ] Saved locale (`app_language`) is applied before first frame — expected: UI renders in correct language on first paint
- [ ] Portrait-only lock (`SystemChrome.setPreferredOrientations`) — expected: rotating device does not change layout
- [ ] `BASE_URL` dart-define missing — `AppConfig.baseUrl` falls back to `http://localhost:8000` — expected: no crash, clear error when API called

---

## 2. Authentication — Login Screen

### Happy Path
- [ ] Enter 10-digit phone number — Send OTP button becomes active — expected: green checkmark appears, button enabled
- [ ] Enter 11-digit phone number — Send OTP button becomes active — expected: same behavior as 10-digit
- [ ] Tap Send OTP with valid 10-digit phone — navigates to `OtpVerificationScreen` — expected: `isNewUser: false` passed
- [ ] Tap Send OTP with valid 11-digit phone — navigates to `OtpVerificationScreen` — expected: same flow

### Validation
- [ ] Enter 9 digits — Send OTP button stays disabled — expected: button not tappable
- [ ] Enter 12 or more digits — input formatter blocks 12th digit — expected: field capped at 11 chars
- [ ] Enter letters or special chars — `FilteringTextInputFormatter.digitsOnly` blocks them — expected: only digits accepted
- [ ] Leave phone field empty — button stays disabled — expected: no API call on tap
- [ ] Rapid-tap Send OTP while loading — loading spinner replaces button — expected: no duplicate OTP requests

### Error States
- [ ] Backend returns 429 (rate limit exceeded) — SnackBar shows error message — expected: no crash
- [ ] Backend returns 400 (invalid phone) — SnackBar shows `ApiException.message` — expected: field remains editable
- [ ] Network timeout (>30s) — generic error SnackBar — expected: button becomes active again after error
- [ ] No internet — `SocketException` caught — expected: SnackBar with error, not crash

### Navigation
- [ ] Tap "Create Account" — navigates to `CreateAccountScreen` — expected: back button returns to `LoginScreen`
- [ ] Country prefix (+91 / IN badge) is non-tappable — expected: no crash on accidental tap

---

## 3. Authentication — OTP Verification Screen

### Happy Path
- [ ] Enter 6-digit OTP — Verify button activates — expected: all 6 boxes filled, button enabled
- [ ] Digit entry auto-focuses next box — expected: cursor moves right automatically
- [ ] Backspace in middle box clears current and focuses previous — expected: smooth backward navigation
- [ ] In demo mode, enter `123456` — verifies successfully — expected: routes to home or profile completion
- [ ] `isNewUser: false` + existing profile — routes to `HomeScreen` or `OwnerDashboardScreen` — expected: correct role routing
- [ ] `isNewUser: true` — after OTP verify, routes to `CreateAccountScreen` in `isCompletingProfile: true` mode — expected: profile form shown

### Validation
- [ ] Enter non-digit character — `FilteringTextInputFormatter.digitsOnly` blocks it — expected: only digits accepted per box
- [ ] Enter wrong OTP (non-123456 in demo mode) — SnackBar shows error — expected: boxes reset or remain editable
- [ ] Partial OTP (< 6 digits) — Verify button disabled — expected: no API call

### Resend OTP
- [ ] Resend timer counts down 30 seconds after screen opens — expected: timer UI visible, resend disabled
- [ ] Resend button enabled after 30 seconds — expected: tap triggers new OTP request
- [ ] Resend in demo mode — instant, no SMS — expected: new OTP is still `123456`
- [ ] Resend while loading — expected: no duplicate requests

### Error States
- [ ] Network failure during OTP verify — SnackBar with error — expected: OTP boxes remain filled and editable
- [ ] Backend returns 400 (invalid OTP) — SnackBar with error — expected: boxes editable for retry

---

## 4. Authentication — Create Account / Complete Profile

### Happy Path (New User Registration)
- [ ] Fill Full Name (letters only), 10-digit phone, address, state, city, role, agree to terms — Continue button activates — expected: all validations pass
- [ ] Fill Full Name (letters only), 11-digit phone — Continue button activates — expected: 11 digits accepted
- [ ] Select "Customer" role — tap Continue — sends OTP to phone — expected: navigates to `OtpVerificationScreen` with `isNewUser: true`
- [ ] Select "Shop Owner" role — tap Continue — sends OTP — expected: same OTP flow
- [ ] State selected first, then city picker enabled — expected: city dropdown shows cities for chosen state
- [ ] Change state — city resets to empty — expected: previously chosen city cleared

### Happy Path (Complete Profile Mode)
- [ ] `isCompletingProfile: true` — phone field hidden — expected: no phone input shown
- [ ] Fill name, state, city, role, agree to terms in complete-profile mode — Continue creates profile immediately — expected: routes to dashboard without OTP
- [ ] Owner completing profile → routes to `OwnerDashboardScreen` — expected: correct role routing
- [ ] Customer completing profile → routes to `HomeScreen` — expected: correct role routing

### Name Validation
- [ ] Enter name with a digit (e.g. "John1") — inline error: "Name cannot contain numbers" — expected: Continue disabled
- [ ] Enter name shorter than 2 characters (e.g. "A") — inline error: "Name must be at least 2 characters" — expected: Continue disabled
- [ ] Enter name with only spaces — treated as empty (`.trim()`) — expected: Continue disabled
- [ ] Enter valid name (letters + spaces + hyphens) like "Mary-Jane" — no error shown — expected: valid
- [ ] Name error clears when digits removed — expected: real-time error clearing
- [ ] Name field shows error only after user starts typing (not on empty state) — expected: no error on blank field

### Phone Validation (Registration Only)
- [ ] Enter exactly 10 digits in phone field — no error — expected: valid
- [ ] Enter exactly 11 digits — no error — expected: valid
- [ ] Enter 9 digits — Continue disabled — expected: insufficient length
- [ ] Attempt to type 12th digit — blocked by formatter — expected: capped at 11

### Other Field Validation
- [ ] Skip state selection — Continue stays disabled — expected: state required
- [ ] Skip city selection (state chosen) — Continue stays disabled — expected: city required
- [ ] Skip role selection — Continue stays disabled — expected: role required
- [ ] Uncheck terms checkbox — Continue stays disabled — expected: terms required
- [ ] Tap "Terms & Privacy Policy" link — terms bottom sheet opens — expected: readable terms content

### Language Selector
- [ ] Tap "Hindi" — UI switches to Hindi strings — expected: all labels update immediately
- [ ] Tap "Marathi" — UI switches to Marathi strings — expected: all labels update
- [ ] Tap "English" — UI reverts to English — expected: language toggle works in both directions
- [ ] Language choice persisted: reopen app — same language — expected: `app_language` in SharedPreferences

### State/City Picker
- [ ] Tap State field — `_SearchPickerSheet` opens — expected: all states listed alphabetically
- [ ] Type in search box — list filters in real time — expected: matching states shown
- [ ] Clear search — full list restored — expected: all states visible
- [ ] Select state with no cities — city picker shows empty or disabled — expected: no crash
- [ ] Tap City before State — city picker disabled — expected: shows "Select state first" hint

### Error States
- [ ] API error during `completeProfile` — SnackBar shows error — expected: form remains editable
- [ ] `sendOtp` fails during registration — SnackBar with error — expected: Continue button active again

---

## 5. Customer — Home Screen

### Shop Listing
- [ ] Home screen loads — featured shops appear at top, all shops in list — expected: data populated, no crash
- [ ] Promoted shops (Featured Promotion) appear at top of list — expected: `isPromoted` flag respected
- [ ] Open-only filter applied by default — closed shops excluded — expected: `open_only=true` in API call
- [ ] Toggle "Show All" — closed shops appear with "Closed" badge — expected: filter state changes
- [ ] Category chip selected — list filters to that category — expected: single category shown
- [ ] Category chip deselected — all shops shown — expected: no category filter applied
- [ ] City filter applied from profile — shows shops in user's city — expected: `city` param in API call
- [ ] City filter changed by user — persisted to SharedPreferences — expected: reopening app uses saved city
- [ ] Shop card shows queue count and "now serving #N" when open — expected: data from enriched shop API
- [ ] Shop card shows subscription-inactive state correctly — expected: "Not accepting queues" indicator
- [ ] Pull-to-refresh — shop list reloads — expected: fresh API data

### Navigation
- [ ] Tap shop card — navigates to `ShopDetailsScreen` — expected: shop ID passed correctly
- [ ] Bottom navigation: Home, Queue, History, Profile tabs — expected: `IndexedStack` switches content
- [ ] Tap Queue tab — shows active queue entries or empty state — expected: `QueueStatusScreen` embedded
- [ ] Tap History tab — shows visit history — expected: `HistoryScreen` loads past visits
- [ ] Tap Profile tab — shows user info and settings — expected: profile data loaded from `AuthService`
- [ ] Tap notification bell — navigates to `NotificationsScreen` — expected: unread count badge visible

### Empty & Loading States
- [ ] No shops in city — empty state with "No shops found" — expected: not a blank white screen
- [ ] Loading spinner shown while fetching — expected: visible indicator
- [ ] API failure on load — error message shown, retry possible — expected: no frozen screen

---

## 6. Customer — Shop Details Screen

### Happy Path
- [ ] Open shop details — name, category, address, opening hours, avg wait shown — expected: all fields populated
- [ ] Image carousel renders — swipe left/right — expected: pagination dots update
- [ ] Single image — no carousel controls — expected: no crash
- [ ] Zero images — placeholder shown — expected: no crash
- [ ] Services list shown — name, price, duration displayed — expected: correct formatting (₹ symbol)
- [ ] Staff list shown — names visible — expected: public staff info only
- [ ] "Open" badge shown for open shop with active subscription — expected: green badge
- [ ] "Closed" badge shown for closed shop — expected: red badge
- [ ] Active scheme/promotion banner visible — expected: scheme title + description shown
- [ ] Queue count and current token displayed — expected: "Now serving #N" visible

### Join Queue
- [ ] Tap "Join Queue" on open shop — `JoinQueueSheet` opens — expected: bottom sheet slides up
- [ ] Select service in sheet — service highlighted — expected: single selection
- [ ] Tap "Join Queue" in sheet — API call made — expected: `TokenScreen` opens with token number
- [ ] Join queue with no service selected — joins with no service_id — expected: allowed (optional)
- [ ] Tap "Join Queue" on closed shop — button disabled or error — expected: user cannot join
- [ ] Tap "Join Queue" when subscription inactive — error shown — expected: queue join blocked
- [ ] Tap "Join Queue" when queue paused — error message from backend — expected: SnackBar shown
- [ ] Tap "Join Queue" when already in queue — 409 error shown — expected: SnackBar shown, no duplicate entry
- [ ] Tap "Join Queue" when queue full (max_size reached) — error shown — expected: QUEUE_FULL message

---

## 7. Customer — Token Screen (Post Join)

- [ ] Token number displayed large and bold — expected: easy to read at a glance
- [ ] Position in queue shown — expected: "Position #N" visible
- [ ] Estimated wait time calculated — `(position - 1) * avg_wait_minutes` — expected: correct arithmetic
- [ ] Countdown timer starts for customer currently being served — expected: counts down from avg_wait_minutes
- [ ] Countdown timer persists app restart — expected: reads from SharedPreferences (`cntdwn_start_`, `cntdwn_dur_`, `cntdwn_token_`)
- [ ] Countdown timer resumes correctly after background — expected: elapsed wall-clock time subtracted
- [ ] Status badge shows "Waiting" initially — expected: `display_status == waiting`
- [ ] Status changes to "Almost There" when position ≤ 3 — expected: real-time update on poll
- [ ] Status changes to "Your Turn" when serving — expected: `status == serving`
- [ ] "I'm Coming" button sends notification — expected: SnackBar confirms, button disabled after tap
- [ ] "I'm Coming" button stays disabled after tap — expected: `_isComing` flag prevents duplicate
- [ ] Cancel button shown while waiting — expected: visible and tappable
- [ ] Cancel confirmation dialog shown — expected: "You will lose your spot" message with Confirm/Cancel options
- [ ] Confirm cancel — entry status set to `cancelled` — expected: screen shows cancelled state
- [ ] Dismiss cancel dialog — no action taken — expected: position unchanged
- [ ] Queue status auto-polls every 10 seconds — expected: `_timer` active while screen in foreground
- [ ] Polling stops when screen disposed — expected: no memory leak from dangling timers

---

## 8. Customer — Queue Status Screen (Queue Tab)

- [ ] Active queue entry shown when customer is in queue — expected: token, shop name, position, status
- [ ] Multiple simultaneous queue entries shown — expected: each entry rendered
- [ ] Empty state when not in any queue — expected: "No active queues" message
- [ ] Completed/cancelled entries removed from active view — expected: only waiting/serving shown
- [ ] Poll resumes on `didChangeAppLifecycleState: resumed` — expected: fresh data on app foregrounding
- [ ] Poll paused on `paused` lifecycle state — expected: no unnecessary API calls in background

---

## 9. Customer — History Screen

- [ ] Past visits loaded — shop name, date, service, token shown — expected: correct `VisitHistory` model data
- [ ] Empty history — "No past visits" state — expected: not blank
- [ ] Visits sorted by date descending — expected: most recent at top
- [ ] Tapping history entry — expected: navigates to shop details or shows info (if implemented)

---

## 10. Customer — Notifications Screen

- [ ] Notifications listed — type icons, messages, timestamps — expected: all notification types render
- [ ] `your_turn` notification shows — "It's your turn!" — expected: correct message
- [ ] `almost_there` notification shows — "Almost there" — expected: correct message
- [ ] `skipped` notification shows — "You were skipped" — expected: correct message
- [ ] `coming` notification shows for owner — customer name visible — expected: correct data
- [ ] Unread notifications highlighted — expected: visual distinction from read
- [ ] Tap notification — marked as read — expected: `PATCH /notifications/{id}/read` called
- [ ] "Mark all read" button — all notifications marked read — expected: unread count drops to 0
- [ ] Notification badge on Home tab icon updates — expected: badge count reflects `unread_count`
- [ ] Empty notifications state — "No notifications" shown — expected: not blank

---

## 11. Owner — Dashboard Screen

- [ ] Dashboard loads with shop info — expected: shop name, status, queue count shown
- [ ] No shop created yet — expected: "Create your shop" CTA shown
- [ ] Shop open toggle visible — expected: current state reflected (open/closed)
- [ ] Toggle shop open → confirmation or immediate — expected: `is_open` updates in backend
- [ ] Queue list shown — waiting customers listed with token, name, service — expected: enriched queue data
- [ ] "Next" button advances queue — marks serving as completed, next waiting becomes serving — expected: queue reordered
- [ ] "Skip" button on customer — expected: customer status set to `skipped`, notification sent
- [ ] Queue grouped by staff when staff exist — expected: `GET /queues/shop/{id}/by-staff` used
- [ ] Pause queue — new joins blocked — expected: `queue_paused = true`, customers see error on join
- [ ] Resume queue — joins allowed again — expected: `queue_paused = false`
- [ ] Refresh queue list — pull-to-refresh or auto-poll — expected: fresh data

---

## 12. Owner — Manage / Edit Shop Screen

### Happy Path
- [ ] Shop name updated — saved correctly — expected: `PUT /shops/{id}` called with new name
- [ ] Category changed — dropdown updates and saves — expected: correct category stored
- [ ] Address updated — saved — expected: address shows on shop card
- [ ] Opening hours updated — saved — expected: hours displayed on shop details
- [ ] Average wait time updated — saved — expected: affects estimated wait calculations for customers
- [ ] State/city picker changes — saves new location — expected: shop appears in new city searches

### Shop Name Validation (Edit)
- [ ] Clear shop name entirely — Save disabled — expected: `_isValid` returns false
- [ ] Enter purely numeric shop name (e.g. "12345") — inline error: "Shop name must contain letters" — expected: Save disabled
- [ ] Enter valid name with numbers (e.g. "Studio 44") — no error — expected: valid, Save enabled
- [ ] Enter 1-character shop name — inline error: "Shop name must be at least 2 characters" — expected: Save disabled

### Services (Edit)
- [ ] Add new service — name, price, duration submitted — expected: `POST /shops/{id}/services` called
- [ ] Delete existing service — removed from list immediately — expected: `DELETE /shops/services/{id}` called
- [ ] Service price accepts decimal (e.g. 249.99) — expected: stored as float
- [ ] Service duration accepts integer only — expected: non-numeric input handled

### Images (Edit)
- [ ] Upload new image — preview added to grid — expected: `POST /shops/{id}/images` on save
- [ ] Remove existing image — removed from grid — expected: `DELETE /shops/{id}/images` called
- [ ] Upload > 10 images total — blocked — expected: "Add" button disabled at limit
- [ ] Upload file > 5 MB — backend returns error — expected: SnackBar with error message
- [ ] Upload invalid MIME type (e.g. .pdf) — backend rejects — expected: error shown

### No-Changes Guard
- [ ] Tap Save with no changes — screen closes without API call — expected: `_hasChanges` check prevents unnecessary PUT

---

## 13. Owner — Create Shop Screen

### Happy Path
- [ ] Fill all required fields (name, category, address, state, city) — Create button activates — expected: all validations pass
- [ ] Add services (at least one) — services submitted with shop — expected: services rows created
- [ ] Set opening hours via time picker — time formatted as "9:00 AM - 8:00 PM" — expected: correct string
- [ ] Add staff by name — chip appears — expected: staff added to list
- [ ] Upload images — grid shows previews — expected: images uploaded after shop creation
- [ ] Submit — shop created, staff added, images uploaded, screen pops — expected: success SnackBar

### Shop Name Validation
- [ ] Enter purely numeric shop name — inline error shown — expected: Create button disabled
- [ ] Enter name with at least one letter (e.g. "Salon 9") — no error — expected: valid
- [ ] Empty shop name — Create button disabled — expected: `_isValid` false

### Staff Name Validation
- [ ] Enter staff name with digit (e.g. "Rahul2") — inline error: "Staff name cannot contain numbers" — expected: Add button disabled
- [ ] Enter valid staff name — no error — expected: chip added on tap

### Service Fields
- [ ] Leave service name empty — service excluded from submission (not sent as empty) — expected: only named services submitted
- [ ] Enter non-numeric price — `double.tryParse` returns 0.0 — expected: price defaults to 0
- [ ] Enter non-numeric duration — `int.tryParse` returns 30 — expected: duration defaults to 30

### Error States
- [ ] Owner already has a shop — backend returns error — expected: SnackBar with "already have a shop" message
- [ ] Partial staff fail (some added, some not found) — SnackBar lists failed names — expected: shop still created
- [ ] API failure during create — SnackBar with error — expected: loading stops, form still editable

---

## 14. Owner — Subscription Screen

- [ ] Subscription status shown — plan name, expiry date, days remaining — expected: correct data displayed
- [ ] No subscription — "Inactive" state shown — expected: subscribe CTA visible
- [ ] Subscribe (Basic, 30 days) — subscription created — expected: `POST /subscriptions/shop/{id}` called
- [ ] Subscribe (Premium, 90 days) — expected: correct plan stored
- [ ] Renew subscription (before expiry) — `expires_at` extended — expected: days remaining increases
- [ ] Cancel subscription — status set to cancelled — expected: shop queue acceptance blocked
- [ ] Subscription expires — shop cannot open or accept queue — expected: `toggle-open` blocked

---

## 15. Owner — Staff Management Screen

- [ ] Staff list loads — names shown — expected: all assigned staff visible
- [ ] Add staff by phone number — finds registered user — expected: staff row created
- [ ] Add staff by phone — user not found — expected: error SnackBar
- [ ] Remove staff member — removed from list — expected: `DELETE /staff/shops/{id}/{user_id}` called
- [ ] Self-register as staff — owner appears in own staff list — expected: `POST /staff/self-register`
- [ ] Staff assignments shown (via `GET /staff/my-assignments`) — expected: correct shops listed

---

## 16. Owner — Promotion / Scheme Screen

- [ ] Active promotions listed — title, description, expiry shown — expected: correct data
- [ ] Create scheme — title + description + valid_until submitted — expected: `POST /promotions/shop/{id}` called
- [ ] Edit existing scheme — updated fields saved — expected: `PUT /promotions/{id}` called
- [ ] Delete promotion — removed from list — expected: `DELETE /promotions/{id}` called
- [ ] Expired promotions excluded from active list — expected: `active_only=true` filter applied
- [ ] Featured Promotion creates `isPromoted` flag — expected: shop appears boosted in customer search
- [ ] Scheme visible on customer shop detail page — expected: scheme banner shown

---

## 17. Owner — Analytics Screen

- [ ] Summary stats load for "Today" — total joined, served, cancelled, skipped shown — expected: correct counts
- [ ] Switch to "Week" period — stats update — expected: `period=week` in API call
- [ ] Switch to "Month" period — stats update — expected: `period=month` in API call
- [ ] Cancel rate and skip rate shown as percentages — expected: `(cancelled / total) * 100`
- [ ] Peak hour shown — expected: hour with most joins in period
- [ ] Hourly chart loads — bars for 7-day window — expected: `days=7` in API call
- [ ] Staff performance table loads — individual metrics per staff — expected: correct per-staff data
- [ ] Zero data (no queue activity) — stats show 0, no divide-by-zero crash — expected: graceful zero state

---

## 18. API Client & Token Lifecycle

- [ ] Every request includes `Authorization: Bearer {access_token}` header — expected: no unauthenticated requests to protected endpoints
- [ ] `GET /` and `GET /health` called without auth header — expected: always 200
- [ ] 401 response triggers token refresh (`POST /auth/refresh`) — expected: original request retried with new token
- [ ] Refresh token rotated by backend — new refresh token stored — expected: old refresh token invalidated
- [ ] Concurrent 401 responses — only one refresh executed (`_isRefreshing` flag) — expected: other requests wait and retry with new token
- [ ] Refresh fails (refresh token expired) — `logout()` called — expected: all tokens cleared, user navigated to login
- [ ] `ApiException` raised on non-2xx — contains `statusCode` and `message` — expected: SnackBar shows human-readable message
- [ ] 422 Validation error — `detail` array parsed, first error message shown — expected: readable message not raw JSON
- [ ] Multipart upload (image) — `Content-Type: multipart/form-data` set correctly — expected: no 400 from missing content-type
- [ ] Request timeout after 30 seconds — `TimeoutException` caught — expected: SnackBar error, not crash

---

## 19. Auth & Session Handling

- [ ] Tokens stored in `SharedPreferences` (`access_token`, `refresh_token`, `user_profile`) — expected: persists across app restarts
- [ ] `user_profile` stored as JSON string — `UserModel.fromJson` parses on load — expected: no crash on malformed JSON
- [ ] `pendingPhone`, `pendingName`, `pendingState`, `pendingCity`, `pendingRole` used during OTP flow — expected: available in `OtpVerificationScreen` after registration
- [ ] `logout()` clears all keys including pending fields — expected: no stale data after logout
- [ ] `isOwner` derived from `userProfile.role == 'owner'` — expected: correct role-based navigation
- [ ] Role change (customer ↔ owner) via `completeProfile` — expected: profile updated, role reflected immediately
- [ ] JWT decoded in backend — HS256 tried first, then JWKS (RS256/ES256) — expected: no 401 from wrong algorithm
- [ ] JWT `audience` must be `authenticated` — expected: other audiences rejected with 401
- [ ] `get_current_owner` dependency — non-owner gets 403 — expected: owner-only routes protected
- [ ] `get_token_claims` used for `complete-profile` — phone extracted from JWT `phone` claim — expected: correct phone stored in profile

---

## 20. API Failures & Loading States

- [ ] `isLoading` set to `true` before API call, `false` in `finally` block — expected: spinner shown during all async operations
- [ ] SnackBar shown on every `ApiException` — expected: user always informed of failure
- [ ] SnackBar shown on unexpected exception (`catch (_)`) — expected: generic "Something went wrong" shown
- [ ] Loading button replaced by spinner (not just disabled) — expected: clear visual feedback during submit
- [ ] Screen remains mounted check (`if (!mounted) return`) after every `await` — expected: no `setState on disposed widget` crash
- [ ] 404 on shop not found — expected: SnackBar error, navigation back
- [ ] 403 on unauthorized action — expected: SnackBar error message
- [ ] 409 on duplicate queue join — expected: "Already in queue" error shown
- [ ] 400 on closed shop join — expected: "Shop is closed" message shown
- [ ] 400 on paused queue join — expected: "Queue is paused" message shown
- [ ] 400 on no subscription join — expected: "Subscription required" message shown
- [ ] 400 on full queue join — expected: "Queue is full" message shown

---

## 21. Navigation & Screen Stack

- [ ] Back button on OTP screen returns to Login — expected: `Navigator.pop`
- [ ] Back button on CreateAccount (new user) returns to Login — expected: back button visible
- [ ] `CreateAccountScreen` in `isCompletingProfile` mode has no back button — expected: user cannot skip profile completion
- [ ] After successful login (existing user) — `pushAndRemoveUntil` clears navigation stack — expected: back button on dashboard not present
- [ ] After profile completion — `pushAndRemoveUntil` clears stack — expected: no way back to login/OTP
- [ ] After cancel queue — screen pops or updates in place — expected: no stale queue data
- [ ] `EditShopScreen` pops with updated `ShopModel` — expected: `ManageShopScreen` refreshes with returned model
- [ ] Create shop success — `Navigator.pop(context)` — expected: dashboard reloads shop data
- [ ] Deep navigation: Home → ShopDetails → JoinQueue → Token → Cancel → back to Home — expected: full stack traversal without crash
- [ ] Bottom nav tabs preserve scroll position — expected: `IndexedStack` not rebuilding on tab switch

---

## 22. Offline / No Internet Behavior

- [ ] Launch app offline with cached tokens — expected: `HomeScreen` or `OwnerDashboardScreen` shown, but data fetch fails gracefully
- [ ] Tap any API-dependent button while offline — expected: SnackBar with connection error, no crash
- [ ] OTP send while offline — expected: SnackBar error, not a spinner that never resolves
- [ ] Queue status poll while offline — expected: timer continues, poll fails silently or with SnackBar
- [ ] Image upload while offline — expected: error SnackBar, no stuck loading state
- [ ] App comes back online — expected: next user interaction or poll attempt succeeds
- [ ] No fallback to mock/cached shop data — API failures show error, not stale data — expected: consistent with `no_mock_fallback` principle

---

## 23. Performance Checkpoints

- [ ] Shop list with 50+ shops — expected: `ListView.builder` renders lazily, no jank
- [ ] Image grid in shop details (up to 10 images) — expected: `GridView.builder` lazy-loads, no memory spike
- [ ] Image carousel — expected: `PageView` loads only adjacent pages
- [ ] OTP boxes — `TextEditingController` per box (6 total) — expected: no excessive rebuilds
- [ ] `LocaleService.notifyListeners()` triggers full tree rebuild — expected: rebuilds only listening widgets
- [ ] `initState` loads data asynchronously — expected: no blocking the UI thread
- [ ] `didChangeAppLifecycleState` polling resumes — expected: no duplicate timers created
- [ ] `dispose()` cancels timers and removes listeners — expected: no memory leaks after screen close
- [ ] `ShopService.getShops()` batch queries (subscriptions + promotions + queue stats) — expected: single page load < 3s
- [ ] Analytics hourly query for 30 days — expected: response < 5s
- [ ] State/city JSON file loaded from assets once — expected: `_stateCityData` cached, not re-read on every open
- [ ] Concurrent image uploads (multiple picks) — expected: sequential upload, no race condition

---

## 24. Platform-Specific Behavior

### Android
- [ ] Android emulator connects to backend at `10.0.2.2:8000` — expected: `BASE_URL` overridden at launch
- [ ] Android back gesture (swipe from edge) — expected: same as hardware back button
- [ ] Image picker on Android — file picker opens, multi-select works — expected: up to 10 images selectable
- [ ] Status bar color matches app gradient — expected: `SystemChrome.setSystemUIOverlayStyle` applied
- [ ] Keyboard avoidance in forms — expected: `SingleChildScrollView` scrolls fields above keyboard
- [ ] Bottom nav insets with gesture bar — expected: no content hidden behind navigation bar

### iOS
- [ ] iOS swipe-back gesture — expected: `CupertinoPageRoute` or `Navigator` pop compatible
- [ ] Image picker on iOS — photo library permission prompt — expected: graceful denial handling
- [ ] Safe area insets (notch) — expected: `SafeArea` wraps all screens
- [ ] Font rendering — Plus Jakarta Sans via `google_fonts` — expected: matches design system

### Web (Chrome)
- [ ] `flutter run -d chrome` — app loads — expected: no platform-specific crash
- [ ] `kIsWeb` flag used for image display — `Image.network` instead of `Image.file` — expected: images shown in web mode
- [ ] `ImagePicker` on web — expected: file upload dialog opens

---

## 25. Locale / Internationalization

- [ ] All user-facing strings go through `LocaleService.instance.tr('key')` — expected: no hardcoded English strings
- [ ] Switching language mid-session — all screens update without reload — expected: `ChangeNotifier` → `setState` chain
- [ ] Missing translation key — expected: key itself shown (no crash)
- [ ] Placeholder substitution — `_l.tr('key', params: {'name': 'John'})` replaces `{name}` — expected: correct substitution
- [ ] Hindi strings display correctly — expected: Devanagari script renders without garbling
- [ ] Marathi strings display correctly — expected: Devanagari script renders
- [ ] Language persisted — app restart uses saved language — expected: `shared_preferences` key `app_language`
- [ ] Language selector on CreateAccountScreen — changes locale before account created — expected: form labels update in real-time

---

## 26. Data Model Edge Cases

- [ ] `ShopModel.canAcceptQueue` — `isOpen && hasActiveSubscription && !queuePaused` — expected: all three conditions required
- [ ] `SchemeModel` parsed from `active_promotions` where `title != 'Featured Promotion'` — expected: featured excluded from schemes list
- [ ] Shop with `isPromoted = true` — has at least one promotion titled "Featured Promotion" — expected: promoted badge shown
- [ ] `QueueEntry.displayStatus` — computed from `status` + `position` combination — expected: correct status for each state
- [ ] `VisitHistory` model — service name, shop name, date, token — expected: all fields nullable-safe
- [ ] `StaffMember` with no profile (name-only staff) — expected: display_name falls back gracefully
- [ ] `AnalyticsSummary` with zero `total_joined` — cancel_rate and skip_rate = 0% — expected: no divide-by-zero
- [ ] `NotificationModel` with unknown `type` — expected: generic icon shown, no crash
- [ ] `UserModel` with missing fields from incomplete profile — expected: null-safe field access throughout
- [ ] Queue token numbers — monotonically increasing, never reset — expected: token N+1 always > N

---

## 27. Backend-Specific Validation

- [ ] `POST /auth/send-otp` with non-E.164 phone — 422 returned — expected: Flutter shows validation error
- [ ] `POST /auth/complete-profile` called twice for same user — second call fails — expected: 409 or 400 from backend
- [ ] `POST /shops` when owner already has shop — 400 returned — expected: "already have a shop" in SnackBar
- [ ] `POST /queues/join` — RPC `join_queue_v2` acquires row lock on shop — concurrent joins serialized — expected: no double-token issue
- [ ] Token numbers never reset — `max(token_number)` per shop increments — expected: tokens unique per shop
- [ ] `execute_one(query)` wrapper — handles `APIError code=204` as `None` — expected: no crash on empty single-row result
- [ ] `DEMO_MODE=True` — OTP bypassed, password-based sign-in used — expected: works without Twilio config
- [ ] `DEMO_MODE=False` — requires real Supabase OTP (Twilio) — expected: demo OTP `123456` rejected
- [ ] Image storage bucket public — returned URL accessible without auth — expected: `Image.network(url)` works
- [ ] Image filename — UUID-based — expected: no filename collision across shops
- [ ] RLS policies — service role bypasses RLS — expected: backend can read/write all rows
- [ ] RLS policies — anon key cannot read profiles directly — expected: customer cannot access other profiles

---

## 28. Known Risk Areas (Code-Identified)

- [ ] `_isRefreshing` flag in `ApiClient` — if refresh request itself returns 401, flag may stick `true` — expected: flag reset in `finally` block
- [ ] Countdown timer key collision — `cntdwn_token_{shop_id}` — if user is in queues at two shops simultaneously, keys are shop-scoped — expected: correct countdown per shop
- [ ] `pendingPhone` in `AuthService` — not cleared if user navigates back from OTP screen before verifying — expected: stale pending phone overwritten on next `sendOtp`
- [ ] `_stateCityData` loaded async — if user opens state picker before JSON loads, empty list shown — expected: loading indicator or graceful empty state
- [ ] `double.tryParse(price)` returns `null` → defaults to `0.0` — user entering letters in price field — expected: service created with price 0, not crash
- [ ] `int.tryParse(duration)` returns `null` → defaults to `30` — expected: fallback used silently
- [ ] Staff added by name only (no phone) — no user account created — expected: staff display works, queue assignment may not work
- [ ] `_hasChanges` in `EditShopScreen` compares strings — opening hours default value mismatch if backend stores different format — expected: no false "no changes" on first save
- [ ] `_staffInputController` listener not added — staff validation only on `setState` from `onChanged` — expected: Add button correctly reflects error state
- [ ] Image upload failure (catch `_`) swallowed silently — expected: partial upload failure does not prevent shop creation but may leave missing images
- [ ] Analytics division by zero — `total_joined == 0` — cancel_rate and skip_rate computed server-side — expected: backend guards against divide-by-zero
- [ ] `NotificationsScreen` polls or loads once — if loaded once, new notifications require manual refresh — expected: known limitation or handled with pull-to-refresh
- [ ] Queue position for staff-specific sub-queues — `_compute_position` counts all entries or only staff-specific — expected: position correct in grouped view
