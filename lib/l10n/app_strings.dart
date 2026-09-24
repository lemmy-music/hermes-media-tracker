import 'package:flutter/widgets.dart';
import 'package:provider/provider.dart';

import '../models/import_error.dart';
import '../models/media_item.dart';
import '../models/tmdb_result.dart';
import '../providers/settings_provider.dart';
import '../services/stats_calculator.dart';
import '../services/tmdb_client.dart';
import 'app_language.dart';

/// Lightweight, dependency-free localization for the app UI.
///
/// Deliberately **no** `arb` / `gen-l10n` setup: one map per language keeps
/// the build simple while still making additional languages trivial — add a
/// value to [AppLanguage] and a matching entry to [_kStrings].
///
/// Lookups never throw. A key missing from the active language falls back to
/// English and finally to the key itself, so a gap is visible but harmless.
///
/// Typical use inside `build`:
/// ```dart
/// Text(context.strings.library)
/// ```
/// …and inside callbacks (where `watch` is not allowed):
/// ```dart
/// final strings = AppStrings.read(context);
/// ```
class AppStrings {
  const AppStrings(this.language);

  /// The language these strings are rendered in.
  final AppLanguage language;

  /// Resolves the strings for the language stored in [SettingsProvider] and
  /// rebuilds the caller whenever it changes. Call inside `build`.
  static AppStrings of(BuildContext context) =>
      AppStrings(context.watch<SettingsProvider>().language);

  /// Like [of] but without subscribing to changes. Use in callbacks
  /// (`onPressed`, after an `await`, …) where `watch` is not allowed.
  static AppStrings read(BuildContext context) =>
      AppStrings(context.read<SettingsProvider>().language);

  /// Builds the strings for a TMDB language code (`de-DE` / `en-US`).
  factory AppStrings.forTmdb(String tmdbLanguage) =>
      AppStrings(AppLanguage.fromTmdbCode(tmdbLanguage));

  String _t(String key) {
    final value = _kStrings[language]?[key] ?? _kStrings[AppLanguage.en]?[key];
    return value ?? key;
  }

  String _tParam(String key, Map<String, String> params) {
    var text = _t(key);
    params.forEach((name, value) => text = text.replaceAll('{$name}', value));
    return text;
  }

  // ───────────────────────────────────────────────────────────────────────────
  // generic / navigation
  // ───────────────────────────────────────────────────────────────────────────

  /// Brand name — intentionally never translated.
  String get appTitle => 'Media Tracker';

  String get library => _t('library');
  String get search => _t('search');
  String get stats => _t('stats');
  String get settings => _t('settings');

  /// Friendly "or" list separator used in empty-state copy.
  String get refresh => _t('refresh');
  String get retry => _t('retry');
  String get clear => _t('clear');
  String get moreActions => _t('moreActions');
  String get loadingLibrary => _t('loadingLibrary');

  // ───────────────────────────────────────────────────────────────────────────
  // media kinds / types / statuses
  // ───────────────────────────────────────────────────────────────────────────

  String kindLabel(MediaKind kind) => switch (kind) {
    MediaKind.movie => _t('kindMovie'),
    MediaKind.series => _t('kindSeries'),
    MediaKind.book => _t('kindBook'),
  };

  /// Plural label of a kind ("Movies" / "Series" / "Books") — used by the
  /// stats screen's count tiles and chart legends.
  String kindPluralLabel(MediaKind kind) => switch (kind) {
    MediaKind.movie => _t('scopeMovies'),
    MediaKind.series => _t('scopeSeries'),
    MediaKind.book => _t('scopeBooks'),
  };

  String statusLabel(MediaStatus status) => switch (status) {
    MediaStatus.planned => _t('statusPlanned'),
    MediaStatus.inProgress => _t('statusInProgress'),
    MediaStatus.completed => _t('statusCompleted'),
    MediaStatus.dropped => _t('statusDropped'),
  };

  String typeLabel(TmdbMediaType type) => switch (type) {
    TmdbMediaType.movie => _t('kindMovie'),
    TmdbMediaType.tv => _t('kindSeries'),
  };

  String scopeLabel(TmdbSearchScope scope) => switch (scope) {
    TmdbSearchScope.all => _t('scopeAll'),
    TmdbSearchScope.movie => _t('scopeMovies'),
    TmdbSearchScope.tv => _t('scopeSeries'),
    TmdbSearchScope.books => _t('scopeBooks'),
  };

  // ───────────────────────────────────────────────────────────────────────────
  // library
  // ───────────────────────────────────────────────────────────────────────────

  String get libraryLoadErrorTitle => _t('libraryLoadErrorTitle');
  String get libraryEmptyTitle => _t('libraryEmptyTitle');
  String get libraryEmptyMessage => _t('libraryEmptyMessage');

  // ───────────────────────────────────────────────────────────────────────────
  // metadata refresh (language change / manual)
  // ───────────────────────────────────────────────────────────────────────────

  /// Overflow-menu action: re-fetch the stored TMDB metadata.
  String get metadataRefreshAction => _t('metadataRefreshAction');

  /// Banner while a run is in flight, e.g. "Updating metadata… (2/5)".
  String metadataRefreshing(int done, int total) =>
      _tParam('metadataRefreshing', {'done': '$done', 'total': '$total'});

  /// Snack bar after a fully successful run.
  String metadataRefreshed(int updated, int total) =>
      _tParam('metadataRefreshed', {'updated': '$updated', 'total': '$total'});

  /// Snack bar after a run where some items kept their old metadata.
  String metadataRefreshPartial(int updated, int total, int failed) => _tParam(
    'metadataRefreshPartial',
    {'updated': '$updated', 'total': '$total', 'failed': '$failed'},
  );

