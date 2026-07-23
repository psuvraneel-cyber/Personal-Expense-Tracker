# ─────────────────────────────────────────────────────────────
# P.E.T — ProGuard / R8 Rules for Release Builds
# ─────────────────────────────────────────────────────────────

# Firebase
-keep class com.google.firebase.** { *; }
-keep class com.google.android.gms.** { *; }
-dontwarn com.google.firebase.**
-dontwarn com.google.android.gms.**

# Google Sign-In
-keep class com.google.android.gms.auth.** { *; }
-keep class com.google.android.gms.common.** { *; }

# Crypto (SHA-256 hashing used in SMS dedup)
-keep class org.bouncycastle.** { *; }
-dontwarn org.bouncycastle.**

# Flutter engine
-keep class io.flutter.** { *; }
-keep class io.flutter.plugins.** { *; }
-dontwarn io.flutter.embedding.**

# Local Auth (biometric)
-keep class androidx.biometric.** { *; }

# SQLCipher (database encryption)
-keep class net.sqlcipher.** { *; }
-keep class net.sqlcipher.database.** { *; }
-dontwarn net.sqlcipher.**

# Keep custom Application class
-keep class com.pet.tracker.pet.** { *; }

# Don't strip Gson/JSON annotations (used by Firebase)
-keepattributes Signature
-keepattributes *Annotation*
-keepattributes EnclosingMethod
-keepattributes InnerClasses

# ─── Privacy: Strip debug/verbose logs from release builds ───────────────────
# android.util.Log.d() and Log.v() output is visible via adb logcat even in
# release builds. Since our native plugins log financial notification content
# (TransactionNotificationListener) and SMS counts (SmsReaderPlugin), we strip
# all debug/verbose log calls unconditionally in release.
# Log.w() and Log.e() are intentionally kept for diagnostics.
-assumenosideeffects class android.util.Log {
    public static int d(...);
    public static int v(...);
}
