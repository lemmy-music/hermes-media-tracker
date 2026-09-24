import 'dart:async';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../l10n/app_strings.dart';
import '../models/tmdb_result.dart';
import '../providers/settings_provider.dart';
import '../repositories/media_repository.dart';
import '../services/tmdb_client.dart';
import '../widgets/media_widgets.dart';
import '../widgets/settings_button.dart';

/// Search tab — finds movies and series on TMDB and adds them to the library.
///
/// The filter chips are driven by [TmdbSearchScope] so a future "Books" tab
/// only needs a new scope value plus a branch in the metadata client; this
/// screen renders whatever scopes exist.
class SearchScreen extends StatefulWidget {
  const SearchScreen({super.key});

  /// Minimum query length before a request is sent.
  static const int minQueryLength = 2;

  /// Above this width the result posters grow a little.
  static const double wideBreakpoint = 720;
  static const double posterNarrow = 96;
  static const double posterWide = 112;

  @override
  State<SearchScreen> createState() => _SearchScreenState();
}

class _SearchScreenState extends State<SearchScreen> {
  static const Duration _debounce = Duration(milliseconds: 400);

  final TextEditingController _controller = TextEditingController();

  Timer? _debounceTimer;

  /// Incremented per request so a slow response cannot overwrite a newer one.
  int _requestId = 0;

  TmdbSearchScope _scope = TmdbSearchScope.all;
  String _query = '';
  List<TmdbSearchResult> _results = const <TmdbSearchResult>[];
  bool _loading = false;
  String? _error;

  @override
  void dispose() {
    _debounceTimer?.cancel();
    _controller.dispose();
    super.dispose();
  }

  String get _trimmed => _query.trim();

  /// `true` when the current query is long enough to search for.
  bool get _isActive => _trimmed.length >= SearchScreen.minQueryLength;

  void _onQueryChanged(String value) {
    _debounceTimer?.cancel();
    setState(() => _query = value);

    if (!_isActive) {
      setState(() {
        _loading = false;
        _error = null;
        _results = const <TmdbSearchResult>[];
      });
      return;
    }

    setState(() {
      _loading = true;
      _error = null;
    });
    _debounceTimer = Timer(_debounce, () => _runSearch(_trimmed));
  }

  void _onScopeChanged(TmdbSearchScope scope) {
    if (scope == _scope) return;
    setState(() => _scope = scope);
    if (_isActive) {
      _debounceTimer?.cancel();
      setState(() => _loading = true);
      _runSearch(_trimmed);
    }
  }

  Future<void> _runSearch(String query) async {
    final client = context.read<TmdbClient>();
    final strings = AppStrings.read(context);
    final language = context.read<SettingsProvider>().tmdbLanguage;
    final requestId = ++_requestId;

    if (!client.hasToken) {
      setState(() {
        _loading = false;
        _error = strings.searchMissingToken;
      });
      return;
    }

    setState(() => _loading = true);
    try {
      final results = await client.search(
        query,
        scope: _scope,
        language: language,
      );
      if (!mounted || requestId != _requestId) return;
      setState(() {
        _results = results;
        _loading = false;
        _error = null;
      });
    } on TmdbException catch (error) {
      if (!mounted || requestId != _requestId) return;
      setState(() {
        _error = error.message;
        _loading = false;
      });
    }
  }

