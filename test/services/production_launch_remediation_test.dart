import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:pet/data/models/enums.dart';
import 'package:pet/data/models/transaction.dart';
import 'package:pet/data/models/recurring_rule.dart';
import 'package:pet/services/sms_service.dart';

void main() {
  group('Production Launch Remediation & Security Invariant Tests', () {
    test('PET-01: Target SDK is 36 in build.gradle.kts', () {
      final buildGradle = File('android/app/build.gradle.kts').readAsStringSync();
      expect(buildGradle.contains('targetSdk = 36'), isTrue,
          reason: 'Google Play requires targetSdk = 36 for August 2026 submissions.');
      expect(buildGradle.contains('compileSdk = 36'), isTrue);
    });

    test('PET-02: Firestore security rules cover all core and premium collections with strict ownership', () {
      final rulesFile = File('firestore.rules').readAsStringSync();

      // Verify helper function
      expect(rulesFile.contains('function isOwner(uid)'), isTrue);
      expect(rulesFile.contains('request.auth != null && request.auth.uid == uid'), isTrue);

      // Verify all required subcollections have explicit match blocks
      final requiredCollections = [
        'transactions',
        'categories',
        'budgets',
        'recurring_rules',
        'recurring_occurrences',
        'tombstones',
        'saving_goals',
        'recurring_payments',
        'alerts',
        'tax_categories',
        'linked_accounts',
        'family_members',
      ];

      for (final collection in requiredCollections) {
        expect(
          rulesFile.contains('match /$collection/{'),
          isTrue,
          reason: 'firestore.rules must contain explicit match block for $collection',
        );
      }

      // Verify default-deny root rule
      expect(rulesFile.contains('match /{document=**} {\n      allow read, write: if false;'), isTrue);
    });

    test('PET-03: Cloudflare Worker enforces server-side system prompt and sanitizes context injection', () {
      final workerSource = File('cloudflare_worker/src/index.js').readAsStringSync();

      expect(workerSource.contains('TRUSTED_SYSTEM_PROMPT'), isTrue);
      expect(workerSource.contains('sanitizeContextSnapshot'), isTrue);
      expect(workerSource.contains('messages: messagesToForward'), isTrue);
      expect(workerSource.contains('invalid_system_message_position'), isTrue);
    });

    test('PET-04: Privacy Policy accurately discloses all third-party processors and AI payload details', () {
      final policy = File('PRIVACY_POLICY.md').readAsStringSync();

      expect(policy.contains('Firebase Authentication'), isTrue);
      expect(policy.contains('Google Cloud Firestore'), isTrue);
      expect(policy.contains('Firebase Crashlytics'), isTrue);
      expect(policy.contains('Cloudflare Workers'), isTrue);
      expect(policy.contains('Groq API'), isTrue);
      expect(policy.contains('RevenueCat'), isTrue);
      expect(policy.contains('Anonymized monthly category totals'), isTrue);
    });

    test('PET-05: External Account Deletion page exists and meets Play Store requirements', () {
      final htmlFile = File('docs/account-deletion.html');
      expect(htmlFile.existsSync(), isTrue);

      final content = htmlFile.readAsStringSync();
      expect(content.contains('P.E.T. — Data Erasure'), isTrue);
      expect(content.contains('In-App Deletion'), isTrue);
      expect(content.contains('Web-Based Deletion Request'), isTrue);
      expect(content.contains('mailto:psuvraneel@gmail.com'), isTrue);
      expect(content.contains('Firebase Authentication Record'), isTrue);
      expect(content.contains('SQLCipher 256-bit encrypted database'), isTrue);
    });

    test('PET-06: Stale Supabase environment variables are removed from AppEnv and .env', () {
      final envFile = File('.env').readAsStringSync();
      expect(envFile.contains('SUPABASE_URL'), isFalse);
      expect(envFile.contains('SUPABASE_ANON_KEY'), isFalse);

      final manifest = File('android/app/src/main/AndroidManifest.xml').readAsStringSync();
      expect(manifest.contains('Supabase'), isFalse);
    });

    test('Financial Data Invariant: PII redaction cleans sensitive numbers from note/merchant strings', () {
      const rawInfo = 'Card ending 5123456789012345, Phone: 9876543210, Account 123456789012';
      final redacted = SmsService.redactSensitiveData(rawInfo);
      expect(redacted.contains('5123456789012345'), isFalse);
      expect(redacted.contains('9876543210'), isFalse);
      expect(redacted.contains('123456789012'), isFalse);
      expect(redacted.contains('XX****'), isTrue);

      const rawAccount = 'debited from A/c XX1234 on 15-Aug-2026';
      final redactedAccount = SmsService.redactSensitiveData(rawAccount);
      expect(redactedAccount.contains('XX1234'), isTrue); // Pre-masked form preserved
    });

    test('Model Serialization: RecurringRule and Transaction toFirestore formats adhere to schema', () {
      final now = DateTime(2026, 8, 24, 12, 0);
      final rule = RecurringRule(
        id: 'rule_1',
        amount: 499.0,
        type: TransactionType.expense,
        categoryId: 'subscriptions',
        note: 'Netflix Subscription',
        paymentMethod: PaymentMethod.creditCard,
        frequency: RecurringFrequency.monthly,
        startDate: now,
        nextOccurrenceDate: now.add(const Duration(days: 30)),
        createdAt: now,
        updatedAt: now,
      );

      final firestoreMap = rule.toFirestore();
      expect(firestoreMap['amount'], equals(499.0));
      expect(firestoreMap['type'], equals('expense'));
      expect(firestoreMap['categoryId'], equals('subscriptions'));
      expect(firestoreMap['frequency'], equals('monthly'));
      expect(firestoreMap['isActive'], isTrue);

      final txn = TransactionRecord(
        id: 'txn_1',
        amount: 250.0,
        type: TransactionType.expense,
        categoryId: 'food',
        date: now,
        updatedAt: now,
        note: 'Lunch at Cafe',
        paymentMethod: PaymentMethod.upi,
      );

      final txnMap = txn.toFirestore();
      expect(txnMap['amount'], equals(250.0));
      expect(txnMap['type'], equals('expense'));
      expect(txnMap['categoryId'], equals('food'));
    });
  });
}
