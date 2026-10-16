import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'package:media_tracker/l10n/app_language.dart';
import 'package:media_tracker/l10n/app_strings.dart';
import 'package:media_tracker/providers/auth_provider.dart';

/// A signed-in session payload as GoTrue returns it from `/verify`.
String _sessionJson({String email = 'daniel@example.com'}) =>
    jsonEncode(<String, dynamic>{
      'access_token': 'access-token',
      'token_type': 'bearer',
      'expires_in': 3600,
      'refresh_token': 'refresh-token',
      'user': <String, dynamic>{
        'id': 'user-1',
        'aud': 'authenticated',
        'role': 'authenticated',
        'email': email,
        'app_metadata': <String, dynamic>{},
        'user_metadata': <String, dynamic>{},
        'created_at': '2026-01-01T00:00:00.000Z',
      },
    });

String _errorJson(String code, String message) =>
    jsonEncode(<String, dynamic>{'error_code': code, 'msg': message});

const _de = AppStrings(AppLanguage.de);

void main() {
  setUp(() => SharedPreferences.setMockInitialValues(<String, Object>{}));

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

    test('localizes the OTP-specific failures', () {
      const wrong = AuthApiException(
        'Invalid token',
        statusCode: '403',
        code: 'otp_invalid',
      );
      const expired = AuthApiException(
        'Token has expired or is invalid',
        statusCode: '403',
        code: 'otp_expired',
      );

      expect(describeAuthError(wrong, strings: _de), _de.authCodeInvalid);
      expect(describeAuthError(expired, strings: _de), _de.authCodeExpired);
      // A retryable fetch failure means the server was unreachable.
      expect(
        describeAuthError(
          AuthRetryableFetchException(message: 'SocketException'),
          strings: _de,
        ),
        _de.authNetworkError,
      );
    });
  });

  group('SupabaseAuthProvider.verifyEmailCode', () {
    /// Builds a provider whose GoTrue client answers `/verify` via [response].
    SupabaseAuthProvider provider(
      List<http.Request> requests,
      http.Response Function(http.Request request) response, {
      AppLanguage language = AppLanguage.en,
    }) {
      final client = SupabaseClient(
        'https://example.supabase.co',
        'public-anon-key',
        httpClient: MockClient((request) async {
          requests.add(request);
          return response(request);
        }),
      );
      final auth = SupabaseAuthProvider(
        client: client,
        language: () => language,
      );
      addTearDown(auth.dispose);
      return auth;
    }

    http.Response okResponse(http.Request request) => http.Response(
      _sessionJson(),
      200,
      request: request,
      headers: <String, String>{'content-type': 'application/json'},
    );

    http.Response expiredResponse(http.Request request) => http.Response(
      _errorJson('otp_expired', 'Token has expired or is invalid'),
      403,
      request: request,
      headers: <String, String>{'content-type': 'application/json'},
    );

    test('verifies the right email + code with OtpType.email', () async {
      final requests = <http.Request>[];
      final auth = provider(requests, okResponse);

      final error = await auth.verifyEmailCode(
        email: 'daniel@example.com',
        code: '123456',
      );

      expect(error, isNull);
      final verify = requests.singleWhere(
        (r) => r.url.path.endsWith('/verify'),
      );
      expect(verify.method, 'POST');
      final body = jsonDecode(verify.body) as Map<String, dynamic>;
      expect(body['email'], 'daniel@example.com');
      expect(body['token'], '123456');
      // `OtpType.email` serializes to the snake_case type `email`.
      expect(body['type'], 'email');
    });

    test('a successful verification signs the user in', () async {
      final auth = provider(<http.Request>[], okResponse);
      expect(auth.status, isNot(AuthStatus.signedIn));

      await auth.verifyEmailCode(email: 'daniel@example.com', code: '123456');
      // `onAuthStateChange` is a stream — let the event reach the provider.
      await Future<void>.delayed(Duration.zero);

      expect(auth.status, AuthStatus.signedIn);
      expect(auth.email, 'daniel@example.com');
    });

    test('returns a localized message for a bad / expired code', () async {
      final auth = provider(
        <http.Request>[],
        expiredResponse,
        language: AppLanguage.de,
      );

      final error = await auth.verifyEmailCode(
        email: 'daniel@example.com',
        code: '000000',
      );

      expect(error, _de.authCodeExpired);
      expect(auth.status, isNot(AuthStatus.signedIn));
    });

    test('catches a network failure', () async {
      final auth = provider(
        <http.Request>[],
        (request) => throw http.ClientException('offline', request.url),
        language: AppLanguage.de,
      );

      final error = await auth.verifyEmailCode(
        email: 'daniel@example.com',
        code: '123456',
      );

      expect(error, _de.authNetworkError);
    });
  });
}
