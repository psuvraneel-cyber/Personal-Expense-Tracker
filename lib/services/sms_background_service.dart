import 'dart:io';
import 'package:flutter/widgets.dart';
import 'package:workmanager/workmanager.dart';
import 'package:pet/core/utils/app_logger.dart';
import 'package:pet/data/repositories/budget_repository.dart';
import 'package:pet/data/repositories/transaction_repository.dart';
import 'package:pet/premium/models/notification_category.dart';
import 'package:pet/premium/repositories/recurring_payment_repository.dart';
import 'package:pet/premium/services/alert_evaluation_coordinator.dart';
import 'package:pet/premium/services/bill_reminder_scheduler.dart';
import 'package:pet/premium/services/daily_reminder_evaluator.dart';
import 'package:pet/premium/services/notification_preferences_service.dart';
import 'package:pet/premium/services/notification_service.dart';
import 'package:pet/services/reconciliation_service.dart';
import 'package:pet/services/sms_service.dart';

/// Background task name for periodic SMS inbox scanning.
const String kSmsInboxScanTask = 'com.pet.tracker.smsInboxScan';

/// Background task name for periodic reconciliation sweep.
const String kReconciliationSweepTask = 'com.pet.tracker.reconciliationSweep';

/// Background task name for periodic budget, anomaly, and bill alert evaluation.
const String kAlertEvaluationTask = 'com.pet.tracker.alertEvaluation';

/// Top-level callback dispatcher for WorkManager.
/// This MUST be a top-level function (not a class method).
///
/// Uses SmsService.scanInbox() which internally uses the native ContentResolver
/// to read SMS from the system content provider — works regardless of which
/// app is set as the default SMS handler.
///
/// Performs incremental scanning: only looks back as far as needed based
/// on the last processed timestamp stored in SharedPreferences.
@pragma('vm:entry-point')
void smsCallbackDispatcher() {
  WidgetsFlutterBinding.ensureInitialized();
  Workmanager().executeTask((taskName, inputData) async {
    AppLogger.debug('[PET-BG] Background task started: $taskName');

    if (taskName == kSmsInboxScanTask) {
      try {
        // Use a short lookback (2 days) since we run every 15 minutes.
        // The hash-based dedup and lastProcessedTimestamp watermark
        // in SmsService prevent duplicates regardless.
        final smsService = SmsService();
        final count = await smsService.scanInbox(lookbackDays: 2);
        AppLogger.debug(
          '[PET-BG] Background scan found $count new transactions',
        );
      } catch (e) {
        AppLogger.debug('[PET-BG] Background scan error: $e');
      }
    } else if (taskName == kReconciliationSweepTask) {
      try {
        final reconciliationService = ReconciliationService();
        final count = await reconciliationService.reconcile();
        AppLogger.debug(
          '[PET-BG] Background reconciliation found $count new transactions',
        );
      } catch (e) {
        AppLogger.debug('[PET-BG] Background reconciliation error: $e');
      }
    } else if (taskName == kAlertEvaluationTask) {
      try {
        await NotificationService.initialize();

        final now = DateTime.now();
        final budgetRepo = BudgetRepository();
        final txnRepo = TransactionRepository();

        final budgetsList = await budgetRepo.getBudgetsByMonth(
          now.month,
          now.year,
        );
        final budgetsMap = <String, double>{};
        final spentMap = <String, double>{};

        for (final budget in budgetsList) {
          budgetsMap[budget.categoryId] = budget.amount;
          spentMap[budget.categoryId] = await txnRepo.getSpentInCategory(
            budget.categoryId,
            now.month,
            now.year,
          );
        }

        final transactions = await txnRepo.getAllTransactions();

        await AlertEvaluationCoordinator().onTransactionsChanged(
          transactions,
          budgets: budgetsMap,
          spent: spentMap,
          now: now,
        );

        // Re-arm scheduled bill reminders for boot safety (P0-2)
        final recurringRepo = RecurringPaymentRepository();
        final recurringPayments = await recurringRepo.getAll();
        await BillReminderScheduler.scheduleReminders(
          recurringPayments,
          now: now,
        );

        // Evaluate Daily Expense Reminder (P2-1)
        final dailyEnabled =
            await NotificationPreferencesService.isCategoryEnabled(
              NotificationCategory.dailySummary,
            );
        if (dailyEnabled) {
          final reminderHour =
              await NotificationPreferencesService.getReminderHour();
          final lastReminderDate =
              await NotificationPreferencesService.getLastDailyReminderDate();

          final startOfToday = DateTime(now.year, now.month, now.day);
          final todayTxns = await txnRepo.getTransactionsByDateRange(
            startOfToday,
            now,
          );

          final shouldFireDaily = DailyReminderEvaluator.shouldFireReminder(
            now: now,
            reminderHour: reminderHour,
            lastReminderDate: lastReminderDate,
            todayTransactionCount: todayTxns.length,
          );

          if (shouldFireDaily) {
            final todayKey = DailyReminderEvaluator.formatDateKey(now);
            await NotificationPreferencesService.setLastDailyReminderDate(
              todayKey,
            );

            await NotificationService.showInstant(
              id: NotificationService.collisionSafeId('daily_$todayKey'),
              title: 'Daily Expense Reminder',
              body: "Don't forget to log your expenses for today!",
              category: NotificationCategory.dailySummary,
              payload: 'daily',
            );
          }
        }

        AppLogger.debug(
          '[PET-BG] Background alert evaluation completed & re-armed bill reminders',
        );
      } catch (e) {
        AppLogger.debug('[PET-BG] Background alert evaluation error: $e');
      }
    }

    return Future.value(true);
  });
}

