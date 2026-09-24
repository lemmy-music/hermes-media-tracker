import 'package:flutter/widgets.dart';
import 'package:provider/provider.dart';

import '../models/media_item.dart';
import '../models/tmdb_result.dart';
import '../providers/settings_provider.dart';
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
    final value =
        _kStrings[language]?[key] ?? _kStrings[AppLanguage.en]?[key];
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
      _tParam('metadataRefreshed', {
        'updated': '$updated',
        'total': '$total',
      });

  /// Snack bar after a run where some items kept their old metadata.
  String metadataRefreshPartial(int updated, int total, int failed) =>
      _tParam('metadataRefreshPartial', {
        'updated': '$updated',
        'total': '$total',
        'failed': '$failed',
      });

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

  // ───────────────────────────────────────────────────────────────────────────
  // stats
  // ───────────────────────────────────────────────────────────────────────────

  String get statsComingSoon => _t('statsComingSoon');
  String get statsDescription => _t('statsDescription');

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
  String sentLinkTo(String email) =>
      _tParam('loginSentTo', {'email': email});

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
  // detail sheet meta
  // ───────────────────────────────────────────────────────────────────────────

  String get minutes => _t('minutes');

  String seasons(int count) =>
      _tParam(count == 1 ? 'seasonOne' : 'seasonMany', {'count': '$count'});

  String episodes(int count) =>
      _tParam(count == 1 ? 'episodeOne' : 'episodeMany', {'count': '$count'});

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
    'searchHint': 'Filme und Serien suchen',
    'searchIdleTitle': 'Finde etwas zum Verfolgen',
    'searchIdleMessage': 'Suche Filme und Serien nach Titel.',
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
    // stats
    'statsComingSoon': 'Statistik folgt bald',
    'statsDescription':
        'Verfolge, wie viel du über die Zeit schaust und liest.',
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
    // detail meta
    'minutes': 'Min.',
    'seasonOne': '{count} Staffel',
    'seasonMany': '{count} Staffeln',
    'episodeOne': '{count} Folge',
    'episodeMany': '{count} Folgen',
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
    'searchHint': 'Search movies and series',
    'searchIdleTitle': 'Find something to track',
    'searchIdleMessage': 'Search for movies and series by title.',
    'searchFailedTitle': 'Search failed',
    'noResultsTitle': 'No results',
    'noResultsMessage': 'Try a different spelling or a shorter query.',
    'searchMissingToken':
        'Search is unavailable: this build has no TMDB token configured. '
            'Rebuild the app with --dart-define=TMDB_TOKEN=….',
    'addToLibrary': 'Add to library',
    'alreadyInLibrary': 'Already in your library',
    'addedToLibrary': 'Added to library',
    // stats
    'statsComingSoon': 'Stats coming soon',
    'statsDescription': 'Track how much you watch and read over time.',
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
    // detail meta
    'minutes': 'min',
    'seasonOne': '{count} season',
    'seasonMany': '{count} seasons',
    'episodeOne': '{count} episode',
    'episodeMany': '{count} episodes',
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
  },
};
