import 'package:flutter_test/flutter_test.dart';
import 'package:media_tracker/providers/auth_provider.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

void main() {
  group('describeAuthError', () {
    test('explains rate limiting', () {
      const error = AuthApiException(
        'Email rate limit exceeded',
        statusCode: '429',
      );

      expect(describeAuthError(error), contains('Too many requests'));
    });

    test('explains an invalid email address', () {
      const error = AuthApiException(
        'Unable to validate email address: invalid format',
        statusCode: '400',
        code: 'validation_failed',
      );

      expect(describeAuthError(error), contains('valid email'));
    });

    test('passes other messages through', () {
      const error = AuthApiException(
        'Signups not allowed for otp',
        statusCode: '422',
      );

      expect(describeAuthError(error), contains('disabled'));
    });

    test('always returns a non-empty message', () {
      const error = AuthApiException('', statusCode: '500');

      expect(describeAuthError(error), isNotEmpty);
    });
  });
}
