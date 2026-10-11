# Growth & monetisation launch checklist

What the app now does, and the console / dashboard setup each feature needs
before release. Nothing here is automatic: the code ships with safe defaults
and simply does less until the matching setup exists.

---

## 1. What's in the app

| Feature | Where | Needs setup? |
| --- | --- | --- |
| Opt-in usage analytics + funnel events | `lib/services/analytics_service.dart`, `engagement_tracker.dart` | Firebase Analytics linked; key events (§3) |
| Play in-app review prompt | `engagement_tracker.dart` | None (only shows for Play installs) |
| Remote Config paywall copy / default plan / review threshold | `lib/services/remote_config_service.dart` | Optional parameters (§3) |
| Blurred previews + personalised hooks on locked screens | `premium_gate.dart`, `premium_teasers.dart` | None |
| Premium Hub open to free users | `premium_hub_screen.dart` | None |
| "We found N subscriptions" dashboard card → paywall | `subscriptions_found_card.dart` | None |
| 3 free AI Copilot questions / month (server-enforced) | Worker `checkFreeAllowance`, `ai_copilot_screen.dart` | Deploy Worker (§4) |
| Free trial button + yearly "SAVE x%" + per-month price | `purchase_screen.dart` | Play trial offer (§2) |
| Win-back offering for lapsed subscribers | `purchase_screen.dart` (`kWinBackOfferingId`) | Play base plan + RevenueCat offering (§2) |
| Home-screen widget | `SpendWidgetProvider.kt`, `home_widget_service.dart` | None |
| Monday weekly recap + monthly Money Wrap (shareable) | `report_notifier.dart`, `money_wrap_screen.dart` | None |
| Invite friends → both get a free month | Worker `/referral/*`, `referral_screen.dart` | Deploy Worker; RevenueCat secret key (§4) |
| Shared household budgets | `household_service.dart`, `shared_budgets_screen.dart` | Deploy Firestore rules (§5) |
| Hindi (beta, opt-in in Settings → Language) | `lib/l10n/` | Native-speaker review (§7) |

---

## 2. Google Play Console + RevenueCat

### Prices (set by hand in INR)
Play Console → Monetize → Subscriptions → your subscription → each base plan →
*Prices*: set **India** manually instead of accepting the converted price.
Round, familiar numbers convert better (₹99, ₹149, ₹499, ₹799). Keep the
yearly price at roughly 6–8× the monthly so the "SAVE x%" badge (shown when
the saving is ≥5%) is meaningful. Test changes with RevenueCat Experiments
rather than editing live prices.

### 7-day free trial
On the **yearly** base plan (and optionally monthly): *Add offer* →
eligibility **New customer acquisition → Never had this subscription** →
phase **Free trial, 7 days**. RevenueCat picks it as the package's
`defaultOption`, and the paywall automatically shows "Start 7-day free
trial" and "Free for 7 days, then ₹X / year".

### Win-back for lapsed subscribers
1. Add a separate **base plan** (e.g. `yearly-winback`) at the discounted
   price. A separate base plan is safer than a developer-determined offer:
   RevenueCat would otherwise pick that offer for *every* buyer.
2. RevenueCat → Product catalog → Offerings → **New offering** with
   identifier **`winback`** containing that base plan as an Annual package.
3. Keep your normal offering as *Current*.

The paywall shows `winback` only to people whose `P.E.T Premium`
entitlement exists but is inactive.

### RevenueCat
- **Experiments**: test prices / plan mixes; the app always shows the
  offering RevenueCat serves, so no release is needed.
- **Integrations → Firebase**: sends renewals, trial conversions and
  cancellations to Google Analytics (the app sets `$firebaseAppInstanceId`
  for users who opted in to analytics).
- The Worker's `REVENUECAT_API_KEY` must be a **secret (sk_)** key. It now
  also grants promotional months for invites
  (`POST /v1/subscribers/{id}/entitlements/P.E.T Premium/promotional`).

### Play policy declarations
- **Financial features declaration** (App content): declare budgeting /
  expense tracking; no loans, no investment products.
- **Advertising ID**: answer **No**. The manifest removes `AD_ID` and the
  Privacy Sandbox ad permissions.
