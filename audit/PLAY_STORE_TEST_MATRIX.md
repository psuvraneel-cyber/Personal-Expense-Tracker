# P.E.T — Play Store QA Test Matrix

**Build under test:** `main@daaa1b1`, 1.0.1 (13) · **Matrix prepared:** 1 November 2026
**How statuses were assigned:**
* **PASS** — an automated test in the repo (run on 1 Nov 2026, all passing) or a direct check performed in this audit covers the scenario. The evidence column says which.
* **FAIL** — the defect is confirmed: by a live check, an emulator probe, or deterministic code (the required behaviour has no implementation).
* **NOT TESTED** — needs a device, a console or production config. The "Actual" column gives the code-analysis prediction where one exists.
* **BLOCKED** — cannot run until an external prerequisite exists.
* **NOT APPLICABLE**.

Severity is the severity *if the scenario fails* (P0–P3). Finding IDs refer to `PLAY_STORE_AUDIT_REPORT.md`.

**Recommended device matrix for the NOT TESTED rows:**

| Android | Device suggestion | Why |
|---|---|---|
| 12 | Xiaomi/Redmi (MIUI 13–14) | Aggressive background killing; historical test device class |
| 13 | Samsung One UI 5 | `POST_NOTIFICATIONS` runtime permission |
| 14 | Pixel or Oppo/Realme (ColorOS 14) | FGS types, exact-alarm changes, ColorOS battery restrictions |
| 15 | Pixel | Target 35+ behaviour, edge-to-edge, 16 KB pages |
| 16 | Pixel (or emulator) | targetSdk 36 behaviour |

---

## Authentication & session

| Test ID | Feature | Setup | Steps | Expected result | Actual result | Status | Severity |
|---|---|---|---|---|---|---|---|
| AUTH-01 | Google sign-in | Fresh install, online | Tap Continue with Google → pick account | Signed in; splash → home; profile doc created | — | NOT TESTED | P1 |
| AUTH-02 | Cancel sign-in | Fresh install | Open account picker → back | Stays on sign-in screen, no error | Handled in code (`canceled` → null) | NOT TESTED | P3 |
| AUTH-03 | Sign-in offline | Airplane mode | Tap Continue with Google | Friendly "Network error" | Mapped in `_friendlyAuthError` | NOT TESTED | P3 |
| AUTH-04 | Session restore | Signed in | Kill app → reopen | Lands on home, same UID, data present | — | NOT TESTED | P1 |
| AUTH-05 | **Sign-out persists across restart** | Signed in; app restarted at least once since sign-in | Settings → Sign out → kill → reopen | Sign-in screen; no automatic sign-in | Code predicts **silent re-sign-in** (P1-3) | NOT TESTED | P1 |
| AUTH-06 | Guest (anonymous) | Fresh install | Continue as guest → enter name | Local-only usage; no cloud sync | `isAuthenticated` false for anonymous (code) | NOT TESTED | P2 |
| AUTH-07 | Guest sign-out | Guest with data | Settings → Delete and sign out | Data wiped; warning shown with Export option | Dialog text verified in code | NOT TESTED | P2 |
| AUTH-08 | Re-auth before deletion | Google user | Settings → Delete account → Continue | Google re-auth prompt; cancel aborts | — | NOT TESTED | P2 |
| AUTH-09 | Worker token expiry | Signed in > 1 h, AI screen open | Ask a question | Fresh token used, answer returned | Worker rejects expired tokens (Worker tests) | NOT TESTED | P2 |

## Authorization & UID isolation

