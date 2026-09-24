import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../config/app_config.dart';

/// High-level auth state for the UI.
enum AuthStatus {
  /// The persisted session has not been resolved yet.
  unknown,
  signedOut,
  signedIn,
}

/// Minimal, UI-facing auth contract.
///
/// Deliberately abstract: widgets can be exercised in widget tests without a
/// live Supabase backend (see `test/widget_test.dart`).
abstract class AuthProvider extends ChangeNotifier {
  AuthStatus get status;

  /// Email of the signed-in user, or `null` when signed out.
  String? get email;

  /// Restores the persisted session. Call once at startup — until it resolves
  /// the [AuthStatus] may stay [AuthStatus.unknown].
  Future<void> init() async {}

  /// Sends a magic link to [email].
  ///
  /// Returns `null` on success, otherwise a user-facing error message.
  Future<String?> sendMagicLink(String email);

  /// Signs the current user out.
  Future<void> signOut();
}

/// [AuthProvider] backed by Supabase GoTrue (email magic-link flow).
///
/// State is derived from two sources:
///  * [SupabaseClient.auth].`currentSession` at construction/`init()` — the SDK
///    restores the persisted session during `Supabase.initialize()`.
///  * `onAuthStateChange` — keeps the UI in sync for sign-in, sign-out, token
///    refresh and the web redirect after a magic-link click.
class SupabaseAuthProvider extends AuthProvider {
  SupabaseAuthProvider({SupabaseClient? client})
      : _client = client ?? Supabase.instance.client {
    _subscription = _client.auth.onAuthStateChange.listen(
      (state) => _apply(state.session),
      onError: (Object _) {
        // Token refresh / network failures land here. We keep the last known
        // state; the next successful event recovers.
      },
    );
    _apply(_client.auth.currentSession);
  }

  final SupabaseClient _client;
  StreamSubscription<AuthState>? _subscription;

  AuthStatus _status = AuthStatus.unknown;
  String? _email;

  @override
  AuthStatus get status => _status;

  @override
  String? get email => _email;

  @override
  Future<void> init() async {
    _apply(_client.auth.currentSession);
  }

  @override
  Future<String?> sendMagicLink(String email) async {
    try {
      await _client.auth.signInWithOtp(
        email: email,
        emailRedirectTo: AppConfig.authRedirectUrl,
        shouldCreateUser: true,
      );
      return null;
    } on AuthException catch (error) {
      return describeAuthError(error);
    } catch (_) {
      return 'Could not reach the server. Check your connection and try again.';
    }
  }

  @override
  Future<void> signOut() async {
    try {
      await _client.auth.signOut();
    } on AuthException {
      // Session already gone — that is the state we wanted anyway.
    } finally {
      _apply(null);
    }
  }

  @override
  void dispose() {
    _subscription?.cancel();
    super.dispose();
  }

  void _apply(Session? session) {
    final nextStatus =
        session == null ? AuthStatus.signedOut : AuthStatus.signedIn;
    final nextEmail = session?.user.email;
    if (nextStatus == _status && nextEmail == _email) return;
    _status = nextStatus;
    _email = nextEmail;
    notifyListeners();
  }
}

/// Maps a GoTrue [AuthException] to a friendly, English message.
String describeAuthError(AuthException error) {
  final message = error.message.toLowerCase();
  final statusCode = error.statusCode;

  final isRateLimited = statusCode == '429' ||
      message.contains('rate limit') ||
      message.contains('too many') ||
      error.code == 'over_email_send_rate_limit';
  if (isRateLimited) {
    return 'Too many requests. Please wait a few minutes before requesting '
        'another link.';
  }

  final isBadEmail = error.code == 'validation_failed' ||
      (message.contains('invalid') && message.contains('email')) ||
      message.contains('unable to validate email');
  if (isBadEmail) {
    return 'That does not look like a valid email address.';
  }

  if (message.contains('signups not allowed') ||
      message.contains('signup is disabled')) {
    return 'New sign-ups are currently disabled.';
  }

  return error.message.isNotEmpty
      ? error.message
      : 'Sign-in failed. Please try again.';
}
