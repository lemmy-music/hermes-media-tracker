import 'package:flutter_test/flutter_test.dart';
import 'package:media_tracker/l10n/app_language.dart';
import 'package:media_tracker/providers/settings_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('AppLanguage', () {
    test('falls back to German for unknown / missing codes', () {
      expect(AppLanguage.fromCode(null), AppLanguage.de);
      expect(AppLanguage.fromCode('fr'), AppLanguage.de);
      expect(AppLanguage.fromCode('de'), AppLanguage.de);
      expect(AppLanguage.fromCode('en'), AppLanguage.en);
    });

    test('exposes the matching TMDB language codes', () {
      expect(AppLanguage.de.tmdbCode, 'de-DE');
      expect(AppLanguage.en.tmdbCode, 'en-US');
      expect(AppLanguage.fromTmdbCode('de-DE'), AppLanguage.de);
      expect(AppLanguage.fromTmdbCode('en-US'), AppLanguage.en);
    });
  });

  group('SettingsProvider', () {
    test('defaults to German when nothing is stored', () async {
      SharedPreferences.setMockInitialValues(<String, Object>{});

      final provider = SettingsProvider();
      expect(provider.language, AppLanguage.de);
      expect(provider.tmdbLanguage, 'de-DE');

      await provider.load();
      expect(provider.language, AppLanguage.de);
    });

    test('loads a previously stored language', () async {
      SharedPreferences.setMockInitialValues(<String, Object>{
        'app_language': 'en',
      });

      final provider = SettingsProvider();
      await provider.load();
      expect(provider.language, AppLanguage.en);
      expect(provider.tmdbLanguage, 'en-US');
    });

    test('setLanguage persists and notifies listeners', () async {
      SharedPreferences.setMockInitialValues(<String, Object>{});

      final provider = SettingsProvider();
      var notifications = 0;
      provider.addListener(() => notifications++);

      await provider.setLanguage(AppLanguage.en);
      expect(provider.language, AppLanguage.en);
      expect(notifications, 1);

      // Setting the same value again is a no-op.
      await provider.setLanguage(AppLanguage.en);
      expect(notifications, 1);

      final prefs = await SharedPreferences.getInstance();
      expect(prefs.getString('app_language'), 'en');
    });
  });
}