  /// Feedback for a manual run without any TMDB entry to refresh.
  String get metadataRefreshEmpty => _t('metadataRefreshEmpty');

  // ───────────────────────────────────────────────────────────────────────────
  // search
  // ───────────────────────────────────────────────────────────────────────────

  String get searchHint => _t('searchHint');
  String get searchIdleTitle => _t('searchIdleTitle');
  String get searchIdleMessage => _t('searchIdleMessage');
  String get searchFailedTitle => _t('searchFailedTitle');
  String get noResultsTitle => _t('noResultsTitle');
  String get noResultsMessage => _t('noResultsMessage');
  String get searchMissingToken => _t('searchMissingToken');
  String get addToLibrary => _t('addToLibrary');
  String get alreadyInLibrary => _t('alreadyInLibrary');
  String get addedToLibrary => _t('addedToLibrary');

  /// Teaser shown for a book hit without a description.
  String get bookNoDescription => _t('bookNoDescription');

  /// Author line for a book hit / detail sheet, e.g. "by J.R.R. Tolkien".
  String byAuthors(String authors) =>
      _tParam('byAuthors', {'authors': authors});

  // ───────────────────────────────────────────────────────────────────────────
  // stats
  // ───────────────────────────────────────────────────────────────────────────

  String get statsComingSoon => _t('statsComingSoon');
  String get statsDescription => _t('statsDescription');

  // ── Phase 5: stats screen ──────────────────────────────────────────────────

  String get statsOverview => _t('statsOverview');
  String get statsStatusDistribution => _t('statsStatusDistribution');
  String get statsCompletionRate => _t('statsCompletionRate');
  String get statsEmptyTitle => _t('statsEmptyTitle');
  String get statsEmptyMessage => _t('statsEmptyMessage');
  String get statsLoadErrorTitle => _t('statsLoadErrorTitle');
  String get statsOverTime => _t('statsOverTime');
  String get statsOverTimeHint => _t('statsOverTimeHint');
  String get statsWatchTime => _t('statsWatchTime');
  String get statsWatchTimeHint => _t('statsWatchTimeHint');
  String get statsWatchTimeNoData => _t('statsWatchTimeNoData');
  String get statsPages => _t('statsPages');
  String get statsPagesHint => _t('statsPagesHint');
  String get statsNoCompletions => _t('statsNoCompletions');

  /// Time-range chips of the second stats block.
  String get range1Month => _t('range1Month');
  String get range6Months => _t('range6Months');
  String get range12Months => _t('range12Months');
  String get rangeAll => _t('rangeAll');

  /// Unit suffixes for the watch-time label.
  String get hoursShort => _t('hoursShort');
  String get minutesShort => _t('minutesShort');

  /// Unit suffix for the pages stat.
  String get pagesUnit => _t('pagesUnit');

  /// Localized time-range label for [range].
  String rangeLabel(StatsRange range) => switch (range) {
    StatsRange.month => range1Month,
    StatsRange.sixMonths => range6Months,
    StatsRange.twelveMonths => range12Months,
    StatsRange.all => rangeAll,
  };

  /// Localized short month name ("Jan", … "Dez") for chart axis labels.
  String monthShort(int month) {
    final names = _t('monthShort').split(',');
    if (month < 1 || month > names.length) return '$month';
    return names[month - 1];
  }

  /// Groups [value] with a thousands separator — "." in German, "," in
  /// English (e.g. `1234` → `1.234` / `1,234`).
  String number(int value) {
    final digits = value.abs().toString();
    final buffer = StringBuffer();
    final separator = language == AppLanguage.de ? '.' : ',';
    for (var i = 0; i < digits.length; i++) {
      if (i > 0 && (digits.length - i) % 3 == 0) buffer.write(separator);
      buffer.write(digits[i]);
    }
    return value < 0 ? '-$buffer' : buffer.toString();
  }

  /// "1.234 Seiten" / "1,234 pages".
  String pagesCount(int count) => '${number(count)} $pagesUnit';

  /// Human watch time: "42 Std. 15 Min." / "42 h 15 min", "42 Std." / "42 h",
  /// "15 Min." / "15 min".
  String watchTime(int minutes) {
    final safe = minutes < 0 ? 0 : minutes;
    final hours = safe ~/ 60;
    final mins = safe % 60;
    if (hours > 0 && mins > 0) return '$hours $hoursShort $mins $minutesShort';
    if (hours > 0) return '$hours $hoursShort';
    return '$mins $minutesShort';
  }

  /// A rounded completion rate, e.g. "50 %" / "50%".
  String ratePercent(double value) => percentValue(value.round());

  // ───────────────────────────────────────────────────────────────────────────
  // login
  // ───────────────────────────────────────────────────────────────────────────

  String get loginTagline => _t('loginTagline');
  String get emailAddress => _t('emailAddress');
  String get emailHint => _t('emailHint');
  String get emailRequired => _t('emailRequired');
  String get emailInvalid => _t('emailInvalid');
  String get sending => _t('sending');
  String get sendMagicLink => _t('sendMagicLink');
  String get magicLinkDetails => _t('magicLinkDetails');
  String get checkInbox => _t('checkInbox');
  String get linkExpiryNote => _t('linkExpiryNote');
  String get useDifferentEmail => _t('useDifferentEmail');

  /// "We sent a sign-in link to the given address…".
  String sentLinkTo(String email) => _tParam('loginSentTo', {'email': email});

  // ───────────────────────────────────────────────────────────────────────────
  // settings sheet
  // ───────────────────────────────────────────────────────────────────────────

  String get signedIn => _t('signedIn');
  String get signedInWithMagicLink => _t('signedInWithMagicLink');
  String get darkMode => _t('darkMode');
  String get darkActive => _t('darkActive');
  String get lightActive => _t('lightActive');
  String get languageLabel => _t('languageLabel');
  String get signOut => _t('signOut');
  String get tmdbAttribution => _t('tmdbAttribution');

