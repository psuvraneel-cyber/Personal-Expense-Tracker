# P.E.T — Google Play Release Checklist

For release 1.0.1 (13) from `main@daaa1b1`, prepared 1 November 2026. Tick items only with evidence (link, screenshot, command output).

Legend: 🧑‍💻 **developer action, code** · 🔐 **needs an external account or console** · ✅ verified in this audit · ❌ verified failing in this audit · ⬜ not yet verified.
Finding IDs refer to `PLAY_STORE_AUDIT_REPORT.md`.

---

## 0. Stop-ship items (must be green before *any* upload)

- [x] ✅ 🔐 **Legal pages live** (P0-1). They returned 404 earlier on 1 Nov 2026; after redeploy, all three return **200** and serve the updated text ("Last updated: 1 November 2026").
  - [x] https://personal-expense-tracker-6891b.web.app/privacy-policy.html
  - [x] https://personal-expense-tracker-6891b.web.app/terms.html
  - [x] https://personal-expense-tracker-6891b.web.app/account-deletion.html
- [x] 🔐 **Revoke the leaked Google/Gemini API key** committed in `backend/.env.example` (commit `1ea4484`) (P0-2). **Revoked by the developer on 1 Nov 2026** (reported; not independently verifiable). ⬜ Review billing since 2026-04-02.
- [ ] 🔐 Restrict the Firebase Android API key to package `com.pet.tracker.pet` + the release/upload SHA-1 and to the Firebase APIs only (P3-14).
- [ ] 🔐 Turn on GitHub **secret scanning + push protection** for the repository.

## 1. Source-code requirements

- [x] 🧑‍💻 **P1-1a:** bank balance disclosed in the consent dialog (key bumped to `v2`) and policy §4/§6. ⬜ Reflect it in Data safety.
- [x] 🧑‍💻 **P1-2:** `sms_transactions.rawSmsBody` purged after 90 days; tests added.
- [x] 🧑‍💻 **P1-3:** sign-out always clears the Google credential; lightweight auth skipped after an explicit sign-out. ⬜ Device-verify AUTH-05.
- [x] 🧑‍💻 **P1-4:** sign-out tries to upload, then warns when changes are still pending. ⬜ Device-verify OFF-07.
- [x] 🧑‍💻 **P2-7:** backup and device-transfer rules exclude every domain. ⬜ Device-verify PRIV-04.
- [x] 🧑‍💻 **P2-8:** wipe clears the Firestore cache (`terminate()` + `clearPersistence()`); policy updated. ⬜ Device-verify PRIV-03.
- [x] 🧑‍💻 **P1-5:** referral redemptions tied to a hashed Google identity. Worker deployed by the developer on 1 Nov 2026 (reported).
- [x] 🔐 Hosting redeployed: updated `privacy-policy.html` and `account-deletion.html` (dated 1 Nov 2026) are live.
- [ ] 🧑‍💻 **P2-6:** make deletion resumable or cancellable; don't report success if Worker records remain; require connectivity.
- [ ] 🧑‍💻 Remove `"claudeCodeChat.permissions.yoloMode": true` and stale tasks from `.vscode/` (P3-1).
- [x] 🧑‍💻 Fix the CRLF-sensitive test (P3-9): `production_launch_remediation_test.dart` now normalises line endings; passes with both CRLF and LF rules files.
- [ ] 🧑‍💻 Bump `version:` in `pubspec.yaml` (versionCode must exceed any previously uploaded build).
- [ ] ✅ `flutter analyze` clean · ✅ `dart format` clean · ✅ 835/835 Flutter tests (on LF checkout) · ✅ Worker 50/50 · ✅ Rules 15/15
- [ ] ✅ Kotlin unit tests green locally (32/32 on 1 Nov 2026), ⬜ added to CI (P2-14).

## 2. Backend deployment (Cloudflare Worker)