| Test ID | Feature | Setup | Steps | Expected result | Actual result | Status | Severity |
|---|---|---|---|---|---|---|---|
| ISO-01 | Firestore owner isolation | Emulator | Bob reads/writes `users/alice/transactions` | Denied | `rules.test.js` | PASS | P0 |
| ISO-02 | Unauthenticated access | Emulator | Signed-out read | Denied | `rules.test.js` | PASS | P0 |
| ISO-03 | Default deny | Emulator | Write to unknown top-level path | Denied | `rules.test.js` | PASS | P0 |
| ISO-04 | Provider data cleared on account switch | Unit | Sign out A → sign in B | No A data in providers/SQLite | `account_isolation_regression_test` | PASS | P0 |
| ISO-05 | Stale snapshot after switch | Unit | Deliver A snapshot after B session | Discarded | Session-generation guards (`account_isolation_regression_test`) | PASS | P0 |
| ISO-06 | Sync queue scoped by UID | Unit | Pending A rows, B signs in | B never uploads A rows | `getPendingSyncActions(uid)` (`transaction_sync_test`) | PASS | P0 |
| ISO-07 | RevenueCat identity reset | Device | Premium A signs out, free B signs in | B is not premium | `logOut()` + UID-bound cache (code) | NOT TESTED | P1 |
| ISO-08 | Shared device, A signs out, B opens app | Device | A signs out → hand phone to B → reopen | Sign-in screen | Predicted: A auto-signed back in (P1-3) | NOT TESTED | P1 |
| ISO-09 | Spend Pause per account | Unit | Switch users | Pause state not shared | `spend_pause_account_isolation_test` | PASS | P2 |

## Offline availability & sync

| Test ID | Feature | Setup | Steps | Expected result | Actual result | Status | Severity |
|---|---|---|---|---|---|---|---|
| OFF-01 | Launch offline | Signed in with data, airplane mode | Cold start | Dashboard + history load from SQLite | Local-first load (code) | NOT TESTED | P1 |
| OFF-02 | Add offline | Airplane mode | Add expense | Saved, sync chip pending | `transaction_sync_test` | PASS | P1 |
| OFF-03 | Edit offline | Airplane mode | Edit amount | Saved locally, queued | `transaction_sync_test` | PASS | P1 |
| OFF-04 | Delete offline | Airplane mode | Delete | Removed locally; delete queued | `transaction_sync_test`, `sms_resurrection_fix_test` | PASS | P1 |
| OFF-05 | Reconnect drains queue | OFF-02..04 | Turn network on | All changes in Firestore, chip "synced" | — | NOT TESTED | P1 |
| OFF-06 | Kill with pending sync | OFF-02 | Force-stop → reopen online | Pending change uploaded | Queue is persistent (code) | NOT TESTED | P1 |
| OFF-07 | **Sign out with pending changes** | Airplane mode, add 3 txns | Sign out → sign in online | Warned, or all 3 present | Queue wiped without warning (P1-4) | FAIL | P1 |
| OFF-08 | Edit vs edit (two devices) | Two devices | Edit same txn on both | Newest edit wins on both | `distributed_lww_regression_test` (client clocks) | PASS | P2 |
| OFF-09 | **Offline edit vs remote delete** | Device A offline edits X; device B deletes X | A reconnects and opens app | X stays deleted (delete wins) | Startup race can resurrect X and delete the tombstone (P2-4) | NOT TESTED | P2 |
| OFF-10 | Clock skew | Device A clock +2 h | Edit on B after A | B's later edit wins | LWW uses client clocks; A wins | NOT TESTED | P3 |
| OFF-11 | New-device restore > 1 000 txns | Account with 2 500 txns | Install on second device, sign in | All 2 500 restored | Paginated `fetchAllTransactions` implemented (code); `transaction_sync_test` covers the provider merge with a **fake** service only. Real Firestore pagination is untested. | NOT TESTED | P1 |
| OFF-12 | Restore interrupted | 2 500 txns, drop network mid-restore | Observe | "Restore incomplete" + resume | Partial list marked synced until next launch (P2-12) | NOT TESTED | P2 |
| OFF-13 | Permission-denied from Firestore | App Check enforced, token failure | Add txn | Retried later | Action dropped as permanent (P2-5) | NOT TESTED | P2 |

## Database migrations

| Test ID | Feature | Setup | Steps | Expected result | Actual result | Status | Severity |
|---|---|---|---|---|---|---|---|
| MIG-01 | Ladder v1→v22 | Unit | Upgrade from old schemas | Data preserved | `database_migration_test` | PASS | P1 |
| MIG-02 | v15/v16/v17/v18/v20/v21 | Unit | Focused migrations | Pass | `database_migration_v1x/v2x_test` | PASS | P1 |
| MIG-03 | v19, v22 focused | Unit | Upgrade with orphan categories | Category IDs repaired | Covered only by ladder test | NOT TESTED | P2 |
| MIG-04 | Upgrade install over 1.0.0 on device | Device with prior Play build | Install 1.0.1 | Data intact, encrypted | — | BLOCKED (needs prior build) | P1 |
| MIG-05 | Legacy plaintext DB → SQLCipher | Device with plaintext DB | Upgrade | Encrypted in place, data intact | Code path exists; not exercised | NOT TESTED | P1 |
| MIG-06 | Wrong/missing key | Clear secure-storage prefs only | Launch | Recovery screen, no silent wipe | `security_test` / key logic | PASS | P0 |

