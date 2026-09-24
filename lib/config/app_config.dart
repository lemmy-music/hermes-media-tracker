import 'package:flutter/foundation.dart';

/// Compile-time configuration for the app.
///
/// Both values below are **public by design** — they ship inside the compiled
/// web bundle. The Supabase *publishable* key only grants what Row Level
/// Security explicitly allows (here: nothing, until the user is signed in).
/// **Never** put an `sb_secret_...` / service-role key here.
///
/// Override at build time, e.g. for a staging project:
/// ```
/// flutter build web \
///   --dart-define=SUPABASE_URL=https://xxx.supabase.co \
///   --dart-define=SUPABASE_ANON_KEY=sb_publishable_xxx
/// ```
class AppConfig {
  const AppConfig._();

  /// Supabase project URL.
  static const String supabaseUrl = String.fromEnvironment(
    'SUPABASE_URL',
    defaultValue: 'https://vqpkejsxfvaovhdomllw.supabase.co',
  );

  /// Supabase publishable (a.k.a. legacy "anon") key.
  static const String supabaseAnonKey = String.fromEnvironment(
    'SUPABASE_ANON_KEY',
    defaultValue: 'sb_publishable_p9YcGjG1CJOxSI_YejdsaQ_xQU8E8je',
  );

  /// Where Supabase should send the browser after a magic-link click.
  ///
  /// Defaults to the current origin + path, which is correct both on GitHub
  /// Pages (`https://lemmy-music.github.io/hermes-media-tracker/`) and for
  /// local development (`http://localhost:<port>/`). Any auth query/fragment
  /// parameters present in the current URL are stripped on purpose.
  ///
  /// The resulting URL must be listed under *Authentication → URL
  /// Configuration → Redirect URLs* in the Supabase dashboard.
  static String? get authRedirectUrl {
    const override = String.fromEnvironment('AUTH_REDIRECT_URL');
    if (override.isNotEmpty) return override;
    if (!kIsWeb) return null;
    final base = Uri.base;
    return '${base.origin}${base.path}';
  }
}
