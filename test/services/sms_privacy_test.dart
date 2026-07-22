import 'package:flutter_test/flutter_test.dart';
import 'package:pet/services/sms_service.dart';
import 'package:pet/services/classification_rule_engine.dart';

void main() {
  group('SMS and Notification Privacy Tests', () {
    test('redactSensitiveData masks account and phone numbers', () {
      // 1. Account number masking (keep last 4 digits)
      final bodyWithAccount = 'Your a/c no. 5678901234 has been debited by Rs.500';
      final redactedAccount = SmsService.redactSensitiveData(bodyWithAccount);
      expect(redactedAccount, contains('XX****1234'));
      expect(redactedAccount, isNot(contains('5678901234')));

      // 2. Phone number masking (+91 or 10-digit)
      final bodyWithPhone = 'Money sent to +919876543210 for snacks';
      final redactedPhone = SmsService.redactSensitiveData(bodyWithPhone);
      expect(redactedPhone, contains('XX****3210'));
      expect(redactedPhone, isNot(contains('9876543210')));
    });

    test('Non-financial / OTP / personal messages are rejected by ClassificationRuleEngine', () async {
      final now = DateTime.now();

      // 1. OTP message
      final otpMsg = 'Your OTP for transaction is 459201. Do not share.';
      final classifiedOtp = await ClassificationRuleEngine.classify(otpMsg, 'AD-HDFCBK', now);
      expect(classifiedOtp, isNull);

      // 2. Personal message
      final personalMsg = 'Hey, did you pick up the milk? Let me know.';
      final classifiedPersonal = await ClassificationRuleEngine.classify(personalMsg, 'Sender', now);
      expect(classifiedPersonal, isNull);

      // 3. Marketing spam
      final marketingMsg = 'Get 50% off on your next purchase at Dominos! Use code PIZZA50.';
      final classifiedMarketing = await ClassificationRuleEngine.classify(marketingMsg, 'DOMINOS', now);
      expect(classifiedMarketing, isNull);
    });

    test('Financial notification parser consensus classification', () async {
      final now = DateTime.now();

      // Valid financial notification (consensus parsing)
      final validNotification = 'INR 500 debited from a/c XX1234 towards groceries';
      final classified = await ClassificationRuleEngine.classify(
        validNotification,
        'com.google.android.apps.nbu.paisa.user',
        now,
      );
      expect(classified, isNotNull);
      expect(classified!.amount, equals(500));
      expect(classified.transactionType, equals('debit'));
    });
  });
}
