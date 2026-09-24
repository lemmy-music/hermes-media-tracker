import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../l10n/app_strings.dart';
import '../models/book_result.dart';
import '../models/media_item.dart';
import '../models/tmdb_result.dart';
import '../providers/settings_provider.dart';
import '../repositories/media_repository.dart';
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
  bool _adding = false;
  bool _added = false;
  String? _error;

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
      try {
        final existing = await repository.findByExternal(
          'tmdb',
          '${widget.result.id}',
        );
        alreadyTracked = existing != null;
      } on MediaRepositoryException {
        // Non-fatal: the insert's unique-index guard still protects us.
      }
      if (!mounted) return;
      setState(() {
        _details = details;
        _added = alreadyTracked;
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

  Future<void> _add() async {
    final details = _details;
    if (details == null || _adding) return;

    final messenger = ScaffoldMessenger.of(context);
    final repository = context.read<MediaRepository>();
    final strings = AppStrings.read(context);

    setState(() => _adding = true);
    try {
      await repository.insert(details.toMediaItem());
      if (!mounted) return;
      setState(() {
        _added = true;
        _adding = false;
      });
      messenger.showSnackBar(SnackBar(content: Text(strings.addedToLibrary)));
    } on MediaRepositoryException catch (error) {
      if (!mounted) return;
      final alreadyInLibrary = isAlreadyInLibraryError(error);
      setState(() {
        _added = alreadyInLibrary;
        _adding = false;
      });
      messenger.showSnackBar(
        SnackBar(
          content: Text(
            alreadyInLibrary ? strings.alreadyInLibrary : error.message,
          ),
        ),
      );
    }
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

    return _AddAction(added: _added, adding: _adding, onAdd: _add);
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
  bool _adding = false;
  bool _added = false;
  String? _error;

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
      try {
        final existing = await repository.findByExternal(
          'openlibrary',
          widget.result.key,
        );
        alreadyTracked = existing != null;
      } on MediaRepositoryException {
        // Non-fatal: the insert's unique-index guard still protects us.
      }
      if (!mounted) return;
      setState(() {
        _details = details;
        _added = alreadyTracked;
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

  Future<void> _add() async {
    final details = _details;
    if (details == null || _adding) return;

    final messenger = ScaffoldMessenger.of(context);
    final repository = context.read<MediaRepository>();
    final strings = AppStrings.read(context);

    setState(() => _adding = true);
    try {
      await repository.insert(
        widget.result.toMediaItem(
          description: details.description,
          totalPages: details.pageCount,
          isbn: details.isbn,
          coverUrl: details.coverUrl,
          releaseYear: details.firstPublishYear,
        ),
      );
      if (!mounted) return;
      setState(() {
        _added = true;
        _adding = false;
      });
      messenger.showSnackBar(SnackBar(content: Text(strings.addedToLibrary)));
    } on MediaRepositoryException catch (error) {
      if (!mounted) return;
      final alreadyInLibrary = isAlreadyInLibraryError(error);
      setState(() {
        _added = alreadyInLibrary;
        _adding = false;
      });
      messenger.showSnackBar(
        SnackBar(
          content: Text(
            alreadyInLibrary ? strings.alreadyInLibrary : error.message,
          ),
        ),
      );
    }
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

    return _AddAction(added: _added, adding: _adding, onAdd: _add);
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

/// Initializes the add button: "Add to library", a spinner while adding, or the
/// "Already in your library" confirmation.
class _AddAction extends StatelessWidget {
  const _AddAction({
    required this.added,
    required this.adding,
    required this.onAdd,
  });

  final bool added;
  final bool adding;
  final VoidCallback onAdd;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final strings = context.strings;

    if (added) {
      return Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(Icons.check_circle, color: cs.primary),
          const SizedBox(width: 8),
          Flexible(
            child: Text(
              strings.alreadyInLibrary,
              textAlign: TextAlign.center,
              style: theme.textTheme.titleMedium?.copyWith(color: cs.primary),
            ),
          ),
        ],
      );
    }

    return FilledButton.icon(
      onPressed: adding ? null : onAdd,
      icon: adding
          ? const SizedBox(
              width: 18,
              height: 18,
              child: CircularProgressIndicator(strokeWidth: 2),
            )
          : const Icon(Icons.add),
      label: Text(strings.addToLibrary),
    );
  }
}

/// Whether a [MediaRepositoryException] describes a duplicate item.
///
/// The repository maps the Postgres unique violation (23505) to this message.
bool isAlreadyInLibraryError(MediaRepositoryException error) =>
    error.message.toLowerCase().contains('already in your library');