  // ───────────────────────────────────────────────────────────────────────────
  // JSON export / import (Phase 1b)
  // ───────────────────────────────────────────────────────────────────────────

  /// Settings sheet: start an export.
  String get dataExport => _t('dataExport');

  /// Settings sheet: subtitle of the export row.
  String get dataExportSubtitle => _t('dataExportSubtitle');

  /// Settings sheet: start an import.
  String get dataImport => _t('dataImport');

  /// Settings sheet: subtitle of the import row.
  String get dataImportSubtitle => _t('dataImportSubtitle');

  /// Progress feedback while the export runs.
  String get exporting => _t('exporting');

  /// Success feedback after a completed export.
  String get exportDone => _t('exportDone');

  /// Title of the export error dialog.
  String get exportFailedTitle => _t('exportFailedTitle');

  /// Feedback when the user dismissed the native save dialog.
  String get exportCancelled => _t('exportCancelled');

  /// Progress feedback while the import writes.
  String get importing => _t('importing');

  /// Title of the dialog that asks merge vs overwrite.
  String get importModeTitle => _t('importModeTitle');

  /// Body of the merge/overwrite dialog.
  String get importModeMessage => _t('importModeMessage');

  /// Merge action — existing data is kept, duplicates are skipped.
  String get importMerge => _t('importMerge');

  /// Overwrite action — everything is deleted first.
  String get importOverwrite => _t('importOverwrite');

  /// Title of the "delete everything?" confirmation.
  String get importOverwriteConfirmTitle => _t('importOverwriteConfirmTitle');

  /// Body of the overwrite confirmation.
  String get importOverwriteConfirmMessage =>
      _t('importOverwriteConfirmMessage');

  /// Destructive confirm button of the overwrite dialog.
  String get importOverwriteConfirmAction => _t('importOverwriteConfirmAction');

  /// Title of the import error dialog.
  String get importFailedTitle => _t('importFailedTitle');

  /// Generic follow-up when an import fails for an unknown reason.
  String get importUnknownError => _t('importUnknownError');

  /// Dialog acknowledgement.
  String get ok => _t('ok');

  /// Result counter snack bar — `{added}` new, `{skipped}` already there,
  /// `{errors}` could not be read.
  String importSummary(int added, int skipped, int errors) => _tParam(
    'importSummary',
    {'added': '$added', 'skipped': '$skipped', 'errors': '$errors'},
  );

  /// Localized explanation for a file the import rejected.
  String importErrorMessage(ImportErrorCode code) => switch (code) {
    ImportErrorCode.emptyFile => _t('importErrorEmptyFile'),
    ImportErrorCode.invalidJson => _t('importErrorInvalidJson'),
    ImportErrorCode.notJsonObject => _t('importErrorNotJsonObject'),
    ImportErrorCode.wrongFormat => _t('importErrorWrongFormat'),
    ImportErrorCode.unsupportedVersion => _t('importErrorUnsupportedVersion'),
    ImportErrorCode.missingMediaItems => _t('importErrorMissingMediaItems'),
    ImportErrorCode.missingEpisodes => _t('importErrorMissingEpisodes'),
  };

  // ───────────────────────────────────────────────────────────────────────────
  // detail sheet meta
  // ───────────────────────────────────────────────────────────────────────────

  String get minutes => _t('minutes');

  String seasons(int count) =>
      _tParam(count == 1 ? 'seasonOne' : 'seasonMany', {'count': '$count'});

  String episodes(int count) =>
      _tParam(count == 1 ? 'episodeOne' : 'episodeMany', {'count': '$count'});

  /// Page count of a book — singular / plural.
  String pages(int count) =>
      _tParam(count == 1 ? 'pageOne' : 'pageMany', {'count': '$count'});

  // ───────────────────────────────────────────────────────────────────────────
  // tracking / detail view (Phase 3a)
  // ───────────────────────────────────────────────────────────────────────────

  /// Section header of the tracking controls.
  String get trackingSection => _t('trackingSection');

  /// Label above the movie / book progress controls.
  String get progress => _t('progress');

  /// Label of the book "current page" input.
  String get currentPage => _t('currentPage');

  /// Label / field for a book's total page count.
  String get totalPages => _t('totalPages');

  /// "Started on" timestamp row.
  String get startedAt => _t('startedAt');

  /// "Completed on" timestamp row.
  String get completedAt => _t('completedAt');

  /// Placeholder for a timestamp that has not been set (yet).
  String get notSet => _t('notSet');

  /// Tooltip of the date-picker buttons.
  String get pickDate => _t('pickDate');

  /// Tooltip of the "clear timestamp" buttons.
  String get clearDate => _t('clearDate');

  /// "Delete item" action / confirmation dialog copy.
  String get deleteItem => _t('deleteItem');
  String get deleteConfirmTitle => _t('deleteConfirmTitle');

  /// Confirmation body — injects the item title.
  String deleteConfirmMessage(String title) =>
      _tParam('deleteConfirmMessage', {'title': title});
  String get delete => _t('delete');
  String get cancel => _t('cancel');
  String get itemDeleted => _t('itemDeleted');
  String get trackingSaveError => _t('trackingSaveError');
  String get invalidPage => _t('invalidPage');
  String get savePage => _t('savePage');

  /// Fallback shown for an item without a description.
  String get noDescription => _t('noDescription');

  // ───────────────────────────────────────────────────────────────────────────
  // series episodes (Phase 3b)
  // ───────────────────────────────────────────────────────────────────────────

  /// Plain "Season" heading / selector label.
  String get seasonLabel => _t('seasonLabel');

