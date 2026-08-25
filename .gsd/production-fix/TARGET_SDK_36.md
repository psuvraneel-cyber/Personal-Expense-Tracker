# Target SDK 36 (Android 16) Migration & Compatibility Verification

**Application:** P.E.T. — Personal Expense Tracker  
**Date:** August 24, 2026  
**Status:** **COMPLIANT & VERIFIED**  

---

## 1. Toolchain & SDK Configuration

- **`compileSdk`:** `36` (Android 16)
- **`targetSdk`:** `36` (Android 16)
- **`minSdk`:** `21` (Android 5.0 Lollipop)
- **Gradle Version:** `8.14`
- **Android Gradle Plugin (AGP):** `8.11.1`
- **Kotlin Version:** `2.2.20`
- **Java Compatibility:** `JavaVersion.VERSION_17` (with Java desugaring enabled via `desugar_jdk_libs:2.1.4`)

---

## 2. Android 16 (API 36) Compatibility & Invariant Checks

| Component / Subsystem | Android 16 Requirement | P.E.T. Implementation | Status |
| :--- | :--- | :--- | :--- |
| **Foreground Services** | Typed foreground services required (`dataSync`) | `SystemForegroundService` in `AndroidManifest.xml` declared with `android:foregroundServiceType="dataSync"`. | **PASS** |
| **Broadcast Receivers** | Manifest receiver restrictions & export flags | `SmsBroadcastReceiver` protected with signature permission `android.permission.BROADCAST_SMS`. Runtime receiver in `SmsReaderPlugin.kt` uses `RECEIVER_NOT_EXPORTED` on API 33+. | **PASS** |
| **Notification Listener** | System service binding permission | `TransactionNotificationListener` bound with `android.permission.BIND_NOTIFICATION_LISTENER_SERVICE`. | **PASS** |
| **Exact Alarms & Reminders** | `POST_NOTIFICATIONS` + `SCHEDULE_EXACT_ALARM` | Uses `flutter_local_notifications` 18.0.1+ with runtime permission checks and `RECEIVE_BOOT_COMPLETED` for reminder re-arming. | **PASS** |
| **Edge-to-Edge Display** | Default edge-to-edge enforcement on Android 15/16 | Handled by Flutter 3.41+ framework engine with `adjustResize` and window insets padding. | **PASS** |
| **Scoped Storage & Backups** | Data extraction rules for Android 12+ | `dataExtractionRules="@xml/backup_rules"` and `fullBackupContent="@xml/backup_rules_legacy"` explicitly exclude SQLite database, WAL, and sensitive storage. | **PASS** |
| **Biometrics** | Modern BiometricPrompt API | Uses `local_auth` 2.3.0 (`USE_BIOMETRIC` / `USE_FINGERPRINT`). | **PASS** |
| **SQLCipher & Keystore** | AES-256 GCM MasterKey hardware backing | `EncryptedNotificationCache` & `sqflite_sqlcipher` with Jetpack Security Crypto 1.1.0-alpha06. | **PASS** |

---

## 3. Play Policy Deadline Verification

- **Google Play Requirement:** New apps and updates targeting API 36 starting August 31, 2026.
- **P.E.T. Status:** Updated and ready for August 2026 Play Store submission.
