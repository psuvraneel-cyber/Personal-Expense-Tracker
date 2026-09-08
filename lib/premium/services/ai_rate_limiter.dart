/// Result of a rate-limit check.
class RateLimitResult {
  final bool allowed;

  /// If not allowed, a human-readable reason why.
  final String? reason;

  /// Optional delay to apply before continuing (burst throttle).
  final Duration? burstDelay;

  const RateLimitResult.allowed({this.burstDelay})
    : allowed = true,
      reason = null;
  const RateLimitResult.denied(this.reason)
    : allowed = false,
      burstDelay = null;
}

/// In-process rate limiter implementing:
///
///   Per-user sliding window
///   • 10 requests / minute
///   • 50 requests / hour
///   • 200 requests / day
///
///   Burst control
///   • first 3 consecutive rapid messages → pass through
///   • 4th+ within 5 s → inject a 1.5 s delay (feels natural)
///
///   Global hard ceiling
///   • 2 000 requests / calendar day across the entire app instance
///
///   Duplicate suppression
///   • identical prompt within 10 s → return cached response instead of
///     burning a new request
class AiRateLimiter {
  // ── Per-user limits ────────────────────────────────────────────────────────
  static const int _maxPerMinute = 10;
  static const int _maxPerHour = 50;
  static const int _maxPerDay = 200;

  // ── Burst control ──────────────────────────────────────────────────────────
  static const int _burstThreshold = 3; // free rapid messages
  static const Duration _burstWindow = Duration(seconds: 5);
  static const Duration _burstDelay = Duration(milliseconds: 1500);

  // ── Global ceiling ────────────────────────────────────────────────────────
  static const int _globalMaxPerDay = 2000;

  // ── Duplicate suppression ─────────────────────────────────────────────────
  static const Duration _dupWindow = Duration(seconds: 10);

  // ── State ──────────────────────────────────────────────────────────────────
  final List<DateTime> _minuteBucket = [];
  final List<DateTime> _hourBucket = [];
  final List<DateTime> _dayBucket = [];

  // Shared across all AiRateLimiter instances (singleton via static).
  static int _globalDayCount = 0;
  static DateTime? _globalDayReset;

  // Burst tracking
  final List<DateTime> _burstBucket = [];

  // Duplicate cache  prompt → (timestamp, cachedReply)
  final Map<String, (DateTime, String)> _dupCache = {};

  // ── Public API ─────────────────────────────────────────────────────────────

  /// Call before sending a message.
  ///
  /// Returns [RateLimitResult.allowed] (possibly with a [burstDelay]) or
  /// [RateLimitResult.denied] with a human-readable [reason].
  RateLimitResult check(String prompt) {
    final now = DateTime.now();
    _evict(now);
    _refreshGlobalDay(now);

    // 1. Global ceiling
    if (_globalDayCount >= _globalMaxPerDay) {
      return const RateLimitResult.denied(
        'Daily AI limit reached. Insights resume tomorrow. 🌙',
      );
    }

    // 2. Per-user daily
    if (_dayBucket.length >= _maxPerDay) {
      return const RateLimitResult.denied(
        "You've used all $_maxPerDay daily AI messages. Come back tomorrow! 🔄",
      );
    }

    // 3. Per-user hourly
    if (_hourBucket.length >= _maxPerHour) {
      return const RateLimitResult.denied(
        "That's $_maxPerHour messages this hour — give it a few minutes. ⏳",
      );
    }

    // 4. Per-user per-minute
    if (_minuteBucket.length >= _maxPerMinute) {
      return const RateLimitResult.denied(
        "Slow down a bit! Max $_maxPerMinute messages per minute. ⚡",
      );
    }

    // 5. Burst control — inject delay on rapid-fire messages
    Duration? delay;
    _burstBucket.removeWhere((t) => now.difference(t) > _burstWindow);
    if (_burstBucket.length >= _burstThreshold) {
      delay = _burstDelay;
    }

    return RateLimitResult.allowed(burstDelay: delay);
  }

  /// Records a successful send (call AFTER [check] returns allowed).
  void record(String prompt) {
    final now = DateTime.now();
    _minuteBucket.add(now);
    _hourBucket.add(now);
    _dayBucket.add(now);
    _burstBucket.add(now);
    _globalDayCount++;
  }

  /// Returns a cached response for [prompt] if one exists within [_dupWindow],
  /// or null if there is no fresh cache entry.
  String? getCached(String prompt) {
    final entry = _dupCache[_normalise(prompt)];
    if (entry == null) return null;
    final (ts, reply) = entry;
    if (DateTime.now().difference(ts) > _dupWindow) {
      _dupCache.remove(_normalise(prompt));
      return null;
    }
    return reply;
  }

  /// Stores [reply] in the duplicate cache for [prompt].
  void cacheReply(String prompt, String reply) {
    _dupCache[_normalise(prompt)] = (DateTime.now(), reply);
    // Keep cache small — 20 entries max
    if (_dupCache.length > 20) {
      _dupCache.remove(_dupCache.keys.first);
    }
  }

  /// Returns a human-readable summary of remaining quota.
  String quotaSummary() {
    _evict(DateTime.now());
    final minLeft = (_maxPerMinute - _minuteBucket.length).clamp(
      0,
      _maxPerMinute,
    );
    final hourLeft = (_maxPerHour - _hourBucket.length).clamp(0, _maxPerHour);
    final dayLeft = (_maxPerDay - _dayBucket.length).clamp(0, _maxPerDay);
    return '$minLeft/min · $hourLeft/hr · $dayLeft/day';
  }

  // ── Private helpers ────────────────────────────────────────────────────────

  void _evict(DateTime now) {
    _minuteBucket.removeWhere(
      (t) => now.difference(t) > const Duration(minutes: 1),
    );
    _hourBucket.removeWhere(
      (t) => now.difference(t) > const Duration(hours: 1),
    );
    _dayBucket.removeWhere((t) => now.difference(t) > const Duration(days: 1));
  }

  void _refreshGlobalDay(DateTime now) {
    final resetTime = _globalDayReset;
    if (resetTime == null ||
        now.difference(resetTime) > const Duration(days: 1)) {
      _globalDayReset = now;
      _globalDayCount = 0;
    }
  }

  String _normalise(String s) => s.trim().toLowerCase();
}
