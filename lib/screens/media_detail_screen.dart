import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../l10n/app_strings.dart';
import '../models/episode.dart';
import '../models/media_item.dart';
import '../providers/library_provider.dart';
import '../providers/series_rules.dart';
import '../repositories/media_repository.dart';
import '../widgets/media_widgets.dart';

/// Full-page detail **and** tracking view for a library entry.
///
/// Movies and books (Phase 3a) get a percent slider / page input, the four
/// statuses and manually editable start / finish timestamps.
///
/// Series (Phase 3b) are tracked **per episode**: the status and the progress
/// are *derived* from the checked-off episodes (see `series_rules.dart` and
/// [LibraryProvider]), so the manual status selector is replaced by a
/// season selector plus an episode list with watched checkboxes. Episode
/// metadata is loaded lazily from TMDB on the first open.
///
/// The screen never crashes on missing metadata (no cover, description, page
/// count, air date, runtime, still or episode list).
///
/// Every change is persisted immediately (no save button); failures surface as
/// a snack bar.
class MediaDetailScreen extends StatelessWidget {
  const MediaDetailScreen({super.key, required this.item});

  /// The item as the caller knows it. The screen resolves the live copy from
  /// [LibraryProvider] by id so it always reflects the latest state.
  final MediaItem item;

  // Keys used by the widget tests.
  static const Key deleteButtonKey = Key('media-detail-delete');
  static const Key percentSliderKey = Key('media-detail-percent-slider');
  static const Key pageSliderKey = Key('media-detail-page-slider');
  static const Key pageFieldKey = Key('media-detail-page-field');
  static const Key savePageButtonKey = Key('media-detail-save-page');
  static const Key totalPagesFieldKey = Key('media-detail-total-pages');
  static const Key saveTotalPagesButtonKey = Key(
    'media-detail-save-total-pages',
  );
  static const Key editStartedAtKey = Key('media-detail-edit-started');
  static const Key editCompletedAtKey = Key('media-detail-edit-completed');

  // Series (phase 3b) keys.
  static const Key seasonSelectorKey = Key('series-season-selector');
  static const Key markSeasonWatchedKey = Key('series-mark-season');
  static const Key resetSeasonKey = Key('series-reset-season');
  static const Key retryEpisodesKey = Key('series-retry-episodes');
  static const Key refreshEpisodesKey = Key('series-refresh-episodes');

  /// Key of the watched checkbox of `S{season}E{episode}`.
  static Key episodeCheckboxKey(int season, int episode) =>
      Key('series-episode-$season-$episode');

  /// Key of the tappable row of `S{season}E{episode}` (expands the
  /// description — it no longer toggles the watched state).
  static Key episodeTileKey(int season, int episode) =>
      Key('series-episode-tile-$season-$episode');

  /// Key of the expanded description panel of `S{season}E{episode}`.
  static Key episodeDescriptionKey(int season, int episode) =>
      Key('series-episode-description-$season-$episode');

  @override
  Widget build(BuildContext context) {
    final library = context.watch<LibraryProvider>();
    final live = library.itemById(item.id) ?? item;
    final strings = context.strings;

    return Scaffold(
      appBar: AppBar(
        title: Text(strings.kindLabel(live.kind)),
        actions: [
          IconButton(
            key: deleteButtonKey,
            icon: const Icon(Icons.delete_outline),
            tooltip: strings.deleteItem,
            onPressed: () => _confirmDelete(context, live),
          ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.only(bottom: 32),
        children: [
          _Header(item: live),
          const Divider(height: 1),
          if (live.kind == MediaKind.series)
            _SeriesTrackingSection(item: live)
          else
            _TrackingSection(item: live),
        ],
      ),
    );
  }

  /// Asks for confirmation, then removes the item and pops back to the list.
  Future<void> _confirmDelete(BuildContext context, MediaItem item) async {
    final strings = AppStrings.read(context);
    final library = context.read<LibraryProvider>();
    final messenger = ScaffoldMessenger.of(context);
    final navigator = Navigator.of(context);

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text(strings.deleteConfirmTitle),
        content: Text(strings.deleteConfirmMessage(item.title)),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: Text(strings.cancel),
          ),
          FilledButton(
            onPressed: () => Navigator.of(dialogContext).pop(true),
            child: Text(strings.delete),
          ),
        ],
      ),
    );
    if (confirmed != true) return;

    try {
      await library.deleteItem(item);
      messenger.showSnackBar(SnackBar(content: Text(strings.itemDeleted)));
      if (navigator.canPop()) navigator.pop();
    } on MediaRepositoryException catch (error) {
      messenger.showSnackBar(SnackBar(content: Text(error.message)));
    }
  }
}

