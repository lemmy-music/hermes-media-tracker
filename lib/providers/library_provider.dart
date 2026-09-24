import 'package:flutter/foundation.dart';

import '../l10n/app_language.dart';
import '../models/media_item.dart';
import '../models/tmdb_result.dart';
import '../repositories/media_repository.dart';
import '../services/tmdb_client.dart';
import 'settings_provider.dart';

/// Outcome of one metadata refresh run.
@immutable
class MetadataRefreshResult {
  const MetadataRefreshResult({
    required this.updated,
    required this.total,
    required this.failed,
  });

  /// Items whose metadata was re-fetched and stored.
  final int updated;

  /// Items that were candidates for a refresh (`external_source == 'tmdb'`).
  final int total;

  /// Items that kept their stored snapshot because loading or saving failed.
  final int failed;

  /// `true` when there was at least one TMDB item to refresh.
  bool get hadCandidates => total > 0;

  /// `true` when at least one item kept its (possibly stale) metadata.
  bool get hadFailures => failed > 0;

  /// A run that found nothing to do.
  static const MetadataRefreshResult empty = MetadataRefreshResult(
    updated: 0,
    total: 0,
    failed: 0,
  );

  @override
  String toString() =>
      'MetadataRefreshResult(updated: $updated, total: $total, '
      'failed: $failed)';
}

/// Holds the library list **and** the language-driven metadata refresh.
///
/// Metadata (title, overview, poster, …) is stored as a snapshot in the
/// language that was active when the item was added. Switching the UI
/// language therefore has to re-fetch the TMDB details of every stored TMDB
/// item — otherwise an English "The Lord of the Rings" stays English in a
/// German library (and it cannot be re-added: the `external_id` unique index
/// would reject it).
///
/// The provider listens to [SettingsProvider]: an actual language change
/// starts a refresh in the background. Tracking state is never touched; see
/// [MediaRepository.updateMetadata].
class LibraryProvider extends ChangeNotifier {
  LibraryProvider({
    required MediaRepository repository,
    required TmdbClient tmdbClient,
    required SettingsProvider settings,
    int maxConcurrency = defaultMaxConcurrency,
  }) : // The two fields below are private and their parameter names must stay
       // public, so an initializing formal is impossible here — the lint is a
       // false positive.
       // ignore: prefer_initializing_formals
       _repository = repository,
       // ignore: prefer_initializing_formals
       _tmdbClient = tmdbClient,
       _settings = settings,
       _language = settings.language,
       _maxConcurrency = maxConcurrency < 1 ? 1 : maxConcurrency {
    _settings.addListener(_onSettingsChanged);
  }

  /// The `external_source` value of TMDB-backed items.
  static const String tmdbSource = 'tmdb';

  /// How many TMDB requests run at the same time. TMDB happily serves a
  /// handful of parallel requests, but the run must stay gentle.
  static const int defaultMaxConcurrency = 4;

  final MediaRepository _repository;
  final TmdbClient _tmdbClient;
  final SettingsProvider _settings;
  final int _maxConcurrency;

  /// The language the metadata currently reflects — the provider refreshes
  /// whenever [SettingsProvider] moves away from it.
  AppLanguage _language;

  List<MediaItem> _items = const <MediaItem>[];
  bool _loading = true;
  String? _error;

  bool _refreshingMetadata = false;
  int _metadataRefreshDone = 0;
  int _metadataRefreshTotal = 0;
  int _metadataRefreshRuns = 0;
  AppLanguage? _metadataRefreshLanguage;
  MetadataRefreshResult? _lastMetadataRefresh;
  Future<MetadataRefreshResult>? _activeRefresh;

  bool _disposed = false;

  // ───────────────────────────────────────────────────────────────────────────
  // library list
  // ───────────────────────────────────────────────────────────────────────────

  /// The loaded items, newest first (as returned by the repository).
  List<MediaItem> get items => _items;

  /// `true` while the list is being (re)loaded.
  bool get loading => _loading;

  /// User-facing message of the last failed load, or `null`.
  String? get error => _error;

  /// Loads (or reloads) the signed-in user's library.
  Future<void> load() async {
    if (!_loading || _error != null) {
      _loading = true;
      _error = null;
      _notify();
    }
    try {
      final items = await _repository.fetchAll();
      _items = items;
      _loading = false;
    } on MediaRepositoryException catch (error) {
      _error = error.message;
      _loading = false;
    }
    _notify();
  }

  // ───────────────────────────────────────────────────────────────────────────
  // metadata refresh
  // ───────────────────────────────────────────────────────────────────────────

  /// `true` while a refresh run is in flight (drives the progress banner).
  bool get refreshingMetadata => _refreshingMetadata;

  /// Items already handled in the current run.
  int get metadataRefreshDone => _metadataRefreshDone;

