import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../l10n/app_strings.dart';
import '../models/book_result.dart';
import '../models/media_item.dart';
import '../models/tmdb_result.dart';
import '../providers/library_provider.dart';
import '../providers/settings_provider.dart';
import '../repositories/media_repository.dart';
import '../screens/media_detail_screen.dart';
import '../services/openlibrary_client.dart';
import '../services/tmdb_client.dart';
import 'media_widgets.dart';

/// Bottom-sheet preview of a TMDB search hit with an "Add to library" action.
///
/// On open it loads the full TMDB details (runtime / season counts) and checks
/// whether the item is already tracked. Adding is guarded twice: the
/// pre-flight library check and the DB unique index on
/// `(external_source, external_id)`.
class TmdbDetailSheet extends StatefulWidget {
  const TmdbDetailSheet({super.key, required this.result});

  final TmdbSearchResult result;

  @override
  State<TmdbDetailSheet> createState() => _TmdbDetailSheetState();
}

class _TmdbDetailSheetState extends State<TmdbDetailSheet> {
  TmdbDetails? _details;
  bool _loading = true;
  bool _watchlistBusy = false;
  bool _watchedBusy = false;
  bool _added = false;

  /// Status of the already-tracked entry (when [_added] came from the library),
  /// so the sheet can say "Already watched" for a completed title.
  MediaStatus? _addedStatus;

  /// The row stored by this sheet's own add (watchlist / watched) — the target
  /// of the in-sheet "Open" offer. `null` while the sheet only mirrors a
  /// *pre-existing* library entry, so no "Open" is offered then.
  MediaItem? _addedItem;

  /// Non-fatal notice shown inside the "added" state (e.g. a series whose
  /// episodes could not be loaded, so it stayed in the watchlist). `null` when
  /// there is nothing to report.
  String? _notice;
  String? _error;

  bool get _busy => _watchlistBusy || _watchedBusy;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final client = context.read<TmdbClient>();
    final repository = context.read<MediaRepository>();
    final language = context.read<SettingsProvider>().tmdbLanguage;

    setState(() {
      _loading = true;
      _error = null;
    });