  /// Plain "Episodes" heading.
  String get episodesLabel => _t('episodesLabel');

  /// "Season 1" — the season selector chips.
  String seasonNumberLabel(int number) =>
      _tParam('seasonNumberLabel', {'number': '$number'});

  /// "Episode 1" — the per-episode number prefix.
  String episodeNumber(int number) =>
      _tParam('episodeNumber', {'number': '$number'});

  /// Checkbox label / heading for a watched episode.
  String get watchedLabel => _t('watchedLabel');

  /// Bulk action: mark the whole season as watched.
  String get markSeasonWatched => _t('markSeasonWatched');

  /// Bulk action: reset the whole season.
  String get resetSeason => _t('resetSeason');

  /// Spinner label while episodes are fetched (`done`/`total` seasons).
  String loadingEpisodesProgress(int done, int total) =>
      _tParam('loadingEpisodesProgress', {'done': '$done', 'total': '$total'});

  /// Empty state when TMDB has no episodes for the series.
  String get noEpisodes => _t('noEpisodes');

  /// "Aired on" label in front of an episode's air date.
  String get airedOn => _t('airedOn');

  /// Fallback shown when an episode has no synopsis (`overview`).
  String get noEpisodeDescription => _t('noEpisodeDescription');

  /// Runtime label of an episode.
  String get runtimeLabel => _t('runtimeLabel');

  /// Tooltip of the manual "reload episodes" action.
  String get refreshEpisodes => _t('refreshEpisodes');

  /// "3 of 12 episodes" — the derived series progress summary.
  String episodesProgressLabel(int watched, int total) => _tParam(
    'episodesProgressLabel',
    {'watched': '$watched', 'total': '$total'},
  );

  /// Confirmation dialog before resetting a season.
  String get resetSeasonConfirmTitle => _t('resetSeasonConfirmTitle');
  String resetSeasonConfirmMessage(int seasonNumber) =>
      _tParam('resetSeasonConfirmMessage', {'number': '$seasonNumber'});

  /// Title of the episode-load error state.
  String get episodesLoadErrorTitle => _t('episodesLoadErrorTitle');

  /// Snack bar after a bulk "mark season as watched".
  String get seasonWatchedDone => _t('seasonWatchedDone');

  /// Snack bar after a bulk "reset season".
  String get seasonResetDone => _t('seasonResetDone');

  /// "Page X of Y" (book progress), e.g. "Seite 42 von 300".
  String pageOf(int current, int total) =>
      _tParam('pageOf', {'current': '$current', 'total': '$total'});

  /// "Page X" when the total page count is unknown.
  String pageOfUnknownTotal(int current) =>
      _tParam('pageOfUnknownTotal', {'current': '$current'});

  /// "42 %" / "42%" — the percent display on the sliders and in the list.
  String percentValue(int value) =>
      _tParam('percentValue', {'value': '$value'});

  // ───────────────────────────────────────────────────────────────────────────
  // TMDB service messages (thrown as [TmdbException] and shown in the UI)
  // ───────────────────────────────────────────────────────────────────────────

  String get tmdbNotConfigured => _t('tmdbNotConfigured');
  String get tmdbTimeout => _t('tmdbTimeout');
  String get tmdbUnreachable => _t('tmdbUnreachable');
  String get tmdbInvalidToken => _t('tmdbInvalidToken');
  String get tmdbNotFound => _t('tmdbNotFound');
  String get tmdbRateLimited => _t('tmdbRateLimited');
  String get tmdbRequestFailed => _t('tmdbRequestFailed');
  String get tmdbUnexpectedResponse => _t('tmdbUnexpectedResponse');
  String get tmdbUnreadableResponse => _t('tmdbUnreadableResponse');

  // ───────────────────────────────────────────────────────────────────────────
  // OpenLibrary service messages (thrown as [OpenLibraryException])
  // ───────────────────────────────────────────────────────────────────────────

  String get openLibraryTimeout => _t('openLibraryTimeout');
  String get openLibraryUnreachable => _t('openLibraryUnreachable');
  String get openLibraryNotFound => _t('openLibraryNotFound');
  String get openLibraryRequestFailed => _t('openLibraryRequestFailed');
  String get openLibraryUnexpectedResponse =>
      _t('openLibraryUnexpectedResponse');
  String get openLibraryUnreadableResponse =>
      _t('openLibraryUnreadableResponse');
}

/// `context.strings` sugar.
extension AppStringsContext on BuildContext {
  /// Subscribing lookup — use in `build`.
  AppStrings get strings => AppStrings.of(this);

  /// Non-subscribing lookup — use in callbacks.
  AppStrings get stringsRead => AppStrings.read(this);
}

