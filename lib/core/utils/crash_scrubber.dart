/// Removes financial and personal details from error messages before they
/// are sent to Crashlytics. Parsing code can throw with message fragments
/// (amounts, account or reference numbers, emails) in the exception text;
/// the type and stack trace are enough to fix the crash.
class CrashScrubber {
  CrashScrubber._();

  static final RegExp _amount = RegExp(
      r'(?:₹|\brs\.?|\binr\.?)\s?\d[\d,]*(?:\.\d+)?',
      caseSensitive: false);
  static final RegExp _email = RegExp(r'[\w.+-]+@[\w-]+(?:\.[\w-]+)+');
  static final RegExp _number = RegExp(r'\d[\d,.\-/]{2,}\d|\d{3,}');

  static String scrub(String text) => text
      .replaceAll(_amount, '<amount>')
      .replaceAll(_email, '<email>')
      .replaceAll(_number, '<n>');

  /// An error carrying the original type name and the scrubbed message.
  static Object scrubError(Object error) =>
      ScrubbedError(error.runtimeType.toString(), scrub(error.toString()));
}

class ScrubbedError implements Exception {
  ScrubbedError(this.type, this.message);

  final String type;
  final String message;

  @override
  String toString() => message.startsWith(type) ? message : '$type: $message';
}