## SMS ingestion

| Test ID | Feature | Setup | Steps | Expected result | Actual result | Status | Severity |
|---|---|---|---|---|---|---|---|
| SMS-01 | Disclosure before permission | Fresh install | Open SMS setup | Disclosure screen, then the system prompt | Screen present (code) | NOT TESTED | P0 |
| SMS-02 | Deny permission | — | Deny | App fully usable, manual entry works | — | NOT TESTED | P1 |
| SMS-03 | Permanently denied | — | Deny twice | Dialog → Open settings | Code present | NOT TESTED | P2 |
| SMS-04 | Live bank SMS (app open) | Permission granted | Send test bank SMS (emulator `adb emu sms send`) | Imported once | — | NOT TESTED | P1 |
| SMS-05 | Bank SMS with app killed | Swipe app away | Send bank SMS | Imported within ~1 min (expedited work) | `BackgroundEnginePluginTest.kt`, `native_sms_reader_missing_plugin_test` | NOT TESTED (device) | P1 |
| SMS-06 | After reboot | Reboot | Send bank SMS | Imported | — | NOT TESTED | P1 |
| SMS-07 | Personal SMS ignored | — | SMS from +91 number with "Rs 500 sent" | Not processed | Native filter (`SmsBroadcastReceiverTest.kt`) | PASS (unit) | P0 |
| SMS-08 | OTP / promo ignored | — | Bank OTP, promo with ₹ | Rejected, text not stored | Parser negative-filter tests | PASS | P1 |
| SMS-09 | Duplicate broadcast | — | Same SMS delivered twice | One transaction | `sms_concurrency_stress_test` | PASS | P1 |
| SMS-10 | Broadcast + inbox scan overlap | — | Receive, then reconciliation | One transaction | `sms_concurrency_stress_test`, `watermark_reliability_stress_test` | PASS | P1 |
| SMS-11 | **SMS + notification, ref only on SMS** | — | GPay notification (no ref) + bank SMS with UPI ref | One transaction | Different identity keys → duplicate (P2-9) | NOT TESTED | P2 |
| SMS-12 | **Bucket boundary** | — | Notification 10:14:50, SMS 10:15:10, same payment, no ref | One transaction | Different 15-min buckets → duplicate (P2-9) | NOT TESTED | P2 |
| SMS-13 | **Two genuine identical payments** | — | Two ₹20 payments to the same merchant, 3 min apart, no ref | Two transactions | Same fingerprint → second collapsed (P2-9) | NOT TESTED | P2 |
| SMS-14 | Credit-card spend + bill payment | — | Card spend SMS ×3, then card bill payment SMS | Spends counted once | No transfer model → double counted (P2-10) | NOT TESTED | P2 |
| SMS-15 | Self-transfer | — | Debit from bank A, credit to own bank B | Not income + expense | Counted as both (P2-10) | NOT TESTED | P2 |
| SMS-16 | Refund / reversal / failed | — | Refund SMS, failed-txn SMS | Refund as credit; failed ignored | Parser tests (`sms_parser_test`, `sms_transaction_parser_test`) | PASS | P1 |
| SMS-17 | Indian number formats | — | "Rs.1,23,456.78", "INR 99" | Parsed exactly | `amount_extractor` tests | PASS | P1 |
| SMS-18 | Pending Review flow | Uncertain SMS | Open review → accept as debit, edit, reject | Correct ledger effect, no dupes | `pending_review_detail_test`, ingestion tests | PASS | P1 |
| SMS-19 | **90-day text retention** | Promoted SMS older than 90 days | Run `purgeExpiredSensitiveData` | No masked text left anywhere | `sms_transactions.rawSmsBody` never purged (P1-2) | FAIL | P1 |
| SMS-20 | Large inbox performance | 20 000 SMS inbox, low-end device | First scan | No ANR; progress shown | Reads on main thread (P2-11) | NOT TESTED | P2 |
| SMS-21 | Parser accuracy on real corpus | Labelled corpus ≥500 SMS across top 15 banks | Batch parse | Precision ≥98% auto-imports; recall reported | Historical 1-device result only | NOT TESTED | P1 |

