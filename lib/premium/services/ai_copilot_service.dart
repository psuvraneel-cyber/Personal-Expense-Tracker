import 'dart:convert';
import 'package:pet/data/models/enums.dart';
import 'package:pet/data/models/transaction.dart';
import 'package:flutter/foundation.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:http/http.dart' as http;
import 'package:pet/premium/services/ai_rate_limiter.dart';
import 'package:pet/services/worker_api.dart';

/// A single chat turn sent to / received from the Groq API.
class _ChatTurn {
  final String role; // 'system' | 'user' | 'assistant'
  final String content;
  const _ChatTurn({required this.role, required this.content});
  Map<String, String> toJson() => {'role': role, 'content': content};
}

/// Financial context snapshot passed by the screen on every message.
class FinancialContext {
  /// Current month name (e.g. "March 2026").
  final String monthLabel;
  final double totalIncome;
  final double totalExpenses;
  final double totalSavings;

  /// categoryName → amountSpent  (top expenses this month).
  final Map<String, double> categorySpending;

  /// categoryName → {budget: x, spent: y}  (only categories with a budget set).
  final List<Map<String, dynamic>> budgets;

  /// Last 10 transactions as readable strings, newest first.
  /// (Capped at 10 to reduce token usage — was 30 before.)
  final List<String> recentTransactions;

  // --- Canonical Cashflow Forecast Metrics (CF-20) ---
  /// Bank balance now (entered by the user, plus tracked activity since);
  /// null when the user hasn't entered one.
  final double? currentBalance;
  final double? projectedEndingBalance;
  final double? safeToSpend;
  final int? cashflowRunwayDays;
  final bool? isCashflowPositive;
  final double? monthlyNetCashflow;
  final double? upcomingBillsNext14Days;
  final double? lowestProjectedBalance;
  final DateTime? lowestProjectedDate;
  final String? cashflowRiskLevel;
  final String? forecastConfidence;

  const FinancialContext({
    required this.monthLabel,
    required this.totalIncome,
    required this.totalExpenses,
    required this.totalSavings,
    required this.categorySpending,
    required this.budgets,
    required this.recentTransactions,
    this.currentBalance,
    this.projectedEndingBalance,
    this.safeToSpend,
    this.cashflowRunwayDays,
    this.isCashflowPositive,
    this.monthlyNetCashflow,
    this.upcomingBillsNext14Days,
    this.lowestProjectedBalance,
    this.lowestProjectedDate,
    this.cashflowRiskLevel,
    this.forecastConfidence,
    this.isFocusModeActive,
    this.focusModeBlockedCount,
    this.focusModeBlockedCategories,
    this.weeklyLimits,
    this.activeGoals,
  });

  // --- Focus Mode & Weekly Planner & Goals Context (Phase I) ---
  final bool? isFocusModeActive;
  final int? focusModeBlockedCount;
  final List<String>? focusModeBlockedCategories;
  final List<Map<String, dynamic>>? weeklyLimits;
  final List<Map<String, dynamic>>? activeGoals;
}

/// Exception thrown when the rate limiter denies a request.
class RateLimitException implements Exception {
  final String message;
  const RateLimitException(this.message);
  @override
  String toString() => message;
}

/// Exception thrown when the server returns a 4xx error.
class ClientErrorException implements Exception {
  final int statusCode;
  final String message;
  const ClientErrorException(this.statusCode, this.message);
  @override
  String toString() => message;
}

/// The user's Copilot allowance as reported by the server.
class AiQuota {
  const AiQuota({
    required this.isPremium,
    this.limit = 0,
    this.remaining = 0,
    this.resetsAt,
  });

  final bool isPremium;

  /// Free questions per month and how many are left (free plan only).
  final int limit;
  final int remaining;
  final DateTime? resetsAt;

  bool get canAsk => isPremium || remaining > 0;

  static AiQuota? fromJson(Object? json) {
    if (json is! Map) return null;
    if (json['plan'] == 'premium') return const AiQuota(isPremium: true);
    if (json['plan'] != 'free') return null;
    return AiQuota(
      isPremium: false,
      limit: (json['limit'] as num?)?.toInt() ?? 0,
      remaining: (json['remaining'] as num?)?.toInt() ?? 0,
      resetsAt: DateTime.tryParse('${json['resetsAt']}')?.toLocal(),
    );
  }
}

