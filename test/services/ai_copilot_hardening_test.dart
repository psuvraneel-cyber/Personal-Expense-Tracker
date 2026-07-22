import 'package:flutter_test/flutter_test.dart';
import 'package:pet/premium/services/ai_copilot_service.dart';
import 'package:pet/services/sms_service.dart';

void main() {
  group('AI Copilot Hardening Tests', () {
    test('ClientErrorException formatting and properties', () {
      const exception = ClientErrorException(429, 'Rate limit exceeded');
      expect(exception.statusCode, equals(429));
      expect(exception.message, equals('Rate limit exceeded'));
      expect(exception.toString(), equals('Rate limit exceeded'));
    });

    test('Financial context fields are sanitized against sensitive values', () {
      // Test that the redaction function correctly masks account and phone numbers in notes
      final sensitiveNote = 'Paid to 9876543210 for a/c 1234567890';
      final redacted = SmsService.redactSensitiveData(sensitiveNote);
      
      // Both the phone number and account number should be masked
      expect(redacted, contains('XX****3210'));
      expect(redacted, contains('XX****7890'));
      expect(redacted, isNot(contains('9876543210')));
      // The account number tail '7890' gets masked based on length pattern matching, let's verify general safety:
      expect(redacted, isNot(contains('1234567890')));
    });

    test('Financial context merchant names are sanitized', () {
      final sensitiveMerchant = 'Merchant +918888888888';
      final redacted = SmsService.redactSensitiveData(sensitiveMerchant);
      expect(redacted, contains('XX****8888'));
      expect(redacted, isNot(contains('8888888888')));
    });
  });
}
