import 'dart:isolate';

import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pet/services/financial_ingestion_service.dart';

/// Regression: an SMS that arrives before the live listener attaches (app
/// start, right after granting SMS permission) is imported by a WorkManager
/// task in a background isolate. Its revision bumps must still reach the UI
/// isolate, or Home / History / Pending Review stay stale until a restart.
Future<void> _waitForChange(ValueNotifier<int> notifier, int from) async {
  final deadline = DateTime.now().add(const Duration(seconds: 5));
  while (notifier.value == from && DateTime.now().isBefore(deadline)) {
    await Future<void>.delayed(const Duration(milliseconds: 10));
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(FinancialIngestionService.listenForOtherIsolates);
  tearDown(FinancialIngestionService.stopListeningForOtherIsolates);

  test('ledger change in a background isolate reaches the UI isolate',
      () async {
    final ledger = FinancialIngestionService.ledgerRevision;
    final before = ledger.value;

    await Isolate.run(FinancialIngestionService.ledgerChangedForTesting);
    await _waitForChange(ledger, before);

    expect(ledger.value, before + 1);
  });

  test('review-queue change in a background isolate reaches the UI isolate',
      () async {
    final review = FinancialIngestionService.reviewRevision;
    final before = review.value;

    await Isolate.run(FinancialIngestionService.reviewChangedForTesting);
    await _waitForChange(review, before);

    expect(review.value, before + 1);
  });

  test('a change in the UI isolate is counted once', () async {
    final ledger = FinancialIngestionService.ledgerRevision;
    final before = ledger.value;

    FinancialIngestionService.ledgerChangedForTesting();
    await Future<void>.delayed(const Duration(milliseconds: 100));

    expect(ledger.value, before + 1);
  });
}