  /// Candidates of the current run.
  int get metadataRefreshTotal => _metadataRefreshTotal;

  /// The language the current run loads metadata in.
  AppLanguage? get metadataRefreshLanguage => _metadataRefreshLanguage;

  /// Result of the most recent completed run (including empty ones).
  MetadataRefreshResult? get lastMetadataRefresh => _lastMetadataRefresh;

  /// Increments once per completed run — the UI uses this to show the result
  /// snack bar exactly once per run (also for the automatic one).
  int get metadataRefreshRuns => _metadataRefreshRuns;

  /// Re-loads the metadata of every stored TMDB item in [language] and stores
  /// it, so the library shows localized titles/overviews.
  ///
  /// Robust by design: a failing request (or write) only skips *that* item —
  /// its stored snapshot stays visible — and the run reports
  /// `updated`/`total`. Concurrent calls share the in-flight run.
  Future<MetadataRefreshResult> refreshMetadata({
    required AppLanguage language,
  }) {
    final active = _activeRefresh;
    if (active != null) return active;

    final future = _runMetadataRefresh(language);
    _activeRefresh = future.whenComplete(() => _activeRefresh = null);
    return _activeRefresh!;
  }

  Future<MetadataRefreshResult> _runMetadataRefresh(AppLanguage language) async {
    final targets = _items.where(_isTmdbItem).toList(growable: false);
    if (targets.isEmpty) {
      _lastMetadataRefresh = MetadataRefreshResult.empty;
      return MetadataRefreshResult.empty;
    }

    _refreshingMetadata = true;
    _metadataRefreshDone = 0;
    _metadataRefreshTotal = targets.length;
    _metadataRefreshLanguage = language;
    _notify();

    var updated = 0;
    var next = 0;
    final workerCount = _maxConcurrency < targets.length
        ? _maxConcurrency
        : targets.length;

    Future<void> worker() async {
      while (true) {
        final index = next++;
        if (index >= targets.length) return;
        if (await _refreshItem(targets[index], language)) updated++;
        _metadataRefreshDone++;
        _notify();
      }
    }

    await Future.wait(<Future<void>>[
      for (var i = 0; i < workerCount; i++) worker(),
    ]);

    final result = MetadataRefreshResult(
      updated: updated,
      total: targets.length,
      failed: targets.length - updated,
    );
    _lastMetadataRefresh = result;
    _metadataRefreshRuns++;
    _refreshingMetadata = false;
    _metadataRefreshLanguage = null;
    _notify();

    // Show the freshly stored titles right away.
    if (updated > 0) await load();

    return result;
  }

  /// Re-fetches one item. Returns `false` when it could not be refreshed —
  /// the stored snapshot then stays untouched.
  Future<bool> _refreshItem(MediaItem item, AppLanguage language) async {
    final tmdbId = int.tryParse(item.externalId ?? '');
    if (tmdbId == null) return false;

    final type = item.kind == MediaKind.series
        ? TmdbMediaType.tv
        : TmdbMediaType.movie;

    try {
      final details = await _tmdbClient.fetchDetails(
        TmdbSearchResult(id: tmdbId, type: type, title: item.title),
        language: language.tmdbCode,
      );
      final title = details.title.trim();
      if (title.isEmpty) return false;

      final isSeries = details is TmdbTvDetails;
      await _repository.updateMetadata(
        item.copyWith(
          title: title,
          originalTitle: _nonEmpty(details.originalTitle),
          releaseYear: details.year,
          overview: _nonEmpty(details.overview),
          posterUrl: details.posterUrl,
          totalSeasons: isSeries
              ? details.numberOfSeasons
              : item.totalSeasons,
          totalEpisodes: isSeries
              ? details.numberOfEpisodes
              : item.totalEpisodes,
        ),
      );
      return true;
    } catch (_) {
      // Single-item failure: keep the old data, keep going.
      return false;
    }
  }

  bool _isTmdbItem(MediaItem item) =>
      item.externalSource == tmdbSource &&
      item.externalId != null &&
      item.externalId!.isNotEmpty;

  /// An empty TMDB field means "no value in this language" — treated as
  /// `null` so [MediaItem.copyWith] keeps the value already stored.
  String? _nonEmpty(String? value) {
    if (value == null || value.trim().isEmpty) return null;
    return value;
  }

  // ───────────────────────────────────────────────────────────────────────────
  // language trigger
  // ───────────────────────────────────────────────────────────────────────────

  void _onSettingsChanged() {
    final language = _settings.language;
    if (language == _language) return;
    _language = language;
    // Fire and forget: the library stays usable while this runs.
    refreshMetadata(language: language);
  }

  void _notify() {
    if (_disposed) return;
    notifyListeners();
  }

  @override
  void dispose() {
    _disposed = true;
    _settings.removeListener(_onSettingsChanged);
    super.dispose();
  }
}
