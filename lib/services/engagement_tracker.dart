import 'dart:io' show Platform;

import 'package:flutter/foundation.dart' show kIsWeb, visibleForTesting;
import 'package:in_app_review/in_app_review.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:pet/core/utils/app_logger.dart';
import 'package:pet/data/database/database_helper.dart';
import 'package:pet/data/repositories/budget_repository.dart';
import 'package:pet/data/repositories/transaction_repository.dart';
import 'package:pet/services/analytics_service.dart';
import 'package:pet/services/native_sms_reader.dart';
import 'package:pet/services/remote_config_service.dart';

/// Device state the funnel milestones and review prompt are derived from.
class EngagementSnapshot {
  const EngagementSnapshot({
    required this.now,
    required this.installedAt,
    required this.smsPermissionGranted,
    required this.notificationAccessGranted,
    required this.autoImportCount,
    required this.previousMonthUnderBudget,
  });

  final DateTime now;
  final DateTime installedAt;
  final bool smsPermissionGranted;
  final bool notificationAccessGranted;

  /// Transactions created from bank SMS or payment-app notifications.
  final int autoImportCount;

  /// Last calendar month had budgets, real spending, and every budgeted
  /// category finished at or under its limit.
  final bool previousMonthUnderBudget;

  int get daysSinceInstall => now.difference(installedAt).inDays;
}

/// Why the review prompt was shown.
enum ReviewTrigger { autoImports, monthUnderBudget }

/// Turns device state into one-off funnel events and decides when to ask
/// for a Play Store review.
///
/// Milestones are derived from state rather than hooked into each screen,
/// so they are also recorded when they happened in a background worker, or
/// before the user opted in to analytics.
///
/// Review prompt rules: only at a good moment (a trigger above), never in
/// the first [minDaysInstalled] days, at most once per trigger, at most
/// [maxPrompts] times, and at least [minDaysBetweenPrompts] apart. Play
/// applies its own quota on top. The prompt is never conditioned on what
/// the user might rate (Play policy forbids review gating).
class EngagementTracker {
  EngagementTracker({
    AnalyticsService? analytics,
    Future<EngagementSnapshot> Function()? snapshot,
    Future<bool> Function()? requestReview,
    int Function()? autoImportThreshold,
  })  : _analytics = analytics,
        _snapshot = snapshot ?? collectSnapshot,
        _requestReview = requestReview ?? _requestPlayReview,
        _autoImportThreshold = autoImportThreshold ??
            (() => RemoteConfigService.reviewAutoImportThreshold);

  static EngagementTracker instance = EngagementTracker();

  static const int minDaysInstalled = 3;
  static const int minDaysBetweenPrompts = 120;
  static const int maxPrompts = 3;

  static const kFirstSeenAt = 'engagementFirstSeenAt';
  static const kMilestonePrefix = 'engagementMilestone_';
  static const kReviewPromptCount = 'reviewPromptCount';
  static const kReviewLastPromptAt = 'reviewLastPromptAt';
  static const kReviewTriggersUsed = 'reviewTriggersUsed';

  /// Device-level state that must survive sign-out (see LocalDataWiper):
  /// otherwise a re-install-like reset would re-log milestones and re-ask
  /// for reviews.
  static const Set<String> deviceStateKeys = {
    kFirstSeenAt,
    kReviewPromptCount,
    kReviewLastPromptAt,
    kReviewTriggersUsed,
    '$kMilestonePrefix${AnalyticsEvents.smsPermissionGranted}',
    '$kMilestonePrefix${AnalyticsEvents.notificationAccessGranted}',
    '$kMilestonePrefix${AnalyticsEvents.firstAutoImport}',
    '$kMilestonePrefix${AnalyticsEvents.retainedDay7}',
  };

  final AnalyticsService? _analytics;
  final Future<EngagementSnapshot> Function() _snapshot;
  final Future<bool> Function() _requestReview;
  final int Function() _autoImportThreshold;

  AnalyticsService get analytics => _analytics ?? AnalyticsService.instance;

  bool _running = false;

  /// Records new milestones and, when [allowReviewPrompt] is true and a
  /// trigger fires, asks Play for the review sheet. Returns the trigger
  /// used, or null if no prompt was requested.
  Future<ReviewTrigger?> evaluate({bool allowReviewPrompt = true}) async {
    if (kIsWeb || _running) return null;
    _running = true;
    try {
      final prefs = await SharedPreferences.getInstance();
      final s = await _snapshot();
      await _recordMilestones(prefs, s);
      if (!allowReviewPrompt) return null;
      return await _maybePromptForReview(prefs, s);
    } catch (e) {
      AppLogger.debug('[Engagement] evaluate failed: $e');
      return null;
    } finally {
      _running = false;
    }
  }

