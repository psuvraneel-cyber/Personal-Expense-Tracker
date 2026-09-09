import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:path/path.dart' as p;
import 'package:shared_preferences/shared_preferences.dart';

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