- [ ] 🔐 `wrangler deployments list`: the deployed version matches `cloudflare_worker/src/index.js` at the release commit.
- [ ] 🔐 Secrets present: `GROQ_API_KEY`, `REVENUECAT_API_KEY` (**secret `sk_` key**; also used for promo grants).
- [ ] 🔐 Vars: `GROQ_MODEL = "openai/gpt-oss-120b"` (confirm still served by Groq), `FREE_AI_QUESTIONS_PER_MONTH = "3"`, `REFERRAL_*`.
- [ ] 🔐 **App Check:** register Play Integrity, watch metrics, then `REQUIRE_APP_CHECK = "true"` and redeploy (P2-2). Add a `sub`/app-ID check in `verifyAppCheckToken`.
- [ ] 🧑‍💻🔐 Referral hardening or disablement before launch (P1-5). Atomic counters (P2-3).
- [ ] 🔐 Deletion-request alerting: an email or webhook on each `/deletion-request` (P2-13).
- [ ] 🔐 Groq: spend limit + alert; confirm data-retention / zero-data-retention setting and record it in the privacy policy.

## 3. Firebase

- [ ] 🔐 Production `google-services.json` and `lib/firebase_options.dart` present on the release machine (they are git-ignored; absent from the audited folder).
- [ ] 🔐 Firestore rules deployed (`firebase deploy --only firestore:rules`) and identical to `firestore.rules` at the release commit.
- [ ] 🧑‍💻 Harden rules: schema/size validation, a premium check for household creation, owner invite revocation (P2-1).
- [ ] 🔐 Firestore TTL policy on `householdInvites.expiresAt` (and consider tombstones).
- [ ] 🔐 Auth providers enabled: Google, Anonymous (if guest mode stays). SHA-1/SHA-256 of the **Play App Signing** key added to the Firebase Android app (needed by Google Sign-In in the Play-distributed build).
- [ ] 🔐 App Check: Play Integrity provider registered; enforcement for Firestore decided **after** metrics look healthy (beware P2-5).
- [ ] 🔐 Crashlytics enabled; Analytics data retention set (policy says 14 months); Remote Config defaults published (`paywall_default_plan`, …).
- [ ] 🔐 Hosting deployed (see §0).

## 4. RevenueCat

- [ ] 🔐 Entitlement identifier exactly `P.E.T Premium`.
- [ ] 🔐 Offering **current** with monthly / annual (+ lifetime if sold) packages mapped to Play products; optional offering **`winback`**.
- [ ] 🔐 Google Play service-account credentials uploaded; real-time developer notifications configured.
- [ ] 🔐 Public SDK key `goog_…` supplied at build time via `REVENUECAT_ANDROID_API_KEY` (the release build throws if it is missing, `test_` or `sk_`).
- [ ] 🔐 Firebase integration (renewal/trial events) if used.
- [ ] 🔐 Sandbox verification with license testers: purchase, restore, cancel, expiry, refund, grace period (RC-03…RC-08).

## 5. Google Play Console declarations

- [ ] 🔐 **SMS & Call Log Permissions Declaration:** use case *SMS-based money management*; permissions `READ_SMS`, `RECEIVE_SMS`; explain the core feature; attach a demo video (disclosure → grant → import → Pending Review); link the **working** privacy policy (P0-3).
- [ ] 🔐 **Financial features declaration:** budgeting / expense tracking only; no loans, banking, payments, trading or investment execution. Avoid "Financial advice" (the AI is labelled not-advice).
- [ ] 🔐 **Data safety:** full draft answers are in `PLAY_DATA_SAFETY_ANSWERS.md`. The app must first be created in Play Console (on 1 Nov 2026 the developer account contained only `com.nimontron.app`). Declare, consistently with the code:
  - [ ] Personal info: name, email, user IDs (collected; account management)
  - [ ] Financial info: transactions/expense records (collected; app functionality; synced for signed-in users); purchase history (RevenueCat)
  - [ ] SMS-derived data: extracted fields synced, **text never leaves the device** (declare as the form requires)
  - [ ] App activity: in-app interactions (**optional**, opt-in analytics)
  - [ ] App info & performance: crash logs, diagnostics (Crashlytics: **on by default with opt-out** → "optional")
  - [ ] Device or other IDs: Firebase installation / app-instance IDs
  - [ ] AI: finance summary + chat sent to the Worker → Groq (state whether Groq is a service provider; include the bank balance if still sent)
  - [ ] Encryption in transit: Yes · Deletion request mechanism: Yes (in-app + web)
