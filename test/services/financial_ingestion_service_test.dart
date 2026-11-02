import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:path/path.dart' as p;
import 'package:shared_preferences/shared_preferences.dart';

import 'package:pet/core/constants/categories.dart';
import 'package:pet/data/database/database_helper.dart';
import 'package:pet/data/models/enums.dart';
import 'package:pet/data/models/financial_observation.dart';
import 'package:pet/services/financial_ingestion_service.dart';
import 'package:pet/services/merchant_rule_service.dart';
import 'package:pet/services/native_sms_reader.dart';
import 'package:pet/services/ingestion_diagnostics.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Database db;
  late Directory tempDir;
  late FinancialIngestionService ingestionService;
  late MerchantRuleService merchantRuleService;

  setUpAll(() {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  });

  setUp(() async {
    SharedPreferences.setMockInitialValues({
      'notifications_enabled': false,
    });

    tempDir = Directory.systemTemp.createTempSync('ingestion_test_');
    final dbPath = p.join(tempDir.path, 'pet_ingestion_test.db');
    db = await openDatabase(
      dbPath,
      version: 18,
      onCreate: (db, version) async {
        await DatabaseHelper().onCreateForTesting(db, version);
      },
    );

    DatabaseHelper.setTestDatabase(db);
    ingestionService = FinancialIngestionService();
    merchantRuleService = MerchantRuleService();
    await merchantRuleService.load();
    IngestionDiagnostics().reset();
  });

  tearDown(() async {
    DatabaseHelper.setTestDatabase(null);
    await db.close();
    try {
      if (tempDir.existsSync()) {
        tempDir.deleteSync(recursive: true);
      }
    } catch (_) {}
  });

  group('P0-P7 Financial Ingestion Pipeline Tests', () {
    test(
        'Test A — SMS debit creates one observation and one canonical ledger transaction',
        () async {
      final msg = NativeSmsMessage(
        address: 'HDFCBK',
        body:
            'Rs 500.00 debited from HDFC Bank A/c XX1234 on 24-Aug-26 at Swiggy. Avl Bal Rs 24,500.00. Ref 123456789.',
        dateMillis: DateTime(2026, 8, 24, 14, 30).millisecondsSinceEpoch,
        source: 'sms',
      );

      final txn = await ingestionService.ingestMessage(msg);

      expect(txn, isNotNull);
      expect(txn!.amount, equals(500.0));
      expect(txn.type, equals(TransactionType.expense));
      expect(txn.merchantName, equals('Swiggy'));
      expect(txn.source, equals(TransactionSource.sms));

      // Verify core ledger table has the transaction
      final ledgerRows = await db.query('transactions');
      expect(ledgerRows.length, equals(1));
      expect(ledgerRows.first['amount'], equals(500.0));
      expect(ledgerRows.first['merchantName'], equals('Swiggy'));

      // Verify financial_observations table has recorded observation
      final obsRows = await db.query('financial_observations');
      expect(obsRows.length, equals(1));
      expect(obsRows.first['state'],
          equals(FinancialObservationState.promoted.name));
      expect(obsRows.first['sourceIdentifier'], equals('HDFCBK'));
    });

    test(
        'Test B — Notification debit preserves title/body and promotes to canonical ledger',
        () async {
      final msg = NativeSmsMessage(
        address: 'PhonePe',
        packageName: 'com.phonepe.app',
        title: 'Paid to Starbucks',
        body: 'Rs 350.00 using HDFC Bank A/c',
        dateMillis: DateTime(2026, 8, 24, 15, 0).millisecondsSinceEpoch,
        source: 'notification',
      );

      final txn = await ingestionService.ingestMessage(msg);

      expect(txn, isNotNull);
      expect(txn!.amount, equals(350.0));
      expect(txn.merchantName, equals('Starbucks'));
      expect(txn.source, equals(TransactionSource.notification));

      final ledgerRows = await db.query('transactions');
      expect(ledgerRows.length, equals(1));
      expect(ledgerRows.first['amount'], equals(350.0));
      expect(ledgerRows.first['merchantName'], equals('Starbucks'));
    });

    test(
        'Test C — Cross-source deduplication collapses SMS and Notification into 1 canonical transaction',
        () async {
      final timestamp = DateTime(2026, 8, 24, 16, 0).millisecondsSinceEpoch;

      // 1. First event arrives via SMS
      final smsMsg = NativeSmsMessage(
        address: 'HDFCBK',
        body:
            'Rs 450.00 debited from HDFC Bank A/c XX1234 on 24-Aug-26 at Starbucks. Ref UPI/987654321.',
        dateMillis: timestamp,
        source: 'sms',
      );
      final smsTxn = await ingestionService.ingestMessage(smsMsg);
      expect(smsTxn, isNotNull);

      // 2. Second event arrives via Notification for the same real-world event
      final notifMsg = NativeSmsMessage(
        address: 'PhonePe',
        packageName: 'com.phonepe.app',
        title: 'Paid to Starbucks',
        body: 'Rs 450.00 debited for UPI txn 987654321',
        dateMillis: timestamp + 2000, // arrived 2s later
        source: 'notification',
      );
      final notifTxn = await ingestionService.ingestMessage(notifMsg);

      // Duplicate notification must collapse and return null (not create second ledger row)
      expect(notifTxn, isNull);

      // Ledger must still contain EXACTLY 1 transaction
      final ledgerRows = await db.query('transactions');
      expect(ledgerRows.length, equals(1),
          reason:
              'Cross-source duplicates must never create 2 ledger transactions');
      expect(ledgerRows.first['amount'], equals(450.0));

      // Observations table contains BOTH observations with provenance linkage
      final obsRows = await db.query('financial_observations');
      expect(obsRows.length, equals(2));
      final states = obsRows.map((r) => r['state']).toSet();
      expect(states.contains('promoted'), isTrue);
      expect(states.contains('linked'), isTrue);

      // Diagnostics check
      expect(IngestionDiagnostics().crossSourceMerged, equals(1));
    });

    group('Money received from people', () {
      test('a UPI credit from a person is "From people", not income', () async {
        final txn = await ingestionService.ingestMessage(NativeSmsMessage(
          address: 'JM-HDFCBK-S',
          body: 'Rs 1,500.00 credited to HDFC Bank A/c XX1234 on 24-Aug-26 '
              'from VPA 9876543210@ybl (RAHUL SHARMA). UPI Ref 412345678901.',
          dateMillis: DateTime(2026, 8, 24, 20).millisecondsSinceEpoch,
          source: 'sms',
        ));
        expect(txn, isNotNull);
        expect(txn!.type, TransactionType.income);
        expect(txn.categoryId, kFromPeopleCategoryId);
        expect(txn.isFromPeople, isTrue);
        expect(txn.countsAsIncome, isFalse);
      });

      test('a salary credit stays income', () async {
        final txn = await ingestionService.ingestMessage(NativeSmsMessage(
          address: 'JM-HDFCBK-S',
          body: 'Rs 50,000.00 credited to HDFC Bank A/c XX1234 on 01-Sep-26 '
              'by NEFT from ACME TECHNOLOGIES PVT LTD - SALARY. '
              'Ref N244260012345.',
          dateMillis: DateTime(2026, 9, 1, 10).millisecondsSinceEpoch,
          source: 'sms',
        ));
        expect(txn, isNotNull);
        expect(txn!.categoryId, isNot(kFromPeopleCategoryId));
        expect(txn.categoryId, 'cat_salary');
        expect(txn.countsAsIncome, isTrue);
      });

      test('salary wording is recognised; a "Salary A/c" alone is not', () {
        const salary = [
          'Rs 50,000 credited by NEFT from ACME PVT LTD - SALARY.',
          'Your a/c XX1234 is credited with INR 42,000 towards Payroll Oct-26.',
          'INR 38,500 SAL CR to A/c XX1234 from EMPLOYER LTD.',
          'Rs 30,000 credited. Sal for Oct from Acme.',
        ];
        const notSalary = [
          'Rs 1,500 credited to your Salary A/c XX1234 from VPA x@ybl.',
          'Rs 900 credited to Salary Account XX1234 by UPI from PRIYA S.',
          'Rs 299 refund credited to A/c XX1234 from AMAZON.',
        ];
        for (final t in salary) {
          expect(FinancialIngestionService.looksLikeSalary(t), isTrue,
              reason: t);
        }
        for (final t in notSalary) {
          expect(FinancialIngestionService.looksLikeSalary(t), isFalse,
              reason: t);
        }
      });

      test('a refund from a shop stays a refund', () async {
        final txn = await ingestionService.ingestMessage(NativeSmsMessage(
          address: 'JM-HDFCBK-S',
          body: 'Refund of Rs 299.00 credited to HDFC Bank A/c XX1234 from '
              'AMAZON on 02-Sep-26. Ref 512345678901.',
          dateMillis: DateTime(2026, 9, 2, 12).millisecondsSinceEpoch,
          source: 'sms',
        ));
        expect(txn, isNotNull);
        expect(txn!.categoryId, isNot(kFromPeopleCategoryId));
      });

      test('"Count as income" sticks for future credits from that payee',
          () async {
        NativeSmsMessage credit(int day, String ref) => NativeSmsMessage(
              address: 'JM-HDFCBK-S',
              body: 'Rs 2,000.00 credited to HDFC Bank A/c XX1234 on '
                  '$day-Sep-26 from VPA 9876500001@ybl (NEHA VERMA). '
                  'UPI Ref $ref.',
              dateMillis: DateTime(2026, 9, day, 18).millisecondsSinceEpoch,
              source: 'sms',
            );
        final first =
            await ingestionService.ingestMessage(credit(3, '412300000001'));
        expect(first!.categoryId, kFromPeopleCategoryId);

        // The user flips "Count as income" on (e.g. rent from a tenant).
        await ingestionService.rememberIncomeChoice(
            first.copyWith(categoryId: 'cat_other_income'));

        final next =
            await ingestionService.ingestMessage(credit(10, '412300000002'));
        expect(next!.categoryId, 'cat_other_income');
        expect(next.countsAsIncome, isTrue);
      });

      test('a "From people" rule never labels money paid to that person', () {
        expect(
          FinancialIngestionService.learnedCategoryFits(kFromPeopleCategoryId,
              isIncome: false),
          isNull,
        );
        expect(
          FinancialIngestionService.learnedCategoryFits(kFromPeopleCategoryId,
              isIncome: true),
          kFromPeopleCategoryId,
        );
        expect(
          FinancialIngestionService.learnedCategoryFits('cat_food',
              isIncome: true),
          isNull,
        );
        expect(
          FinancialIngestionService.learnedCategoryFits('my_custom_cat',
              isIncome: false),
          'my_custom_cat',
        );
      });
    });

    group('Transfers and card-bill payments (audit P2-10)', () {
      test('are recognised; card purchases are not', () {
        const transfers = [
          'Payment of Rs 15,000.00 received towards your HDFC Bank Credit Card XX4321. Thank you.',
          'Rs 15000.00 debited from A/c XX1234 for Credit Card Bill payment.',
          'We have received payment of Rs.8,450.00 on your ICICI Bank Credit Card.',
          'Rs 5000 transferred to self A/c XX9876 via IMPS.',
          'Rs 2,000 debited towards your own account XX5555. Self transfer.',
        ];
        const purchases = [
          'Rs 500.00 spent on your HDFC Bank Credit Card XX4321 at AMAZON on 24-Aug-26.',
          'Rs 450.00 debited from HDFC Bank A/c XX1234 at Starbucks. Ref UPI/987654321.',
          'Rs 20000.00 credited to A/c XX1234 by NEFT from ACME PVT LTD (salary).',
        ];
        for (final t in transfers) {
          expect(FinancialIngestionService.isPossibleTransfer(t), isTrue,
              reason: t);
        }
        for (final t in purchases) {
          expect(FinancialIngestionService.isPossibleTransfer(t), isFalse,
              reason: t);
        }
      });

      test('a card-bill payment goes to Review instead of the ledger',
          () async {
        final txn = await ingestionService.ingestMessage(NativeSmsMessage(
          address: 'HDFCBK',
          body: 'Rs 15000.00 debited from HDFC Bank A/c XX1234 on 24-Aug-26 '
              'for Credit Card Bill payment. Ref 4455667788.',
          dateMillis: DateTime(2026, 8, 24, 10).millisecondsSinceEpoch,
          source: 'sms',
        ));
        expect(txn, isNull);
        expect(await db.query('transactions'), isEmpty);
        final pending = await ingestionService.getPendingReviewObservations();
        expect(
            pending.map((o) => o.stateReason), contains('possible_transfer'));
      });

      test('accepting it as a transfer keeps it out of income and spending',
          () async {
        await ingestionService.ingestMessage(NativeSmsMessage(
          address: 'HDFCBK',
          body: 'Rs 15000.00 debited from HDFC Bank A/c XX1234 on 24-Aug-26 '
              'for Credit Card Bill payment. Ref 4455667788.',
          dateMillis: DateTime(2026, 8, 24, 10).millisecondsSinceEpoch,
          source: 'sms',
        ));
        final id = (await ingestionService.getPendingReviewObservations())
            .single
            .observationId;

        final txn = await ingestionService.confirmObservation(
          observationId: id,
          overrideType: TransactionType.transfer,
        );

        expect(txn!.type, TransactionType.transfer);
        expect(txn.categoryId, kTransferCategoryId);
        expect(txn.countsAsIncome, isFalse);
        // The SMS list keeps the direction the message shows.
        final sms = await db
            .query('sms_transactions', where: 'id = ?', whereArgs: [id]);
        expect(sms.single['transactionType'], 'debit');
      });

      test('a learned Transfer category fits either direction', () {
        expect(
          FinancialIngestionService.learnedCategoryFits(kTransferCategoryId,
              isIncome: false),
          kTransferCategoryId,
        );
        expect(
          FinancialIngestionService.learnedCategoryFits(kTransferCategoryId,
              isIncome: true),
          kTransferCategoryId,
        );
      });
    });

    group('Cross-source dedup edge cases (audit P2-9)', () {
      Future<int> ledgerCount() async =>
          (await db.rawQuery('SELECT COUNT(*) AS c FROM transactions'))
              .first['c'] as int;

      test('notification without a ref + SMS with a ref → one transaction',
          () async {
        final t = DateTime(2026, 8, 24, 16, 0);
        await ingestionService.ingestMessage(NativeSmsMessage(
          address: 'PhonePe',
          packageName: 'com.phonepe.app',
          title: 'Paid to Starbucks',
          body: 'Rs 350.00 using HDFC Bank A/c',
          dateMillis: t.millisecondsSinceEpoch,
          source: 'notification',
        ));
        await ingestionService.ingestMessage(NativeSmsMessage(
          address: 'HDFCBK',
          body: 'Rs 350.00 debited from HDFC Bank A/c XX1234 on 24-Aug-26 '
              'at Starbucks. Ref UPI/555666777.',
          dateMillis: t.add(const Duration(minutes: 2)).millisecondsSinceEpoch,
          source: 'sms',
        ));
        expect(await ledgerCount(), 1);
      });

      test('same payment either side of a 15-minute bucket edge → one',
          () async {
        // 16:14:50 and 16:15:10 fall in different fixed 15-minute buckets.
        final t = DateTime(2026, 8, 24, 16, 14, 50);
        await ingestionService.ingestMessage(NativeSmsMessage(
          address: 'PhonePe',
          packageName: 'com.phonepe.app',
          title: 'Paid to Starbucks',
          body: 'Rs 275.00 using HDFC Bank A/c',
          dateMillis: t.millisecondsSinceEpoch,
          source: 'notification',
        ));
        await ingestionService.ingestMessage(NativeSmsMessage(
          address: 'HDFCBK',
          body: 'Rs 275.00 debited from HDFC Bank A/c XX1234 on 24-Aug-26 '
              'at Starbucks.',
          dateMillis: t.add(const Duration(seconds: 20)).millisecondsSinceEpoch,
          source: 'sms',
        ));
        expect(await ledgerCount(), 1);
      });

      test('two genuine identical payments from the same source → two',
          () async {
        final t = DateTime(2026, 8, 24, 9, 1);
        Future<void> pay(DateTime at, String bal) =>
            ingestionService.ingestMessage(NativeSmsMessage(
              address: 'HDFCBK',
              body: 'Rs 20.00 debited from HDFC Bank A/c XX1234 on 24-Aug-26 '
                  'at Chai Point. Avl Bal Rs $bal.',
              dateMillis: at.millisecondsSinceEpoch,
              source: 'sms',
            ));
        await pay(t, '1,000.00');
        await pay(t.add(const Duration(minutes: 3)), '980.00');
        expect(await ledgerCount(), 2);
      });

      test('the same SMS text delivered twice (different receive times) → one',
          () async {
        final t = DateTime(2026, 8, 24, 11, 0);
        const body = 'Rs 20.00 debited from HDFC Bank A/c XX1234 on 24-Aug-26 '
            'at Chai Point. Avl Bal Rs 1,000.00.';
        for (final offset in [0, 900]) {
          await ingestionService.ingestMessage(NativeSmsMessage(
            address: 'HDFCBK',
            body: body,
            dateMillis:
                t.add(Duration(milliseconds: offset)).millisecondsSinceEpoch,
            source: 'sms',
          ));
        }
        expect(await ledgerCount(), 1);
      });

      test('different merchants with the same amount stay separate', () async {
        final t = DateTime(2026, 8, 24, 13, 0);
        await ingestionService.ingestMessage(NativeSmsMessage(
          address: 'PhonePe',
          packageName: 'com.phonepe.app',
          title: 'Paid to Starbucks',
          body: 'Rs 199.00 using HDFC Bank A/c',
          dateMillis: t.millisecondsSinceEpoch,
          source: 'notification',
        ));
        await ingestionService.ingestMessage(NativeSmsMessage(
          address: 'HDFCBK',
          body: 'Rs 199.00 debited from HDFC Bank A/c XX1234 on 24-Aug-26 '
              'at Dominos.',
          dateMillis: t.add(const Duration(minutes: 1)).millisecondsSinceEpoch,
          source: 'sms',
        ));
        expect(await ledgerCount(), 2);
      });
    });

    test(
        'Test E — Uncertain transaction holds in review queue without entering core ledger until confirmed',
        () async {
      // Ambiguous message with moderate confidence (0.35 - 0.79)
      final msg = NativeSmsMessage(
        address: 'HDFCBK',
        body: 'Rs 150.00 debited at Unknown Shop. Info txn.',
        dateMillis: DateTime(2026, 8, 24, 17, 0).millisecondsSinceEpoch,
        source: 'sms',
      );

      final txn = await ingestionService.ingestMessage(msg);
      // Below auto-accept threshold -> returns null
      expect(txn, isNull);

      // Ledger must be empty
      final ledgerRows = await db.query('transactions');
      expect(ledgerRows.isEmpty, isTrue);

      // Check review queue
      final pending = await ingestionService.getPendingReviewObservations();
      expect(pending.length, equals(1));
      expect(pending.first.state, equals(FinancialObservationState.uncertain));

      // User confirms in review queue
      final confirmedTxn = await ingestionService.confirmObservation(
        observationId: pending.first.observationId,
        overrideAmount: 150.0,
        overrideMerchant: 'Local Shop',
      );

      expect(confirmedTxn, isNotNull);
      expect(confirmedTxn!.amount, equals(150.0));
      expect(confirmedTxn.merchantName, equals('Local Shop'));

      // Core ledger now has the confirmed transaction
      final ledgerAfter = await db.query('transactions');
      expect(ledgerAfter.length, equals(1));
      expect(ledgerAfter.first['merchantName'], equals('Local Shop'));
    });

    group('Always add messages like this', () {
      NativeSmsMessage shopDebit(String amount, int hour) => NativeSmsMessage(
            address: 'HDFCBK',
            body: 'Rs $amount debited at Unknown Shop. Info txn.',
            dateMillis: DateTime(2026, 8, 25, hour).millisecondsSinceEpoch,
            source: 'sms',
          );

      test('after accepting with trust, the next one is added directly',
          () async {
        expect(await ingestionService.ingestMessage(shopDebit('150.00', 9)),
            isNull);
        final pending = await ingestionService.getPendingReviewObservations();
        final id = pending.single.observationId;
        await ingestionService.confirmObservation(observationId: id);
        expect(
          await ingestionService.trustObservation(id,
              type: TransactionType.expense),
          isNotNull,
        );

        final next =
            await ingestionService.ingestMessage(shopDebit('275.50', 13));
        expect(next, isNotNull);
        expect(next!.amount, 275.50);
        final obs = await db.query('financial_observations',
            where: 'canonicalTransactionId = ?', whereArgs: [next.id]);
        expect(obs.single['stateReason'], 'trusted_template_auto_promotion');
      });

      test('without trust, or after undo, it still goes to review', () async {
        await ingestionService.ingestMessage(shopDebit('150.00', 9));
        final id = (await ingestionService.getPendingReviewObservations())
            .single
            .observationId;
        await ingestionService.confirmObservation(observationId: id);
        final hash = await ingestionService.trustObservation(id,
            type: TransactionType.expense);
        await ingestionService.untrustTemplate(hash!);

        expect(await ingestionService.ingestMessage(shopDebit('80.00', 15)),
            isNull);
      });

      test('a trusted debit shape does not accept money in', () async {
        await ingestionService.ingestMessage(shopDebit('150.00', 9));
        final id = (await ingestionService.getPendingReviewObservations())
            .single
            .observationId;
        await ingestionService.confirmObservation(observationId: id);
        // The user (wrongly) accepted it as money in: debits of this shape
        // must still be reviewed.
        await ingestionService.trustObservation(id,
            type: TransactionType.income);
        expect(await ingestionService.ingestMessage(shopDebit('60.00', 16)),
            isNull);
      });
    });

    test(
        'Test F — Rejected transaction records persistent tombstone and prevents resurrection on re-scan',
        () async {
      final msg = NativeSmsMessage(
        address: 'SBIINB',
        body: 'Rs 120.00 debited at Unknown Vendor. Info txn.',
        dateMillis: DateTime(2026, 8, 24, 18, 0).millisecondsSinceEpoch,
        source: 'sms',
      );

      // Ingest -> routes to review
      await ingestionService.ingestMessage(msg);
      final pending = await ingestionService.getPendingReviewObservations();
      expect(pending.length, equals(1));

      // User rejects the observation
      await ingestionService.rejectObservation(
        observationId: pending.first.observationId,
        reason: 'not_a_real_expense',
      );

      // Verify rejected state
      final obsRows = await db.query('financial_observations');
      expect(obsRows.first['state'],
          equals(FinancialObservationState.rejected.name));

      // Verify tombstone in sms_processing_state
      final stateRows = await db.query('sms_processing_state');
      expect(stateRows.first['status'], equals('rejected'));

      // Re-scan inbox: ingest same message again
      final rescanResult = await ingestionService.ingestMessage(msg);
      expect(rescanResult, isNull,
          reason: 'Re-ingesting rejected event must be dropped');

      // Core ledger remains empty
      final ledgerRows = await db.query('transactions');
      expect(ledgerRows.isEmpty, isTrue,
          reason: 'Rejected event must never enter core ledger');
    });

    test(
        'Test H — Bill statement is routed to commitments and does NOT create an expense in ledger',
        () async {
      final msg = NativeSmsMessage(
        address: 'HDFCBK',
        body:
            'Total Amount Due on your HDFC Bank Credit Card ending 5678 is Rs 14,500.00. Payment Due Date 25-Aug-2026. Min Due Rs 1,000.00.',
        dateMillis: DateTime(2026, 8, 24, 19, 0).millisecondsSinceEpoch,
        source: 'sms',
      );

      final txn = await ingestionService.ingestMessage(msg);

      // Must NOT be an expense in core ledger
      expect(txn, isNull);
      final ledgerRows = await db.query('transactions');
      expect(ledgerRows.isEmpty, isTrue,
          reason:
              'Credit card bill statement must never be treated as an expense transaction');

      // Diagnostics check
      expect(IngestionDiagnostics().billEvents, equals(1));
    });

    test(
        'Test I — Balance-only notification does NOT manufacture a fake expense transaction',
        () async {
      final msg = NativeSmsMessage(
        address: 'SBIINB',
        body:
            'Dear Customer, Available balance for your A/c XX1234 is Rs 45,230.50 as on 24-Aug-2026.',
        dateMillis: DateTime(2026, 8, 24, 20, 0).millisecondsSinceEpoch,
        source: 'sms',
      );

      final txn = await ingestionService.ingestMessage(msg);

      expect(txn, isNull);
      final ledgerRows = await db.query('transactions');
      expect(ledgerRows.isEmpty, isTrue,
          reason: 'Balance alert must never manufacture a fake transaction');

      expect(IngestionDiagnostics().balanceObservations, equals(1));
    });

    test(
        'Test J — Refund message creates income transaction in canonical ledger',
        () async {
      final msg = NativeSmsMessage(
        address: 'HDFCBK',
        body:
            'Rs 299.00 credited to your HDFC Bank A/c XX1234 towards refund from Zomato. Ref 456789123.',
        dateMillis: DateTime(2026, 8, 24, 21, 0).millisecondsSinceEpoch,
        source: 'sms',
      );

      final txn = await ingestionService.ingestMessage(msg);

      expect(txn, isNotNull);
      expect(txn!.amount, equals(299.0));
      expect(txn.type, equals(TransactionType.income));
      expect(txn.merchantName, equals('Zomato'));

      final ledgerRows = await db.query('transactions');
      expect(ledgerRows.length, equals(1));
      expect(ledgerRows.first['type'], equals('income'));
    });

    test(
        'Test K — User learned merchant rule deterministically overrides classification',
        () async {
      // 1. Learn a custom rule
      await merchantRuleService.learnRule(
        identifier: 'kirana_store@upi',
        learnedMerchantName: 'Sharma Grocery Store',
        categoryId: 'cat_food',
      );

      // 2. Ingest transaction with this UPI ID
      final msg = NativeSmsMessage(
        address: 'HDFCBK',
        body:
            'Rs 650.00 debited from HDFC Bank A/c XX1234 to VPA kirana_store@upi on 24-Aug-26. Ref 112233.',
        dateMillis: DateTime(2026, 8, 24, 22, 0).millisecondsSinceEpoch,
        source: 'sms',
      );

      final txn = await ingestionService.ingestMessage(msg);

      expect(txn, isNotNull);
      expect(txn!.merchantName, equals('Sharma Grocery Store'));
      expect(txn.categoryId, equals('cat_food'));
    });
  });
}
