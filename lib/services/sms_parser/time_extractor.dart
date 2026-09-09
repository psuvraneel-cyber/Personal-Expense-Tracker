/// Time extraction module — extracts transaction time from SMS body text.
///
/// Indian bank SMS often embed timestamps in various formats:
/// - `(2026:02:13 01:45:36)` — BOB colon-separated with parentheses
/// - `at 14:30` — time after "at" keyword
/// - `HH:MM:SS` — standalone 24-hour format
/// - `HH:MM` — standalone without seconds
/// - `hh:mm AM/PM` — 12-hour format
///
/// The extractor tries patterns in order of specificity, returning the
/// first successful match. If no time is found, returns a null time —
/// the caller can then fall back to the SMS OS timestamp's time component.
///
/// SECURITY: Pure function, no side effects, no external calls.
library;

/// Result of time extraction from an SMS body.
class TimeResult {
  /// Extracted hour (0–23), or null if no time found.
  final int? hour;

  /// Extracted minute (0–59), or null if no time found.
  final int? minute;

  /// Extracted second (0–59), or null if no time found.
  final int? second;

  /// Whether a time was successfully extracted.
  bool get hasTime => hour != null && minute != null;

  /// Reasons explaining the extraction decision.
  final List<String> reasons;

  const TimeResult({
    this.hour,
    this.minute,
    this.second,
    required this.reasons,
  });

  const TimeResult.none()
      : hour = null,
        minute = null,
        second = null,
        reasons = const ['No time found in SMS body'];

  @override
  String toString() {
    if (!hasTime) return 'TimeResult.none';
    final h = hour.toString().padLeft(2, '0');
    final m = minute.toString().padLeft(2, '0');
    final s = (second ?? 0).toString().padLeft(2, '0');
    return 'TimeResult($h:$m:$s)';
  }
}

/// Extracts transaction time from SMS body text.
///
/// Usage:
/// ```dart
/// final time = TimeExtractor.extract(smsBody);
/// if (time.hasTime) {
///   // Use time.hour, time.minute, time.second
/// }
/// ```
class TimeExtractor {
  TimeExtractor._();

  // ═══════════════════════════════════════════════════════════════════
  //  REGEX PATTERNS — ordered by specificity (most specific first)
  // ═══════════════════════════════════════════════════════════════════

  /// Pattern 1: Parenthesized datetime — BOB format
  /// `(2026:02:13 01:45:36)` or `(13-02-26 14:30)`
  static final RegExp _parenthesizedDateTime = RegExp(
    r'\(\s*'
    r'(?:\d{4}[:\-/]\d{2}[:\-/]\d{2}|\d{2}[:\-/]\d{2}[:\-/]\d{2,4})'
    r'\s+'
    r'(\d{1,2}):(\d{2})(?::(\d{2}))?'
    r'\s*\)',
  );

  /// Pattern 2: "at HH:MM:SS" or "at HH:MM"
  static final RegExp _atTimePattern = RegExp(
    r'\bat\s+(\d{1,2}):(\d{2})(?::(\d{2}))?\b',
    caseSensitive: false,
  );

  /// Pattern 3: 12-hour format with AM/PM
  /// `2:30 PM`, `11:45 am`, `12:00 AM`
  static final RegExp _amPmPattern = RegExp(
    r'\b(\d{1,2}):(\d{2})(?::(\d{2}))?\s*(am|pm)\b',
    caseSensitive: false,
  );

  /// Pattern 4: Standalone HH:MM:SS (24-hour)
  /// Must be preceded by space/start and followed by space/end/punctuation.
  /// Excludes date-like patterns (where colons separate date components).
  static final RegExp _hhmmssPattern = RegExp(
    r'(?:^|[\s,;])'
    r'(\d{1,2}):(\d{2}):(\d{2})'
    r'(?=$|[\s,;.)>\]])',
  );

  /// Pattern 5: Standalone HH:MM (24-hour)
  /// Same boundary rules. Using a negative lookbehind to avoid
  /// matching date separators like "13:02" in "13:02:26".
  static final RegExp _hhmmPattern = RegExp(
    r'(?:^|[\s,;])'
    r'(\d{1,2}):(\d{2})'
    r'(?=$|[\s,;.)>\]])'
    r'(?!:\d)',
  );