- **Data safety**: add *App activity → App interactions* (optional,
  analytics) and keep *Financial info* accurate (synced for signed-in users,
  household category totals shared with members the user invites).
- Referral rewards are allowed; never reward ratings or reviews.

---

## 3. Firebase

### Analytics
- Project settings → Integrations → **Google Analytics** must be linked.
- Mark as key events: `trial_start`, `subscribe`, `referral_redeemed`,
  `household_created`.
- GA4 → Explore → Funnel: `first_open` → `sms_permission_granted` →
  `first_auto_import` → `retained_day_7` → `paywall_view` → `trial_start` →
  `subscribe`. Only users who opted in appear; take installs from Play
  Console.
- Other events: `paywall_winback_shown`, `ai_free_quota_exhausted`,
  `money_wrap_share`, `referral_shared`, `household_joined`, `review_prompt`.

### Remote Config (all optional; defaults are built in)
| Parameter | Default | Valid values |
| --- | --- | --- |
| `paywall_headline` | Unlock P.E.T Premium | ≤ 40 chars (English users only) |
| `paywall_subtitle` | Unlock AI insights, … | ≤ 140 chars (English users only) |
| `paywall_default_plan` | `annual` | `annual`, `monthly`, `lifetime`, `first` |
| `review_auto_import_threshold` | `10` | 3–50 |

Fetched values apply on the **next app launch**. A/B Testing → Remote
Config experiment, goal = `subscribe`.

---

## 4. Cloudflare Worker

```bash
cd cloudflare_worker && npx wrangler deploy
```

New `wrangler.toml` vars (already set): `FREE_AI_QUESTIONS_PER_MONTH = "3"`
(`"0"` = Premium-only), `REFERRAL_NEW_USER_DAYS = "30"`,
`REFERRAL_MAX_PER_YEAR = "12"`.

New routes (all need a Firebase ID token): `POST /quota`,
`POST /referral/code`, `POST /referral/redeem`, `POST /referral/forget`.

**KV usage goes up** (free-question counters, referral records, premium
cache). The KV free tier allows 1,000 writes/day, so move to Workers Paid
before launch.

---

## 5. Firestore

```bash
firebase deploy --only firestore:rules,hosting
```

The rules add `households/{id}` (+ `budgets`, `spending`) and
`householdInvites/{code}`. The queries only use single-field indexes, which
Firestore creates automatically. Hosting redeploys the updated privacy
policy and terms.

Rules tests: `cd firestore_tests && npm test` (Java 21) or
`npm run test:java17`.

---

## 6. Store listing (English)

**App name (26/30):** P.E.T: UPI Expense Tracker

**Short description (80/80):**
Auto-track UPI & bank SMS spending. Budgets, bill alerts, AI tips. No bank login

**Full description:**

> Stop typing every expense. P.E.T reads the bank and UPI SMS you already
> receive and turns them into a clean, categorised record of your spending,
> automatically.
>
> **No bank login. Encrypted on your phone. We never sell your data.**
> Message text is processed on your device and never uploaded. Your records
> are stored in an encrypted database on your phone, and backed up only if
> you sign in with Google.
>
> **What you get, free**
> • Automatic expense tracking from bank SMS and payment-app notifications
>   (Google Pay, PhonePe, Paytm and more)
> • Monthly budgets for each category, with alerts before you overspend
> • A dashboard that shows where your money goes
> • A home-screen widget: today's spending and what's left in your budget
> • Your monthly Money Wrap and a Monday spending recap
> • Export to CSV or PDF
> • 3 free questions a month to the AI Copilot
> • Join your family's shared budgets
>
> **P.E.T Premium**
> • Unlimited AI Copilot: "Can I afford a ₹25,000 purchase next week?"
> • Bills & subscriptions: every recurring payment found for you, with
>   reminders before they're due and price-rise alerts
> • Cash-flow forecast: safe-to-spend and how long your money will last
> • Tax buckets for 80C, 80D and HRA
> • Savings goals, Focus Mode and weekly planner
> • Start a shared household budget for up to 6 people
>
> Try Premium free for 7 days. Cancel any time in Google Play.
>
> **Invite friends:** when a friend joins with your code, you both get a
> month of Premium free.
>
> P.E.T is not a bank and doesn't give financial advice. AI answers can be
> wrong.

