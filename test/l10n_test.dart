import 'package:flutter_test/flutter_test.dart';
import 'package:media_tracker/l10n/app_language.dart';
import 'package:media_tracker/l10n/app_strings.dart';
import 'package:media_tracker/models/media_item.dart';
import 'package:media_tracker/models/tmdb_result.dart';
import 'package:media_tracker/services/stats_calculator.dart';
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

  group('tracking strings (phase 3a)', () {
    test('German covers the whole tracking UI', () {
      const de = AppStrings(AppLanguage.de);
      expect(de.trackingSection, 'Verfolgung');
      expect(de.progress, 'Fortschritt');
      expect(de.currentPage, 'Aktuelle Seite');
      expect(de.totalPages, 'Seiten gesamt');
      expect(de.startedAt, 'Begonnen am');
      expect(de.completedAt, 'Abgeschlossen am');
      expect(de.notSet, 'Noch nicht gesetzt');
      expect(de.deleteItem, 'Eintrag löschen');
      expect(de.seasonLabel, 'Staffel');
      expect(de.episodesLabel, 'Folgen');
      expect(de.episodeNumber(3), 'Folge 3');
      expect(de.markSeasonWatched, 'Staffel als gesehen markieren');
      expect(de.resetSeason, 'Staffel zurücksetzen');
      expect(de.noEpisodes, 'Keine Folgen gefunden');
      expect(de.airedOn, 'Ausgestrahlt am');
      expect(de.pageOf(42, 300), 'Seite 42 von 300');
      expect(de.pageOfUnknownTotal(7), 'Seite 7');
      expect(de.percentValue(42), '42 %');
      expect(de.deleteConfirmMessage('Dune'), contains('Dune'));
    });

    test('English covers the whole tracking UI', () {
      const en = AppStrings(AppLanguage.en);
      expect(en.trackingSection, 'Tracking');
      expect(en.progress, 'Progress');
      expect(en.currentPage, 'Current page');
      expect(en.totalPages, 'Total pages');
      expect(en.startedAt, 'Started on');
      expect(en.completedAt, 'Completed on');
      expect(en.notSet, 'Not set yet');
      expect(en.deleteItem, 'Delete item');
      expect(en.seasonLabel, 'Season');
      expect(en.episodesLabel, 'Episodes');
      expect(en.episodeNumber(3), 'Episode 3');
      expect(en.markSeasonWatched, 'Mark season as watched');
      expect(en.resetSeason, 'Reset season');
      expect(en.noEpisodes, 'No episodes found');
      expect(en.airedOn, 'Aired on');
      expect(en.pageOf(42, 300), 'Page 42 of 300');
      expect(en.percentValue(42), '42%');
      expect(en.deleteConfirmMessage('Dune'), contains('Dune'));
    });

    test('every new string is present in both languages', () {
      const de = AppStrings(AppLanguage.de);
      const en = AppStrings(AppLanguage.en);
      // A missing key would fall back to the raw key — catch that with a list
      // of the strings whose value must differ between the two languages.
      final pairs = <(String, String)>[
        (de.trackingSection, en.trackingSection),
        (de.progress, en.progress),
        (de.currentPage, en.currentPage),
        (de.totalPages, en.totalPages),
        (de.startedAt, en.startedAt),
        (de.completedAt, en.completedAt),
        (de.notSet, en.notSet),
        (de.pickDate, en.pickDate),
        (de.clearDate, en.clearDate),
        (de.deleteItem, en.deleteItem),
        (de.deleteConfirmTitle, en.deleteConfirmTitle),
        (de.delete, en.delete),
        (de.cancel, en.cancel),
        (de.itemDeleted, en.itemDeleted),
        (de.trackingSaveError, en.trackingSaveError),
        (de.invalidPage, en.invalidPage),
        (de.savePage, en.savePage),
        (de.noDescription, en.noDescription),
        (de.seasonLabel, en.seasonLabel),
        (de.episodesLabel, en.episodesLabel),
        (de.watchedLabel, en.watchedLabel),
        (de.markSeasonWatched, en.markSeasonWatched),
        (de.resetSeason, en.resetSeason),
        (de.noEpisodes, en.noEpisodes),
        (de.airedOn, en.airedOn),
        (de.runtimeLabel, en.runtimeLabel),
        (de.resetSeasonConfirmTitle, en.resetSeasonConfirmTitle),
        (de.episodesLoadErrorTitle, en.episodesLoadErrorTitle),
      ];
      for (final (german, english) in pairs) {
        expect(german.trim(), isNotEmpty);
        expect(english.trim(), isNotEmpty);
        expect(german, isNot(english));
      }
    });
  });

  group('stats strings (phase 5)', () {
    test('every new stats string exists in both languages', () {
      const de = AppStrings(AppLanguage.de);
      const en = AppStrings(AppLanguage.en);
      final pairs = <(String, String)>[
        (de.statsOverview, en.statsOverview),
        (de.statsStatusDistribution, en.statsStatusDistribution),
        (de.statsCompletionRate, en.statsCompletionRate),
        (de.statsEmptyTitle, en.statsEmptyTitle),
        (de.statsEmptyMessage, en.statsEmptyMessage),
        (de.statsLoadErrorTitle, en.statsLoadErrorTitle),
        (de.statsOverTime, en.statsOverTime),
        (de.statsWatchTime, en.statsWatchTime),
        (de.statsWatchTimeNoData, en.statsWatchTimeNoData),
        (de.statsPages, en.statsPages),
        (de.range1Month, en.range1Month),
        (de.range6Months, en.range6Months),
        (de.range12Months, en.range12Months),
        (de.rangeAll, en.rangeAll),
        (de.hoursShort, en.hoursShort),
        (de.minutesShort, en.minutesShort),
        (de.statsNoCompletions, en.statsNoCompletions),
      ];
      for (final (german, english) in pairs) {
        expect(german.trim(), isNotEmpty);
        expect(english.trim(), isNotEmpty);
        expect(german, isNot(english));
      }
    });

    test('range labels and month abbreviations are localized', () {
      const de = AppStrings(AppLanguage.de);
      const en = AppStrings(AppLanguage.en);

      expect(de.rangeLabel(StatsRange.all), 'Gesamt');
      expect(en.rangeLabel(StatsRange.all), 'All time');
      expect(de.rangeLabel(StatsRange.month), '1 Monat');
      expect(en.rangeLabel(StatsRange.sixMonths), '6 months');

      expect(de.monthShort(1), 'Jan');
      expect(de.monthShort(3), 'Mär');
      expect(en.monthShort(3), 'Mar');
    });

    test('thousands and watch-time formatting', () {
      const de = AppStrings(AppLanguage.de);
      const en = AppStrings(AppLanguage.en);

      expect(de.number(1234), '1.234');
      expect(en.number(1234), '1,234');
      expect(de.number(999), '999');
      expect(en.number(1234567), '1,234,567');

      expect(de.watchTime(0), '0 Min.');
      expect(de.watchTime(15), '15 Min.');
      expect(de.watchTime(42 * 60), '42 Std.');
      expect(de.watchTime(42 * 60 + 15), '42 Std. 15 Min.');
      expect(en.watchTime(42 * 60 + 15), '42 h 15 min');
      expect(de.pagesCount(1234), '1.234 Seiten');
      expect(en.pagesCount(1234), '1,234 pages');
    });
  });
}
