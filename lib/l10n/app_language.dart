/// The UI languages the app supports.
///
/// Adding a language only needs a new value here plus a matching map in
/// [AppStrings] — no `arb` / `gen-l10n` tooling involved.
enum AppLanguage {
  de(code: 'de', label: 'Deutsch', tmdbCode: 'de-DE'),
  en(code: 'en', label: 'English', tmdbCode: 'en-US');

  const AppLanguage({
    required this.code,
    required this.label,
    required this.tmdbCode,
  });

  /// Stable, persisted code (`de` / `en`) used by SharedPreferences.
  final String code;

  /// Native display name shown in the language picker — identical in every
  /// language, exactly like most apps do it.
  final String label;

  /// TMDB API language code passed as the `language` query parameter.
  final String tmdbCode;

  /// The app default. Used when nothing has been persisted yet — Daniel's
  /// call: first launch is **German**.
  static const AppLanguage fallback = AppLanguage.de;

  /// Parses a persisted [code]; unknown / `null` input yields [fallback].
  static AppLanguage fromCode(String? code) {
    for (final language in values) {
      if (language.code == code) return language;
    }
    return fallback;
  }

  /// Maps a TMDB language code (e.g. `de-DE`) back to an [AppLanguage].
  static AppLanguage fromTmdbCode(String? tmdbCode) {
    if (tmdbCode != null && tmdbCode.toLowerCase().startsWith('de')) {
      return AppLanguage.de;
    }
    return AppLanguage.en;
  }
}
