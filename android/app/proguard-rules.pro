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

# SQLCipher (database encryption). sqflite_sqlcipher 3.x uses
# net.zetetic:sqlcipher-android, whose classes are reached from JNI.
-keep class net.zetetic.database.** { *; }
-dontwarn net.zetetic.database.**

# Keep custom Application class
-keep class com.pet.tracker.pet.** { *; }

# Don't strip Gson/JSON annotations (used by Firebase)
-keepattributes Signature
-keepattributes *Annotation*
-keepattributes EnclosingMethod
-keepattributes InnerClasses

# ─── Investment-Grade Privacy: Complete Logcat Elimination ───────────────────
# Strip ALL android.util.Log and io.flutter.Log method calls unconditionally
# from release APKs. Zero log statements or exception traces reach Android Logcat.
-assumenosideeffects class android.util.Log {
    public static *** d(...);
    public static *** v(...);
    public static *** i(...);
    public static *** w(...);
    public static *** e(...);
    public static *** println(...);
}

-assumenosideeffects class io.flutter.Log {
    public static *** d(...);
    public static *** v(...);
    public static *** i(...);
    public static *** w(...);
    public static *** e(...);
    public static *** println(...);
}
