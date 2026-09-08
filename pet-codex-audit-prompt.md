# P.E.T. — Comprehensive Codebase Audit Brief for Codex CLI

## Role

You are acting as a senior/principal-level mobile security, Android release, and Flutter
architecture engineer conducting an independent, adversarial, evidence-based audit of this
repository (P.E.T. — Personal Expense Tracker), ahead of its first Google Play Store
submission. You have direct read (and, where useful, execute) access to every file in this
repo — use it. Do not answer from assumptions or from any pre-existing document already in
this repo; verify everything against the actual current source.

## Project context (for orientation only — verify, don't assume)

- Flutter/Dart app (Flutter SDK ^3.10.8), Android-first, targeting Indian personal finance users.
- Auto-detects UPI/bank transactions by parsing SMS (`SmsBroadcastReceiver`, native Kotlin) and
  by reading financial notifications (`TransactionNotificationListener` +
  `NotificationListenerService`), entirely on-device.
- Local storage: SQLite via `sqflite_sqlcipher` (encrypted). Cloud sync/auth: Firebase
  (Auth + Firestore). Crash reporting: Firebase Crashlytics. Premium billing: RevenueCat.
  An AI "Copilot" reaches Groq's LLM via a Cloudflare Worker proxy (`cloudflare_worker/`) that
  verifies Firebase ID tokens and applies server-side rate limiting and a locked system prompt.
- State management: `provider` package with `ChangeNotifierProxyProvider` chains.
- Solo developer, ~4-5 months of active development, several past internal audit/remediation
  cycles already recorded in this repo (see below — treat with caution).
- Version is currently `1.0.1+13` in `pubspec.yaml`; this app has not yet shipped to the Play Store.

## Critical starting instruction: this repo's own audit trail is unreliable — verify, don't cite

This repository already contains several self-generated "audit" and "final report" documents:

- `docs/PRODUCTION_LAUNCH_AUDIT_REPORT.md`
- `docs/play-store-audit.html`
- `.gsd/production-fix/BASELINE.md`, `ISSUES.md`, `FINAL_REPORT.md`, `TARGET_SDK_36.md`
- `.gsd/revenuecat-debug/FINAL_REPORT.md`, `SDK_UPGRADE_FINAL_REPORT.md`
- `.gsd/debug/AI_COPILOT_AUTH_FINAL_REPORT.md`

I compared the most recent of these (`docs/PRODUCTION_LAUNCH_AUDIT_REPORT.md`, dated August
2026, self-scored 9.3/10) against the actual current source in this repo and found it is
**already wrong or stale on multiple points it lists as launch blockers**, for example:

- It claims `android/app/build.gradle.kts` sets `targetSdk = 35` (a "BLOCKER"). The current
  file sets `targetSdk = 36`.
- It claims `firestore.rules` only grants `read, delete` on premium subcollections via a bare
  wildcard, omitting `create`/`update` (a "BLOCKER"). The current `firestore.rules` has
  explicit `allow read, write` blocks for every premium collection it names (`saving_goals`,
  `recurring_payments`, `alerts`, `tax_categories`, `linked_accounts`, `family_members`).
- It flags dead `SUPABASE_URL`/`SUPABASE_ANON_KEY` constants as still present in
  `lib/config/app_env.dart` (LOW severity). The current `app_env.dart` has no Supabase
  references at all — though `.github/workflows/ci.yml` still injects
  `SUPABASE_URL`/`SUPABASE_ANON_KEY` as secrets, which *is* real leftover cruft worth cleaning up.
- It flags the Cloudflare Worker as letting arbitrary client-supplied `system` role messages
  reach Groq unfiltered (HIGH). The current `cloudflare_worker/src/index.js` already enforces
  a hardcoded `TRUSTED_SYSTEM_PROMPT`, only accepts one client `system` message (position 0,
  used purely as sanitized context via `sanitizeContextSnapshot()`), and rejects any
  subsequent system-role message.
- It flags `PRIVACY_POLICY.md` as understating what's sent to the AI Copilot. The current
  policy already discloses "sanitized recent transaction labels" being sent — though whether
  the actual sanitization is real and complete still needs checking (see below).

