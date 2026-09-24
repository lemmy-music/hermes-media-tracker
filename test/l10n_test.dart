import 'package:flutter_test/flutter_test.dart';
import 'package:media_tracker/l10n/app_language.dart';
import 'package:media_tracker/l10n/app_strings.dart';
import 'package:media_tracker/models/media_item.dart';
import 'package:media_tracker/models/tmdb_result.dart';
import 'package:media_tracker/services/tmdb_client.dart';

void main() {
  group('AppStrings (German)', () {
    const de = AppStrings(AppLanguage.de);

    test('covers the headline UI terms', () {
      expect(de.library, 'Bibliothek');
      expect(de.search, 'Suche');
      expect(de.stats, 'Statistik');
      expect(de.settings, 'Einstellungen');
      expect(de.addToLibrary, 'Zur Bibliothek hinzufügen');
      expect(de.alreadyInLibrary, 'Bereits in deiner Bibliothek');
      expect(de.libraryEmptyTitle, 'Deine Bibliothek ist leer');
      expect(de.sendMagicLink, 'Anmelde-Link senden');
      expect(de.checkInbox, 'Prüfe dein Postfach');
    });

    test('localizes enums', () {
      expect(de.kindLabel(MediaKind.movie), 'Film');
      expect(de.kindLabel(MediaKind.series), 'Serie');
      expect(de.kindLabel(MediaKind.book), 'Buch');
      expect(de.statusLabel(MediaStatus.planned), 'Geplant');
      expect(de.statusLabel(MediaStatus.inProgress), 'Angefangen');
      expect(de.statusLabel(MediaStatus.dropped), 'Abgebrochen');
      expect(de.typeLabel(TmdbMediaType.tv), 'Serie');
      expect(de.scopeLabel(TmdbSearchScope.all), 'Alle');
      expect(de.scopeLabel(TmdbSearchScope.movie), 'Filme');
      expect(de.scopeLabel(TmdbSearchScope.tv), 'Serien');
      expect(de.scopeLabel(TmdbSearchScope.books), 'Bücher');
    });
  });

  group('AppStrings (English)', () {
    const en = AppStrings(AppLanguage.en);

    test('keeps the original copy', () {
      expect(en.library, 'Library');
      expect(en.addToLibrary, 'Add to library');
      expect(en.alreadyInLibrary, 'Already in your library');
      expect(en.sendMagicLink, 'Send magic link');
    });

    test('plural helpers agree with their count', () {
      expect(en.seasons(1), '1 season');
      expect(en.seasons(3), '3 seasons');
      expect(en.episodes(1), '1 episode');
      expect(en.episodes(2), '2 episodes');
      expect(en.pages(1), '1 page');
      expect(en.pages(2), '2 pages');
    });

    test('localizes the book scope and author line', () {
      expect(en.scopeLabel(TmdbSearchScope.books), 'Books');
      expect(en.byAuthors('J.R.R. Tolkien'), 'by J.R.R. Tolkien');
    });
  });

  test('German plural helpers', () {
    const de = AppStrings(AppLanguage.de);
    expect(de.seasons(1), '1 Staffel');
    expect(de.seasons(3), '3 Staffeln');
    expect(de.episodes(1), '1 Folge');
    expect(de.episodes(5), '5 Folgen');
    expect(de.pages(1), '1 Seite');
    expect(de.pages(5), '5 Seiten');
  });

  test('book strings are available in both languages', () {
    const de = AppStrings(AppLanguage.de);
    const en = AppStrings(AppLanguage.en);

    expect(de.bookNoDescription, isNot('bookNoDescription'));
    expect(en.bookNoDescription, 'No description available.');
    expect(de.byAuthors('Tolkien'), 'von Tolkien');

    // The OpenLibrary service messages must not fall back to the raw key.
    for (final message in <String>[
      de.openLibraryTimeout,
      de.openLibraryUnreachable,
      de.openLibraryNotFound,
      de.openLibraryRequestFailed,
      de.openLibraryUnexpectedResponse,
      de.openLibraryUnreadableResponse,
      en.openLibraryTimeout,
      en.openLibraryUnreachable,
      en.openLibraryNotFound,
      en.openLibraryRequestFailed,
      en.openLibraryUnexpectedResponse,
      en.openLibraryUnreadableResponse,
    ]) {
      expect(message, contains('OpenLibrary'));
    }
  });

  test('parameterized strings inject the value', () {
    expect(
      AppStrings(AppLanguage.en).sentLinkTo('me@example.com'),
      contains('me@example.com'),
    );
    expect(
      AppStrings(AppLanguage.de).sentLinkTo('me@example.com'),
      contains('me@example.com'),
    );
  });

  test('TMDB language codes map onto the matching strings', () {
    expect(AppStrings.forTmdb('de-DE').language, AppLanguage.de);
    expect(AppStrings.forTmdb('en-US').language, AppLanguage.en);
    expect(AppStrings.forTmdb('de-DE').tmdbTimeout, contains('TMDB'));
  });
}