    try {
      final details = await client.fetchDetails(
        widget.result,
        language: language,
      );
      bool alreadyTracked = false;
      MediaStatus? existingStatus;
      try {
        final existing = await repository.findByExternal(
          kExternalSourceTmdb,
          widget.result.externalId,
        );
        alreadyTracked = existing != null;
        existingStatus = existing?.status;
      } on MediaRepositoryException {
        // Non-fatal: the insert's unique-index guard still protects us.
      }
      if (!mounted) return;
      setState(() {
        _details = details;
        _added = alreadyTracked;
        _addedStatus = existingStatus;
        _loading = false;
      });
    } on TmdbException catch (error) {
      if (!mounted) return;
      setState(() {
        _error = error.message;
        _loading = false;
      });
    }
  }

  /// Adds the hit to the watchlist (`planned`) — the classic "add".
  Future<void> _addToWatchlist() async {
    final details = _details;
    if (details == null || _busy) return;

    // Captured **before** the async gap: the messenger outlives this sheet, so
    // a failure can still be reported if the sheet was dismissed meanwhile.
    final messenger = ScaffoldMessenger.of(context);
    final repository = context.read<MediaRepository>();
    final library = context.read<LibraryProvider>();
    final strings = AppStrings.read(context);

    setState(() => _watchlistBusy = true);
    try {
      final inserted = await repository.insert(details.toMediaItem());
      // Instant, network-free visibility: adopt the stored row so the library
      // list, the tile counts and the search badge update right away.
      library.adoptInserted(inserted);
      if (!mounted) return;
      setState(() {
        _added = true;
        _addedStatus = MediaStatus.planned;
        _addedItem = inserted;
        _notice = null;
        _watchlistBusy = false;
      });
      // The sheet deliberately stays open and now offers "Open" right in the
      // visible state — no snack bar (it would sit behind the sheet's modal
      // barrier, invisible and un-tappable).
    } on MediaRepositoryException catch (error) {
      _handleAddFailure(error, messenger, strings, () {
        _added = isAlreadyInLibraryError(error);
        _watchlistBusy = false;
      });
    }
  }

  /// Adds the hit **directly as watched** (movie → `completed`; series → all
  /// episodes marked watched through the lazy loader + episode automation).
  Future<void> _addAsWatched() async {
    final details = _details;
    if (details == null || _busy) return;

    final messenger = ScaffoldMessenger.of(context);
    final repository = context.read<MediaRepository>();
    final library = context.read<LibraryProvider>();
    final strings = AppStrings.read(context);

    setState(() => _watchedBusy = true);
    try {
      // [insertAsWatched] adopts the stored row and runs the normal automation
      // (series: derived status/progress), so the returned item is the final
      // state — no reload needed.
      final outcome = await insertAsWatched(
        repository,
        library,
        details.toMediaItem(),
      );
      final done = outcome.result == AddAsWatchedResult.done;
      if (!mounted) return;
      setState(() {
        _added = true;
        _addedStatus = done ? MediaStatus.completed : MediaStatus.planned;
        _addedItem = outcome.item;
        _notice = done ? null : strings.addAsWatchedEpisodesError;
        _watchedBusy = false;
      });
      // See [_addToWatchlist]: the offer lives in the sheet, not a snack bar.
    } on MediaRepositoryException catch (error) {
      _handleAddFailure(error, messenger, strings, () {
        _added = isAlreadyInLibraryError(error);
        _watchedBusy = false;
      });
    }
  }

  /// Opens the just-added item's detail view: a **controlled close** of this
  /// sheet (only while it is still the top route), then the push — so the
  /// sheet is gone before the detail view appears.
  ///
  /// The app-level [Navigator] is captured *before* the pop, so the push never
  /// touches a disposed `BuildContext`.
  void _openAddedItem() {
    final item = _addedItem;
    if (item == null) return;
    final navigator = Navigator.of(context);
    if (mounted && ModalRoute.of(context)?.isCurrent == true) {
      navigator.pop();
    }
    navigator.push(
      MaterialPageRoute<void>(builder: (_) => MediaDetailScreen(item: item)),
    );
  }

  /// Shared failure handling of both add actions: a duplicate flips the sheet
  /// into the "already in your library" state, anything else is shown as-is.
  void _handleAddFailure(
    MediaRepositoryException error,
    ScaffoldMessengerState messenger,
    AppStrings strings,
    void Function() applyState,
  ) {
    final alreadyInLibrary = isAlreadyInLibraryError(error);
    // A duplicate leaves the tracked status unknown to this sheet → the generic
    // "already in your library" wording.
    if (alreadyInLibrary) _addedStatus = null;
    if (mounted) setState(applyState);
    messenger.showSnackBar(
      SnackBar(
        content: Text(
          alreadyInLibrary ? strings.alreadyInLibrary : error.message,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final strings = context.strings;
    final details = _details;
    final result = widget.result;

    final posterPath = details?.posterPath ?? result.posterPath;
    final title = details?.title ?? result.title;
    final year = details?.year ?? result.year;
    final overview = details?.overview ?? result.overview;

    return _SheetFrame(
      poster: PosterThumbnail(
        url: TmdbImages.poster(posterPath, size: 'w500'),
        placeholderIcon: tmdbTypeIcon(result.type),
        width: 168,
        height: 252,
        iconSize: 56,
        borderRadius: 14,
      ),
      title: title,
      badges: <Widget>[
        PillBadge(
          icon: tmdbTypeIcon(result.type),
          label: strings.typeLabel(result.type),
        ),
        if (year != null) Text('$year', style: theme.textTheme.bodyMedium),
        ..._detailsMeta(context, details),
      ],
      body: overview != null && overview.isNotEmpty
          ? Text(overview, style: theme.textTheme.bodyMedium)
          : null,
      actions: _buildActions(context, cs),
    );
  }

  /// Extra detail chips (runtime for movies, seasons/episodes for series).
  List<Widget> _detailsMeta(BuildContext context, TmdbDetails? details) {
    final strings = context.strings;
    final style = Theme.of(context).textTheme.bodyMedium;
    if (details is TmdbMovieDetails && details.runtime != null) {
      return [Text('${details.runtime} ${strings.minutes}', style: style)];
    }
    if (details is TmdbTvDetails) {
      final chips = <Widget>[];
      final seasons = details.numberOfSeasons;
      final episodes = details.numberOfEpisodes;
      if (seasons != null) {
        chips.add(Text(strings.seasons(seasons), style: style));
      }
      if (episodes != null) {
        chips.add(Text(strings.episodes(episodes), style: style));
      }
      return chips;
    }
    return const <Widget>[];
  }

  Widget _buildActions(BuildContext context, ColorScheme cs) {
    final strings = context.strings;
    if (_loading) {
      return const Center(
        child: Padding(
          padding: EdgeInsets.all(8),
          child: CircularProgressIndicator(),
        ),
      );
    }

    final error = _error;
    if (error != null) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            error,
            style: Theme.of(
              context,
            ).textTheme.bodyMedium?.copyWith(color: cs.error),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 12),
          FilledButton.icon(
            onPressed: _load,
            icon: const Icon(Icons.refresh),
            label: Text(strings.retry),
          ),
        ],
      );
    }

    return _AddActions(
      added: _added,
      completed: _addedStatus == MediaStatus.completed,
      watchlistBusy: _watchlistBusy,
      watchedBusy: _watchedBusy,
      onWatchlist: _addToWatchlist,
      onWatched: _addAsWatched,
      onOpen: _addedItem == null ? null : _openAddedItem,
      notice: _notice,
    );
  }
}

