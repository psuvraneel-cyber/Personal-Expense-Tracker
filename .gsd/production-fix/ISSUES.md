# Production Launch Issue Tracking Matrix

**Application:** P.E.T. — Personal Expense Tracker  
**Source Document:** `PRODUCTION_LAUNCH_AUDIT_REPORT.md`  
**Date:** August 24, 2026  

---

## Issue Matrix

## Issue Matrix

| ID | Report Severity | Current Status | Actual Finding in Source Code | Required Fix | Verification Proof |
| :--- | :--- | :--- | :--- | :--- | :--- |
| **PET-01** | **BLOCKER** | **RESOLVED** | `android/app/build.gradle.kts` specified `targetSdk = 35`. Google Play mandates API 36 for submissions from Aug 31, 2026. | Set `targetSdk = 36` in `android/app/build.gradle.kts`. Validated Android 16 compatibility chain. | `targetSdk = 36` in `build.gradle.kts`; `TARGET_SDK_36.md` verified; tests pass. |
| **PET-02** | **BLOCKER** | **RESOLVED** | `firestore.rules` lacked explicit rules for subcollections (`saving_goals`, `recurring_payments`, `recurring_rules`, `alerts`, etc.), causing potential `PERMISSION_DENIED`. | Added explicit, strongly-typed collection rules enforcing UID matching, immutable fields, and ownership checks for all 12 collections. | `firestore.rules` verified; `production_launch_remediation_test.dart` passes. |
| **PET-03** | **HIGH** | **RESOLVED** | `cloudflare_worker/src/index.js` permitted arbitrary client system prompts, enabling prompt injection / jailbreaks. | Enforced authoritative server-controlled system prompt, sanitized client context snapshots, and restricted system role to initial position. | 24/24 Node tests pass in `cloudflare_worker/test/index.test.js` including injection tests. |
| **PET-04** | **MEDIUM** | **RESOLVED** | `PRIVACY_POLICY.md` lacked granular third-party disclosure for Crashlytics and exact AI payload description. | Added Firebase Crashlytics to third-party table and updated Section 4 to explicitly describe anonymized category totals, budget utilization, and sanitized merchant labels. | `PRIVACY_POLICY.md` updated; verified by `production_launch_remediation_test.dart`. |
| **PET-05** | **MEDIUM** | **RESOLVED** | Google Play Data Safety policy requires a publicly accessible web deletion page for users who uninstalled the app. | Created `docs/account-deletion.html` with step-by-step instructions, email support, and clear data erasure scope. | `docs/account-deletion.html` verified by `production_launch_remediation_test.dart`. |
| **PET-06** | **LOW** | **RESOLVED** | `lib/config/app_env.dart`, `.env`, and manifest contained obsolete Supabase constants and comments. | Pruned dead Supabase constants from `app_env.dart`, `.env`, `AndroidManifest.xml`, and docstrings. | 0 Supabase references in runtime code; verified by `production_launch_remediation_test.dart`. |
| **PET-07** | **LOW** | **RESOLVED** | SQLite `transactions` index coverage required investigation. | Audited `TransactionRepository.dart` against `DatabaseHelper.dart`; confirmed all active filter clauses are covered by `idx_txn_date`, `idx_txn_category`, `idx_txn_type`, and `idx_txn_recurring`. No unindexed filters exist. | Database indexes confirmed optimal; 428/428 tests pass. |

---

## "Do Not Launch Until" Gating Conditions

- [x] `targetSdk = 36` verified and tested with Android 16 compatibility.
- [x] `firestore.rules` updated with complete subcollection rules & verified.
- [x] `cloudflare_worker/src/index.js` hardened against system prompt injection.
- [x] `PRIVACY_POLICY.md` synchronized with exact AI data payload.
- [x] External web account deletion page created and verified.
- [x] Stale Supabase references pruned without regressions.
- [x] All analyzer warnings resolved (0 errors, 0 warnings).
- [x] 100% test suite pass rate maintained (428/428 Flutter tests, 24/24 Worker tests).