I don't know whether these docs are simply stale (fixes landed after they were written) or
were inaccurate when written (an LLM audit that asserted things without actually reading the
referenced files/lines). Either way: **treat every claim in every one of those documents as
an unverified lead, never as a fact.** Where a document's specific claim can no longer be
reproduced against current source, say so explicitly in your output rather than repeating the
old claim. Build your verdict entirely from what you observe in the live repo, tests, and any
commands you run — not from these documents' conclusions or scores.

## Ground rules

1. For every claim you make, cite the exact file path and line number/range, and quote or
   paraphrase the actual code you're relying on. Open and read the file yourself before
   asserting its contents.
2. Actually run these and include real output (state clearly if a command isn't runnable in
   your environment, e.g. no Android SDK/emulator — don't fabricate output):
   - `flutter analyze`
   - `flutter test` (report real pass/fail/skip counts)
   - `flutter pub outdated`
   - `dart format --output=none --set-exit-if-changed .`
   - `grep -rniE "TODO|FIXME|HACK|XXX|mock|placeholder|not.?implemented" lib/ android/ cloudflare_worker/src/`
   - `grep -n "identical(_last" -r lib/` (see systemic risk below)
   - Confirm `.gitignore` actually covers `.env`, `google-services.json`,
     `GoogleService-Info.plist`, `key.properties`, `firebase_options.dart`, and check for any
     accidentally-tracked secret files with
     `git ls-files | grep -iE "google-services|GoogleService-Info|\.env$|key\.properties"`.
   - `git log --all --oneline -- '*.env' 'android/app/google-services.json'` (or similar) to
     sanity-check no secret files were ever committed — a past session found and rotated one
     leaked Firebase key in git history; confirm no other artifacts remain.
3. Be adversarial: actively try to break assumptions and find what's wrong, rather than
   confirming that things are fine. Prefer "unverified — could not confirm X" over guessing.
4. Where a past bug (below) is supposed to already be fixed, don't just check that a fix
   exists — trace the actual current logic end-to-end and confirm it's correct and complete,
   not partial.

## Known history to specifically re-verify

- **Provider memoization bug**: in-place list mutation defeating `identical()`
  reference-equality guards, so downstream `ChangeNotifier`s never see a change. This pattern
  is used pervasively — `identical(_last...)` checks appear in at least 7 locations across the
  codebase (weekly planner, spend/budget tracking, anomaly detection, recurring detection —
  grep for `identical(_last` to find them all). For **every single one**, trace the upstream
  provider/repository/service that produces the compared value and confirm it constructs a
  **new** list/object on every real data change rather than mutating an existing list in place
  (`list.add()`/`list.removeAt()` on the same instance vs. `[...list, x]` or `List.from(...)`).
  A single violation anywhere in this chain silently breaks reactivity for that feature with no
  error or crash — this needs exhaustive checking, not a spot check.
- **`firebase_crashlytics`**: previously reported missing; `pubspec.yaml` now lists
  `firebase_crashlytics: ^4.3.0` — confirm it's actually initialized and wired up in
  `main.dart` (`FlutterError.onError`, `PlatformDispatcher.instance.onError`), not just declared.
- **Cashflow forecast clamping bug** that previously prevented alerts from firing correctly —
  re-verify `cashflow_forecast_service.dart` and `alert_evaluator.dart` end-to-end (trace an
  example number through the clamp logic), don't just check that `cashflow_risk_test.dart` exists.
- **Leaked Firebase API key**: previously found in git history and rotated — confirm the
  currently-configured key(s) are the rotated ones, no old key remains reachable/valid, and no
  other secret-shaped strings exist anywhere in the repo
  (`grep -rnoE "AIza[0-9A-Za-z_-]{20,}|gsk_[A-Za-z0-9]{20,}|sk_[A-Za-z0-9]{20,}"`).
- **Linked Accounts** (`lib/premium/screens/linked_accounts_screen.dart`,
  `lib/premium/services/mock_bank_integration.dart`, `bank_integration_provider.dart`) and
  **Tax Buckets** (`tax_buckets_screen.dart`, `tax_category_service.dart`) were previously
  flagged as serving mock/placeholder data or thin functionality dressed up as a real premium
  feature. Determine their current real status precisely: is a paying user shown data that
  looks real but isn't? Is this clearly labeled ("Coming Soon"/"Preview"), or does it risk
  feeling like paid vaporware? This matters for both Play Store policy (no misrepresenting
  functionality) and user trust.
- **Malformed `.gitignore` entry**: near the end of the root `.gitignore` there's a line that
  looks like `P E T _ T e c h n i c a l _ A u d i t _ R e p o r t . *` (letters separated by
  spaces) followed by `audit_report.md` on an oddly-indented line of its own — as literally
  written this glob won't match a real filename like `PET_Technical_Audit_Report.pdf`. Confirm
  whether this is a copy/paste corruption and fix or remove it.
- **Repo hygiene**: the repo root has a pile of loose analysis-dump files (`analyze_final.txt`,
  `analyze_out.txt`, `analyze_output.txt`, `analyze_output2.txt`, `analyze_output3.txt`,
  `analyze_output4.txt`, `analyze_premium.txt`, `analyze_redesign.txt`, `analyze.json`,
  `analyze.txt`, `analyze2.txt`, `plan_extracted.txt`) plus a stray `desktop.ini`. Confirm
  whether these are tracked in git (not just present on disk) and, if so, recommend removal
  plus `.gitignore` entries.

## What to evaluate (organize your findings under these headings)

### A. Play Store submission readiness
- `targetSdk`/`compileSdk` actual current values vs. the Android 16 (API 36) requirement for
  new submissions/updates from Aug 31, 2026 — confirm current compliance status.
- Sensitive permissions (`READ_SMS`, `RECEIVE_SMS`, notification listener access): confirm
  Play Console's Restricted Permissions declaration requirements (justification, demo video)
  are addressed, and that runtime permission requests are properly soft-gated rather than
  auto-triggered on launch — check `sms_permission_screen.dart`,
  `notification_permission_banner.dart`.
- Data Safety form accuracy: cross-check `PRIVACY_POLICY.md`'s claims about what's
  collected/transmitted (including to Groq/Cloudflare) against what `ai_copilot_service.dart`,
  `firestore_sync_service.dart`, and Crashlytics actually send. Specifically confirm the
  "sanitized recent transaction labels" sent to the AI copilot
  (`ai_copilot_service.dart`, `recentTransactions.take(10)`) are genuinely sanitized (no
  account numbers, phone numbers, raw SMS text) before being included in the Groq prompt.
- Account deletion: confirm both an in-app flow (`account_deletion_service.dart`,
  `account_deletion_sheet.dart`) and a working, publicly-reachable web deletion URL exist and
  would actually be linkable from the Play Console listing — is `docs/account-deletion.html`
  actually hosted anywhere, or just sitting unpublished in the repo?
- Signing/release config: in `android/app/build.gradle.kts`, confirm a real release build
  cannot silently fall back to debug signing — read the logic closely for a bypassable path.
- ProGuard/R8 (`android/app/proguard-rules.pro`) completeness for SQLCipher, Firebase,
  RevenueCat, Crashlytics, and any reflection-based libraries — a missing keep rule can cause
  release-only crashes invisible in debug.
- Firestore rules vs. actual usage: read `firestore.rules` in full, then cross-reference every
  Firestore collection path actually referenced in `lib/data/repositories/*.dart` and
  `lib/premium/repositories/*.dart`. Flag any mismatch either direction.

### B. Security & privacy
- SQLCipher key lifecycle: generated per-install, stored only in Android Keystore-backed
  secure storage, never logged or hardcoded? (`secure_storage_service.dart`, `database_helper.dart`)
- `EncryptedNotificationCache.kt`: correctness of AES-256-GCM usage (IV handling/reuse, key
  rotation, MasterKey scheme).
- `SafeLog.kt` / `app_logger.dart`: confirm release builds cannot log financial data, SMS
  content, or tokens — and confirm `test/core/app_logger_release_safety_test.dart` exercises a
  realistic case, not a trivial one.
- Cloudflare Worker (`cloudflare_worker/src/index.js`): re-verify the prompt-injection defenses
  in full (`TRUSTED_SYSTEM_PROMPT` lock, `sanitizeContextSnapshot()`, single-position system
  message rule), Firebase ID token verification against Google's JWKS, per-user rate limiting,
  CORS configuration, and that `GROQ_API_KEY`/`REVENUECAT_API_KEY` are only ever read from
  Worker secrets, never hardcoded or logged.
- Biometric app lock (`biometric_service.dart`, `biometric_lock_screen.dart`): bypassable via
  backgrounding/killing the app, task-switcher screenshots, or a missing re-lock timeout?

### C. Architecture & code quality
- Repository/provider layering consistency across `lib/data/`, `lib/premium/`, and top-level
  `lib/providers/` — one coherent pattern, or drift between older and newer features?
- Database migrations (`database_helper.dart` + `test/data/database_migration_test.dart`,
  `database_migration_v15_test.dart`): how many versions, are they linear/idempotent, and is
  there a real test that runs a fresh v1 install through every migration to latest?
- Offline-first sync: `firestore_sync_service.dart` + `reconciliation_service.dart` — walk
  through the delete-wins tombstone logic for a realistic multi-device conflict and confirm it
  actually holds up, rather than trusting the test names (`high_2_oem_reconciliation_test.dart`,
  `high_4_persistence_sync_integration_test.dart`, `transaction_sync_test.dart`).
- Concurrency in the SMS/notification ingestion pipeline (`SmsBroadcastReceiver.kt`,
  `TransactionNotificationListener.kt`, the EventChannel bridge, `sms_background_service.dart`)
  — real risk of duplicate transactions or dropped events under rapid-fire SMS arrival; assess
  whether `sms_concurrency_stress_test.dart` and `TransactionNotificationListenerConcurrencyTest.kt`
  genuinely stress-test this or just smoke-test it.
- Cross-platform bridge (`platform_native.dart`/`platform_stub.dart`): does the app actually
  build and run without crashing on non-Android targets (this repo also has `ios/`, `windows/`,
  `web/` scaffolding), correctly no-op'ing SMS/notification features there?
- Test suite: enumerate `test/` and classify each file as (1) genuine feature/unit coverage,
  (2) a one-off regression test pinning a specific past bug, or (3) superficial/placeholder.
  Actually run the suite and report real numbers.
- Dependency health: `flutter pub outdated` output — flag anything meaningfully behind,
  especially security-relevant packages (`firebase_*`, `flutter_secure_storage`,
  `sqflite_sqlcipher`, `purchases_flutter`).

### D. Product completeness & monetization
- For each premium feature (Tax Buckets, Linked Accounts, Family Sharing, Cashflow Forecast,
  Spend Pause, Weekly Planner, AI Copilot, Recurring Bills, Savings Goals, Alerts): classify it
  as fully real, real-but-not-cloud-synced, or mock/placeholder, and confirm `premium_gate.dart`
  is applied consistently so no premium screen is reachable by non-subscribers via a missed gate.
- `premium_entitlement_service.dart`: confirm test-store vs. release RevenueCat key selection
  can't leak a dev/test override into a real release build
  (read what `developer_premium_override_test.dart` actually asserts).
- `export_service.dart`: does PDF/CSV export reflect the live database accurately, and is it
  properly premium-gated if intended to be?

## Deliverable format

Produce a single report with these sections, in this order:

1. **Executive verdict** — Launch-ready: Yes / No / Conditional. List only genuine,
   currently-reproducible hard blockers (things that would cause Play Store rejection or real
   harm to a real user's financial data), each with file:line proof.
2. **Play Store Readiness Score (/10)** — short rationale per sub-area (policy compliance,
   security, privacy, data safety, billing/paywall, account deletion).
3. **Architecture Score (/10)** — short rationale per sub-area (state management, data layer,
   offline sync, concurrency, testing, code organization).
4. **Positives** — specific, evidence-based (cite files/patterns), not generic praise.
5. **Issues found** — a table: `ID | Severity (Blocker/High/Medium/Low) | Area | File:Line |
   Problem | Evidence | User/Play impact | Suggested fix | Fix before launch? (Y/N)`.
6. **Discrepancy log** — every place where an existing in-repo audit/report document turned out
   to be wrong, stale, or unverifiable against current source (so the user knows which
   historical docs in `.gsd/` and `docs/` to stop trusting or to update/retire).
7. **Pre-launch checklist** — the minimal ordered set of must-fix items only.
8. **Post-launch roadmap** — feature/architecture improvements worth doing after v1 ships,
   prioritized, distinguishing "finish what's already scaffolded" (Linked Accounts, Tax
   Buckets, Family Sharing) from genuinely new ideas.
9. **Testing gaps** — specific missing scenarios worth adding, beyond what already exists.

Be direct and specific throughout. Where you're not confident, say so rather than filling the
gap with a plausible-sounding guess.
