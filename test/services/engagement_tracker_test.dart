import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:pet/data/database/database_helper.dart';
import 'package:pet/data/models/budget.dart';
import 'package:pet/data/models/enums.dart';
import 'package:pet/data/models/transaction.dart';
import 'package:pet/data/repositories/budget_repository.dart';
import 'package:pet/data/repositories/transaction_repository.dart';
import 'package:pet/services/analytics_service.dart';
import 'package:pet/services/engagement_tracker.dart';
import 'package:pet/services/local_data_wiper.dart';

import 'analytics_service_test.dart' show FakeAnalyticsBackend;

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  final installed = DateTime(2026, 9, 1);
  late FakeAnalyticsBackend backend;
  late AnalyticsService analytics;
  late EngagementSnapshot snapshot;
  late int reviewRequests;
  late bool reviewAvailable;
  late EngagementTracker tracker;

  EngagementSnapshot snap({
    int day = 1,
    bool sms = false,
    bool notif = false,
    int imports = 0,
    bool underBudget = false,
  }) =>
      EngagementSnapshot(
        now: installed.add(Duration(days: day, hours: 12)),
        installedAt: installed,
        smsPermissionGranted: sms,
        notificationAccessGranted: notif,
        autoImportCount: imports,
        previousMonthUnderBudget: underBudget,
      );

  setUp(() {
    SharedPreferences.setMockInitialValues({});
    backend = FakeAnalyticsBackend();
    analytics = AnalyticsService(backend: backend);
    snapshot = snap();
    reviewRequests = 0;
    reviewAvailable = true;
    tracker = EngagementTracker(
      analytics: analytics,
      snapshot: () async => snapshot,
      requestReview: () async {
        if (!reviewAvailable) return false;
        reviewRequests++;
        return true;
      },
      autoImportThreshold: () => 10,
    );
  });

  group('funnel milestones', () {
    test('are not sent without analytics consent', () async {
      snapshot = snap(sms: true, imports: 3);
      await tracker.evaluate();
      expect(backend.events, isEmpty);
    });

    test('are sent once each, including ones reached before opting in',
        () async {
      snapshot = snap(sms: true, notif: true, imports: 3);
      await tracker.evaluate(); // not opted in yet
      await analytics.setEnabled(true);
      backend.events.clear();

      await tracker.evaluate();
      await tracker.evaluate();
      expect(backend.events, [
        AnalyticsEvents.smsPermissionGranted,
        AnalyticsEvents.notificationAccessGranted,
        AnalyticsEvents.firstAutoImport,
      ]);
    });

    test('day-7 retention fires only in the second week', () async {
      await analytics.setEnabled(true);
      snapshot = snap(day: 6);
      await tracker.evaluate();
      expect(backend.events, isNot(contains(AnalyticsEvents.retainedDay7)));

      snapshot = snap(day: 8);
      await tracker.evaluate();
      expect(backend.events, contains(AnalyticsEvents.retainedDay7));
    });

    test('day-7 retention is not logged for users first seen after week 2',
        () async {
      await analytics.setEnabled(true);
      snapshot = snap(day: 30);
      await tracker.evaluate();
      expect(backend.events, isNot(contains(AnalyticsEvents.retainedDay7)));
    });

    test('milestone and review state survive sign-out', () {
      expect(LocalDataWiper.deviceSettingKeys,
          containsAll(EngagementTracker.deviceStateKeys));
    });
  });

  group('review prompt', () {
    test('asks after the 10th auto-import, not before', () async {
      snapshot = snap(day: 5, imports: 9);
      expect(await tracker.evaluate(), isNull);
      snapshot = snap(day: 5, imports: 10);
      expect(await tracker.evaluate(), ReviewTrigger.autoImports);
      expect(reviewRequests, 1);
    });

    test('works without analytics consent but only logs with it', () async {
      snapshot = snap(day: 5, imports: 10);
      await tracker.evaluate();
      expect(reviewRequests, 1);
      expect(backend.events, isEmpty);
    });

    test('logs the trigger when analytics is on', () async {
      await analytics.setEnabled(true);
      snapshot = snap(day: 5, imports: 10);
      await tracker.evaluate();
      expect(backend.events.last, AnalyticsEvents.reviewPrompt);
      expect(backend.params[AnalyticsEvents.reviewPrompt],
          {'trigger': 'autoImports'});
    });

    test('never asks in the first days after install', () async {
      snapshot = snap(day: 1, imports: 50, underBudget: true);
      expect(await tracker.evaluate(), isNull);
      expect(reviewRequests, 0);
    });

    test('a month finished under budget is a trigger', () async {
      snapshot = snap(day: 35, underBudget: true);
      expect(await tracker.evaluate(), ReviewTrigger.monthUnderBudget);
    });

    test('each trigger is used once and prompts are 120+ days apart', () async {
      snapshot = snap(day: 5, imports: 10);
      await tracker.evaluate();
      expect(reviewRequests, 1);

      // Same trigger again, and a new trigger too soon: no prompt.
      snapshot = snap(day: 40, imports: 30, underBudget: true);
      expect(await tracker.evaluate(), isNull);

      // New trigger after the cool-down: prompt.
      snapshot = snap(day: 130, imports: 30, underBudget: true);
      expect(await tracker.evaluate(), ReviewTrigger.monthUnderBudget);

      // Both triggers used: never again.
      snapshot = snap(day: 400, imports: 300, underBudget: true);
      expect(await tracker.evaluate(), isNull);
      expect(reviewRequests, 2);
    });

    test('stops after the lifetime maximum', () async {
      SharedPreferences.setMockInitialValues({
        EngagementTracker.kReviewPromptCount: EngagementTracker.maxPrompts,
      });
      snapshot = snap(day: 5, imports: 10);
      expect(await tracker.evaluate(), isNull);
    });

    test('is not shown when the caller says the moment is wrong', () async {
      snapshot = snap(day: 5, imports: 10);
      expect(await tracker.evaluate(allowReviewPrompt: false), isNull);
      expect(reviewRequests, 0);
      // Still eligible later.
      expect(await tracker.evaluate(), ReviewTrigger.autoImports);
    });

    test('an unavailable review flow does not use up the trigger', () async {
      reviewAvailable = false;
      snapshot = snap(day: 5, imports: 10);
      expect(await tracker.evaluate(), isNull);
      reviewAvailable = true;
      expect(await tracker.evaluate(), ReviewTrigger.autoImports);
    });
  });

  group('database-derived state', () {
    late Database db;

    setUpAll(() {
      sqfliteFfiInit();
      databaseFactory = databaseFactoryFfi;
    });

    setUp(() async {
      db = await openDatabase(
        inMemoryDatabasePath,
        version: kDatabaseVersion,
        onCreate: (db, v) => DatabaseHelper().onCreateForTesting(db, v),
      );
      DatabaseHelper.setTestDatabase(db);
    });

    tearDown(() async {
      await db.close();
      DatabaseHelper.setTestDatabase(null);
    });

    TransactionRecord txn(String id, double amount, DateTime date,
            {TransactionSource source = TransactionSource.manual}) =>
        TransactionRecord(
          id: id,
          amount: amount,
          type: TransactionType.expense,
          categoryId: 'food',
          date: date,
          source: source,
          sourceFingerprint: source == TransactionSource.manual ? null : id,
          updatedAt: date,
        );

    test('counts only SMS and notification imports', () async {
      final repo = TransactionRepository();
      final d = DateTime(2026, 9, 3);
      await repo.insertTransaction(txn('a', 10, d));
      await repo
          .insertTransaction(txn('b', 10, d, source: TransactionSource.sms));
      await repo.insertTransaction(
          txn('c', 10, d, source: TransactionSource.notification));
      expect(await EngagementTracker.countAutoImports(), 2);
    });

    test('under budget needs budgets, real spending and every limit kept',
        () async {
      final budgets = BudgetRepository(database: db);
      final repo = TransactionRepository();
      final sept = DateTime(2026, 9);

      expect(await EngagementTracker.wasUnderBudget(sept), isFalse,
          reason: 'no budgets');

      await budgets.insertOrUpdateBudget(Budget(
          id: 'b1', categoryId: 'food', amount: 5000, month: 9, year: 2026));
      expect(await EngagementTracker.wasUnderBudget(sept), isFalse,
          reason: 'nothing tracked');

      await repo.insertTransaction(txn('t1', 4000, DateTime(2026, 9, 10)));
      expect(await EngagementTracker.wasUnderBudget(sept), isTrue);

      await repo.insertTransaction(txn('t2', 1500, DateTime(2026, 9, 20)));
      expect(await EngagementTracker.wasUnderBudget(sept), isFalse,
          reason: 'over the limit');
    });
  });
}
