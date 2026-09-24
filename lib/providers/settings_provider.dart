import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../l10n/app_language.dart';

/// SharedPreferences key for the persisted UI language.
const _kLanguageKey = 'app_language';

/// Manages user preferences that are not theme-related (currently: the UI
/// language).
///
/// Kept separate from `ThemeProvider` so each provider owns a single concern
/// and can be tested in isolation.
///
/// Resolution order for the language:
///   1. Saved SharedPreferences value (if any)
///   2. [AppLanguage.fallback] — **German** — on first launch
class SettingsProvider extends ChangeNotifier {
  /// [initial] is only used before [load] resolves (and directly by widget
  /// tests that never touch SharedPreferences).
  SettingsProvider({AppLanguage initial = AppLanguage.fallback})
    : _language = initial;

  AppLanguage _language;

  /// The active UI language.
  AppLanguage get language => _language;

  /// Convenience: the TMDB `language` query value for the active language.
  String get tmdbLanguage => _language.tmdbCode;

  /// Loads the persisted preference. Call once at startup.
  Future<void> load() async {
    final prefs = await SharedPreferences.getInstance();
    final loaded = AppLanguage.fromCode(prefs.getString(_kLanguageKey));
    if (loaded == _language) return;
    _language = loaded;
    notifyListeners();
  }

  /// Sets and persists the UI language. Listeners rebuild immediately, so the
  /// toggle takes effect without an app restart.
  Future<void> setLanguage(AppLanguage language) async {
    if (language == _language) return;
    _language = language;
    notifyListeners();
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_kLanguageKey, language.code);
  }
}