/// All translations, keyed by language then by string key.
///
/// Keep the two maps in sync; missing keys fall back to English / the key.
const Map<AppLanguage, Map<String, String>> _kStrings = {
  AppLanguage.de: <String, String>{
    // navigation / generic
    'library': 'Bibliothek',
    'search': 'Suche',
    'stats': 'Statistik',
    'settings': 'Einstellungen',
    'refresh': 'Aktualisieren',
    'retry': 'Erneut versuchen',
    'clear': 'Leeren',
    'moreActions': 'Weitere Aktionen',
    'loadingLibrary': 'Bibliothek wird geladen…',
    // kinds / statuses
    'kindMovie': 'Film',
    'kindSeries': 'Serie',
    'kindBook': 'Buch',
    'statusPlanned': 'Geplant',
    'statusInProgress': 'Angefangen',
    'statusCompleted': 'Abgeschlossen',
    'statusDropped': 'Abgebrochen',
    'scopeAll': 'Alle',
    'scopeMovies': 'Filme',
    'scopeSeries': 'Serien',
    'scopeBooks': 'Bücher',
    // library
    'libraryLoadErrorTitle': 'Bibliothek konnte nicht geladen werden',
    'libraryEmptyTitle': 'Deine Bibliothek ist leer',
    'libraryEmptyMessage':
        'Filme, Serien und Bücher, die du verfolgst, erscheinen hier.',
    // metadata refresh
    'metadataRefreshAction': 'Metadaten aktualisieren',
    'metadataRefreshing': 'Metadaten werden aktualisiert… ({done}/{total})',
    'metadataRefreshed': '{updated} von {total} Einträgen aktualisiert',
    'metadataRefreshPartial':
        '{updated} von {total} aktualisiert – {failed} konnten nicht geladen '
        'werden. Die alten Angaben bleiben sichtbar.',
    'metadataRefreshEmpty': 'Keine TMDB-Einträge zum Aktualisieren.',
    // search
    'searchHint': 'Filme, Serien und Bücher suchen',
    'searchIdleTitle': 'Finde etwas zum Verfolgen',
    'searchIdleMessage': 'Suche Filme, Serien und Bücher nach Titel.',
    'searchFailedTitle': 'Suche fehlgeschlagen',
    'noResultsTitle': 'Keine Treffer',
    'noResultsMessage':
        'Versuch eine andere Schreibweise oder eine kürzere Suche.',
    'searchMissingToken':
        'Die Suche ist nicht verfügbar: In diesem Build ist kein '
        'TMDB-Token konfiguriert. Baue die App mit '
        '--dart-define=TMDB_TOKEN=…. neu.',
    'addToLibrary': 'Zur Bibliothek hinzufügen',
    'alreadyInLibrary': 'Bereits in deiner Bibliothek',
    'addedToLibrary': 'Zur Bibliothek hinzugefügt',
    'bookNoDescription': 'Keine Beschreibung verfügbar.',
    'byAuthors': 'von {authors}',
    // stats
    'statsComingSoon': 'Statistik folgt bald',
    'statsDescription':
        'Verfolge, wie viel du über die Zeit schaust und liest.',
    // stats screen (phase 5)
    'statsOverview': 'Überblick',
    'statsStatusDistribution': 'Status-Verteilung',
    'statsCompletionRate': 'Abschlussquote',
    'statsEmptyTitle': 'Noch keine Statistik',
    'statsEmptyMessage':
        'Füge Filme, Serien oder Bücher hinzu, um deine Statistik zu sehen.',
    'statsLoadErrorTitle': 'Statistik konnte nicht geladen werden',
    'statsOverTime': 'Abschlüsse über Zeit',
    'statsOverTimeHint':
        'Filme und Bücher nach Abschlussdatum, Serien-Folgen nach Sehdatum.',
    'statsWatchTime': 'TV-Minuten',
    'statsWatchTimeHint':
        'Laufzeit gesehener Folgen und abgeschlossener Filme.',
    'statsWatchTimeNoData': 'Noch keine Laufzeitdaten vorhanden.',
    'statsNoCompletions': 'In diesem Zeitraum keine Abschlüsse.',
    'statsPages': 'Seiten',
    'statsPagesHint':
        'Seitenzahl abgeschlossener Bücher – eine Näherung, da es keine '
        'Lese-Historie gibt.',
    'range1Month': '1 Monat',
    'range6Months': '6 Monate',
    'range12Months': '12 Monate',
    'rangeAll': 'Gesamt',
    'hoursShort': 'Std.',
    'minutesShort': 'Min.',
    'pagesUnit': 'Seiten',
    'monthShort': 'Jan,Feb,Mär,Apr,Mai,Jun,Jul,Aug,Sep,Okt,Nov,Dez',
    // login
    'loginTagline':
        'Verfolge die Filme, Serien und Bücher, die du gesehen, geschaut '
        'und gelesen hast.',
    'emailAddress': 'E-Mail-Adresse',
    'emailHint': 'du@beispiel.de',
    'emailRequired': 'Bitte gib deine E-Mail-Adresse ein.',
    'emailInvalid': 'Bitte gib eine gültige E-Mail-Adresse ein.',
    'sending': 'Wird gesendet…',
    'sendMagicLink': 'Anmelde-Link senden',
    'magicLinkDetails':
        'Kein Passwort nötig — wir senden dir einen einmaligen Anmelde-Link '
        'per E-Mail. Bei der ersten Anmeldung wird automatisch ein Konto '
        'angelegt.',
    'checkInbox': 'Prüfe dein Postfach',
    'loginSentTo':
        'Wir haben einen Anmelde-Link an {email} gesendet. Öffne ihn in '
        'diesem Browser, um die Anmeldung abzuschließen.',
    'linkExpiryNote':
        'Der Link läuft nach kurzer Zeit ab. Nichts im Postfach? Schau auch '
        'im Spam-Ordner nach.',
    'useDifferentEmail': 'Andere E-Mail-Adresse verwenden',
    // settings
    'signedIn': 'Angemeldet',
    'signedInWithMagicLink': 'Angemeldet per Anmelde-Link',
    'darkMode': 'Dunkles Design',
    'darkActive': 'Dunkles Farbschema aktiv',
    'lightActive': 'Helles Farbschema aktiv',
    'languageLabel': 'Sprache',
    'signOut': 'Abmelden',
    'tmdbAttribution':
        'Dieses Produkt verwendet die TMDB-API, wird aber nicht von TMDB '
        'unterstützt oder zertifiziert.',
    // JSON export / import (phase 1b)
    'dataExport': 'Daten exportieren',
    'dataExportSubtitle': 'Deine Bibliothek als JSON-Datei sichern',
    'dataImport': 'Daten importieren',
    'dataImportSubtitle':
        'Bibliothek aus einer Sicherungsdatei wiederherstellen',
    'exporting': 'Daten werden exportiert…',
    'exportDone': 'Export abgeschlossen',
    'exportFailedTitle': 'Export fehlgeschlagen',
    'exportCancelled': 'Export abgebrochen',
    'importing': 'Daten werden importiert…',
    'importModeTitle': 'Import-Modus',
    'importModeMessage':
        'Wie sollen die importierten Daten behandelt werden?\n\n'
        '• Zusammenführen: Deine aktuellen Einträge bleiben erhalten, bereits '
        'vorhandene werden übersprungen.\n'
        '• Überschreiben: Alle aktuellen Daten werden vorher gelöscht.',
    'importMerge': 'Zusammenführen',
    'importOverwrite': 'Überschreiben',
    'importOverwriteConfirmTitle': 'Alle aktuellen Daten löschen?',
    'importOverwriteConfirmMessage':
        'Alle deine aktuellen Einträge und Folgen werden gelöscht, bevor die '
        'Datei importiert wird. Das kann nicht rückgängig gemacht werden.\n\n'
        'Fortfahren?',
    'importOverwriteConfirmAction': 'Löschen und importieren',
    'importFailedTitle': 'Import fehlgeschlagen',
    'importUnknownError': 'Unbekannter Fehler.',
    'ok': 'OK',
    'importSummary':
        '{added} hinzugefügt, {skipped} übersprungen, '
        '{errors} Fehler',
    'importErrorEmptyFile': 'Die Datei ist leer.',
    'importErrorInvalidJson': 'Die Datei enthält kein gültiges JSON.',
    'importErrorNotJsonObject':
        'Die Datei hat ein unerwartetes Format: Das oberste Element ist kein '
        'JSON-Objekt.',
    'importErrorWrongFormat': 'Die Datei ist keine Media-Tracker-Sicherung.',
    'importErrorUnsupportedVersion':
        'Diese Version der Sicherungsdatei wird nicht unterstützt.',
    'importErrorMissingMediaItems':
        'In der Datei fehlt die Liste der Medieneinträge.',
    'importErrorMissingEpisodes': 'In der Datei fehlt die Liste der Folgen.',
    // detail meta
    'minutes': 'Min.',
    'seasonOne': '{count} Staffel',
    'seasonMany': '{count} Staffeln',
    'episodeOne': '{count} Folge',
    'episodeMany': '{count} Folgen',
    'pageOne': '{count} Seite',
    'pageMany': '{count} Seiten',
    // tracking / detail (phase 3a)
    'trackingSection': 'Verfolgung',
    'progress': 'Fortschritt',
    'currentPage': 'Aktuelle Seite',
    'totalPages': 'Seiten gesamt',
    'startedAt': 'Begonnen am',
    'completedAt': 'Abgeschlossen am',
    'notSet': 'Noch nicht gesetzt',
    'pickDate': 'Datum wählen',
    'clearDate': 'Datum löschen',
    'deleteItem': 'Eintrag löschen',
    'deleteConfirmTitle': 'Eintrag löschen?',
    'deleteConfirmMessage': '„{title}“ wird aus deiner Bibliothek entfernt.',
    'delete': 'Löschen',
    'cancel': 'Abbrechen',
    'itemDeleted': 'Eintrag gelöscht',
    'trackingSaveError': 'Änderung konnte nicht gespeichert werden.',
    'invalidPage': 'Bitte gib eine gültige Seitenzahl ein.',
    'savePage': 'Seite speichern',
    'noDescription': 'Keine Beschreibung verfügbar.',
    'seasonLabel': 'Staffel',
    'episodesLabel': 'Folgen',
    'seasonNumberLabel': 'Staffel {number}',
    'episodeNumber': 'Folge {number}',
    'watchedLabel': 'Gesehen',
    'markSeasonWatched': 'Staffel als gesehen markieren',
    'resetSeason': 'Staffel zurücksetzen',
    'loadingEpisodesProgress': 'Lade Folgen… ({done}/{total})',
    'noEpisodes': 'Keine Folgen gefunden',
    'airedOn': 'Ausgestrahlt am',
    'noEpisodeDescription': 'Keine Beschreibung vorhanden.',
    'runtimeLabel': 'Laufzeit',
    'refreshEpisodes': 'Folgen aktualisieren',
    'episodesProgressLabel': '{watched} von {total} Folgen',
    'resetSeasonConfirmTitle': 'Staffel zurücksetzen?',
    'resetSeasonConfirmMessage':
        'Alle gesehenen Folgen von Staffel {number} werden wieder auf „nicht '
        'gesehen“ gesetzt.',
    'episodesLoadErrorTitle': 'Folgen konnten nicht geladen werden',
    'seasonWatchedDone': 'Staffel als gesehen markiert',
    'seasonResetDone': 'Staffel zurückgesetzt',
    'pageOf': 'Seite {current} von {total}',
    'pageOfUnknownTotal': 'Seite {current}',
    'percentValue': '{value} %',
    // TMDB service
    'tmdbNotConfigured':
        'TMDB ist für diesen Build nicht konfiguriert. Baue neu mit '
        '--dart-define=TMDB_TOKEN=….',
    'tmdbTimeout':
        'Die Anfrage an TMDB hat zu lange gedauert. Bitte versuch es erneut.',
    'tmdbUnreachable':
        'TMDB ist nicht erreichbar. Prüfe deine Verbindung und versuch es '
        'erneut.',
    'tmdbInvalidToken':
        'TMDB hat das API-Token abgelehnt. Prüfe, ob TMDB_TOKEN gültig ist.',
    'tmdbNotFound': 'TMDB konnte diesen Titel nicht finden.',
    'tmdbRateLimited':
        'Zu viele Anfragen an TMDB. Bitte warte einen Moment und versuch es '
        'erneut.',
    'tmdbRequestFailed':
        'TMDB-Anfrage fehlgeschlagen. Bitte versuch es erneut.',
    'tmdbUnexpectedResponse': 'TMDB hat eine unerwartete Antwort gesendet.',
    'tmdbUnreadableResponse': 'TMDB hat eine unlesbare Antwort gesendet.',
    // OpenLibrary service
    'openLibraryTimeout':
        'Die Anfrage an OpenLibrary hat zu lange gedauert. Bitte versuch es '
        'erneut.',
    'openLibraryUnreachable':
        'OpenLibrary ist nicht erreichbar. Prüfe deine Verbindung und versuch '
        'es erneut.',
    'openLibraryNotFound': 'OpenLibrary konnte diesen Titel nicht finden.',
    'openLibraryRequestFailed':
        'OpenLibrary-Anfrage fehlgeschlagen. Bitte versuch es erneut.',
    'openLibraryUnexpectedResponse':
        'OpenLibrary hat eine unerwartete Antwort gesendet.',
    'openLibraryUnreadableResponse':
        'OpenLibrary hat eine unlesbare Antwort gesendet.',
  },
  AppLanguage.en: <String, String>{
    // navigation / generic
    'library': 'Library',
    'search': 'Search',
    'stats': 'Stats',
    'settings': 'Settings',
    'refresh': 'Refresh',
    'retry': 'Retry',
    'clear': 'Clear',
    'moreActions': 'More actions',
    'loadingLibrary': 'Loading your library…',
    // kinds / statuses
    'kindMovie': 'Movie',
    'kindSeries': 'Series',
    'kindBook': 'Book',
    'statusPlanned': 'Planned',
    'statusInProgress': 'In progress',
    'statusCompleted': 'Completed',
    'statusDropped': 'Dropped',
    'scopeAll': 'All',
    'scopeMovies': 'Movies',
    'scopeSeries': 'Series',
    'scopeBooks': 'Books',
    // library
    'libraryLoadErrorTitle': 'Could not load your library',
    'libraryEmptyTitle': 'Your library is empty',
    'libraryEmptyMessage':
        'Movies, series and books you track will show up here.',
    // metadata refresh
    'metadataRefreshAction': 'Refresh metadata',
    'metadataRefreshing': 'Updating metadata… ({done}/{total})',
    'metadataRefreshed': '{updated} of {total} items updated',
    'metadataRefreshPartial':
        '{updated} of {total} updated — {failed} could not be loaded. The '
        'previously stored details stay visible.',
    'metadataRefreshEmpty': 'No TMDB entries to update.',
    // search
    'searchHint': 'Search movies, series and books',
    'searchIdleTitle': 'Find something to track',
    'searchIdleMessage': 'Search for movies, series and books by title.',
    'searchFailedTitle': 'Search failed',
    'noResultsTitle': 'No results',
    'noResultsMessage': 'Try a different spelling or a shorter query.',
    'searchMissingToken':
        'Search is unavailable: this build has no TMDB token configured. '
        'Rebuild the app with --dart-define=TMDB_TOKEN=….',
    'addToLibrary': 'Add to library',
    'alreadyInLibrary': 'Already in your library',
    'addedToLibrary': 'Added to library',
    'bookNoDescription': 'No description available.',
    'byAuthors': 'by {authors}',
    // stats
    'statsComingSoon': 'Stats coming soon',
    'statsDescription': 'Track how much you watch and read over time.',
    // stats screen (phase 5)
    'statsOverview': 'Overview',
    'statsStatusDistribution': 'Status distribution',
    'statsCompletionRate': 'Completion rate',
    'statsEmptyTitle': 'No stats yet',
    'statsEmptyMessage': 'Add movies, series or books to see your stats.',
    'statsLoadErrorTitle': 'Could not load your stats',
    'statsOverTime': 'Completions over time',
    'statsOverTimeHint':
        'Movies and books by completion date, series episodes by watch date.',
    'statsWatchTime': 'TV minutes',
    'statsWatchTimeHint': 'Runtime of watched episodes and completed movies.',
    'statsWatchTimeNoData': 'No runtime data available yet.',
    'statsNoCompletions': 'No completions in this period.',
    'statsPages': 'Pages',
    'statsPagesHint':
        'Page count of completed books — an approximation, since there is no '
        'reading history.',
    'range1Month': '1 month',
    'range6Months': '6 months',
    'range12Months': '12 months',
    'rangeAll': 'All time',
    'hoursShort': 'h',
    'minutesShort': 'min',
    'pagesUnit': 'pages',
    'monthShort': 'Jan,Feb,Mar,Apr,May,Jun,Jul,Aug,Sep,Oct,Nov,Dec',
    // login
    'loginTagline':
        'Track the movies, series and books you have seen, watched and read.',
    'emailAddress': 'Email address',
    'emailHint': 'you@example.com',
    'emailRequired': 'Please enter your email address.',
    'emailInvalid': 'Please enter a valid email address.',
    'sending': 'Sending…',
    'sendMagicLink': 'Send magic link',
    'magicLinkDetails':
        'No password needed — we will email you a one-time sign-in link. '
        'A new account is created on your first sign-in.',
    'checkInbox': 'Check your inbox',
    'loginSentTo':
        'We sent a sign-in link to {email}. Open it in this browser to '
        'finish signing in.',
    'linkExpiryNote':
        'The link expires after a short while. Nothing in your inbox? Check '
        'the spam folder.',
    'useDifferentEmail': 'Use a different email',
    // settings
    'signedIn': 'Signed in',
    'signedInWithMagicLink': 'Signed in with a magic link',
    'darkMode': 'Dark Mode',
    'darkActive': 'Dark color scheme active',
    'lightActive': 'Light color scheme active',
    'languageLabel': 'Language',
    'signOut': 'Sign out',
    'tmdbAttribution':
        'This product uses the TMDB API but is not endorsed or certified by '
        'TMDB.',
    // JSON export / import (phase 1b)
    'dataExport': 'Export data',
    'dataExportSubtitle': 'Back up your library as a JSON file',
    'dataImport': 'Import data',
    'dataImportSubtitle': 'Restore your library from a backup file',
    'exporting': 'Exporting your data…',
    'exportDone': 'Export complete',
    'exportFailedTitle': 'Export failed',
    'exportCancelled': 'Export cancelled',
    'importing': 'Importing your data…',
    'importModeTitle': 'Import mode',
    'importModeMessage':
        'How should the imported data be handled?\n\n'
        '• Merge: your current entries stay, existing ones are skipped.\n'
        '• Overwrite: all current data is deleted first.',
    'importMerge': 'Merge',
    'importOverwrite': 'Overwrite',
    'importOverwriteConfirmTitle': 'Delete all current data?',
    'importOverwriteConfirmMessage':
        'All your current entries and episodes will be deleted before the '
        'file is imported. This cannot be undone.\n\n'
        'Continue?',
    'importOverwriteConfirmAction': 'Delete & import',
    'importFailedTitle': 'Import failed',
    'importUnknownError': 'Unknown error.',
    'ok': 'OK',
    'importSummary': '{added} added, {skipped} skipped, {errors} errors',
    'importErrorEmptyFile': 'The file is empty.',
    'importErrorInvalidJson': 'The file does not contain valid JSON.',
    'importErrorNotJsonObject':
        'The file has an unexpected format: the root element is not a JSON '
        'object.',
    'importErrorWrongFormat': 'This file is not a Media Tracker backup.',
    'importErrorUnsupportedVersion':
        'This backup file version is not supported.',
    'importErrorMissingMediaItems':
        'The file is missing the list of media items.',
    'importErrorMissingEpisodes': 'The file is missing the list of episodes.',
    // detail meta
    'minutes': 'min',
    'seasonOne': '{count} season',
    'seasonMany': '{count} seasons',
    'episodeOne': '{count} episode',
    'episodeMany': '{count} episodes',
    'pageOne': '{count} page',
    'pageMany': '{count} pages',
    // tracking / detail (phase 3a)
    'trackingSection': 'Tracking',
    'progress': 'Progress',
    'currentPage': 'Current page',
    'totalPages': 'Total pages',
    'startedAt': 'Started on',
    'completedAt': 'Completed on',
    'notSet': 'Not set yet',
    'pickDate': 'Pick a date',
    'clearDate': 'Clear date',
    'deleteItem': 'Delete item',
    'deleteConfirmTitle': 'Delete this item?',
    'deleteConfirmMessage': '“{title}” will be removed from your library.',
    'delete': 'Delete',
    'cancel': 'Cancel',
    'itemDeleted': 'Item deleted',
    'trackingSaveError': 'Could not save the change.',
    'invalidPage': 'Please enter a valid page number.',
    'savePage': 'Save page',
    'noDescription': 'No description available.',
    'seasonLabel': 'Season',
    'episodesLabel': 'Episodes',
    'seasonNumberLabel': 'Season {number}',
    'episodeNumber': 'Episode {number}',
    'watchedLabel': 'Watched',
    'markSeasonWatched': 'Mark season as watched',
    'resetSeason': 'Reset season',
    'loadingEpisodesProgress': 'Loading episodes… ({done}/{total})',
    'noEpisodes': 'No episodes found',
    'airedOn': 'Aired on',
    'noEpisodeDescription': 'No description available.',
    'runtimeLabel': 'Runtime',
    'refreshEpisodes': 'Refresh episodes',
    'episodesProgressLabel': '{watched} of {total} episodes',
    'resetSeasonConfirmTitle': 'Reset this season?',
    'resetSeasonConfirmMessage':
        'Every watched episode of season {number} will be marked unwatched '
        'again.',
    'episodesLoadErrorTitle': 'Could not load the episodes',
    'seasonWatchedDone': 'Season marked as watched',
    'seasonResetDone': 'Season reset',
    'pageOf': 'Page {current} of {total}',
    'pageOfUnknownTotal': 'Page {current}',
    'percentValue': '{value}%',
    // TMDB service
    'tmdbNotConfigured':
        'TMDB is not configured for this build. Rebuild with '
        '--dart-define=TMDB_TOKEN=….',
    'tmdbTimeout': 'The request to TMDB timed out. Please try again.',
    'tmdbUnreachable':
        'Could not reach TMDB. Check your connection and try again.',
    'tmdbInvalidToken':
        'TMDB rejected the API token. Check that TMDB_TOKEN is valid.',
    'tmdbNotFound': 'TMDB could not find that title.',
    'tmdbRateLimited':
        'Too many requests to TMDB. Please wait a moment and retry.',
    'tmdbRequestFailed': 'TMDB request failed. Please try again.',
    'tmdbUnexpectedResponse': 'TMDB returned an unexpected response.',
    'tmdbUnreadableResponse': 'TMDB returned an unreadable response.',
    // OpenLibrary service
    'openLibraryTimeout':
        'The request to OpenLibrary timed out. Please try again.',
    'openLibraryUnreachable':
        'Could not reach OpenLibrary. Check your connection and try again.',
    'openLibraryNotFound': 'OpenLibrary could not find that title.',
    'openLibraryRequestFailed': 'OpenLibrary request failed. Please try again.',
    'openLibraryUnexpectedResponse':
        'OpenLibrary returned an unexpected response.',
    'openLibraryUnreadableResponse':
        'OpenLibrary returned an unreadable response.',
  },
};
