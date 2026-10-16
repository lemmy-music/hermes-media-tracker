import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../config/app_config.dart';
import '../l10n/app_language.dart';
import '../l10n/app_strings.dart';

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

  /// Sends a sign-in email to [email].
  ///
  /// The same email carries **both** a magic link and a one-time code (see
  /// [verifyEmailCode] and PROJECT.md for why). Returns `null` on success,
  /// otherwise a user-facing, localized error message.
  Future<String?> sendMagicLink(String email);

  /// Verifies the numeric one-time code from the sign-in email for [email].
  ///
  /// Typing the code here creates the session **in the current browser / PWA
  /// context** — unlike tapping the link, which on iOS can open in another
  /// context (Safari or the mail app's in-app browser) that has its own,
  /// separate storage from a homescreen-PWA. Supabase sends the code in the
  /// same email as the link; both keep working.
  ///
  /// `code` may be 6–8 digits. Returns `null` on success (the SDK then reports
  /// the new session through `onAuthStateChange`), otherwise a user-facing,
  /// localized error message.
  Future<String?> verifyEmailCode({
    required String email,
    required String code,
  });

  /// Verifies a **magic-link token** the user copied out of the sign-in email
  /// and pasted into the field ([parseAuthInput] extracts it).
  ///
  /// This is the iOS-PWA workaround: tapping the link opens a *different*
  /// browser context (Safari or the mail app's in-app browser), whose storage
  /// iOS keeps apart from a homescreen-PWA — so the session would never reach
  /// the app. Redeeming the token **in this context** creates the session
  /// exactly where the app runs.
  ///
  /// [tokenHash] is the value of the `token` / `token_hash` query parameter of
  /// the mail link. Returns `null` on success (the SDK then reports the new
  /// session through `onAuthStateChange`), otherwise a user-facing, localized
  /// error message — an expired or already-used token is reported as such.
  Future<String?> verifyEmailLinkToken({required String tokenHash});

  /// Signs the current user out.
  Future<void> signOut();
}

/// [AuthProvider] backed by Supabase GoTrue (email magic-link + OTP flow).
///
/// State is derived from two sources:
///  * [SupabaseClient.auth].`currentSession` at construction/`init()` — the SDK
///    restores the persisted session during `Supabase.initialize()`.
///  * `onAuthStateChange` — keeps the UI in sync for sign-in, sign-out, token
///    refresh and the web redirect after a magic-link click.
class SupabaseAuthProvider extends AuthProvider {
  SupabaseAuthProvider({
    SupabaseClient? client,
    AppLanguage Function()? language,
  }) : _client = client ?? Supabase.instance.client,
       _language = language ?? _english {
    _subscription = _client.auth.onAuthStateChange.listen(
      (state) => _apply(state.session),
      onError: (Object _) {
        // Token refresh / network failures land here. We keep the last known
        // state; the next successful event recovers.
      },
    );
    _apply(_client.auth.currentSession);
  }

  static AppLanguage _english() => AppLanguage.en;

  final SupabaseClient _client;

  /// Supplies the UI language for localized error messages — injected by
  /// `main.dart` from the [SettingsProvider], English by default. Kept as a
  /// callback so the provider stays independent of the settings layer.
  final AppLanguage Function() _language;

  StreamSubscription<AuthState>? _subscription;

  AuthStatus _status = AuthStatus.unknown;
  String? _email;

