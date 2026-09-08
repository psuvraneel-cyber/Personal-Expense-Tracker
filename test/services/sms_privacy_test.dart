import 'package:flutter_test/flutter_test.dart';
import 'package:pet/services/sms_service.dart';
import 'package:pet/services/classification_rule_engine.dart';

void main() {
  group('SMS and Notification Privacy Tests', () {
    test('redactSensitiveData masks account and phone numbers', () {
      // 1. Account number masking (keep last 4 digits)
      final bodyWithAccount =
          'Your a/c no. 5678901234 has been debited by Rs.500';
      final redactedAccount = SmsService.redactSensitiveData(bodyWithAccount);
      expect(redactedAccount, contains('XX****1234'));
      expect(redactedAccount, isNot(contains('5678901234')));

      // 2. Phone number masking (+91 or 10-digit)
      final bodyWithPhone = 'Money sent to +919876543210 for snacks';
      final redactedPhone = SmsService.redactSensitiveData(bodyWithPhone);
      expect(redactedPhone, contains('XX****3210'));
      expect(redactedPhone, isNot(contains('9876543210')));
    });

    test(
      'Non-financial / OTP / personal messages are rejected by ClassificationRuleEngine',
      () async {
        final now = DateTime.now();

        // 1. OTP message
        final otpMsg = 'Your OTP for transaction is 459201. Do not share.';
        final classifiedOtp = await ClassificationRuleEngine.classify(
          otpMsg,
          'AD-HDFCBK',
          now,
        );
        expect(classifiedOtp, isNull);

        // 2. Personal message
        final personalMsg = 'Hey, did you pick up the milk? Let me know.';
        final classifiedPersonal = await ClassificationRuleEngine.classify(
          personalMsg,
          'Sender',
          now,
        );
        expect(classifiedPersonal, isNull);

        // 3. Marketing spam
        final marketingMsg =
            'Get 50% off on your next purchase at Dominos! Use code PIZZA50.';
        final classifiedMarketing = await ClassificationRuleEngine.classify(
          marketingMsg,
          'DOMINOS',
          now,
        );
        expect(classifiedMarketing, isNull);
      },
    );

    test('Financial notification parser consensus classification', () async {
      final now = DateTime.now();

      // Valid financial notification (consensus parsing)
      final validNotification =
          'INR 500 debited from a/c XX1234 towards groceries';
      final classified = await ClassificationRuleEngine.classify(
        validNotification,
        'com.google.android.apps.nbu.paisa.user',
        now,
      );
      expect(classified, isNotNull);
      expect(classified!.amount, equals(500));
      expect(classified.transactionType, equals('debit'));
    });

    test('HIGH-1 Regression: 12-digit UPI ref numbers survive redaction unmangled', () {
      // HDFC Bank sample with 12-digit UPI Ref
      const hdfcMsg =
          'Rs 500.00 debited from A/c XX1234 on 20-Jul-26 to VPA swiggy@hdfcbank UPI Ref 402312345678.';
      final redactedHdfc = SmsService.redactSensitiveData(hdfcMsg);
      expect(
        redactedHdfc,
        contains('402312345678'),
      ); // 12-digit UPI ref preserved unmangled
      expect(
        redactedHdfc,
        isNot(contains('XX****5678')),
      ); // Not mangled as account/phone

      // SBI sample with ref no
      const sbiMsg =
          'Dear Customer, A/c 550123456789 debited by Rs 2500.00 on 20Jul26 ref no 123456789012.';
      final redactedSbi = SmsService.redactSensitiveData(sbiMsg);
      expect(
        redactedSbi,
        contains('123456789012'),
      ); // 12-digit ref no preserved unmangled
      expect(
        redactedSbi,
        contains('A/c XX****6789'),
      ); // Full account masked with last 4 retained

      // ICICI sample with full account & phone number
      const iciciMsg =
          'Your A/c 550123456789 is debited for Rs 1200. Call +919876543210 for help.';
      final redactedIcici = SmsService.redactSensitiveData(iciciMsg);
      expect(
        redactedIcici,
        contains('A/c XX****6789'),
      ); // Account masked (last 4 kept)
      expect(
        redactedIcici,
        contains('XX****3210'),
      ); // Phone masked (last 4 kept)
      expect(redactedIcici, isNot(contains('550123456789')));
      expect(redactedIcici, isNot(contains('9876543210')));

      // Axis sample with IMPS Ref No
      const axisMsg =
          'INR 350.00 debited from Card ending 5678 at Swiggy. IMPS Ref No 987654321098.';
      final redactedAxis = SmsService.redactSensitiveData(axisMsg);
      expect(
        redactedAxis,
        contains('987654321098'),
      ); // IMPS Ref preserved unmangled

      // UPI App (PhonePe / GPay) sample with helpline phone number
      const upiAppMsg =
          'Paid ₹150 to Swiggy using PhonePe. Contact helpline 9876543210 for support.';
      final redactedUpi = SmsService.redactSensitiveData(upiAppMsg);
      expect(
        redactedUpi,
        contains('XX****3210'),
      ); // Phone masked preserving last 4
      expect(redactedUpi, isNot(contains('9876543210')));
    });
  });
}
