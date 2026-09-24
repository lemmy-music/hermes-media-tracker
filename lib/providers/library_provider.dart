import 'package:flutter/foundation.dart';

import '../l10n/app_language.dart';
import '../models/media_item.dart';
import '../models/tmdb_result.dart';
import '../repositories/media_repository.dart';
import '../services/tmdb_client.dart';
import 'settings_provider.dart';
import 'tracking_rules.dart';

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
    DateTime Function()? clock,
  }) : // The two fields below are private and their parameter names must stay
       // public, so an initializing formal is impossible here — the lint is a
       // false positive.
       // ignore: prefer_initializing_formals
       _repository = repository,
       // ignore: prefer_initializing_formals
       _tmdbClient = tmdbClient,
       _settings = settings,
       _language = settings.language,
       _clock = clock ?? DateTime.now,
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

  /// Injectable clock — production uses [DateTime.now], tests pin it so the
  /// auto-filled timestamps are deterministic.
  final DateTime Function() _clock;

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
  // tracking (Phase 3a — movies & books)
  // ───────────────────────────────────────────────────────────────────────────

  /// The loaded item with [id], or `null` when it is not (or no longer) in the
  /// list. Backs the live detail view, which must not work on a stale copy.
  MediaItem? itemById(String? id) {
    if (id == null) return null;
    for (final item in _items) {
      if (item.id == id) return item;
    }
    return null;
  }

  /// Changes [item]'s status.
  ///
  /// The columns are computed by [statusChangeFields] — `in_progress` fills a
  /// missing `started_at`, `completed` fills a missing `completed_at` and forces
  /// 100 %, `planned` resets the progress and clears both timestamps. Manually
  /// entered values are never overwritten.
  Future<MediaItem> setStatus(MediaItem item, MediaStatus status) =>
      _applyTracking(item, statusChangeFields(item, status, now: _clock()));

  /// Sets the percent progress of a movie or a book.
  ///
  /// Reaching 100 % also completes the item (unless it was dropped).
  Future<MediaItem> setProgressPercent(MediaItem item, num percent) =>
      _applyTracking(item, progressPercentFields(item, percent, now: _clock()));

  /// Sets the current page of a book with a known page count.
  ///
  /// The percent value is derived and stored alongside it; the last page
  /// completes the item (unless it was dropped).
  Future<MediaItem> setProgressPage(MediaItem item, int page) =>
      _applyTracking(item, progressPageFields(item, page, now: _clock()));

  /// Sets (or clears) the "started on" timestamp manually — Daniel wants to be
  /// able to back-date an entry.
  Future<MediaItem> setStartedAt(MediaItem item, DateTime? value) =>
      _applyTracking(item, startedAtFields(value));

  /// Sets (or clears) the "completed on" timestamp manually.
  Future<MediaItem> setCompletedAt(MediaItem item, DateTime? value) =>
      _applyTracking(item, completedAtFields(value));

  /// Sets (or clears) a book's total page count.
  Future<MediaItem> setTotalPages(MediaItem item, int? value) =>
      _applyTracking(item, totalPagesFields(item, value));

  /// Removes [item] from the library.
  Future<void> deleteItem(MediaItem item) async {
    final id = _requireId(item);
    await _repository.delete(id);
    _items = _items.where((candidate) => candidate.id != id).toList();
    _notify();
  }

  /// Writes [fields], swaps the stored row into the list and notifies — so the
  /// library list and the detail view both reflect the change immediately.
  Future<MediaItem> _applyTracking(
    MediaItem item,
    Map<String, dynamic> fields,
  ) async {
    final updated = await _repository.updateTracking(_requireId(item), fields);
    _replace(updated);
    return updated;
  }

  /// Replaces the stored copy of [item] (matched by id), keeping the list order.
  void _replace(MediaItem item) {
    final id = item.id;
    if (id == null) return;
    final index = _items.indexWhere((candidate) => candidate.id == id);
    if (index == -1) {
      // Not in the list (e.g. loaded elsewhere) — append so it stays visible.
      _items = <MediaItem>[..._items, item];
    } else {
      final next = List<MediaItem>.of(_items)..[index] = item;
      _items = next;
    }
    _notify();
  }

  String _requireId(MediaItem item) {
    final id = item.id;
    if (id == null) {
      throw const MediaRepositoryException('This item has not been saved yet.');
    }
    return id;
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

  Future<MetadataRefreshResult> _runMetadataRefresh(
    AppLanguage language,
  ) async {
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
          totalSeasons: isSeries ? details.numberOfSeasons : item.totalSeasons,
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

  /// A refresh candidate is always a TMDB item.
  ///
  /// Books (`external_source == 'openlibrary'`) are deliberately **excluded**:
  /// OpenLibrary is not a localized metadata API — a work's title does not
  /// vary by language (only its editions do, and the stored snapshot already
  /// holds the fields we show). Re-fetching would add requests without
  /// improving anything, and books must not inflate `total`/`failed`.
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
