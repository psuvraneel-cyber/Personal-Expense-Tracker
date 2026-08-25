/// Centralised compile-time environment configuration.
///
/// Values are injected at build time via `--dart-define-from-file=.env`.
/// This replaces the old `flutter_dotenv` approach, which bundled the `.env`
/// file as a readable asset inside the APK — a critical security risk.
///
/// Usage:
///   ```
///   flutter run --dart-define-from-file=.env
///   flutter build apk --dart-define-from-file=.env
///   ```
class AppEnv {
  AppEnv._(); // non-instantiable

  // ── Groq AI Copilot ───────────────────────────────────────────────────────
  static const groqModel = String.fromEnvironment(
    'GROQ_MODEL',
    defaultValue: 'llama-3.3-70b-versatile',
  );

  // ── RevenueCat (Premium/IAP) ───────────────────────────────────────────────
  static const revenueCatGoogleApiKey = String.fromEnvironment(
    'REVENUECAT_GOOGLE_API_KEY',
  );
}