/// Big cover, title, badges, year / pages, authors and the description.
class _Header extends StatelessWidget {
  const _Header({required this.item});

  final MediaItem item;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final strings = context.strings;
    final year = item.releaseYear;
    final description = item.overview;
    final totalPages = item.totalPages;

    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Center(
            child: PosterThumbnail(
              url: item.posterUrl,
              placeholderIcon: mediaKindIcon(item.kind),
              width: 180,
              height: 270,
              iconSize: 64,
              borderRadius: 14,
            ),
          ),
          const SizedBox(height: 16),
          Text(
            item.title,
            textAlign: TextAlign.center,
            style: theme.textTheme.headlineSmall?.copyWith(
              fontWeight: FontWeight.bold,
            ),
          ),
          const SizedBox(height: 10),
          Wrap(
            alignment: WrapAlignment.center,
            spacing: 8,
            runSpacing: 6,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              PillBadge(
                icon: mediaKindIcon(item.kind),
                label: strings.kindLabel(item.kind),
              ),
              StatusBadge(
                status: item.status,
                label: strings.statusLabel(item.status),
              ),
              if (year != null)
                Text(
                  '$year',
                  style: theme.textTheme.bodyMedium?.copyWith(
                    color: cs.onSurfaceVariant,
                  ),
                ),
              if (item.kind == MediaKind.book && totalPages != null)
                Text(
                  strings.pages(totalPages),
                  style: theme.textTheme.bodyMedium?.copyWith(
                    color: cs.onSurfaceVariant,
                  ),
                ),
            ],
          ),
          if (item.kind == MediaKind.book && item.authors.isNotEmpty) ...[
            const SizedBox(height: 12),
            Text(
              strings.byAuthors(item.authors.join(', ')),
              textAlign: TextAlign.center,
              style: theme.textTheme.bodyMedium?.copyWith(
                color: cs.onSurfaceVariant,
              ),
            ),
          ],
          const SizedBox(height: 16),
          Text(
            description == null || description.isEmpty
                ? strings.noDescription
                : description,
            style: theme.textTheme.bodyMedium,
          ),
        ],
      ),
    );
  }
}

/// Season / episode tracking for a series (Phase 3b).
///
/// Loads the episode metadata lazily on first open, lets the user pick a
/// season and check off episodes; the series status and progress are derived
/// and persisted by [LibraryProvider].
class _SeriesTrackingSection extends StatefulWidget {
  const _SeriesTrackingSection({required this.item});

  final MediaItem item;

  @override
  State<_SeriesTrackingSection> createState() => _SeriesTrackingSectionState();
}

class _SeriesTrackingSectionState extends State<_SeriesTrackingSection> {
  /// The season currently shown. `null` until episodes are loaded — then the
  /// lowest season number wins.
  int? _seasonNumber;

  /// `true` while a mutation is in flight (disables the bulk actions).
  bool _busy = false;

  /// Episodes whose description is currently expanded, keyed by
  /// `"{season}-{episode}"`. Tapping a row toggles one of these — tapping a
  /// row deliberately no longer toggles the *watched* state (that is the
  /// checkbox's job, so the primary action stays unambiguous).
  final Set<String> _expanded = <String>{};

  String _expandedKey(Episode episode) =>
      '${episode.seasonNumber}-${episode.episodeNumber}';

