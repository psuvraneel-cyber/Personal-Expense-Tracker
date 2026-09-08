# Production Launch Baseline Status

**Application:** P.E.T. — Personal Expense Tracker  
**Date:** August 24, 2026  
**Commit:** `3eec7a98b46b4357ff1a5515f6f2042c544da0bb`  
**Branch:** `main`

---

## 1. Environment & Toolchain

- **Flutter SDK:** `3.41.6` (Channel stable, Framework revision `db50e20168`)
- **Dart SDK:** `3.11.4` (Tools / DevTools `2.54.2`)
- **Android Gradle Plugin (AGP):** `8.11.1` (`android/settings.gradle.kts`)
- **Gradle Wrapper:** `8.14` (`android/gradle/wrapper/gradle-wrapper.properties`)
- **Kotlin Version:** `2.2.20` (`android/settings.gradle.kts`)
- **Java Compatibility:** `JavaVersion.VERSION_17` (Core library desugaring enabled: `desugar_jdk_libs:2.1.4`)
- **Android SDK:**
  - `compileSdk`: `36`
  - `targetSdk`: `35` (Baseline)
  - `minSdk`: `21` (Android 5.0 Lollipop)

---

## 2. Test Suite Baseline

- **Total Test Files:** 42 test files in `test/`
- **Total Tests Executed:** **420 tests**
- **Test Result:** **420 / 420 Passed (100% Pass Rate)**
- **Execution Time:** ~111 seconds (including massive 15,000-message concurrent SMS stress tests)
- **Known Test Failures:** `0`

---

## 3. Static Analysis Baseline (`flutter analyze`)

- **Errors:** `0`
- **Warnings:** `3`
  1. `lib/services/reconciliation_service.dart:276:8` — `warning: The declaration '_advanceWatermark' isn't referenced`
  2. `lib/services/sms_service.dart:27:23` — `warning: The value of the field '_kLastProcessedTimestamp' isn't used`
  3. `test/services/sms_concurrency_stress_test.dart:545:13` — `warning: The value of the local variable 'successCount' isn't used`
- **Info Lints:** `7` (Print calls in test harness)

---

## 4. Release Build Status

- **Android Signing Configuration:** Configured in `android/app/build.gradle.kts` via `key.properties` resolution.
- **R8 / Minification:** `isMinifyEnabled = true`, `isShrinkResources = true`, `proguard-rules.pro` active.
- **Git Tracking:** `android/app/key.properties` is ignored by `.gitignore` and untracked.