  // ═══════════════════════════════════════════════════════════════════
  //  MAIN EXTRACTION METHOD
  // ═══════════════════════════════════════════════════════════════════

  /// Extract time from an SMS body.
  ///
  /// Returns a [TimeResult] with the extracted time components.
  /// If no time is found, returns [TimeResult.none].
  static TimeResult extract(String body) {
    final reasons = <String>[];

    // Try Pattern 1: Parenthesized datetime (most specific — BOB)
    final p1 = _parenthesizedDateTime.firstMatch(body);
    if (p1 != null) {
      final h = int.tryParse(p1.group(1)!);
      final m = int.tryParse(p1.group(2)!);
      final s = p1.group(3) != null ? int.tryParse(p1.group(3)!) : 0;
      if (h != null && m != null && _isValidTime(h, m, s)) {
        reasons.add(
          'Time from parenthesized datetime: '
          '${h.toString().padLeft(2, "0")}:'
          '${m.toString().padLeft(2, "0")}:'
          '${(s ?? 0).toString().padLeft(2, "0")}',
        );
        return TimeResult(hour: h, minute: m, second: s, reasons: reasons);
      }
    }

    // Try Pattern 2: "at HH:MM(:SS)"
    final p2 = _atTimePattern.firstMatch(body);
    if (p2 != null) {
      final h = int.tryParse(p2.group(1)!);
      final m = int.tryParse(p2.group(2)!);
      final s = p2.group(3) != null ? int.tryParse(p2.group(3)!) : null;
      if (h != null && m != null && _isValidTime(h, m, s)) {
        reasons.add(
          'Time from "at HH:MM" pattern: '
          '${h.toString().padLeft(2, "0")}:'
          '${m.toString().padLeft(2, "0")}',
        );
        return TimeResult(hour: h, minute: m, second: s, reasons: reasons);
      }
    }

    // Try Pattern 3: 12-hour AM/PM
    final p3 = _amPmPattern.firstMatch(body);
    if (p3 != null) {
      var h = int.tryParse(p3.group(1)!);
      final m = int.tryParse(p3.group(2)!);
      final s = p3.group(3) != null ? int.tryParse(p3.group(3)!) : null;
      final isPm = p3.group(4)!.toLowerCase() == 'pm';

      if (h != null && m != null) {
        // Convert 12-hour to 24-hour
        if (isPm && h != 12) h += 12;
        if (!isPm && h == 12) h = 0;

        if (_isValidTime(h, m, s)) {
          reasons.add(
            'Time from AM/PM pattern: '
            '${h.toString().padLeft(2, "0")}:'
            '${m.toString().padLeft(2, "0")}',
          );
          return TimeResult(hour: h, minute: m, second: s, reasons: reasons);
        }
      }
    }

    // Try Pattern 4: Standalone HH:MM:SS
    final p4 = _hhmmssPattern.firstMatch(body);
    if (p4 != null) {
      final h = int.tryParse(p4.group(1)!);
      final m = int.tryParse(p4.group(2)!);
      final s = int.tryParse(p4.group(3)!);
      if (h != null && m != null && s != null && _isValidTime(h, m, s)) {
        reasons.add(
          'Time from HH:MM:SS pattern: '
          '${h.toString().padLeft(2, "0")}:'
          '${m.toString().padLeft(2, "0")}:'
          '${s.toString().padLeft(2, "0")}',
        );
        return TimeResult(hour: h, minute: m, second: s, reasons: reasons);
      }
    }

    // Try Pattern 5: Standalone HH:MM
    final p5 = _hhmmPattern.firstMatch(body);
    if (p5 != null) {
      final h = int.tryParse(p5.group(1)!);
      final m = int.tryParse(p5.group(2)!);
      if (h != null && m != null && _isValidTime(h, m, null)) {
        reasons.add(
          'Time from HH:MM pattern: '
          '${h.toString().padLeft(2, "0")}:'
          '${m.toString().padLeft(2, "0")}',
        );
        return TimeResult(hour: h, minute: m, second: null, reasons: reasons);
      }
    }

    return const TimeResult.none();
  }

  /// Validate time components are within valid ranges.
  static bool _isValidTime(int h, int m, int? s) {
    if (h < 0 || h > 23) return false;
    if (m < 0 || m > 59) return false;
    if (s != null && (s < 0 || s > 59)) return false;
    return true;
  }
}
