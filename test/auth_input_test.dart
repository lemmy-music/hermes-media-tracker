import 'package:flutter_test/flutter_test.dart';

import 'package:media_tracker/services/auth_input.dart';

void main() {
  group('parseAuthInput — numeric code', () {
    test('accepts a 6-digit code', () {
      final result = parseAuthInput('123456');
      expect(result.kind, AuthInputKind.code);
      expect(result.value, '123456');
      expect(result.isValid, isTrue);
    });

    test('accepts an 8-digit code', () {
      final result = parseAuthInput('12345678');
      expect(result.kind, AuthInputKind.code);
      expect(result.value, '12345678');
    });

    test('rejects a 5- or 9-digit run (not a code, not a token)', () {
      expect(parseAuthInput('12345').kind, AuthInputKind.invalid);
      expect(parseAuthInput('123456789').kind, AuthInputKind.invalid);
    });
  });

  group('parseAuthInput — pasted magic link', () {
    test('extracts the token from a full verify URL', () {
      final result = parseAuthInput(
        'https://example.supabase.co/auth/v1/verify'
        '?token=9c2d4f6a8b&type=magiclink&redirect_to=https://app.example/',
      );
      expect(result.kind, AuthInputKind.tokenHash);
      expect(result.value, '9c2d4f6a8b');
      expect(result.isValid, isTrue);
    });

    test('falls back to the token_hash query parameter', () {
      final result = parseAuthInput(
        'https://example.supabase.co/auth/v1/verify'
        '?token_hash=abc123def456&type=magiclink',
      );
      expect(result.kind, AuthInputKind.tokenHash);
      expect(result.value, 'abc123def456');
    });

    test('prefers token over token_hash when both are present', () {
      final result = parseAuthInput(
        'https://example.supabase.co/verify?token=first&token_hash=second',
      );
      expect(result.kind, AuthInputKind.tokenHash);
      expect(result.value, 'first');
    });

    test('tolerates surrounding whitespace and newlines', () {
      final result = parseAuthInput(
        '\n   https://example.supabase.co/verify?token=spaced  \n',
      );
      expect(result.kind, AuthInputKind.tokenHash);
      expect(result.value, 'spaced');
    });

    test('tolerates a URL wrapped across lines', () {
      final result = parseAuthInput(
        'https://example.supabase.co/verify?token=wrapped\n&type=magiclink',
      );
      expect(result.kind, AuthInputKind.tokenHash);
      expect(result.value, 'wrapped');
    });

    test('a foreign URL without a token is invalid', () {
      expect(
        parseAuthInput('https://example.com/some/page').kind,
        AuthInputKind.invalid,
      );
      expect(
        parseAuthInput('https://example.com/?other=1').kind,
        AuthInputKind.invalid,
      );
    });
  });

  group('parseAuthInput — bare token', () {
    test('accepts a long opaque token pasted on its own', () {
      const token =
          '9c2d4f6a8b1c3e5f7a9b0c2d4e6f8a1b3c5d7e9f0a2b4c6d8e0f2468ace01234';
      final result = parseAuthInput(token);
      expect(result.kind, AuthInputKind.tokenHash);
      expect(result.value, token);
    });

    test('accepts a JWT-shaped token', () {
      final result = parseAuthInput(
        'eyJhbGciOiJIUzI1NiJ9.eyJzdWIiOiJ1c2VyIn0.signaturepart',
      );
      expect(result.kind, AuthInputKind.tokenHash);
    });
  });

  group('parseAuthInput — invalid', () {
    test('empty / whitespace-only input', () {
      expect(parseAuthInput('').kind, AuthInputKind.invalid);
      expect(parseAuthInput('   ').kind, AuthInputKind.invalid);
      expect(parseAuthInput('\n\t ').kind, AuthInputKind.invalid);
    });

    test('digits mixed with (short) text', () {
      expect(parseAuthInput('12ab34').kind, AuthInputKind.invalid);
      expect(parseAuthInput('abc123').kind, AuthInputKind.invalid);
      expect(parseAuthInput('12345x').kind, AuthInputKind.invalid);
    });

    test('a non-http string with a token-looking query is invalid', () {
      // No scheme → not treated as a URL, and too short to be a bare token.
      expect(
        parseAuthInput('example.com/verify?token=abc').kind,
        AuthInputKind.invalid,
      );
    });

    test('isValid mirrors the kind', () {
      expect(parseAuthInput('').isValid, isFalse);
      expect(parseAuthInput('123456').isValid, isTrue);
    });
  });
}