/// Initialize WorkManager for periodic background SMS scanning and alert evaluation.
///
/// Call this once during app startup (after permissions are granted).
Future<void> initSmsBackgroundService() async {
  if (!Platform.isAndroid) return;

  await Workmanager().initialize(smsCallbackDispatcher);

  // Register a periodic task that runs every 15 minutes (minimum interval).
  // WorkManager handles battery optimization and doze mode automatically.
  await Workmanager().registerPeriodicTask(
    kSmsInboxScanTask,
    kSmsInboxScanTask,
    frequency: const Duration(minutes: 15),
    constraints: Constraints(
      networkType: NetworkType.notRequired,
      requiresBatteryNotLow: true,
    ),
    existingWorkPolicy: ExistingPeriodicWorkPolicy.keep,
    backoffPolicy: BackoffPolicy.linear,
    backoffPolicyDelay: const Duration(minutes: 5),
  );

  // Register a periodic reconciliation sweep that runs every 6 hours.
  // This provides a safety net for transactions missed by the real-time
  // listener and the 15-minute scan task. Uses requiresBatteryNotLow
  // and requiresDeviceIdle to minimize battery impact.
  await Workmanager().registerPeriodicTask(
    kReconciliationSweepTask,
    kReconciliationSweepTask,
    frequency: const Duration(hours: 6),
    constraints: Constraints(
      networkType: NetworkType.notRequired,
      requiresBatteryNotLow: true,
    ),
    existingWorkPolicy: ExistingPeriodicWorkPolicy.keep,
    backoffPolicy: BackoffPolicy.linear,
    backoffPolicyDelay: const Duration(minutes: 15),
  );

  // Register a periodic task for budget & anomaly alert evaluation (every 30 minutes).
  await Workmanager().registerPeriodicTask(
    kAlertEvaluationTask,
    kAlertEvaluationTask,
    frequency: const Duration(minutes: 30),
    constraints: Constraints(
      networkType: NetworkType.notRequired,
      requiresBatteryNotLow: true,
    ),
    existingWorkPolicy: ExistingPeriodicWorkPolicy.keep,
    backoffPolicy: BackoffPolicy.linear,
    backoffPolicyDelay: const Duration(minutes: 5),
  );

  AppLogger.debug(
    '[PET-BG] Background SMS scan, reconciliation, and alert evaluation services initialized',
  );
}

/// Cancel background SMS scanning, reconciliation, and alert evaluation.
Future<void> cancelSmsBackgroundService() async {
  if (!Platform.isAndroid) return;
  await Workmanager().cancelByUniqueName(kSmsInboxScanTask);
  await Workmanager().cancelByUniqueName(kReconciliationSweepTask);
  await Workmanager().cancelByUniqueName(kAlertEvaluationTask);
  AppLogger.debug(
    '[PET-BG] Background SMS scan, reconciliation, and alert evaluation services cancelled',
  );
}
