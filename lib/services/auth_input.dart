/// Parsing of the login screen's second-step input (Phase 14).
///
/// That single field accepts **either** the numeric one-time code from the
/// sign-in email **or** the pasted magic link (the whole point of the feature:
/// on iOS the link would otherwise open in a *different* browser context — see
/// PROJECT.md). Keeping the decision here as a pure, testable function means
/// the widget never contains the (surprisingly fiddly) URL/token rules.
///
/// **What the Supabase sign-in email contains.** GoTrue sends one email that
/// carries a clickable link *and* a one-time code. The link points at GoTrue's
/// `/verify` endpoint and carries the token in a query parameter — the modern
/// templates use `token_hash`, older / hand-written ones use `token`. Both
/// refer to the same value (GoTrue's `TokenHash`); the client SDK then posts it
/// as `token_hash`. We accept either parameter name.
library;

/// What the step-2 field turned out to hold.
enum AuthInputKind {
  /// A numeric one-time code (6–8 digits) — the traditional code path
  /// (`verifyEmailCode`).
  code,

  /// A magic-link token extracted from a pasted URL (or a bare opaque token) —
  /// resolved through `verifyEmailLinkToken`.
  tokenHash,

  /// Nothing usable — empty, a foreign URL, or mixed garbage.
  invalid,
}

/// Result of [parseAuthInput]: the detected [kind] plus the cleaned value to
/// hand to the provider (the digits for [AuthInputKind.code], the token for
/// [AuthInputKind.tokenHash], empty otherwise).
class AuthInput {
  const AuthInput(this.kind, [this.value = '']);

  final AuthInputKind kind;
  final String value;

  /// `true` for the two usable kinds — drives the "Sign in" button.
  bool get isValid => kind != AuthInputKind.invalid;

  @override
  String toString() => 'AuthInput(${kind.name}, "$value")';

  @override
  bool operator ==(Object other) =>
      other is AuthInput && other.kind == kind && other.value == value;

  @override
  int get hashCode => Object.hash(kind, value);
}

/// 6–8 digits — Supabase's default code length is 6; 8 is tolerated.
final RegExp _code = RegExp(r'^\d{6,8}$');

/// A bare, opaque token: one "word", long enough not to be a typo. Supabase's
/// `TokenHash` is a 64-char hex string (JWT-style tokens contain dots too).
final RegExp _rawToken = RegExp(r'^[A-Za-z0-9_\-\.=]+$');
const int _minRawTokenLength = 20;

/// Any whitespace — used to compact a URL that a mail client wrapped across
/// lines before parsing. Tokens never contain whitespace.
final RegExp _whitespace = RegExp(r'\s');

/// Classifies the raw text of the step-2 field.
///
/// * 6–8 digits → [AuthInputKind.code] (the pre-existing path).
/// * An `http(s)` URL carrying a `token` (or `token_hash`) query parameter →
///   [AuthInputKind.tokenHash] with the parameter's value. A URL **without**
///   such a parameter (a foreign link) is [AuthInputKind.invalid].
/// * A bare opaque token (see [_rawToken] / [_minRawTokenLength]) →
///   [AuthInputKind.tokenHash].
/// * Anything else (empty, `12ab34`, digits glued to text, …) →
///   [AuthInputKind.invalid].
///
/// Surrounding whitespace / newlines are tolerated (mail clients love to
/// append a line break), and a wrapped URL is compacted before parsing.
AuthInput parseAuthInput(String raw) {
  final text = raw.trim();
  if (text.isEmpty) return const AuthInput(AuthInputKind.invalid);

  // 1) The plain numeric code — checked first so a code never goes through the
  //    URL/token branches.
  if (_code.hasMatch(text)) return AuthInput(AuthInputKind.code, text);

  // 2) A pasted magic link. Compact it first so a wrapped link still parses.
  final compact = text.replaceAll(_whitespace, '');
  final uri = Uri.tryParse(compact);
  if (uri != null && (uri.scheme == 'http' || uri.scheme == 'https')) {
    final token =
        uri.queryParameters['token'] ?? uri.queryParameters['token_hash'];
    final value = token?.trim() ?? '';
    if (value.isNotEmpty) return AuthInput(AuthInputKind.tokenHash, value);
    // A URL that carries no token is not something we can use.
    return const AuthInput(AuthInputKind.invalid);
  }

  // 3) A bare token pasted on its own.
  if (text.length >= _minRawTokenLength && _rawToken.hasMatch(text)) {
    return AuthInput(AuthInputKind.tokenHash, text);
  }

  return const AuthInput(AuthInputKind.invalid);
}