/// Bottom-sheet preview of an OpenLibrary book with "Add to library".
///
/// Loads the work details (description) and pre-checks the library for a
/// duplicate `openlibrary` / work-key pair. Failure to load the description is
/// surfaced with a retry instead of blocking the sheet.
class BookDetailSheet extends StatefulWidget {
  const BookDetailSheet({super.key, required this.result});

  final BookResult result;

  @override
  State<BookDetailSheet> createState() => _BookDetailSheetState();
}

class _BookDetailSheetState extends State<BookDetailSheet> {
  BookDetails? _details;
  bool _loading = true;
  bool _watchlistBusy = false;
  bool _watchedBusy = false;
  bool _added = false;

  /// Status of the already-tracked entry (when [_added] came from the library),
  /// so the sheet can say "Already watched" for a completed title.
  MediaStatus? _addedStatus;

  /// The row stored by this sheet's own add (watchlist / watched) — the target
  /// of the in-sheet "Open" offer. `null` while the sheet only mirrors a
  /// *pre-existing* library entry, so no "Open" is offered then.
  MediaItem? _addedItem;

  /// Non-fatal notice shown inside the "added" state (e.g. a series whose
  /// episodes could not be loaded, so it stayed in the watchlist). `null` when
  /// there is nothing to report.
  String? _notice;
  String? _error;

  bool get _busy => _watchlistBusy || _watchedBusy;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final client = context.read<OpenLibraryClient>();
    final repository = context.read<MediaRepository>();

    setState(() {
      _loading = true;
      _error = null;
    });