/// The server refused because the free allowance can't be used: the
/// monthly questions are used up ([quotaExhausted]), the user is a guest
/// ([signInRequired]), or the Copilot is premium-only.
class AiAccessException implements Exception {
  const AiAccessException(this.errorCode, this.message, {this.quota});

  final String errorCode;
  final String message;
  final AiQuota? quota;

  static const quotaExhaustedCode = 'FREE_QUOTA_EXHAUSTED';
  static const signInRequiredCode = 'SIGN_IN_REQUIRED';
  static const premiumRequiredCode = 'PREMIUM_REQUIRED';

  bool get quotaExhausted => errorCode == quotaExhaustedCode;
  bool get signInRequired => errorCode == signInRequiredCode;

  @override
  String toString() => message;
}

/// Exception thrown when the server returns a 401 authentication error.
class AuthErrorException implements Exception {
  final int statusCode;
  final String message;
  final String? errorCode;
  const AuthErrorException(this.statusCode, this.message, {this.errorCode});
  @override
  String toString() => message;

  /// Whether this auth error is potentially resolvable by refreshing the token.
  bool get isRetryable =>
      errorCode == null ||
      errorCode == 'AUTH_TOKEN_EXPIRED' ||
      errorCode == 'AUTH_TOKEN_UNKNOWN_KEY';
}

/// Income, spending and spending per category id for one calendar month.
typedef MonthTotals = ({
  double income,
  double expense,
  Map<String, double> byCategory,
});

class AiCopilotService {
  /// Totals for the calendar month containing [now]. The AI always talks
  /// about the current month, whatever month a screen is showing.
  static MonthTotals monthTotals(
    Iterable<TransactionRecord> transactions,
    DateTime now,
  ) {
    var income = 0.0, expense = 0.0;
    final byCategory = <String, double>{};
    for (final t in transactions) {
      if (t.date.year != now.year || t.date.month != now.month) continue;
      if (t.date.isAfter(now)) continue;
      if (t.type == TransactionType.income) {
        income += t.amount;
      } else if (t.type == TransactionType.expense) {
        expense += t.amount;
        byCategory[t.categoryId] = (byCategory[t.categoryId] ?? 0) + t.amount;
      }
    }
    return (income: income, expense: expense, byCategory: byCategory);
  }

  AiCopilotService({required this.model});

  final String model;

  /// Max response tokens — keeps replies concise and saves quota.
  static const _maxTokens = 400;

  /// How many history turns (user+assistant pairs) to keep in context.
  /// Keeping this small is the single biggest token saver.
  static const _maxHistoryTurns = 8; // = 4 exchanges

  // In-memory chat history
  final List<_ChatTurn> _history = [];

  // Rate limiter — one per service instance (= one per user session)
  final AiRateLimiter _limiter = AiRateLimiter();

  /// Allowance reported with the latest answer (null until known).
  AiQuota? lastQuota;

  /// Returns a human-readable quota summary string, e.g. "8/min · 44/hr · 144/day"
  String get quotaSummary => _limiter.quotaSummary();

