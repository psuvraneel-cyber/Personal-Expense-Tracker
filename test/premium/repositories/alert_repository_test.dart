import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:path/path.dart' as p;
import 'package:pet/data/database/database_helper.dart';
import 'package:pet/premium/models/app_alert.dart';
import 'package:pet/premium/repositories/alert_repository.dart';

void main() {
  late Directory tempDir;
  late String dbPath;
  late AlertRepository repository;

  setUpAll(() {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  });

  setUp(() async {
    tempDir = Directory.systemTemp.createTempSync();
    dbPath = p.join(tempDir.path, 'alert_repo_test.db');

    final db = await openDatabase(
      dbPath,
      version: 17,
      onCreate: (db, version) async {
        await DatabaseHelper().onCreateForTesting(db, version);
      },
    );

    repository = AlertRepository(database: db);
  });

  tearDown(() async {
    try {
      if (tempDir.existsSync()) {
        tempDir.deleteSync(recursive: true);
      }
    } catch (_) {}
  });

  group('AlertRepository Tests', () {
    test('insert and existsByKey works and enforces alertKey deduplication', () async {
      final alert1 = AppAlert(
        id: 'alert_1',
        type: AppAlertType.budget,
        title: 'Budget Alert 1',
        message: 'Close to limit',
        createdAt: DateTime(2026, 7, 10),
        alertKey: 'budget:cat_food:2026-07:warning',
      );

      await repository.insert(alert1);

      expect(await repository.existsByKey('budget:cat_food:2026-07:warning'), isTrue);
      expect(await repository.existsByKey('non_existent_key'), isFalse);

      // Inserting duplicate key should be ignored without throwing
      final alertDup = AppAlert(
        id: 'alert_dup',
        type: AppAlertType.budget,
        title: 'Duplicate Budget Alert',
        message: 'Should be ignored',
        createdAt: DateTime(2026, 7, 11),
        alertKey: 'budget:cat_food:2026-07:warning',
      );

      await repository.insert(alertDup);

      final count = await repository.getActiveCount();
      expect(count, equals(1));

      final fetched = await repository.getById('alert_1');
      expect(fetched?.title, equals('Budget Alert 1'));
    });

    test('insertBatch ignores duplicate keys in same or prior batches', () async {
      final batch = [
        AppAlert(
          id: 'b1',
          type: AppAlertType.budget,
          title: 'B1',
          message: 'M1',
          createdAt: DateTime(2026, 7, 10),
          alertKey: 'key_1',
        ),
        AppAlert(
          id: 'b2',
          type: AppAlertType.anomaly,
          title: 'B2',
          message: 'M2',
          createdAt: DateTime(2026, 7, 10),
          alertKey: 'key_2',
        ),
        AppAlert(
          id: 'b3',
          type: AppAlertType.budget,
          title: 'B3 duplicate of b1',
          message: 'M3',
          createdAt: DateTime(2026, 7, 10),
          alertKey: 'key_1',
        ),
      ];

      await repository.insertBatch(batch);
      expect(await repository.getActiveCount(), equals(2));
    });

    test('getPage pagination and sorting (limit, offset, createdAt DESC)', () async {
      final alerts = List.generate(
        15,
        (i) => AppAlert(
          id: 'alert_$i',
          type: AppAlertType.budget,
          title: 'Alert $i',
          message: 'Message $i',
          createdAt: DateTime(2026, 7, i + 1),
          alertKey: 'key_$i',
        ),
      );

      await repository.insertBatch(alerts);

      // First page of 5 items
      final page1 = await repository.getPage(limit: 5, offset: 0);
      expect(page1.length, equals(5));
      expect(page1.first.id, equals('alert_14')); // Newest first
      expect(page1.last.id, equals('alert_10'));

      // Second page of 5 items
      final page2 = await repository.getPage(limit: 5, offset: 5);
      expect(page2.length, equals(5));
      expect(page2.first.id, equals('alert_9'));
      expect(page2.last.id, equals('alert_5'));
    });

    test('getPage filtering by type, severity, unreadOnly, and period', () async {
      await repository.insertBatch([
        AppAlert(
          id: 'f1',
          type: AppAlertType.budget,
          severity: AlertSeverity.critical,
          title: 'Budget Crit',
          message: 'M',
          period: '2026-07',
          isRead: false,
          createdAt: DateTime(2026, 7, 1),
          alertKey: 'f1',
        ),
        AppAlert(
          id: 'f2',
          type: AppAlertType.budget,
          severity: AlertSeverity.warning,
          title: 'Budget Warn',
          message: 'M',
          period: '2026-07',
          isRead: true,
          createdAt: DateTime(2026, 7, 2),
          alertKey: 'f2',
        ),
        AppAlert(
          id: 'f3',
          type: AppAlertType.bill,
          severity: AlertSeverity.info,
          title: 'Bill Info',
          message: 'M',
          period: '2026-08',
          isRead: false,
          createdAt: DateTime(2026, 7, 3),
          alertKey: 'f3',
        ),
      ]);

      // Filter by type
      final budgetAlerts = await repository.getPage(type: AppAlertType.budget);
      expect(budgetAlerts.length, equals(2));

      // Filter by severity
      final criticalAlerts = await repository.getPage(severity: AlertSeverity.critical);
      expect(criticalAlerts.length, equals(1));
      expect(criticalAlerts.first.id, equals('f1'));

      // Filter by unreadOnly
      final unreadAlerts = await repository.getPage(unreadOnly: true);
      expect(unreadAlerts.length, equals(2));
      expect(unreadAlerts.map((a) => a.id).toSet(), equals({'f1', 'f3'}));

      // Filter by period
      final periodAlerts = await repository.getPage(period: '2026-08');
      expect(periodAlerts.length, equals(1));
      expect(periodAlerts.first.id, equals('f3'));
    });

    test('fast SQL count queries: getUnreadCount and getActiveCount', () async {
      await repository.insertBatch([
        AppAlert(
          id: 'c1',
          type: AppAlertType.budget,
          title: 'T',
          message: 'M',
          createdAt: DateTime(2026, 7, 1),
          isRead: false,
          alertKey: 'c1',
        ),
        AppAlert(
          id: 'c2',
          type: AppAlertType.budget,
          title: 'T',
          message: 'M',
          createdAt: DateTime(2026, 7, 2),
          isRead: true,
          alertKey: 'c2',
        ),
        AppAlert(
          id: 'c3',
          type: AppAlertType.budget,
          title: 'T',
          message: 'M',
          createdAt: DateTime(2026, 7, 3),
          isRead: false,
          isDismissed: true,
          alertKey: 'c3',
        ),
      ]);

      expect(await repository.getActiveCount(), equals(2)); // c1 and c2 (not dismissed)
      expect(await repository.getUnreadCount(), equals(1)); // c1 only (not read, not dismissed)
    });

    test('markRead and markAllRead update database state in single SQL statement', () async {
      await repository.insertBatch([
        AppAlert(
          id: 'm1',
          type: AppAlertType.budget,
          title: 'T',
          message: 'M',
          createdAt: DateTime(2026, 7, 1),
          isRead: false,
          alertKey: 'm1',
        ),
        AppAlert(
          id: 'm2',
          type: AppAlertType.anomaly,
          title: 'T',
          message: 'M',
          createdAt: DateTime(2026, 7, 2),
          isRead: false,
          alertKey: 'm2',
        ),
      ]);

      await repository.markRead('m1');
      expect((await repository.getById('m1'))?.isRead, isTrue);
      expect((await repository.getById('m2'))?.isRead, isFalse);

      await repository.markAllRead();
      expect(await repository.getUnreadCount(), equals(0));
    });

    test('dismiss, undoDismiss, and dismissAllRead soft deletion operations', () async {
      await repository.insertBatch([
        AppAlert(
          id: 'd1',
          type: AppAlertType.budget,
          title: 'T',
          message: 'M',
          createdAt: DateTime(2026, 7, 1),
          isRead: true,
          alertKey: 'd1',
        ),
        AppAlert(
          id: 'd2',
          type: AppAlertType.budget,
          title: 'T',
          message: 'M',
          createdAt: DateTime(2026, 7, 2),
          isRead: false,
          alertKey: 'd2',
        ),
      ]);

      // Soft dismiss d2
      await repository.dismiss('d2');
      expect((await repository.getById('d2'))?.isDismissed, isTrue);
      expect(await repository.getActiveCount(), equals(1)); // only d1 is active

      // Undo dismiss d2
      await repository.undoDismiss('d2');
      expect((await repository.getById('d2'))?.isDismissed, isFalse);
      expect(await repository.getActiveCount(), equals(2));

      // Dismiss all read alerts (should dismiss d1)
      await repository.dismissAllRead();
      expect((await repository.getById('d1'))?.isDismissed, isTrue);
      expect(await repository.getActiveCount(), equals(1)); // only d2 remains active
    });

    test('purgeOldDismissedAlerts removes dismissed alerts older than retention threshold', () async {
      await repository.insertBatch([
        AppAlert(
          id: 'old_dismissed',
          type: AppAlertType.budget,
          title: 'T',
          message: 'M',
          createdAt: DateTime(2026, 1, 1),
          updatedAt: DateTime(2026, 1, 2),
          isDismissed: true,
          alertKey: 'p1',
        ),
        AppAlert(
          id: 'recent_dismissed',
          type: AppAlertType.budget,
          title: 'T',
          message: 'M',
          createdAt: DateTime(2026, 7, 1),
          updatedAt: DateTime(2026, 7, 2),
          isDismissed: true,
          alertKey: 'p2',
        ),
        AppAlert(
          id: 'old_active',
          type: AppAlertType.budget,
          title: 'T',
          message: 'M',
          createdAt: DateTime(2026, 1, 1),
          isDismissed: false,
          alertKey: 'p3',
        ),
      ]);

      // Purge alerts dismissed before June 2026 (older than 30 days relative to July)
      final purged = await repository.purgeOldDismissedAlerts(
        retentionThreshold: DateTime(2026, 6, 1),
      );

      expect(purged, equals(1));
      expect(await repository.getById('old_dismissed'), isNull);
      expect(await repository.getById('recent_dismissed'), isNotNull);
      expect(await repository.getById('old_active'), isNotNull);
    });
  });
}