    try {
      final details = await client.fetchDetails(widget.result.key);
      bool alreadyTracked = false;
      MediaStatus? existingStatus;
      try {
        final existing = await repository.findByExternal(
          kExternalSourceOpenLibrary,
          widget.result.key,
        );
        alreadyTracked = existing != null;
        existingStatus = existing?.status;
      } on MediaRepositoryException {
        // Non-fatal: the insert's unique-index guard still protects us.
      }
      if (!mounted) return;
      setState(() {
        _details = details;
        _added = alreadyTracked;
        _addedStatus = existingStatus;
        _loading = false;
      });
    } on OpenLibraryException catch (error) {
      if (!mounted) return;
      setState(() {
        _error = error.message;
        _loading = false;
      });
    }
  }

  /// Builds the [MediaItem] for this book from the (lazily loaded) details.
  MediaItem _buildItem(BookDetails details) => widget.result.toMediaItem(
    description: details.description,
    totalPages: details.pageCount,
    isbn: details.isbn,
    coverUrl: details.coverUrl,
    releaseYear: details.firstPublishYear,
  );

  /// Adds the book to the watchlist (`planned`) — the classic "add".
  Future<void> _addToWatchlist() async {
    final details = _details;
    if (details == null || _busy) return;

    // Captured before the async gap so a failure can still be reported if the
    // sheet was dismissed meanwhile.
    final messenger = ScaffoldMessenger.of(context);
    final repository = context.read<MediaRepository>();
    final library = context.read<LibraryProvider>();
    final strings = AppStrings.read(context);

    setState(() => _watchlistBusy = true);
    try {
      final inserted = await repository.insert(_buildItem(details));
      // Instant, network-free visibility: adopt the stored row so the library
      // list, the tile counts and the search badge update right away.
      library.adoptInserted(inserted);
      if (!mounted) return;
      setState(() {
        _added = true;
        _addedStatus = MediaStatus.planned;
        _addedItem = inserted;
        _notice = null;
        _watchlistBusy = false;
      });
      // The sheet deliberately stays open and now offers "Open" right in the
      // visible state — no snack bar (it would sit behind the sheet's modal
      // barrier, invisible and un-tappable).
    } on MediaRepositoryException catch (error) {
      _handleAddFailure(error, messenger, strings, () {
        _added = isAlreadyInLibraryError(error);
        _watchlistBusy = false;
      });
    }
  }

  /// Adds the book **directly as read** (`completed`). When the page count is
  /// known, the full page jump is logged through the reading-log funnel.
  Future<void> _addAsWatched() async {
    final details = _details;
    if (details == null || _busy) return;

    final messenger = ScaffoldMessenger.of(context);
    final repository = context.read<MediaRepository>();
    final library = context.read<LibraryProvider>();
    final strings = AppStrings.read(context);

    setState(() => _watchedBusy = true);
    try {
      // [insertAsWatched] adopts the stored row and completes it through the
      // normal automation, so the returned item is the final state.
      final outcome = await insertAsWatched(
        repository,
        library,
        _buildItem(details),
      );
      final done = outcome.result == AddAsWatchedResult.done;
      if (!mounted) return;
      setState(() {
        _added = true;
        _addedStatus = done ? MediaStatus.completed : MediaStatus.planned;
        _addedItem = outcome.item;
        _notice = done ? null : strings.addAsWatchedEpisodesError;
        _watchedBusy = false;
      });
      // See [_addToWatchlist]: the offer lives in the sheet, not a snack bar.
    } on MediaRepositoryException catch (error) {
      _handleAddFailure(error, messenger, strings, () {
        _added = isAlreadyInLibraryError(error);
        _watchedBusy = false;
      });
    }
  }

  /// Opens the just-added item's detail view: a **controlled close** of this
  /// sheet (only while it is still the top route), then the push — so the
  /// sheet is gone before the detail view appears.
  ///
  /// The app-level [Navigator] is captured *before* the pop, so the push never
  /// touches a disposed `BuildContext`.
  void _openAddedItem() {
    final item = _addedItem;
    if (item == null) return;
    final navigator = Navigator.of(context);
    if (mounted && ModalRoute.of(context)?.isCurrent == true) {
      navigator.pop();
    }
    navigator.push(
      MaterialPageRoute<void>(builder: (_) => MediaDetailScreen(item: item)),
    );
  }

  /// Shared failure handling of both add actions: a duplicate flips the sheet
  /// into the "already in your library" state, anything else is shown as-is.
  void _handleAddFailure(
    MediaRepositoryException error,
    ScaffoldMessengerState messenger,
    AppStrings strings,
    void Function() applyState,
  ) {
    final alreadyInLibrary = isAlreadyInLibraryError(error);
    // A duplicate leaves the tracked status unknown to this sheet → the generic
    // "already in your library" wording.
    if (alreadyInLibrary) _addedStatus = null;
    if (mounted) setState(applyState);
    messenger.showSnackBar(
      SnackBar(
        content: Text(
          alreadyInLibrary ? strings.alreadyInLibrary : error.message,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final strings = context.strings;
    final result = widget.result;
    final details = _details;

    final year = details?.firstPublishYear ?? result.firstPublishYear;
    final pages = details?.pageCount ?? result.pageCount;
    final description = details?.description;
    final authors = result.authors;

    return _SheetFrame(
      poster: PosterThumbnail(
        url:
            details?.coverLargeUrl ??
            result.coverLargeUrl ??
            OpenLibraryImages.coverByIsbn(
              result.isbn,
              size: OpenLibraryImages.detailSize,
            ),
        placeholderIcon: Icons.menu_book_outlined,
        width: 168,
        height: 252,
        iconSize: 56,
        borderRadius: 14,
      ),
      title: result.title,
      badges: <Widget>[
        PillBadge(
          icon: Icons.menu_book_outlined,
          label: strings.kindLabel(MediaKind.book),
        ),
        if (year != null) Text('$year', style: theme.textTheme.bodyMedium),
        if (pages != null)
          Text(strings.pages(pages), style: theme.textTheme.bodyMedium),
      ],
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (authors.isNotEmpty) ...[
            Text(
              strings.byAuthors(authors.join(', ')),
              style: theme.textTheme.bodyMedium?.copyWith(
                color: cs.onSurfaceVariant,
              ),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 12),
          ],
          Text(
            description ?? strings.bookNoDescription,
            style: theme.textTheme.bodyMedium,
          ),
        ],
      ),
      actions: _buildActions(context, cs),
    );
  }

  Widget _buildActions(BuildContext context, ColorScheme cs) {
    final strings = context.strings;
    if (_loading) {
      return const Center(
        child: Padding(
          padding: EdgeInsets.all(8),
          child: CircularProgressIndicator(),
        ),
      );
    }

    final error = _error;
    if (error != null) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            error,
            style: Theme.of(
              context,
            ).textTheme.bodyMedium?.copyWith(color: cs.error),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 12),
          FilledButton.icon(
            onPressed: _load,
            icon: const Icon(Icons.refresh),
            label: Text(strings.retry),
          ),
        ],
      );
    }

    return _AddActions(
      added: _added,
      completed: _addedStatus == MediaStatus.completed,
      watchlistBusy: _watchlistBusy,
      watchedBusy: _watchedBusy,
      onWatchlist: _addToWatchlist,
      onWatched: _addAsWatched,
      onOpen: _addedItem == null ? null : _openAddedItem,
      notice: _notice,
    );
  }
}