  /// Sends [message] to Groq with the latest financial context embedded in the
  /// system prompt. Returns the assistant's reply text.
  ///
  /// Throws [RateLimitException] when any limit is reached.
  Future<String> sendMessage({
    required String message,
    required FinancialContext context,
  }) async {
    // ── 1. Duplicate suppression ─────────────────────────────────────────────
    final cached = _limiter.getCached(message);
    if (cached != null) return cached;

    // ── 2. Rate-limit check ──────────────────────────────────────────────────
    final result = _limiter.check(message);
    if (!result.allowed) {
      throw RateLimitException(result.reason!);
    }

    // ── 3. Burst delay ───────────────────────────────────────────────────────
    if (result.burstDelay != null) {
      await Future.delayed(result.burstDelay!);
    }

    // ── 4. Build prompt ──────────────────────────────────────────────────────
    final system = _buildSystemPrompt(context);

    // Truncated history to save tokens
    final historyToSend = _history.length > _maxHistoryTurns
        ? _history.sublist(_history.length - _maxHistoryTurns)
        : _history;

    final messages = <Map<String, String>>[
      {'role': 'system', 'content': system},
      ...historyToSend.map((t) => t.toJson()),
      {'role': 'user', 'content': message},
    ];

    // ── 5. API call with auth retry + general retry ──────────────────────────
    String reply;
    try {
      reply = await _callApi(messages);
    } on AuthErrorException catch (e) {
      // On 401, force-refresh the Firebase ID token and retry exactly once
      if (e.isRetryable) {
        try {
          reply = await _callApi(messages, forceRefresh: true);
        } on AuthErrorException {
          // Second 401 — do not retry further
          rethrow;
        }
      } else {
        rethrow;
      }
    } on ClientErrorException {
      rethrow;
    } on AiAccessException {
      rethrow;
    } on Exception {
      // Retry once after a brief pause — then surface the error.
      await Future.delayed(const Duration(seconds: 2));
      reply = await _callApi(messages); // second failure propagates upward
    }

    // ── 6. Record usage + cache reply ────────────────────────────────────────
    _limiter.record(message);
    _limiter.cacheReply(message, reply);

    // ── 7. Append to history ─────────────────────────────────────────────────
    _history
      ..add(_ChatTurn(role: 'user', content: message))
      ..add(_ChatTurn(role: 'assistant', content: reply));

    // Keep history trimmed
    if (_history.length > _maxHistoryTurns * 2) {
      _history.removeRange(0, _history.length - _maxHistoryTurns * 2);
    }

    return reply;
  }

  /// Clears the conversation history (e.g. when starting a fresh session).
  void clearHistory() => _history.clear();