## Notification ingestion

| Test ID | Feature | Setup | Steps | Expected result | Actual result | Status | Severity |
|---|---|---|---|---|---|---|---|
| NOT-01 | Disclosure + settings hand-off | — | Enable notification import | Dialog → system settings | Code present | NOT TESTED | P1 |
| NOT-02 | Allow-listed payment notification | GPay installed | Make a payment | Imported once | — | NOT TESTED | P1 |
| NOT-03 | WhatsApp / chat ignored | — | Message containing "₹500 paid" | Ignored | Allow-list excludes messaging (code) | NOT TESTED | P0 |
| NOT-04 | Amazon Shopping promo | — | Promo notification "Get ₹100 cashback" | Ignored | Shopping app allow-listed; "cashback" passes verb filter (P3-4) | NOT TESTED | P3 |
| NOT-05 | App killed | Swipe away | Receive payment notification | Cached encrypted, imported by worker | `EncryptedNotificationCacheTest.kt`, concurrency test | NOT TESTED (device) | P1 |
| NOT-06 | Keystore failure | Unit | Encrypted prefs throw | RAM buffer only, never plaintext | `EncryptedNotificationCacheTest.kt` 9/9 (run 1 Nov 2026) | PASS | P1 |
| NOT-07 | Access revoked | Revoke in settings | Return to app | Banner / state updated, app works | `refreshNotificationAccess` on resume | NOT TESTED | P2 |

## Transactions, categories, budgets, recurring

| Test ID | Feature | Setup | Steps | Expected result | Actual result | Status | Severity |
|---|---|---|---|---|---|---|---|
| TXN-01 | Invalid amount | — | Enter 0 / negative / NaN | Rejected | `ArgumentError` guard + rules | PASS | P2 |
| TXN-02 | Totals consistency | — | Compare dashboard vs history totals | Equal | Aggregate tests | PASS | P1 |
| TXN-03 | Filters & search | — | Date, type, amount filters | Correct rows | `transaction_filter_test` | PASS | P3 |
| CAT-01 | Orphan category IDs | Legacy data | Migrate | Valid category IDs | `category_mapper_ids_test`, v20–v22 tests | PASS | P2 |
| BUD-01 | Budget utilisation & alerts | Budget ₹1 000 | Spend ₹800, ₹1 100 | 80% alert, overspend alert, once each | `alert_evaluator_test`, adversarial alerts tests | PASS | P2 |
| BUD-02 | Zero / huge budget | — | ₹0, ₹1e9 | No crash; sensible % | Adversarial tests | PASS | P3 |
| REC-01 | Recurrence math | Unit | Month-end, leap year, year rollover | Correct dates | `recurrence_calculator_test` (×2) | PASS | P2 |
| REC-02 | No duplicate generation | Unit | Concurrent generation | One occurrence | `recurring_concurrency_idempotency_test` | PASS | P1 |

## Premium modules