/// Shared layout of both detail sheets: centered poster, title, badge row,
/// body and the action area.
class _SheetFrame extends StatelessWidget {
  const _SheetFrame({
    required this.poster,
    required this.title,
    required this.badges,
    required this.actions,
    this.body,
  });

  final Widget poster;
  final String title;
  final List<Widget> badges;
  final Widget? body;
  final Widget actions;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: EdgeInsets.only(
        left: 24,
        right: 24,
        bottom: MediaQuery.of(context).viewInsets.bottom + 24,
      ),
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Center(child: poster),
            const SizedBox(height: 16),
            Text(
              title,
              style: theme.textTheme.headlineSmall?.copyWith(
                fontWeight: FontWeight.bold,
              ),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 8),
            Wrap(
              alignment: WrapAlignment.center,
              spacing: 8,
              runSpacing: 4,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: badges,
            ),
            const SizedBox(height: 16),
            ?body,
            const Divider(height: 32),
            actions,
          ],
        ),
      ),
    );
  }
}

/// The outcome of an "add as watched" attempt.
///
/// [keepInWatchlist] means the item was inserted but could not be completed
/// (a series whose episodes failed to load) — it deliberately stays in the
/// watchlist instead of ending up half-finished, and the caller shows a
/// localized message.
enum AddAsWatchedResult { done, keepInWatchlist }

/// What [insertAsWatched] hands back: the outcome plus the **final** stored
/// item — the caller opens this exact state in the detail view.
typedef AddAsWatchedOutcome = ({AddAsWatchedResult result, MediaItem item});

/// Adds [item] to the library and tries to mark it watched straight away.
///
///  * **Movie / book:** inserted, then set to `completed` through the normal
///    status automation ([LibraryProvider.setStatus]) — progress 100 %,
///    `completed_at` filled; a book's page jump is logged via the existing
///    reading-log funnel (never written directly).
///  * **Series:** inserted, episodes loaded lazily ([LibraryProvider.ensureEpisodes]),
///    then **every** episode marked watched — which derives `completed` / 100 %
///    via the episode automation.
///
/// The freshly inserted row is **adopted** into the in-memory library
/// ([LibraryProvider.adoptInserted]) right after the insert, so it is visible
/// immediately and the running automation updates the very same entry in place
/// — no reload, no extra query. The returned [AddAsWatchedOutcome.item] is the
/// **derived** final state (series: from the checked-off episodes).
///
/// A series whose episodes cannot be loaded (or that simply has none) is left
/// in the watchlist (planned) — an explicit, documented trade-off: a *planned*
/// entry the user can retry beats a broken one that claims to be complete
/// without any watched episodes.
Future<AddAsWatchedOutcome> insertAsWatched(
  MediaRepository repository,
  LibraryProvider library,
  MediaItem item,
) async {
  final inserted = await repository.insert(item);
  // Instant, network-free visibility — adopted before the automation so every
  // following `_replace` finds the entry and updates it in place.
  library.adoptInserted(inserted);

  var result = AddAsWatchedResult.done;
  if (inserted.kind == MediaKind.series) {
    await library.ensureEpisodes(inserted);
    final episodes = library.episodesFor(inserted.id);
    if (episodes.isEmpty) {
      result = AddAsWatchedResult.keepInWatchlist;
    } else {
      await library.markAllEpisodesWatched(inserted);
    }
  } else {
    await library.setStatus(inserted, MediaStatus.completed);
  }

  // The automation wrote the derived state through the provider, so the fresh
  // copy is already in the list — read it back instead of querying the server.
  final finalItem = library.itemById(inserted.id) ?? inserted;
  return (result: result, item: finalItem);
}