  /// Records a user report about an AI-generated reply (Google Play
  /// AI-Generated Content policy). Stored under the reporter's own Firestore
  /// tree (`users/{uid}/ai_reports`) for review; deleted with the account.
  static Future<void> reportResponse({
    required String reply,
    required String prompt,
    required String reason,
  }) async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) {
      throw Exception('Sign in to report a response.');
    }
    await FirebaseFirestore.instance
        .collection('users')
        .doc(user.uid)
        .collection('ai_reports')
        .add({
      'reply': reply.length > 5000 ? reply.substring(0, 5000) : reply,
      'prompt': prompt.length > 2000 ? prompt.substring(0, 2000) : prompt,
      'reason': reason,
      'createdAt': FieldValue.serverTimestamp(),
    });
  }

  // ---------------------------------------------------------------------------
  // Private helpers
  // ---------------------------------------------------------------------------

  /// Asks the server how many free questions are left, without asking
  /// the AI anything. Returns null when signed out or offline.
  static Future<AiQuota?> fetchQuota() async {
    try {
      final response = await _post('/quota', const {});
      if (response.statusCode != 200) return null;
      final decoded = jsonDecode(response.body);
      return decoded is Map ? AiQuota.fromJson(decoded['quota']) : null;
    } catch (_) {
      return null;
    }
  }

  static Future<http.Response> _post(String path, Map<String, Object?> body,
          {bool forceRefresh = false}) =>
      WorkerApi.post(path, body, forceRefresh: forceRefresh);

  Future<String> _callApi(List<Map<String, String>> messages,
      {bool forceRefresh = false}) async {
    final response = await _post(
      '',
      {
        'model': model,
        'messages': messages,
        'max_tokens': _maxTokens,
      },
      forceRefresh: forceRefresh,
    );

    if (response.statusCode == 401) {
      // Parse structured error code if available
      String? errorCode;
      String errMsg = response.body;
      try {
        final decoded = jsonDecode(response.body);
        if (decoded is Map) {
          errorCode = decoded['errorCode']?.toString();
          if (decoded['error'] != null) {
            errMsg = decoded['error'].toString();
          }
        }
      } catch (_) {}
      throw AuthErrorException(response.statusCode, errMsg,
          errorCode: errorCode);
    }

    if (response.statusCode == 403) {
      final access = parseAccessError(response.body);
      if (access != null) {
        if (access.quota != null) lastQuota = access.quota;
        throw access;
      }
    }

    if (response.statusCode >= 400 && response.statusCode < 500) {
      String errMsg = response.body;
      try {
        final decoded = jsonDecode(response.body);
        if (decoded is Map && decoded['error'] != null) {
          errMsg = decoded['error'].toString();
        }
      } catch (_) {}
      throw ClientErrorException(response.statusCode, errMsg);
    }

    if (response.statusCode != 200) {
      throw Exception('Server error ${response.statusCode}: ${response.body}');
    }

    final decoded = jsonDecode(response.body) as Map<String, dynamic>;
    lastQuota = AiQuota.fromJson(decoded['quota']) ?? lastQuota;
    return (decoded['choices'] as List?)?.firstOrNull?['message']?['content']
            as String? ??
        'No response.';
  }

  /// Maps a 403 body with a free-allowance error code to [AiAccessException].
  @visibleForTesting
  static AiAccessException? parseAccessError(String body) {
    try {
      final decoded = jsonDecode(body);
      if (decoded is! Map) return null;
      final code = decoded['errorCode']?.toString();
      if (code != AiAccessException.quotaExhaustedCode &&
          code != AiAccessException.signInRequiredCode &&
          code != AiAccessException.premiumRequiredCode) {
        return null;
      }
      return AiAccessException(
        code!,
        decoded['error']?.toString() ?? code,
        quota: AiQuota.fromJson(decoded['quota']),
      );
    } catch (_) {
      return null;
    }
  }

  @visibleForTesting
  String buildSystemPromptForTesting(FinancialContext ctx) =>
      _buildSystemPrompt(ctx);

  /// Builds a concise system prompt — sends totals & top categories only,
  /// NOT the full transaction list, to minimise token usage.
  String _buildSystemPrompt(FinancialContext ctx) {
    final buf = StringBuffer();

    buf.writeln(
      'You are a friendly, concise personal finance assistant for an Indian expense tracker app. '
      'Currency is Indian Rupees (₹). Payment methods: UPI, Credit Card, Debit Card, Cash. '
      'Be conversational and keep answers under 150 words unless the user asks for detail. '
      'Format numbers as ₹X,XX,XXX. Never fabricate data — only use the snapshot below.',
    );

    buf.writeln('\n--- FINANCIAL SNAPSHOT (${ctx.monthLabel}) ---');
    buf.writeln('Income  : ₹${_fmt(ctx.totalIncome)}');
    buf.writeln('Expenses: ₹${_fmt(ctx.totalExpenses)}');
    buf.writeln('Savings : ₹${_fmt(ctx.totalSavings)}');

    if (ctx.categorySpending.isNotEmpty) {
      // Send only top 5 categories to save tokens
      final top5 = (ctx.categorySpending.entries.toList()
            ..sort((a, b) => b.value.compareTo(a.value)))
          .take(5);
      buf.writeln('\nTop spending categories:');
      for (final e in top5) {
        buf.writeln('  • ${e.key}: ₹${_fmt(e.value)}');
      }
    }

    if (ctx.budgets.isNotEmpty) {
      buf.writeln('\nBudgets:');
      for (final b in ctx.budgets) {
        final name = b['category'] as String;
        final budget = b['budget'] as double;
        final spent = b['spent'] as double;
        final pct = budget > 0 ? ((spent / budget) * 100).round() : 0;
        buf.writeln(
          '  • $name: $pct% used (₹${_fmt(spent)} / ₹${_fmt(budget)})',
        );
      }
    }

    // Only recent 10 transactions (was 30 — saves ~60% tokens)
    if (ctx.recentTransactions.isNotEmpty) {
      buf.writeln('\nRecent transactions (newest first):');
      for (final t in ctx.recentTransactions.take(10)) {
        buf.writeln('  • $t');
      }
    }

    // --- Bank balance: entered by the user, or explicitly unknown ---
    if (ctx.currentBalance != null) {
      buf.writeln(
          '\nCurrent bank balance (user-entered, plus tracked activity since): '
          '₹${_fmt(ctx.currentBalance!)}');
    } else {
      buf.writeln('\nBANK BALANCE: UNKNOWN. The user has not entered their '
          'balance and P.E.T only sees tracked transactions, so income may be '
          'missing. Do not say whether they can afford something, how long '
          'their money will last, or that they are heading for a deficit. '
          'Suggest entering their balance in Premium Hub → Cash Flow.');
    }

    // --- Canonical Cashflow Forecast Section (CF-20) ---
    if (ctx.projectedEndingBalance != null || ctx.safeToSpend != null) {
      buf.writeln('\n--- 30-DAY CASHFLOW FORECAST (ESTIMATED) ---');
      if (ctx.safeToSpend != null) {
        buf.writeln('Safe-to-spend allowance: ₹${_fmt(ctx.safeToSpend!)}/day');
      }
      if (ctx.projectedEndingBalance != null) {
        buf.writeln(
            'Projected 30-day ending balance: ₹${_fmt(ctx.projectedEndingBalance!)}');
      }
      if (ctx.cashflowRunwayDays != null) {
        if (ctx.isCashflowPositive == true) {
          buf.writeln(
              'Runway: Cashflow positive (+₹${_fmt(ctx.monthlyNetCashflow ?? 0)}/mo surplus)');
        } else {
          buf.writeln('Runway: ~${ctx.cashflowRunwayDays} days of liquidity');
        }
      }
      if (ctx.lowestProjectedBalance != null) {
        final dateStr = ctx.lowestProjectedDate != null
            ? ' on ${ctx.lowestProjectedDate!.day}/${ctx.lowestProjectedDate!.month}'
            : '';
        buf.writeln(
            'Lowest projected trough: ₹${_fmt(ctx.lowestProjectedBalance!)}$dateStr');
      }
      if (ctx.upcomingBillsNext14Days != null &&
          ctx.upcomingBillsNext14Days! > 0) {
        buf.writeln(
            'Upcoming confirmed bills (next 14 days): ₹${_fmt(ctx.upcomingBillsNext14Days!)}');
      }
      if (ctx.cashflowRiskLevel != null) {
        buf.writeln('Forecast risk status: ${ctx.cashflowRiskLevel}');
      }
      if (ctx.forecastConfidence != null) {
        buf.writeln('Forecast confidence: ${ctx.forecastConfidence}');
      }
      buf.writeln(
          'Note: Forecasts are estimates based on recent activity, not guarantees or formal financial advice.');
    }

    if (ctx.isFocusModeActive == true) {
      buf.writeln('\n--- FOCUS MODE (SPEND PAUSE) ---');
      buf.writeln(
          'Status: ACTIVE (${ctx.focusModeBlockedCount ?? 0} discretionary categories paused)');
      if (ctx.focusModeBlockedCategories != null &&
          ctx.focusModeBlockedCategories!.isNotEmpty) {
        buf.writeln(
            'Paused categories: ${ctx.focusModeBlockedCategories!.join(', ')}');
      }
    }

    if (ctx.weeklyLimits != null && ctx.weeklyLimits!.isNotEmpty) {
      buf.writeln('\n--- WEEKLY PLANNER LIMITS ---');
      for (final w in ctx.weeklyLimits!) {
        final cat = w['category'] as String? ?? 'Category';
        final limit = (w['limit'] as num?)?.toDouble() ?? 0.0;
        final spent = (w['spent'] as num?)?.toDouble() ?? 0.0;
        final isOver = w['isOver'] as bool? ?? false;
        buf.writeln(
            '  • $cat: ₹${_fmt(spent)} / ₹${_fmt(limit)} (this week)${isOver ? ' [OVER LIMIT]' : ''}');
      }
    }

    if (ctx.activeGoals != null && ctx.activeGoals!.isNotEmpty) {
      buf.writeln('\n--- SAVINGS GOALS ---');
      for (final g in ctx.activeGoals!) {
        final name = g['name'] as String? ?? 'Goal';
        final current = (g['current'] as num?)?.toDouble() ?? 0.0;
        final target = (g['target'] as num?)?.toDouble() ?? 0.0;
        final pct = target > 0 ? ((current / target) * 100).round() : 0;
        buf.writeln('  • $name: $pct% (₹${_fmt(current)} / ₹${_fmt(target)})');
      }
    }

    buf.writeln('--- END OF SNAPSHOT ---');
    return buf.toString();
  }

  String _fmt(double v) {
    if (v < 0) return '-${_fmt(-v)}';
    final str = v.toStringAsFixed(0);
    if (str.length <= 3) return str;
    final last3 = str.substring(str.length - 3);
    final rest = str.substring(0, str.length - 3);
    final grouped = rest.replaceAllMapped(
      RegExp(r'(\d{1,2})(?=(\d{2})+$)'),
      (m) => '${m[1]},',
    );
    return '$grouped,$last3';
  }
}