| Test ID | Feature | Setup | Steps | Expected result | Actual result | Status | Severity |
|---|---|---|---|---|---|---|---|
| CF-01 | Forecast without balance | Premium, no balance | Open Cash Flow | "Balance unknown", no invented balance | `cashflow_*` tests | PASS | P1 |
| CF-02 | Forecast correctness | Unit | Bills, sparse history, negative balance, month/leap boundaries | Matches spec | `cashflow_engine_correctness_test`, `cashflow_surgical_remediation_test` | PASS | P1 |
| CF-03 | Salary timing | Monthly salary on the 1st | 30-day forecast on the 25th | Dip before payday | Income spread evenly (P3-12) | NOT TESTED | P3 |
| BILL-01 | Detection thresholds | Unit | ≥3 occurrences, ≥₹30 | Detected with confidence | `recurring_detection_service_test` | PASS | P2 |
| BILL-02 | No double count in forecast | Unit | Confirmed bill + history | Counted once | `cashflow_recurring_integration_test` | PASS | P1 |
| GOAL-01 | Goals CRUD & atomicity | Unit | Contribute / edit / delete | Consistent | `goal_provider_test`, atomicity tests | PASS | P2 |
| ALRT-01 | Duplicate alert suppression | Unit | Re-evaluate same event | One alert | `adversarial_alerts_audit_test` | PASS | P2 |
| TAX-01 | Caps applied | Unit | 80C ₹2L tagged | Claimable ₹1.5L | `tax_provider_test` | PASS | P2 |
| TAX-02 | Old-regime slab choices | — | Choose 10%/15% | Only 5/20/30% offered for old regime | Offered (P3-3) | FAIL | P3 |
| TAX-03 | Disclaimer visible | — | Open Tax buckets | "Indicative… consult a CA" | Present (`tax_buckets_screen.dart:335`) | PASS | P2 |
| WEEK-01 | Week spanning months/years | Unit | Week Dec 29–Jan 4 | Correct totals | `weekly_planner_*` tests | PASS | P2 |
| FOCUS-01 | Focus mode flags, never blocks | Unit | Purchase in focus category | Flagged; still recorded | `spend_pause_*` tests | PASS | P2 |

## AI Copilot

| Test ID | Feature | Setup | Steps | Expected result | Actual result | Status | Severity |
|---|---|---|---|---|---|---|---|
| AI-01 | Consent before first use | — | Open Copilot, send | Consent dialog; cancel sends nothing | Code present | NOT TESTED | P1 |
| AI-02 | **Consent/policy lists all data sent** | Balance entered | Inspect request payload | Every field disclosed | Bank balance sent but not disclosed (P1-1a) | FAIL | P1 |
| AI-03 | Free quota 3/month | Worker unit | 4 requests | 4th → `FREE_QUOTA_EXHAUSTED` | Worker tests | PASS | P2 |
| AI-04 | Failed calls don't consume quota | Worker unit | Upstream 500 | Count unchanged | Worker tests | PASS | P2 |
| AI-05 | Guests blocked | Worker unit | Anonymous token | `SIGN_IN_REQUIRED` | Worker tests | PASS | P2 |
| AI-06 | Concurrent requests vs quota | Staging Worker | 10 parallel requests as a free user | ≤3 answered | Non-atomic KV (P2-3) | NOT TESTED | P2 |
| AI-07 | App Check enforced | Staging | Call Worker with a valid ID token, no App Check | 401 | `REQUIRE_APP_CHECK="false"` (P2-2) | FAIL (config) | P2 |
| AI-08 | Forged/expired/wrong-aud token | Worker unit | Bad tokens | 401 | Worker tests | PASS | P0 |
| AI-09 | Prompt structure abuse | Worker unit | System msg at index>0, >20 msgs, >5 000 chars | 400 | Worker tests | PASS | P2 |
| AI-10 | Report an answer | Device | Long-press → report | Stored in `ai_reports` | Rules test (`ai_reports`) | PASS (rules) / NOT TESTED (UI) | P1 |
| AI-11 | Numeric accuracy | Golden set of 30 questions | Compare answers with app totals | No invented figures | — | NOT TESTED | P2 |

## RevenueCat / purchases

| Test ID | Feature | Setup | Steps | Expected result | Actual result | Status | Severity |
|---|---|---|---|---|---|---|---|
| RC-01 | Release key guard | Unit | Release build with `test_`/`sk_`/empty key | Throws | `revenuecat_environment_config_test` | PASS | P0 |
| RC-02 | Debug override not in release | Unit | Release flags | Override false | `developer_premium_override_test` | PASS | P0 |
| RC-03 | Offerings load | License tester, internal track | Open paywall | Monthly/annual/lifetime with Play prices | — | BLOCKED (Play products) | P1 |
| RC-04 | Purchase (license tester) | Internal track | Buy monthly | Premium unlocks immediately | — | BLOCKED | P0 |
| RC-05 | Restore | Reinstall | Restore purchases | Premium restored | — | BLOCKED | P1 |
| RC-06 | Cancel / expire | Test sub (5-min renewals) | Cancel; wait for expiry | Premium removed (≤5 min server, next refresh client) | — | BLOCKED | P1 |
| RC-07 | Refund | Refund in Play Console | — | Premium removed | — | BLOCKED | P1 |
| RC-08 | Grace period / billing retry | Test card "declined" | — | Premium kept during grace | Worker `expires_date` semantics unverified (P3-13) | BLOCKED | P2 |
| RC-09 | Pending UPI payment | Test "slow" card | Purchase | "Payment pending" | Shows "Purchase failed" (P3-6) | NOT TESTED | P3 |
| RC-10 | Double-tap purchase | — | Tap Subscribe twice | One flow | `_isLoading` guard (code) | NOT TESTED | P3 |

