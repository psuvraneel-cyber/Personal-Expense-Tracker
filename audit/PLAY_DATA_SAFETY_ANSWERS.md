# P.E.T — Draft Play Console Data safety answers

Drafted 1 November 2026 from the code at `main@daaa1b1` plus the P1 fixes. Enter these under **Play Console → P.E.T → Policy → App content → Data safety** once the app exists. They must stay consistent with the live privacy policy (https://personal-expense-tracker-6891b.web.app/privacy-policy.html).

Items marked **⚠ Decide** need your judgement or a fact only you can confirm.

---

## Step 1 — Data collection and security

| Question | Answer | Why |
|---|---|---|
| Does your app collect or share any of the required user data types? | **Yes** | Firebase, the Worker, Crashlytics, opt-in Analytics and RevenueCat all send data off the device |
| Is all of the user data collected by your app encrypted in transit? | **Yes** | Every endpoint is HTTPS/TLS; no cleartext traffic is allowed (targetSdk 36 defaults, no custom network config) |
| Do you provide a way for users to request that their data is deleted? | **Yes** | In-app: Settings → Danger Zone → Delete Account. Web: https://personal-expense-tracker-6891b.web.app/account-deletion.html |
| Account deletion URL (separate "Data deletion" question) | https://personal-expense-tracker-6891b.web.app/account-deletion.html | Live (200) as of 1 Nov 2026 |
| Independent security review (MASA) | **No** (optional) | — |

## Step 2 — Data types

**Collected** = sent off the device by the app or its SDKs. **Shared** = transferred to a third party *other than* a service provider acting on your instructions. Transfers the user starts and expects (household totals shown to members they invited) are exempt from "shared".

| Category → Data type | Collected | Shared | Ephemeral only? | Required / Optional | Purposes | Source in the app |
|---|---|---|---|---|---|---|
| **Personal info → Name** | Yes | No | No | Optional | App functionality, Account management | Google sign-in display name; Firestore profile; household member names; invoice business and client names (`invoice_profile`, `invoice_clients`, `invoices`) |
| **Personal info → Email address** | Yes | No | No | Optional | App functionality, Account management | Firebase Auth; Firestore profile (`users/{uid}`); business and client emails entered for invoices |
| **Personal info → Phone number** | Yes | No | No | Optional | App functionality | Business and client phone numbers entered for invoices (synced for signed-in users) |
| **Personal info → Address** | Yes | No | No | Optional | App functionality | Business and client addresses entered for invoices (synced for signed-in users) |
| **Personal info → User IDs** | Yes | No | No | **Required** | App functionality, Account management, Fraud prevention/security | Firebase UID (also created for anonymous guests), Google account ID, RevenueCat app user ID; Worker quota and referral records |
| **Financial info → Purchase history** | Yes | No | No | Optional | App functionality, Analytics | RevenueCat subscription and entitlement records; purchase events forwarded to Analytics only for users who opted in |
| **Financial info → Other financial info** | Yes | **⚠ Decide** (see note A) | No | Optional | App functionality | Transactions (amount, type, category, date, note, merchant, payment method), budgets, goals, bills, weekly limits and invoices (items, amounts, payments, GSTIN, UPI IDs) synced to Firestore; household category totals; AI Copilot finance summary **including the bank balance** sent through the Worker to Groq |
| **Financial info → User payment info** | **No** | — | — | — | — | Card and UPI details are handled by Google Play; the app never sees them |
| **Financial info → Credit score** | No | — | — | — | — | — |
| **Messages → SMS or MMS** | **No** (see note B) | — | — | — | — | SMS text is read and parsed only on the device and never uploaded; the extracted fields are declared under "Other financial info" |
| **App activity → App interactions** | Yes | No | No | Optional | Analytics | Firebase Analytics events, **opt-in only** |
| **App activity → Other user-generated content** | Yes | **⚠ Decide** (note A) | No | Optional | App functionality | AI Copilot questions and chat sent to Groq through the Worker (not stored); reported answers stored in Firestore `ai_reports` |
| **App info and performance → Crash logs** | Yes | No | No | **Optional** (note C) | Analytics | Firebase Crashlytics (on by default, can be turned off in Settings) |
| **App info and performance → Diagnostics** | Yes | No | No | Optional | Analytics | Crashlytics device/OS/app version; Worker logs (hashed UID, status, latency) |
| **Device or other IDs** | Yes | No | No | **Required** | App functionality, Analytics, Fraud prevention/security | Firebase installation ID (Remote Config, App Check, Crashlytics); Analytics app-instance ID (opt-in) |
| **Location → Approximate location** | Yes | No | No | Optional | Analytics | Google Analytics derives country/city from the IP address, **only when the user opts in** (note D) |
| **Location → Precise location** | No | — | — | — | — | — |
| Contacts, Calendar, Photos/videos, Audio, Files and docs, Health and fitness, Web browsing, Installed apps, Search history, Emails, Race/religion/politics | **No** | — | — | — | — | Not accessed or sent (invoice client details are typed in by the user; the app does not read the phone's contacts) |

---

## Notes

**A — Is Groq a "service provider"? ⚠ Decide.** The AI finance summary (including the bank balance) and chat go to Groq, Inc. through your Worker. Play exempts transfers to a *service provider* that processes data only on your behalf and under your instructions. If your Groq API terms say inputs aren't used for training or other customers, answer **Shared: No**. If you can't confirm that, answer **Shared: Yes** for "Other financial info" and "Other user-generated content", purpose **App functionality**. Saying Yes is the safer choice. Check the Groq console (data retention / zero-data-retention setting) before choosing.

**B — Why SMS is "not collected".** Play's guidance says data processed only on the device and not sent off it does not need to be declared. P.E.T never uploads SMS text; only the extracted transaction fields leave the device, and those are declared under "Other financial info". The SMS use is declared separately in the **SMS & Call Log Permissions Declaration** (blocker P0-3). If a reviewer questions it, point to privacy policy §2.

**C — Crashlytics "optional".** Play allows "optional" only if *every* user can opt out. Settings has a "Share crash reports" switch that controls Crashlytics collection, but it starts **on**. "Optional" is correct because users can turn it off; it does not mean it starts off.

**D — Approximate location.** Google Analytics derives a coarse location from the IP address. Analytics is opt-in, so declare it as **Optional**, purpose **Analytics**. If you remove Analytics, remove this row too.

## Keep consistent

- If you later stop sending the bank balance to the AI, the "Other financial info" row stays (transactions are still synced), but update privacy policy §4 and §6.
- If Analytics or Crashlytics defaults change, revisit the Optional/Required answers.
- Re-check this form whenever a new SDK is added; SDK traffic counts as collection.