- [ ] 🔐 **Foreground service:** the merged manifest contains `FOREGROUND_SERVICE` and `FOREGROUND_SERVICE_SHORT_SERVICE` from `workmanager_android` (expedited work). If Play Console asks, declare the shortService use (expedited background import), or answer per the current form.
- [ ] 🔐 Advertising ID: **No** (permission removed).
- [ ] 🔐 Content rating questionnaire; target audience **18+** (policy says so).
- [ ] 🔐 App access: reviewer instructions (Google test account or guest path; how to enable SMS and notification access; RevenueCat license tester for Premium).
- [ ] 🔐 Privacy policy URL = the hosted policy (200 OK).
- [ ] 🔐 Account deletion URL = the hosted deletion page (200 OK), which explains subscription cancellation.

## 6. Subscription products & pricing

- [ ] 🔐 Play products / base plans created and **active** (monthly, annual, lifetime if offered); India prices set manually (₹99 / ₹149 / ₹499 / ₹799 per the plan).
- [ ] 🔐 7-day free trial offer on the annual base plan; win-back base plan if used.
- [ ] 🔐 In-app copy matches Play terms (auto-renew, cancel ≥24 h before renewal; text present in `purchase_screen.dart`).
- [ ] 🧑‍💻 Handle pending payments (`paymentPendingError`) (P3-6).

## 7. Store listing

- [ ] 🔐 Short and full description lead with **automatic expense tracking from bank SMS** (supports the SMS declaration).
- [ ] 🔐 Do **not** claim linked bank accounts, a receipt scanner, "bank-grade" guarantees, full Hindi support, or financial advice.
- [ ] 🔐 Screenshots from the release build with synthetic data only.
- [ ] 🔐 Contact email, website (hosted pages) and privacy policy filled in.

## 8. Signed App Bundle

- [ ] 🔐 Upload keystore stored safely (not in the repo); Play App Signing enrolled.
- [ ] 🔐 Build: `flutter build appbundle --release --dart-define-from-file=.env --obfuscate --split-debug-info=build/symbols` (keep symbols for Crashlytics).
- [ ] ✅ Audit smoke build (placeholder config, throwaway key) succeeded: 66.9 MB AAB; ABIs arm64-v8a / armeabi-v7a / x86_64; **16 KB-aligned** 64-bit native libraries; targetSdk 36 / minSdk 24; no `debuggable`; R8 mapping + native symbols embedded; no secret files in the bundle.
- [ ] 🔐 Repeat the merged-manifest check on the **production** build: permissions = INTERNET, ACCESS_NETWORK_STATE, READ_SMS, RECEIVE_SMS, POST_NOTIFICATIONS, RECEIVE_BOOT_COMPLETED, USE_BIOMETRIC (+ library: BILLING, WAKE_LOCK, VIBRATE, USE_FINGERPRINT, FOREGROUND_SERVICE(_SHORT_SERVICE), BIND_GET_INSTALL_REFERRER_SERVICE, READ_GSERVICES); **no** `AD_ID`.
- [ ] 🔐 Upload Crashlytics symbols / the R8 mapping.

## 9. Internal testing track

- [ ] 🔐 Upload to **Internal testing** with license testers.
- [ ] Run the device matrix in `PLAY_STORE_TEST_MATRIX.md` for every P0/P1 row marked NOT TESTED / BLOCKED. At minimum:
  - [ ] AUTH-01/04/05
  - [ ] OFF-01/05/06/07
  - [ ] SMS-01/02/04/05/06
  - [ ] NOT-01/02/05
  - [ ] RC-03…RC-07
  - [ ] DEL-01…DEL-06
  - [ ] PRIV-01/03/04
- [ ] Pre-launch report reviewed (crashes, ANRs, accessibility warnings, sensitive permission warnings).

## 10. Closed testing

- [ ] 🔐 If the developer account requires it, a closed test with the required number of testers for the required duration before production access. Check the current Play Console requirement for your account type.
- [ ] Collect feedback on SMS parsing accuracy across banks; track the precision of auto-imports.

## 11. Production rollout

- [ ] 🔐 Staged rollout (e.g. 5% → 20% → 50% → 100%) with halt criteria: crash-free users < 99.5%, ANR rate > 0.47%, a spike in the sync error rate, or Worker 5xx > 2%.
- [ ] 🔐 Monitoring:
  - [ ] Crashlytics
  - [ ] Android vitals (ANR on SMS scan, P2-11)
  - [ ] Worker logs (status categories)
  - [ ] Groq spend
  - [ ] RevenueCat charts
  - [ ] the deletion-request queue
- [ ] 🔐 Rollback plan: keep the previous AAB and Worker version; Remote Config kill-switches (consider adding them for AI and referrals).