## Household & referral

| Test ID | Feature | Setup | Steps | Expected result | Actual result | Status | Severity |
|---|---|---|---|---|---|---|---|
| HH-01 | Only members read | Emulator | Outsider reads household | Denied | `rules.test.js` | PASS | P0 |
| HH-02 | Join only with a valid invite | Emulator | Join without / with an expired code | Denied | `rules.test.js` | PASS | P1 |
| HH-03 | Max 6 members | Emulator | 7th join | Denied | Rule `memberUids.size() <= 6` present (`firestore.rules:193`); no rules test covers it | NOT TESTED | P2 |
| HH-04 | **Free/guest cannot create** | Emulator | Anonymous user creates household | Denied | **Allowed** (audit probe) (P2-1) | FAIL | P2 |
| HH-05 | **Removed member stays removed** | Emulator | Owner removes Bob; Bob re-joins with the same valid code | Denied | **Allowed** (audit probe) (P2-1) | FAIL | P2 |
| HH-06 | Only own totals published | Emulator | Bob writes Alice's spending doc | Denied | `rules.test.js` | PASS | P1 |
| HH-07 | Aggregates only shared | Device | Inspect shared screen | No transactions or merchants | Data model has totals only | NOT TESTED | P1 |
| REF-01 | Redeem once, both rewarded | Worker unit | Redeem | Both get a month; second redeem fails | Worker tests | PASS | P2 |
| REF-02 | Own code / guest / old user | Worker unit | Redeem | Rejected | Worker tests | PASS | P2 |
| REF-03 | **Delete + recreate redeemer** | Staging | B redeems A's code → B deletes account → B signs in again → redeems | Rejected | Expected allowed (P1-5) | NOT TESTED | P1 |
| REF-04 | Parallel redeem | Staging | 5 parallel redeem calls | One grant | Non-atomic KV (P1-5) | NOT TESTED | P2 |

## Widget, recap, export

| Test ID | Feature | Setup | Steps | Expected result | Actual result | Status | Severity |
|---|---|---|---|---|---|---|---|
| WID-01 | Widget amounts | Add widget | Import a txn | Today's spend updates | — | NOT TESTED | P3 |
| WID-02 | Widget hides amounts with lock | App Lock on | View widget | 🔒, no amounts | `SpendWidgetStateTest.kt` 6/6 (unit); not checked on a launcher | PASS (unit) | P2 |
| WID-03 | Midnight rollover | — | Next day without opening app | "Spent today" resets | `SpendWidgetStateTest.kt` (unit) | PASS (unit) | P3 |
| WRAP-01 | Money Wrap share card hides amounts by default | — | Share | No amounts unless toggled | — | NOT TESTED | P2 |
| EXP-01 | CSV formula injection | Unit | Merchant `=HYPERLINK(...)` | Prefixed with `'` | `csv_injection_test` | PASS | P2 |
| EXP-02 | Export correctness & temp cleanup | Unit/device | Export CSV/PDF | Correct rows; temp file deleted after share | `export_service_test` | PASS | P3 |

## Account deletion

| Test ID | Feature | Setup | Steps | Expected result | Actual result | Status | Severity |
|---|---|---|---|---|---|---|---|
| DEL-01 | Full deletion | Account with data, household owner, referral code | Delete account | All Firestore docs, household, Worker records, Auth user, local data gone | `account_deletion_test` (mocked) | PASS (unit) / NOT TESTED (real) | P0 |
| DEL-02 | Deletion offline | Airplane mode | Delete | Clear "needs internet" message | Hangs on `batch.commit()` (P2-6) | NOT TESTED | P2 |
| DEL-03 | **Network loss mid-deletion** | Drop network after step 1 | Retry / reopen app | Resumes or can be cancelled | Stuck in deletion mode (P2-6) | NOT TESTED | P2 |
| DEL-04 | Worker forget fails | Worker down | Delete | Not reported as complete | Reported as complete (P2-6) | FAIL (code) | P2 |
| DEL-05 | RevenueCat customer | After deletion | Check RevenueCat dashboard | Customer deleted or retention disclosed | Only `logOut()` | FAIL (code) | P2 |
| DEL-06 | Web deletion page | Browser | Open URL, submit form | Page loads; request recorded; developer alerted | **404 Site Not Found** (P0-1) | FAIL | P0 |

