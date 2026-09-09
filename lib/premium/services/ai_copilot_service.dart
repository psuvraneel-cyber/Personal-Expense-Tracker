import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:http/http.dart' as http;
import 'package:pet/premium/services/ai_rate_limiter.dart';

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

class AiCopilotService {
  AiCopilotService({required this.model});

  final String model;

  /// Production Cloudflare Worker that proxies requests to Groq.
  static const _baseUrl = 'https://pet-ai-copilot.pet-app.workers.dev';

  /// Max response tokens — keeps replies concise and saves quota.
  static const _maxTokens = 400;

  /// How many history turns (user+assistant pairs) to keep in context.
  /// Keeping this small is the single biggest token saver.
  static const _maxHistoryTurns = 8; // = 4 exchanges

  // In-memory chat history
  final List<_ChatTurn> _history = [];

  // Rate limiter — one per service instance (= one per user session)
  final AiRateLimiter _limiter = AiRateLimiter();

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

  // ---------------------------------------------------------------------------
  // Private helpers
  // ---------------------------------------------------------------------------

  Future<String> _callApi(List<Map<String, String>> messages,
      {bool forceRefresh = false}) async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) {
      throw Exception('Login required to use the AI Copilot.');
    }

    final idToken = await user.getIdToken(forceRefresh);
    if (idToken == null) {
      throw Exception('Failed to get authentication token.');
    }

    final response = await http
        .post(
          Uri.parse(_baseUrl),
          headers: {
            'Content-Type': 'application/json',
            'Authorization': 'Bearer $idToken',
          },
          body: jsonEncode({
            'model': model,
            'messages': messages,
            'max_tokens': _maxTokens,
          }),
        )
        .timeout(const Duration(seconds: 30));

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
    return (decoded['choices'] as List?)?.firstOrNull?['message']?['content']
            as String? ??
        'No response.';
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