  /// Collapses/expands the description of [episode]. No persistence involved.
  void _toggleExpanded(Episode episode) {
    final key = _expandedKey(episode);
    setState(() {
      if (!_expanded.remove(key)) _expanded.add(key);
    });
  }

  MediaItem get item => widget.item;

  @override
  void initState() {
    super.initState();
    _ensureEpisodes();
  }

  @override
  void didUpdateWidget(covariant _SeriesTrackingSection oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.item.id != item.id) {
      _seasonNumber = null;
      _ensureEpisodes();
    }
  }

  /// Kicks off the lazy load in the next frame (never during build).
  void _ensureEpisodes() {
    final library = context.read<LibraryProvider>();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      library.ensureEpisodes(item);
    });
  }

  Future<void> _run(Future<void> Function() action) async {
    final messenger = ScaffoldMessenger.of(context);
    final strings = AppStrings.read(context);
    setState(() => _busy = true);
    try {
      await action();
    } on MediaRepositoryException catch (error) {
      messenger.showSnackBar(SnackBar(content: Text(error.message)));
    } catch (_) {
      messenger.showSnackBar(
        SnackBar(content: Text(strings.trackingSaveError)),
      );
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _toggleEpisode(Episode episode, bool watched) => _run(
    () => context.read<LibraryProvider>().setEpisodeWatched(
      item,
      episode,
      watched,
    ),
  );

  Future<void> _markSeason(int seasonNumber) async {
    final messenger = ScaffoldMessenger.of(context);
    final strings = AppStrings.read(context);
    await _run(
      () =>
          context.read<LibraryProvider>().markSeasonWatched(item, seasonNumber),
    );
    messenger.showSnackBar(SnackBar(content: Text(strings.seasonWatchedDone)));
  }

  Future<void> _resetSeason(int seasonNumber) async {
    final strings = AppStrings.read(context);
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text(strings.resetSeasonConfirmTitle),
        content: Text(strings.resetSeasonConfirmMessage(seasonNumber)),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: Text(strings.cancel),
          ),
          FilledButton(
            onPressed: () => Navigator.of(dialogContext).pop(true),
            child: Text(strings.resetSeason),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;
    final messenger = ScaffoldMessenger.of(context);
    await _run(
      () => context.read<LibraryProvider>().resetSeason(item, seasonNumber),
    );
    messenger.showSnackBar(SnackBar(content: Text(strings.seasonResetDone)));
  }

  Future<void> _refresh() =>
      _run(() => context.read<LibraryProvider>().refreshEpisodes(item));

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final strings = context.strings;
    final library = context.watch<LibraryProvider>();

    final loading = library.episodesLoading(item.id);
    final error = library.episodesError(item.id);
    final seasons = library.seasonsFor(item.id);
    final allEpisodes = library.episodesFor(item.id);

    // Pick (and keep) a valid season.
    var season = _seasonNumber;
    if (seasons.isNotEmpty && (season == null || !seasons.contains(season))) {
      season = seasons.first;
    }

    return Padding(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  strings.episodesLabel,
                  style: theme.textTheme.titleLarge,
                ),
              ),
              if (seasons.isNotEmpty)
                IconButton(
                  key: MediaDetailScreen.refreshEpisodesKey,
                  tooltip: strings.refreshEpisodes,
                  onPressed: loading ? null : _refresh,
                  icon: const Icon(Icons.sync),
                ),
            ],
          ),
          const SizedBox(height: 4),
          ..._body(
            context,
            loading: loading,
            error: error,
            seasons: seasons,
            season: season,
            allEpisodes: allEpisodes,
          ),
        ],
      ),
    );
  }

  List<Widget> _body(
    BuildContext context, {
    required bool loading,
    required String? error,
    required List<int> seasons,
    required int? season,
    required List<Episode> allEpisodes,
  }) {
    final strings = context.strings;

    // Loading — the spinner is also shown while a retry runs.
    if (loading) {
      final done = context.read<LibraryProvider>().episodesLoadDone(item.id);
      final total = context.read<LibraryProvider>().episodesLoadTotal(item.id);
      return [
        const SizedBox(height: 16),
        const Center(child: CircularProgressIndicator()),
        const SizedBox(height: 12),
        Center(
          child: Text(
            total > 0 ? strings.loadingEpisodesProgress(done, total) : '…',
            style: Theme.of(context).textTheme.bodyMedium,
          ),
        ),
        const SizedBox(height: 16),
      ];
    }

    // A load that produced nothing at all → retry.
    if (error != null && allEpisodes.isEmpty) {
      return [
        CenteredMessage(
          icon: Icons.cloud_off,
          title: strings.episodesLoadErrorTitle,
          message: error,
          scrollable: false,
          action: FilledButton.icon(
            key: MediaDetailScreen.retryEpisodesKey,
            onPressed: _refresh,
            icon: const Icon(Icons.refresh),
            label: Text(strings.retry),
          ),
        ),
      ];
    }

    if (seasons.isEmpty) {
      return [
        CenteredMessage(
          icon: Icons.tv_off_outlined,
          title: strings.noEpisodes,
          message: '',
          scrollable: false,
        ),
      ];
    }

    final selected = season ?? seasons.first;
    final episodes = allEpisodes
        .where((episode) => episode.seasonNumber == selected)
        .toList();
    final watched = allEpisodes.where((episode) => episode.watched).length;

    return [
      const SizedBox(height: 8),
      _progress(context, watched, allEpisodes.length),
      const SizedBox(height: 16),
      _seasonSelector(seasons, selected),
      const SizedBox(height: 12),
      _bulkActions(selected),
      const SizedBox(height: 8),
      for (final episode in episodes) _episodeTile(context, episode),
    ];
  }

  /// Derived progress summary (bar + "watched of total").
  Widget _progress(BuildContext context, int watched, int total) {
    final theme = Theme.of(context);
    final strings = context.strings;
    final percent = seriesProgressPercent(watched, total);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            Expanded(
              child: Text(strings.progress, style: theme.textTheme.titleMedium),
            ),
            Text(
              strings.percentValue(percent.round()),
              style: theme.textTheme.titleMedium?.copyWith(
                fontWeight: FontWeight.bold,
              ),
            ),
          ],
        ),
        const SizedBox(height: 8),
        LinearProgressIndicator(
          value: percent / 100,
          minHeight: 6,
          borderRadius: BorderRadius.circular(3),
        ),
        const SizedBox(height: 6),
        Text(
          strings.episodesProgressLabel(watched, total),
          style: theme.textTheme.bodySmall?.copyWith(
            color: theme.colorScheme.onSurfaceVariant,
          ),
        ),
      ],
    );
  }

  /// Horizontal, scrollable season chips (mobile friendly).
  Widget _seasonSelector(List<int> seasons, int selected) {
    final strings = context.strings;
    return SingleChildScrollView(
      key: MediaDetailScreen.seasonSelectorKey,
      scrollDirection: Axis.horizontal,
      child: Row(
        children: [
          for (final number in seasons) ...[
            ChoiceChip(
              label: Text(strings.seasonNumberLabel(number)),
              selected: number == selected,
              onSelected: (_) => setState(() => _seasonNumber = number),
            ),
            const SizedBox(width: 8),
          ],
        ],
      ),
    );
  }

  Widget _bulkActions(int seasonNumber) {
    final strings = context.strings;
    return Wrap(
      spacing: 8,
      runSpacing: 8,
      children: [
        OutlinedButton.icon(
          key: MediaDetailScreen.markSeasonWatchedKey,
          onPressed: _busy ? null : () => _markSeason(seasonNumber),
          icon: const Icon(Icons.done_all),
          label: Text(strings.markSeasonWatched),
        ),
        OutlinedButton.icon(
          key: MediaDetailScreen.resetSeasonKey,
          onPressed: _busy ? null : () => _resetSeason(seasonNumber),
          icon: const Icon(Icons.restart_alt),
          label: Text(strings.resetSeason),
        ),
      ],
    );
  }

  /// One episode: watched checkbox, number + title, air date / runtime and an
  /// optional still thumbnail.
  ///
  /// Interaction is split on purpose: the **checkbox** toggles the watched
  /// state (the primary action, unchanged), while tapping the **row** expands
  /// or collapses the episode description (which used to toggle watched).
  Widget _episodeTile(BuildContext context, Episode episode) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final strings = context.strings;
    final name = episode.name?.trim();
    final title = (name == null || name.isEmpty)
        ? strings.episodeNumber(episode.episodeNumber)
        : '${strings.episodeNumber(episode.episodeNumber)} · $name';

    final details = <String>[
      if (episode.airDate != null)
        '${strings.airedOn} '
            '${MaterialLocalizations.of(context).formatMediumDate(episode.airDate!.toLocal())}',
      if (episode.runtime != null) '${episode.runtime} ${strings.minutes}',
    ];

    final expanded = _expanded.contains(_expandedKey(episode));
    final hasStill = episode.stillUrl != null && episode.stillUrl!.isNotEmpty;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Primary action: the checkbox toggles the watched state. It sits
            // *outside* the tappable row so the two gestures never overlap.
            Checkbox(
              key: MediaDetailScreen.episodeCheckboxKey(
                episode.seasonNumber,
                episode.episodeNumber,
              ),
              value: episode.watched,
              onChanged: _busy
                  ? null
                  : (value) => _toggleEpisode(episode, value ?? false),
            ),
            Expanded(
              child: InkWell(
                key: MediaDetailScreen.episodeTileKey(
                  episode.seasonNumber,
                  episode.episodeNumber,
                ),
                borderRadius: BorderRadius.circular(8),
                onTap: () => _toggleExpanded(episode),
                child: Padding(
                  padding: const EdgeInsets.symmetric(
                    vertical: 8,
                    horizontal: 4,
                  ),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      if (hasStill) ...[
                        PosterThumbnail(
                          url: episode.stillUrl,
                          placeholderIcon: Icons.movie_outlined,
                          width: 72,
                          height: 44,
                          iconSize: 20,
                          borderRadius: 6,
                        ),
                        const SizedBox(width: 10),
                      ],
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              title,
                              style: theme.textTheme.bodyLarge?.copyWith(
                                fontWeight: episode.watched
                                    ? FontWeight.w400
                                    : FontWeight.w500,
                                color: episode.watched
                                    ? cs.onSurfaceVariant
                                    : null,
                              ),
                            ),
                            if (details.isNotEmpty) ...[
                              const SizedBox(height: 2),
                              Text(
                                details.join(' · '),
                                style: theme.textTheme.bodySmall?.copyWith(
                                  color: cs.onSurfaceVariant,
                                ),
                              ),
                            ],
                          ],
                        ),
                      ),
                      Icon(
                        expanded ? Icons.expand_less : Icons.expand_more,
                        color: cs.onSurfaceVariant,
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ],
        ),
        // The description collapses away entirely (not just fades out) so it
        // is absent from the tree while hidden.
        AnimatedSize(
          duration: const Duration(milliseconds: 200),
          curve: Curves.easeInOut,
          alignment: Alignment.topCenter,
          child: expanded
              ? _episodeDescription(context, episode)
              : const SizedBox(width: double.infinity, height: 0),
        ),
      ],
    );
  }

  /// Expanded panel of an episode: a larger still (when available) plus the
  /// full description, or the localized fallback when there is none.
  Widget _episodeDescription(BuildContext context, Episode episode) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final strings = context.strings;
    final description = episode.overview?.trim();
    final hasDescription = description != null && description.isNotEmpty;
    final hasStill = episode.stillUrl != null && episode.stillUrl!.isNotEmpty;

    return Padding(
      key: MediaDetailScreen.episodeDescriptionKey(
        episode.seasonNumber,
        episode.episodeNumber,
      ),
      padding: const EdgeInsets.only(left: 4, right: 4, top: 8, bottom: 12),
      child: Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: cs.surfaceContainerHighest,
          borderRadius: BorderRadius.circular(10),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            if (hasStill) ...[
              Center(
                child: PosterThumbnail(
                  url: episode.stillUrl,
                  placeholderIcon: Icons.movie_outlined,
                  width: 240,
                  height: 135,
                  iconSize: 40,
                  borderRadius: 10,
                ),
              ),
              const SizedBox(height: 12),
            ],
            // Long synopses wrap fully; the surrounding list provides the
            // scrolling, so the text is never clipped.
            Text(
              hasDescription ? description : strings.noEpisodeDescription,
              style: theme.textTheme.bodyMedium?.copyWith(
                color: hasDescription ? null : cs.onSurfaceVariant,
                fontStyle: hasDescription ? null : FontStyle.italic,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Status, progress and timestamps of a movie or a book.
class _TrackingSection extends StatefulWidget {
  const _TrackingSection({required this.item});

  final MediaItem item;

  @override
  State<_TrackingSection> createState() => _TrackingSectionState();
}

class _TrackingSectionState extends State<_TrackingSection> {
  /// Draft value of the percent slider while the user drags it. `null` means
  /// "use the stored value".
  double? _percentDraft;

  /// Draft value of the page slider while the user drags it.
  double? _pageDraft;

  final TextEditingController _pageController = TextEditingController();
  final TextEditingController _totalPagesController = TextEditingController();
  final FocusNode _pageFocus = FocusNode();
  final FocusNode _totalPagesFocus = FocusNode();

  MediaItem get item => widget.item;

  @override
  void initState() {
    super.initState();
    _syncControllers();
  }

  @override
  void didUpdateWidget(covariant _TrackingSection oldWidget) {
    super.didUpdateWidget(oldWidget);
    _syncControllers();
  }

  /// Keeps the text fields in sync with the stored values — but never while the
  /// user is typing in them.
  void _syncControllers() {
    if (!_pageFocus.hasFocus) {
      _pageController.text = _pageText();
    }
    if (!_totalPagesFocus.hasFocus) {
      final total = item.totalPages;
      _totalPagesController.text = total == null ? '' : '$total';
    }
  }

  String _pageText() {
    final current = item.progressCurrent;
    return current == null ? '' : '$current';
  }

  @override
  void dispose() {
    _pageController.dispose();
    _totalPagesController.dispose();
    _pageFocus.dispose();
    _totalPagesFocus.dispose();
    super.dispose();
  }

  // ── mutations ──────────────────────────────────────────────────────────────

  /// Runs a persistence action, surfacing any failure as a snack bar.
  Future<void> _run(Future<void> Function() action) async {
    final messenger = ScaffoldMessenger.of(context);
    final strings = AppStrings.read(context);
    try {
      await action();
    } on MediaRepositoryException catch (error) {
      messenger.showSnackBar(SnackBar(content: Text(error.message)));
    } catch (_) {
      messenger.showSnackBar(
        SnackBar(content: Text(strings.trackingSaveError)),
      );
    }
  }

  Future<void> _setStatus(MediaStatus status) {
    if (status == item.status) return Future<void>.value();
    return _run(() => context.read<LibraryProvider>().setStatus(item, status));
  }

  Future<void> _savePercent(double percent) => _run(
    () => context.read<LibraryProvider>().setProgressPercent(item, percent),
  );

  Future<void> _savePage(int? page) async {
    if (page == null || page < 0) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(AppStrings.read(context).invalidPage)),
      );
      return;
    }
    await _run(
      () => context.read<LibraryProvider>().setProgressPage(item, page),
    );
  }

  Future<void> _saveTotalPages(String raw) async {
    final trimmed = raw.trim();
    if (trimmed.isEmpty) {
      await _run(
        () => context.read<LibraryProvider>().setTotalPages(item, null),
      );
      return;
    }
    final value = int.tryParse(trimmed);
    if (value == null || value <= 0) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(AppStrings.read(context).invalidPage)),
      );
      return;
    }
    await _run(
      () => context.read<LibraryProvider>().setTotalPages(item, value),
    );
  }

  Future<void> _editTimestamp(
    DateTime? initial,
    Future<void> Function(DateTime?) apply,
  ) async {
    final picked = await _pickDateTime(context, initial);
    if (picked == null || !mounted) return;
    await apply(picked);
  }

  /// Date **and** time so a back-dated entry can carry the actual moment.
  Future<DateTime?> _pickDateTime(
    BuildContext context,
    DateTime? initial,
  ) async {
    final now = DateTime.now();
    final date = await showDatePicker(
      context: context,
      initialDate: initial ?? now,
      firstDate: DateTime(1900),
      lastDate: DateTime(now.year + 1, 12, 31),
    );
    if (date == null || !context.mounted) return null;
    final time = await showTimePicker(
      context: context,
      initialTime: initial == null
          ? TimeOfDay.now()
          : TimeOfDay.fromDateTime(initial.toLocal()),
    );
    if (time == null) return null;
    return DateTime(date.year, date.month, date.day, time.hour, time.minute);
  }

  String _formatDateTime(BuildContext context, DateTime value) {
    final local = value.toLocal();
    final localizations = MaterialLocalizations.of(context);
    final date = localizations.formatMediumDate(local);
    final time = localizations.formatTimeOfDay(TimeOfDay.fromDateTime(local));
    return '$date, $time';
  }

  // ── build ──────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final strings = context.strings;

    return Padding(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(strings.trackingSection, style: theme.textTheme.titleLarge),
          const SizedBox(height: 12),
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: SegmentedButton<MediaStatus>(
              segments: [
                for (final status in MediaStatus.values)
                  ButtonSegment<MediaStatus>(
                    value: status,
                    label: Text(strings.statusLabel(status)),
                  ),
              ],
              selected: <MediaStatus>{item.status},
              showSelectedIcon: false,
              onSelectionChanged: (selection) => _setStatus(selection.first),
            ),
          ),
          const SizedBox(height: 20),
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: _progressCard(context),
              ),
            ),
          ),
          if (item.kind == MediaKind.book) ...[
            const SizedBox(height: 12),
            _totalPagesRow(context),
          ],
          const SizedBox(height: 20),
          Text(
            strings.startedAt,
            style: theme.textTheme.labelMedium?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
          _timestampRow(
            context,
            value: item.startedAt,
            editKey: MediaDetailScreen.editStartedAtKey,
            apply: (value) => _run(
              () => context.read<LibraryProvider>().setStartedAt(item, value),
            ),
          ),
          const SizedBox(height: 12),
          Text(
            strings.completedAt,
            style: theme.textTheme.labelMedium?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
          _timestampRow(
            context,
            value: item.completedAt,
            editKey: MediaDetailScreen.editCompletedAtKey,
            apply: (value) => _run(
              () => context.read<LibraryProvider>().setCompletedAt(item, value),
            ),
          ),
        ],
      ),
    );
  }

  /// Header row (percent readout), the bar and the kind-specific control.
  List<Widget> _progressCard(BuildContext context) {
    final theme = Theme.of(context);
    final strings = context.strings;
    final percent = _percentDraft ?? (item.progressPercent ?? 0).toDouble();
    final clamped = percent.clamp(0, 100).toDouble();

    return [
      Row(
        children: [
          Expanded(
            child: Text(strings.progress, style: theme.textTheme.titleMedium),
          ),
          Text(
            strings.percentValue(clamped.round()),
            style: theme.textTheme.titleMedium?.copyWith(
              fontWeight: FontWeight.bold,
            ),
          ),
        ],
      ),
      const SizedBox(height: 8),
      LinearProgressIndicator(
        value: clamped / 100,
        minHeight: 6,
        borderRadius: BorderRadius.circular(3),
      ),
      const SizedBox(height: 8),
      ..._progressControls(context),
    ];
  }

  List<Widget> _progressControls(BuildContext context) {
    final total = item.totalPages;
    final hasPageCount =
        item.kind == MediaKind.book && total != null && total > 0;
    if (!hasPageCount) return [_percentSlider(context)];
    return [_pageSlider(context, total), _pageInputRow(context, total)];
  }

  /// Percent slider — movies, and books without a known page count.
  Widget _percentSlider(BuildContext context) {
    final strings = context.strings;
    final value = (_percentDraft ?? (item.progressPercent ?? 0).toDouble())
        .clamp(0, 100)
        .toDouble();
    return Slider(
      key: MediaDetailScreen.percentSliderKey,
      value: value,
      max: 100,
      divisions: 100,
      label: strings.percentValue(value.round()),
      onChanged: (next) => setState(() => _percentDraft = next),
      onChangeEnd: (next) {
        setState(() => _percentDraft = null);
        _savePercent(next);
      },
    );
  }

  /// Page slider — books with a known page count.
  Widget _pageSlider(BuildContext context, int total) {
    final strings = context.strings;
    final value = (_pageDraft ?? (item.progressCurrent ?? 0).toDouble())
        .clamp(0, total.toDouble())
        .toDouble();
    return Slider(
      key: MediaDetailScreen.pageSliderKey,
      value: value,
      max: total.toDouble(),
      divisions: total <= 200 ? total : null,
      label: strings.pageOf(value.round(), total),
      onChanged: (next) => setState(() => _pageDraft = next),
      onChangeEnd: (next) {
        setState(() => _pageDraft = null);
        _savePage(next.round());
      },
    );
  }

  Widget _pageInputRow(BuildContext context, int total) {
    final strings = context.strings;
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Expanded(
          child: TextField(
            key: MediaDetailScreen.pageFieldKey,
            controller: _pageController,
            focusNode: _pageFocus,
            keyboardType: TextInputType.number,
            decoration: InputDecoration(
              labelText: strings.currentPage,
              helperText: strings.pageOf(item.progressCurrent ?? 0, total),
              border: const OutlineInputBorder(),
              isDense: true,
            ),
            onSubmitted: (value) => _savePage(int.tryParse(value.trim())),
          ),
        ),
        const SizedBox(width: 8),
        IconButton(
          key: MediaDetailScreen.savePageButtonKey,
          tooltip: strings.savePage,
          onPressed: () => _savePage(int.tryParse(_pageController.text.trim())),
          icon: const Icon(Icons.check),
        ),
      ],
    );
  }

  /// Editable total page count — lets the user fix a missing OpenLibrary value.
  Widget _totalPagesRow(BuildContext context) {
    final strings = context.strings;
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Expanded(
          child: TextField(
            key: MediaDetailScreen.totalPagesFieldKey,
            controller: _totalPagesController,
            focusNode: _totalPagesFocus,
            keyboardType: TextInputType.number,
            decoration: InputDecoration(
              labelText: strings.totalPages,
              border: const OutlineInputBorder(),
              isDense: true,
            ),
            onSubmitted: _saveTotalPages,
          ),
        ),
        const SizedBox(width: 8),
        IconButton(
          key: MediaDetailScreen.saveTotalPagesButtonKey,
          tooltip: strings.totalPages,
          onPressed: () => _saveTotalPages(_totalPagesController.text),
          icon: const Icon(Icons.check),
        ),
      ],
    );
  }

  /// One timestamp with edit and (when set) clear actions.
  Widget _timestampRow(
    BuildContext context, {
    required DateTime? value,
    required Key editKey,
    required Future<void> Function(DateTime?) apply,
  }) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final strings = context.strings;
    return Row(
      children: [
        Expanded(
          child: Text(
            value == null ? strings.notSet : _formatDateTime(context, value),
            style: theme.textTheme.bodyLarge?.copyWith(
              color: value == null ? cs.onSurfaceVariant : null,
            ),
          ),
        ),
        IconButton(
          key: editKey,
          icon: const Icon(Icons.edit_calendar_outlined),
          tooltip: strings.pickDate,
          onPressed: () => _editTimestamp(value, apply),
        ),
        if (value != null)
          IconButton(
            icon: const Icon(Icons.clear),
            tooltip: strings.clearDate,
            onPressed: () => apply(null),
          ),
      ],
    );
  }
}