Avoid "best", "#1", or repeating keywords; Play rejects listings for
keyword stuffing. The text above uses "UPI", "expense tracker",
"automatic", "SMS" and "budget" naturally.

**Screenshots (phone, in this order). Put the caption in the image:**
1. Dashboard with auto-imported UPI transactions: "Your spending, tracked automatically"
2. SMS permission screen: "No bank login. Message text never leaves your phone"
3. Subscriptions found card + bills list: "We found your subscriptions"
4. Budget tab: "Budgets that warn you before you overspend"
5. Home-screen widget: "Today's spending at a glance"
6. Money Wrap card: "Your month in money, ready to share"
7. AI Copilot answering a question: "Ask your money anything"
8. Household budgets: "Budget together with family"

**Feature graphic text:** "Your UPI spending, tracked automatically. No bank login."

## 6a. Store listing (Hindi, `hi-IN`). Have a native speaker review it

**App name:** P.E.T: UPI खर्च ट्रैकर

**Short description (79/80):**
UPI और बैंक SMS से खर्च अपने-आप ट्रैक करें। बजट, बिल रिमाइंडर। बैंक लॉगिन नहीं।

**Full description (summary to expand):**

> हर खर्च लिखना बंद करें। P.E.T आपको मिलने वाले बैंक और UPI SMS पढ़कर आपका
> खर्च अपने-आप श्रेणियों में दर्ज करता है।
>
> **बैंक लॉगिन नहीं। आपके फ़ोन पर एन्क्रिप्टेड। हम आपका डेटा कभी नहीं बेचते।**
>
> मुफ़्त: अपने-आप खर्च ट्रैकिंग, श्रेणी के हिसाब से मासिक बजट, होम-स्क्रीन
> विजेट, मासिक Money Wrap, CSV/PDF एक्सपोर्ट, हर महीने AI कोपायलट से 3 सवाल।
>
> Premium: असीमित AI कोपायलट, बिल और सब्सक्रिप्शन रिमाइंडर, कैश-फ़्लो अनुमान,
> 80C/80D/HRA टैक्स बकेट, बचत लक्ष्य, परिवार के साथ साझा बजट।
> 7 दिन मुफ़्त आज़माएँ। Google Play में कभी भी रद्द करें।

---

## 7. Hindi (beta)

Translated: bottom navigation, onboarding, SMS permission screen,
notification-access disclosure, analytics consent, paywall (except plan
tiles and the legal footer), Premium lock card, most of Settings, and the
home-screen widget. Everything else is still English, so Hindi is only used
when chosen in **Settings → Language**, never automatically.

To translate more: add keys to `lib/l10n/app_en.arb`, the same keys to
`app_hi.arb`, run `flutter gen-l10n`, and use
`AppLocalizations.of(context).key`. `test/l10n/arb_parity_test.dart` fails
if a key or placeholder is missing. **Have a native Hindi speaker review
`app_hi.arb` and the Hindi listing before release.**

---

## 8. Test on a real device before release

- [ ] Analytics consent sheet appears once; Settings switch works; events
      visible in Firebase DebugView (`adb shell setprop debug.firebase.analytics.app com.pet.tracker.pet`)
- [ ] Review prompt: install from an internal test track (it never shows for
      sideloaded builds)
- [ ] Free user: Bills / Cash Flow / Alerts / Tax show blurred previews and
      teasers; Premium Hub opens without a lock
- [ ] AI Copilot as a free Google user: 3 answers, then the upgrade bar;
      as a guest: sign-in message
- [ ] Paywall: trial button text, SAVE badge, trust strip; win-back offering
      with a lapsed test account
- [ ] Widget: add from Settings; numbers update after an SMS import; shows
      🔒 when biometric lock is on; resets after midnight
- [ ] Money Wrap: change device date to the 1st after 10:00 → notification;
      share card hides amounts by default
- [ ] Invites: code shows; redeeming on a second new account grants both a
      month (RevenueCat customer page shows the promotional entitlement)
- [ ] Households: create (Premium), invite, join from a second account,
      shared budget totals update, leave / remove / delete
- [ ] Account deletion removes household membership and Worker records
- [ ] Hindi: switch language in Settings; check text fits on small screens
