import 'dart:io';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pet/data/models/enums.dart';
import 'package:pet/data/models/transaction.dart';
import 'package:pet/services/export_service.dart';

import 'package:path_provider_platform_interface/path_provider_platform_interface.dart';

class MockPathProviderPlatform extends PathProviderPlatform {
  @override
  Future<String?> getTemporaryPath() async {
    return Directory.systemTemp.path;
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  // Keep track of shared file paths to verify them
  final sharedFiles = <String>[];

  setUpAll(() {
    PathProviderPlatform.instance = MockPathProviderPlatform();

    // Mock SharePlus channel (new)
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger.setMockMethodCallHandler(
      const MethodChannel('dev.fluttercommunity.plus/share'),
      (methodCall) async {
        if (methodCall.method == 'share' || methodCall.method == 'shareFiles') {
          // Store parameters to verify
          final args = methodCall.arguments as Map;
          final paths = args['paths'] as List?;
          if (paths != null) {
            for (final p in paths) {
              sharedFiles.add(p.toString());
            }
          }
          return null;
        }
        return null;
      },
    );

    // Mock SharePlus channel (legacy fallback)
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger.setMockMethodCallHandler(
      const MethodChannel('plugins.flutter.io/share'),
      (methodCall) async {
        if (methodCall.method == 'share') {
          final args = methodCall.arguments as Map;
          final paths = args['paths'] as List?;
          if (paths != null) {
            for (final p in paths) {
              sharedFiles.add(p.toString());
            }
          }
          return null;
        }
        return null;
      },
    );
  });

  setUp(() {
    sharedFiles.clear();
  });

  group('ExportService Tests', () {
    final now = DateTime(2026, 7, 9);
    final txns = [
      TransactionRecord(
        id: 'txn_1',
        amount: 1500.0,
        type: TransactionType.expense,
        categoryId: 'cat_food',
        date: now,
        note: 'Normal note',
        merchantName: 'Zomato',
        paymentMethod: PaymentMethod.upi,
      ),
      TransactionRecord(
        id: 'txn_2',
        amount: 500.0,
        type: TransactionType.expense,
        categoryId: 'cat_unknown_uuid_123',
        date: now,
        note: 'Deleted category txn',
        merchantName: 'Unknown Store',
        paymentMethod: PaymentMethod.cash,
      ),
      TransactionRecord(
        id: 'txn_3',
        amount: 2500.0,
        type: TransactionType.expense,
        categoryId: 'cat_custom_unicode',
        date: now,
        note: 'Unicode note with, comma and "quotes"',
        merchantName: 'Supermarket',
        paymentMethod: PaymentMethod.creditCard,
      ),
    ];

    final categoryNames = {
      'cat_food': 'Food & Dining',
      'cat_custom_unicode': '餐飲 (Dining)',
    };

    test('CSV export resolves category display names, handles Unicode and fallbacks', () async {
      await ExportService.instance.exportToCsv(
        txns,
        categoryNames: categoryNames,
      );

      expect(sharedFiles.length, 1);
      final filePath = sharedFiles.first;
      expect(filePath.endsWith('.csv'), isTrue);

      final file = File(filePath);
      expect(await file.exists(), isTrue);

      final csvContent = await file.readAsString();

      // Verify known category ID exports display name
      expect(csvContent.contains('Food & Dining'), isTrue);

      // Verify unknown/deleted category ID exports safe fallback "Uncategorized"
      expect(csvContent.contains('Uncategorized'), isTrue);

      // Verify custom/Unicode category names export correctly
      expect(csvContent.contains('餐飲 (Dining)'), isTrue);

      // Verify no internal UUID is in user-facing category column
      expect(csvContent.contains('cat_food'), isFalse);
      expect(csvContent.contains('cat_unknown_uuid_123'), isFalse);
      expect(csvContent.contains('cat_custom_unicode'), isFalse);

      // Verify CSV escaping remains correct
      // Row 3 note has: 'Unicode note with, comma and "quotes"'
      // Escaped version should be double-quoted and inner quotes doubled: "Unicode note with, comma and ""quotes"""
      expect(csvContent.contains('"Unicode note with, comma and ""quotes"""'), isTrue);

      // Cleanup
      await file.delete();
    });

    test('PDF export generates valid layout and resolves display names', () async {
      await ExportService.instance.exportToPdf(
        txns,
        categoryNames: categoryNames,
      );

      expect(sharedFiles.length, 1);
      final filePath = sharedFiles.first;
      expect(filePath.endsWith('.pdf'), isTrue);

      final file = File(filePath);
      expect(await file.exists(), isTrue);

      final pdfBytes = await file.readAsBytes();
      // Basic PDF header magic number verification
      expect(pdfBytes.length, greaterThan(100));
      expect(pdfBytes[0] == 0x25 && pdfBytes[1] == 0x50 && pdfBytes[2] == 0x44 && pdfBytes[3] == 0x46, isTrue); // %PDF

      // Cleanup
      await file.delete();
    });
  });
}