  Future<void> _recordMilestones(
    SharedPreferences prefs,
    EngagementSnapshot s,
  ) async {
    // Only marked as done once actually sent, so milestones reached before
    // opting in are still counted after opting in.
    if (!analytics.isEnabled) return;
    Future<void> once(String event, bool reached,
        [Map<String, Object>? params]) async {
      final key = '$kMilestonePrefix$event';
      if (!reached || (prefs.getBool(key) ?? false)) return;
      await analytics.logEvent(event, params);
      await prefs.setBool(key, true);
    }

    await once(AnalyticsEvents.smsPermissionGranted, s.smsPermissionGranted);
    await once(
        AnalyticsEvents.notificationAccessGranted, s.notificationAccessGranted);
    await once(AnalyticsEvents.firstAutoImport, s.autoImportCount > 0);
    // "Still using the app in its second week" — the day-7 retention step.
    await once(
      AnalyticsEvents.retainedDay7,
      s.daysSinceInstall >= 7 && s.daysSinceInstall < 14,
    );
  }

  Future<ReviewTrigger?> _maybePromptForReview(
    SharedPreferences prefs,
    EngagementSnapshot s,
  ) async {
    if (s.daysSinceInstall < minDaysInstalled) return null;
    final count = prefs.getInt(kReviewPromptCount) ?? 0;
    if (count >= maxPrompts) return null;
    final last = DateTime.tryParse(prefs.getString(kReviewLastPromptAt) ?? '');
    if (last != null && s.now.difference(last).inDays < minDaysBetweenPrompts) {
      return null;
    }

    final used = (prefs.getStringList(kReviewTriggersUsed) ?? const []).toSet();
    ReviewTrigger? trigger;
    if (!used.contains(ReviewTrigger.monthUnderBudget.name) &&
        s.previousMonthUnderBudget) {
      trigger = ReviewTrigger.monthUnderBudget;
    } else if (!used.contains(ReviewTrigger.autoImports.name) &&
        s.autoImportCount >= _autoImportThreshold()) {
      trigger = ReviewTrigger.autoImports;
    }
    if (trigger == null) return null;

    final shown = await _requestReview();
    if (!shown) return null;
    await prefs.setInt(kReviewPromptCount, count + 1);
    await prefs.setString(kReviewLastPromptAt, s.now.toIso8601String());
    await prefs.setStringList(kReviewTriggersUsed, [...used, trigger.name]);
    await analytics
        .logEvent(AnalyticsEvents.reviewPrompt, {'trigger': trigger.name});
    return trigger;
  }

  static Future<bool> _requestPlayReview() async {
    final review = InAppReview.instance;
    if (!await review.isAvailable()) return false;
    await review.requestReview();
    return true;
  }

  /// Reads the snapshot from the device, database and permissions.
  static Future<EngagementSnapshot> collectSnapshot() async {
    final now = DateTime.now();
    return EngagementSnapshot(
      now: now,
      installedAt: await _installedAt(now),
      smsPermissionGranted: await _safe(
          () async => Platform.isAndroid && await Permission.sms.isGranted),
      notificationAccessGranted:
          await _safe(() => NativeSmsReader().hasNotificationAccess()),
      autoImportCount: await countAutoImports(),
      previousMonthUnderBudget: await _safe(() => wasUnderBudget(
            DateTime(now.year, now.month - 1),
          )),
    );
  }

  static Future<bool> _safe(Future<bool> Function() read) async {
    try {
      return await read();
    } catch (_) {
      return false;
    }
  }

  static Future<DateTime> _installedAt(DateTime now) async {
    try {
      final installed = (await PackageInfo.fromPlatform()).installTime;
      if (installed != null) return installed;
    } catch (_) {}
    // Fallback: the first time this code ran on the device.
    final prefs = await SharedPreferences.getInstance();
    final stored = DateTime.tryParse(prefs.getString(kFirstSeenAt) ?? '');
    if (stored != null) return stored;
    await prefs.setString(kFirstSeenAt, now.toIso8601String());
    return now;
  }

  @visibleForTesting
  static Future<int> countAutoImports({DatabaseHelper? dbHelper}) async {
    final db = await (dbHelper ?? DatabaseHelper()).database;
    final rows = await db.rawQuery(
      "SELECT COUNT(*) AS n FROM transactions "
      "WHERE source IN ('sms', 'notification')",
    );
    return (rows.first['n'] as num?)?.toInt() ?? 0;
  }

  /// Whether every budget set for [month] finished at or under its limit,
  /// with at least some spending tracked against them.
  @visibleForTesting
  static Future<bool> wasUnderBudget(
    DateTime month, {
    BudgetRepository? budgets,
    TransactionRepository? transactions,
  }) async {
    final list = await (budgets ?? BudgetRepository())
        .getBudgetsByMonth(month.month, month.year);
    if (list.isEmpty) return false;
    final txns = transactions ?? TransactionRepository();
    var totalSpent = 0.0;
    for (final budget in list) {
      final spent = await txns.getSpentInCategory(
          budget.categoryId, month.month, month.year);
      if (spent > budget.amount) return false;
      totalSpent += spent;
    }
    return totalSpent > 0;
  }
}