  AppStrings get _strings => AppStrings(_language());

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
      return describeAuthError(error, strings: _strings);
    } catch (_) {
      return _strings.authNetworkError;
    }
  }

  @override
  Future<String?> verifyEmailCode({
    required String email,
    required String code,
  }) async {
    try {
      // Supabase's GoTrue serializes the OTP type to snake_case in the request
      // body: `OtpType.email` → `type=email`. That is the current name of the
      // email magic-link/OTP verification type ("magiclink" is the deprecated
      // alias the server still maps onto it), so `OtpType.email` is the
      // correct, forward-compatible choice for verifying a code from a
      // magic-link mail.
      await _client.auth.verifyOTP(
        email: email,
        token: code,
        type: OtpType.email,
      );
      return null;
    } on AuthException catch (error) {
      return describeAuthError(error, strings: _strings);
    } catch (_) {
      return _strings.authNetworkError;
    }
  }

  @override
  Future<String?> verifyEmailLinkToken({required String tokenHash}) async {
    try {
      // The sign-in mail's link points at GoTrue's `/verify` endpoint with the
      // token in the `token` / `token_hash` query parameter. `verifyOTP` with
      // `tokenHash` posts exactly that value as `token_hash`, and the type must
      // match how the mail was generated: `OtpType.magiclink` for a magic link
      // (`OtpType.email` is the type for the plain numeric code — see
      // `verifyEmailCode`). This redeems the token in the *current* browser/PWA
      // context, so the session lands where the app runs.
      await _client.auth.verifyOTP(
        tokenHash: tokenHash,
        type: OtpType.magiclink,
      );
      return null;
    } on AuthException catch (error) {
      return describeAuthError(error, strings: _strings, forLink: true);
    } catch (_) {
      return _strings.authNetworkError;
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
    final nextStatus = session == null
        ? AuthStatus.signedOut
        : AuthStatus.signedIn;
    final nextEmail = session?.user.email;
    if (nextStatus == _status && nextEmail == _email) return;
    _status = nextStatus;
    _email = nextEmail;
    notifyListeners();
  }
}

/// Maps a GoTrue [AuthException] to a friendly, user-facing message.
///
/// The message is localized with [strings] (English by default) so the login
/// screen can show it in the active language. Kept in one place so the
/// magic-link send, the email-code verify and the pasted-link verify share the
/// exact same wording and never drift apart.
///
/// Set [forLink] when the failure came from redeeming a **pasted magic link**
/// rather than typing a code: the "invalid" / "expired" cases then return
/// link-specific wording (a used-up link is the common one) instead of the
/// code wording — the mapping itself is not duplicated.
String describeAuthError(
  AuthException error, {
  AppStrings strings = const AppStrings(AppLanguage.en),
  bool forLink = false,
}) {
  // A failed fetch (offline, DNS, CORS, or a 5xx) surfaces as a retryable
  // fetch exception without a response body — report it as a connection issue.
  if (error is AuthRetryableFetchException) {
    return strings.authNetworkError;
  }

  final message = error.message.toLowerCase();
  final statusCode = error.statusCode;

  final isRateLimited =
      statusCode == '429' ||
      message.contains('rate limit') ||
      message.contains('too many') ||
      error.code == 'over_email_send_rate_limit';
  if (isRateLimited) {
    return strings.authRateLimited;
  }

  // An expired one-time code (or an expired request). GoTrue reports this as
  // `otp_expired` ("Token has expired or is invalid"); an **already used**
  // magic link surfaces the same way, so the link wording mentions both.
  final isExpired = error.code == 'otp_expired' || message.contains('expired');
  if (isExpired) {
    return forLink ? strings.authLinkExpired : strings.authCodeExpired;
  }

  // A wrong one-time code. GoTrue reports `otp_invalid` ("Invalid token") — the
  // wording differs between versions, so also match on the message.
  final looksWrongCode =
      message.contains('invalid') || message.contains('incorrect');
  final mentionsCode =
      message.contains('token') ||
      message.contains('otp') ||
      message.contains('code');
  if (error.code == 'otp_invalid' || (looksWrongCode && mentionsCode)) {
    return forLink ? strings.authLinkInvalid : strings.authCodeInvalid;
  }

  final isBadEmail =
      error.code == 'validation_failed' ||
      (message.contains('invalid') && message.contains('email')) ||
      message.contains('unable to validate email');
  if (isBadEmail) {
    return strings.emailInvalid;
  }

  if (message.contains('signups not allowed') ||
      message.contains('signup is disabled')) {
    return strings.authSignupsDisabled;
  }

  return error.message.isNotEmpty ? error.message : strings.authGenericError;
}