/// The two add actions of a detail sheet.
///
/// * "Add to watchlist" — the classic `planned` add.
/// * "Mark as watched" — inserts and completes the item in one step.
///
/// While an action runs both buttons are disabled and the running one shows a
/// spinner, so the user gets a visible loading state (important for a series,
/// whose episode load can take a moment). Once the item is tracked, the
/// actions are replaced by the "already in your library" confirmation —
/// **plus**, when this sheet did the add itself ([onOpen] is set), a clearly
/// visible **"Open"** button that jumps straight into the new entry's detail
/// view (so the user can record "where am I"). The offer lives *in the sheet*,
/// not in a snack bar: a snack bar would render behind the sheet's modal
/// barrier and be unreachable while the sheet stays open (which it does).
class _AddActions extends StatelessWidget {
  const _AddActions({
    required this.added,
    required this.completed,
    required this.watchlistBusy,
    required this.watchedBusy,
    required this.onWatchlist,
    required this.onWatched,
    this.onOpen,
    this.notice,
  });

  final bool added;

  /// `true` when the already-tracked entry is completed — the confirmation then
  /// reads "Already watched" instead of "Already in your library".
  final bool completed;
  final bool watchlistBusy;
  final bool watchedBusy;
  final VoidCallback onWatchlist;
  final VoidCallback onWatched;

  /// Opens the just-added item's detail view. `null` while the sheet only
  /// mirrors a *pre-existing* library entry (no add happened here), in which
  /// case no "Open" is offered.
  final VoidCallback? onOpen;

  /// Optional non-fatal note shown in the "added" state (e.g. the series that
  /// had to stay in the watchlist). `null` when there is nothing to report.
  final String? notice;

  /// A spinner sized for use inside a button icon slot.
  static const Widget _spinner = SizedBox(
    width: 18,
    height: 18,
    child: CircularProgressIndicator(strokeWidth: 2),
  );

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final strings = context.strings;

    if (added) {
      final open = onOpen;
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(Icons.check_circle, color: cs.primary),
              const SizedBox(width: 8),
              Flexible(
                child: Text(
                  completed ? strings.alreadyWatched : strings.alreadyInLibrary,
                  textAlign: TextAlign.center,
                  style: theme.textTheme.titleMedium?.copyWith(
                    color: cs.primary,
                  ),
                ),
              ),
            ],
          ),
          if (notice != null) ...[
            const SizedBox(height: 12),
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(Icons.info_outline, size: 18, color: cs.onSurfaceVariant),
                const SizedBox(width: 8),
                Flexible(
                  child: Text(
                    notice!,
                    textAlign: TextAlign.center,
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: cs.onSurfaceVariant,
                    ),
                  ),
                ),
              ],
            ),
          ],
          if (open != null) ...[
            const SizedBox(height: 16),
            OutlinedButton.icon(
              onPressed: open,
              icon: const Icon(Icons.open_in_new),
              label: Text(strings.openInLibrary),
            ),
          ],
        ],
      );
    }

    final busy = watchlistBusy || watchedBusy;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        OutlinedButton.icon(
          onPressed: busy ? null : onWatchlist,
          icon: watchlistBusy
              ? _spinner
              : const Icon(Icons.bookmark_add_outlined),
          label: Text(strings.addToWatchlist),
        ),
        const SizedBox(height: 8),
        FilledButton.icon(
          onPressed: busy ? null : onWatched,
          icon: watchedBusy ? _spinner : const Icon(Icons.check_circle_outline),
          label: Text(strings.addAsWatched),
        ),
      ],
    );
  }
}

/// Whether a [MediaRepositoryException] describes a duplicate item.
///
/// The repository maps the Postgres unique violation (23505) to this message.
bool isAlreadyInLibraryError(MediaRepositoryException error) =>
    error.message.toLowerCase().contains('already in your library');