## Android permissions, privacy, platform

| Test ID | Feature | Setup | Steps | Expected result | Actual result | Status | Severity |
|---|---|---|---|---|---|---|---|
| PERM-01 | Merged manifest permissions | Release AAB | Inspect | Only expected permissions | Adds `FOREGROUND_SERVICE` + `_SHORT_SERVICE` (WorkManager), `BILLING`, `WAKE_LOCK`, `VIBRATE`, `USE_FINGERPRINT`; no `AD_ID` | PASS (with note) | P3 |
| PERM-02 | `POST_NOTIFICATIONS` (13+) | Android 13+ | Fresh install | Requested in context; app works if denied | Banner + request code | NOT TESTED | P2 |
| PERM-03 | Exported components protected | Release manifest | Inspect | Only launcher/system-bound exported | Verified (§L of report) | PASS | P0 |
| PRIV-01 | Legal URLs reachable | Browser | Open privacy, terms, deletion | HTTP 200 | **404** (P0-1) | FAIL | P0 |
| PRIV-02 | Analytics opt-in | Fresh install | Decline consent | No GA events | `analytics_service_test` | PASS | P1 |
| PRIV-03 | Sign-out removes all local data | Debug build | Sign out → `run-as` list files | No user data files | Firestore cache remains (P2-8) | NOT TESTED | P2 |
| PRIV-04 | D2D transfer | Two Android 12+ devices | Device-to-device setup | Clean first launch, no DB copied | Rules mis-targeted (P2-7) | NOT TESTED | P2 |
| PRIV-05 | Lock-screen notifications private | Device | Receive transaction notification on lock screen | Content hidden | `NotificationVisibility.private` | NOT TESTED | P2 |
| PRIV-06 | Recents thumbnail | App Lock off | Open Recents | (Recommendation) blurred | Visible unless App Lock on (P3-5) | NOT TESTED | P3 |
| PRIV-07 | Release logs | Release build | `adb logcat` during SMS import | No PII | `SafeLog`, R8 strip, logging guard script | PASS (static) | P1 |
| SEC-01 | Secrets in history | Repo | Scan all refs | None | **Gemini key found** (P0-2) | FAIL | P0 |
| SEC-02 | Rules schema validation | Emulator | Arbitrary fields / 900 KB docs | Rejected | Accepted (P2-1) | FAIL | P2 |
| PLAT-01 | 16 KB page size | Release AAB | `llvm-readelf -l` | LOAD align ≥ 0x4000 | All 64-bit libs ≥ 0x4000 | PASS | P0 |
| PLAT-02 | Target API | Release manifest | Inspect | targetSdk 36 | 36 | PASS | P0 |
| PLAT-03 | Release not debuggable | Release manifest | Inspect | No `debuggable=true` | Not present | PASS | P0 |

## Accessibility & localisation

| Test ID | Feature | Setup | Steps | Expected result | Actual result | Status | Severity |
|---|---|---|---|---|---|---|---|
| A11Y-01 | TalkBack labels | TalkBack on | Navigate dashboard, add txn | All controls labelled | `semantic_wrapper` exists; not audited | NOT TESTED | P2 |
| A11Y-02 | Font scale 200% | Settings | Open key screens | No overflow | — | NOT TESTED | P3 |
| A11Y-03 | Lock screen hides content from TalkBack | App Lock on | TalkBack on lock overlay | Underlying content excluded | `ExcludeSemantics` (code) | NOT TESTED | P2 |
| L10N-01 | ARB parity | Unit | en vs hi keys | Same keys | `arb_parity_test` | PASS | P3 |
| L10N-02 | Hindi coverage | Hindi selected | Walk all screens | All text Hindi | ≥217 hard-coded English strings (P3-2) | FAIL | P3 |
