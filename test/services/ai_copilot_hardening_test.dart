import 'package:flutter_test/flutter_test.dart';
import 'package:pet/premium/services/ai_copilot_service.dart';
import 'package:pet/premium/services/ai_rate_limiter.dart';
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

  group('AuthErrorException Tests', () {
    test('AuthErrorException formatting and properties', () {
      const exception = AuthErrorException(
        401,
        'Unauthorized: Token has expired',
        errorCode: 'AUTH_TOKEN_EXPIRED',
      );
      expect(exception.statusCode, equals(401));
      expect(exception.message, equals('Unauthorized: Token has expired'));
      expect(exception.errorCode, equals('AUTH_TOKEN_EXPIRED'));
      expect(exception.toString(), equals('Unauthorized: Token has expired'));
    });

    test('AUTH_TOKEN_EXPIRED is retryable', () {
      const exception = AuthErrorException(
        401,
        'Token expired',
        errorCode: 'AUTH_TOKEN_EXPIRED',
      );
      expect(exception.isRetryable, isTrue);
    });

    test('AUTH_TOKEN_UNKNOWN_KEY is retryable', () {
      const exception = AuthErrorException(
        401,
        'Unknown key',
        errorCode: 'AUTH_TOKEN_UNKNOWN_KEY',
      );
      expect(exception.isRetryable, isTrue);
    });

    test('null errorCode is retryable (fallback for old Worker)', () {
      const exception = AuthErrorException(401, 'Some error');
      expect(exception.isRetryable, isTrue);
    });

    test('AUTH_TOKEN_INVALID_AUDIENCE is NOT retryable', () {
      const exception = AuthErrorException(
        401,
        'Wrong audience',
        errorCode: 'AUTH_TOKEN_INVALID_AUDIENCE',
      );
      expect(exception.isRetryable, isFalse);
    });

    test('AUTH_TOKEN_INVALID_ISSUER is NOT retryable', () {
      const exception = AuthErrorException(
        401,
        'Wrong issuer',
        errorCode: 'AUTH_TOKEN_INVALID_ISSUER',
      );
      expect(exception.isRetryable, isFalse);
    });

    test('AUTH_TOKEN_INVALID_SIGNATURE is NOT retryable', () {
      const exception = AuthErrorException(
        401,
        'Bad signature',
        errorCode: 'AUTH_TOKEN_INVALID_SIGNATURE',
      );
      expect(exception.isRetryable, isFalse);
    });

    test('AUTH_CONFIGURATION_ERROR is NOT retryable', () {
      const exception = AuthErrorException(
        401,
        'Config error',
        errorCode: 'AUTH_CONFIGURATION_ERROR',
      );
      expect(exception.isRetryable, isFalse);
    });
  });

  group('Rate Limit Alignment Tests', () {
    test('Client daily limit matches server authoritative limit of 200', () {
      // The server enforces 200/day. The client must match.
      final limiter = AiRateLimiter();
      final summary = limiter.quotaSummary();
      // Initial state: all limits at maximum
      expect(summary, contains('10/min'));
      expect(summary, contains('50/hr'));
      expect(summary, contains('200/day'));
    });

    test('Client daily limit does NOT show old value of 150', () {
      final limiter = AiRateLimiter();
      final summary = limiter.quotaSummary();
      expect(summary, isNot(contains('150/day')));
    });
  });
}