  void _openDetail(TmdbSearchResult result) {
    showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      isScrollControlled: true,
      useSafeArea: true,
      constraints: const BoxConstraints(maxWidth: 640),
      builder: (_) => TmdbDetailSheet(result: result),
    );
  }

  @override
  Widget build(BuildContext context) {
    final strings = context.strings;
    return Scaffold(
      appBar: AppBar(title: Text(strings.search), actions: const [SettingsButton()]),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
            child: TextField(
              controller: _controller,
              onChanged: _onQueryChanged,
              textInputAction: TextInputAction.search,
              decoration: InputDecoration(
                hintText: strings.searchHint,
                prefixIcon: const Icon(Icons.search),
                suffixIcon: _query.isEmpty
                    ? null
                    : IconButton(
                        icon: const Icon(Icons.clear),
                        tooltip: strings.clear,
                        onPressed: () {
                          _controller.clear();
                          _onQueryChanged('');
                        },
                      ),
                filled: true,
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: BorderSide.none,
                ),
              ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: SegmentedButton<TmdbSearchScope>(
                segments: [
                  for (final scope in TmdbSearchScope.values)
                    ButtonSegment<TmdbSearchScope>(
                      value: scope,
                      label: Text(strings.scopeLabel(scope)),
                    ),
                ],
                selected: <TmdbSearchScope>{_scope},
                showSelectedIcon: false,
                onSelectionChanged: (selection) =>
                    _onScopeChanged(selection.first),
              ),
            ),
          ),
          const SizedBox(height: 8),
          Expanded(child: _buildBody(context)),
        ],
      ),
    );
  }

  Widget _buildBody(BuildContext context) {
    final strings = context.strings;

    if (!_isActive) {
      return CenteredMessage(
        icon: Icons.search,
        title: strings.searchIdleTitle,
        message: strings.searchIdleMessage,
        scrollable: false,
      );
    }
    if (_loading) {
      return const Center(child: CircularProgressIndicator());
    }
    final error = _error;
    if (error != null) {
      return CenteredMessage(
        icon: Icons.cloud_off,
        title: strings.searchFailedTitle,
        message: error,
        scrollable: false,
        action: FilledButton.icon(
          onPressed: () => _runSearch(_trimmed),
          icon: const Icon(Icons.refresh),
          label: Text(strings.retry),
        ),
      );
    }
    if (_results.isEmpty) {
      return CenteredMessage(
        icon: Icons.search_off,
        title: strings.noResultsTitle,
        message: strings.noResultsMessage,
        scrollable: false,
      );
    }
    return LayoutBuilder(
      builder: (context, constraints) {
        final posterWidth =
            constraints.maxWidth >= SearchScreen.wideBreakpoint
            ? SearchScreen.posterWide
            : SearchScreen.posterNarrow;
        return ListView.separated(
          padding: const EdgeInsets.only(bottom: 16),
          itemCount: _results.length,
          separatorBuilder: (_, _) =>
              Divider(height: 1, indent: 16 + posterWidth + 14),
          itemBuilder: (context, index) {
            final result = _results[index];
            return _SearchResultTile(
              result: result,
              posterWidth: posterWidth,
              onTap: () => _openDetail(result),
            );
          },
        );
      },
    );
  }
}

/// One hit in the search results: poster, title, year, kind badge, teaser.
class _SearchResultTile extends StatelessWidget {
  const _SearchResultTile({
    required this.result,
    required this.posterWidth,
    required this.onTap,
  });

  final TmdbSearchResult result;
  final double posterWidth;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final strings = context.strings;
    final year = result.year;
    final overview = result.shortOverview;
    final posterHeight = posterWidth * 3 / 2;

    return InkWell(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            PosterThumbnail(
              url: result.posterUrl,
              placeholderIcon: tmdbTypeIcon(result.type),
              width: posterWidth,
              height: posterHeight,
              iconSize: posterWidth * 0.35,
              borderRadius: 10,
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    result.title,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: theme.textTheme.titleMedium,
                  ),
                  const SizedBox(height: 6),
                  Wrap(
                    spacing: 8,
                    runSpacing: 4,
                    crossAxisAlignment: WrapCrossAlignment.center,
                    children: [
                      PillBadge(
                        icon: tmdbTypeIcon(result.type),
                        label: strings.typeLabel(result.type),
                      ),
                      if (year != null)
                        Text('$year', style: theme.textTheme.bodySmall),
                    ],
                  ),
                  if (overview != null) ...[
                    const SizedBox(height: 6),
                    Text(
                      overview,
                      maxLines: 3,
                      overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: theme.colorScheme.onSurfaceVariant,
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Bottom-sheet preview of a search hit with an "Add to library" action.
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
      final alreadyInLibrary = error.message.toLowerCase().contains(
        'already in your library',
      );
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
            Center(
              child: PosterThumbnail(
                url: TmdbImages.poster(posterPath, size: 'w500'),
                placeholderIcon: tmdbTypeIcon(result.type),
                width: 168,
                height: 252,
                iconSize: 56,
                borderRadius: 14,
              ),
            ),
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
              children: [
                PillBadge(
                  icon: tmdbTypeIcon(result.type),
                  label: strings.typeLabel(result.type),
                ),
                if (year != null)
                  Text('$year', style: theme.textTheme.bodyMedium),
                ..._detailsMeta(context, details),
              ],
            ),
            const SizedBox(height: 16),
            if (overview != null && overview.isNotEmpty)
              Text(overview, style: theme.textTheme.bodyMedium),
            const Divider(height: 32),
            _buildActions(context, cs),
          ],
        ),
      ),
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

    if (_added) {
      return Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(Icons.check_circle, color: cs.primary),
          const SizedBox(width: 8),
          Flexible(
            child: Text(
              strings.alreadyInLibrary,
              textAlign: TextAlign.center,
              style: Theme.of(
                context,
              ).textTheme.titleMedium?.copyWith(color: cs.primary),
            ),
          ),
        ],
      );
    }

    return FilledButton.icon(
      onPressed: _adding ? null : _add,
      icon: _adding
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
