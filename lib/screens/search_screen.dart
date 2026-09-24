import 'dart:async';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../models/tmdb_result.dart';
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
    final requestId = ++_requestId;

    if (!client.hasToken) {
      setState(() {
        _loading = false;
        _error =
            'Search is unavailable: this build has no TMDB token '
            'configured. Rebuild the app with --dart-define=TMDB_TOKEN=….';
      });
      return;
    }

    setState(() => _loading = true);
    try {
      final results = await client.search(query, scope: _scope);
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
    return Scaffold(
      appBar: AppBar(
        title: const Text('Search'),
        actions: const [SettingsButton()],
      ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
            child: TextField(
              controller: _controller,
              onChanged: _onQueryChanged,
              textInputAction: TextInputAction.search,
              decoration: InputDecoration(
                hintText: 'Search movies and series',
                prefixIcon: const Icon(Icons.search),
                suffixIcon: _query.isEmpty
                    ? null
                    : IconButton(
                        icon: const Icon(Icons.clear),
                        tooltip: 'Clear',
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
                      label: Text(scope.label),
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
    if (!_isActive) {
      return const CenteredMessage(
        icon: Icons.search,
        title: 'Find something to track',
        message: 'Search for movies and series by title.',
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
        title: 'Search failed',
        message: error,
        scrollable: false,
        action: FilledButton.icon(
          onPressed: () => _runSearch(_trimmed),
          icon: const Icon(Icons.refresh),
          label: const Text('Retry'),
        ),
      );
    }
    if (_results.isEmpty) {
      return const CenteredMessage(
        icon: Icons.search_off,
        title: 'No results',
        message: 'Try a different spelling or a shorter query.',
        scrollable: false,
      );
    }
    return ListView.separated(
      padding: const EdgeInsets.only(bottom: 16),
      itemCount: _results.length,
      separatorBuilder: (_, _) => const Divider(height: 1, indent: 80),
      itemBuilder: (context, index) {
        final result = _results[index];
        return _SearchResultTile(
          result: result,
          onTap: () => _openDetail(result),
        );
      },
    );
  }
}

/// One hit in the search results: poster, title, year, kind badge, teaser.
class _SearchResultTile extends StatelessWidget {
  const _SearchResultTile({required this.result, required this.onTap});

  final TmdbSearchResult result;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final year = result.year;
    final overview = result.shortOverview;

    return ListTile(
      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
      onTap: onTap,
      leading: PosterThumbnail(
        url: result.posterUrl,
        placeholderIcon: tmdbTypeIcon(result.type),
      ),
      title: Text(result.title, maxLines: 1, overflow: TextOverflow.ellipsis),
      subtitle: Padding(
        padding: const EdgeInsets.only(top: 4),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Wrap(
              spacing: 8,
              runSpacing: 4,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: [
                PillBadge(
                  icon: tmdbTypeIcon(result.type),
                  label: result.type.label,
                ),
                if (year != null)
                  Text('$year', style: theme.textTheme.bodySmall),
              ],
            ),
            if (overview != null) ...[
              const SizedBox(height: 4),
              Text(
                overview,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: theme.textTheme.bodySmall?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
            ],
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

    setState(() {
      _loading = true;
      _error = null;
    });

    try {
      final details = await client.fetchDetails(widget.result);
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

    setState(() => _adding = true);
    try {
      await repository.insert(details.toMediaItem());
      if (!mounted) return;
      setState(() {
        _added = true;
        _adding = false;
      });
      messenger.showSnackBar(const SnackBar(content: Text('Added to library')));
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
            alreadyInLibrary ? 'Already in your library' : error.message,
          ),
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
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
                width: 132,
                height: 198,
                iconSize: 48,
                borderRadius: 12,
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
                  label: result.type.label,
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
    final style = Theme.of(context).textTheme.bodyMedium;
    if (details is TmdbMovieDetails && details.runtime != null) {
      return [Text('${details.runtime} min', style: style)];
    }
    if (details is TmdbTvDetails) {
      final chips = <Widget>[];
      final seasons = details.numberOfSeasons;
      final episodes = details.numberOfEpisodes;
      if (seasons != null) {
        chips.add(
          Text('$seasons season${seasons == 1 ? '' : 's'}', style: style),
        );
      }
      if (episodes != null) {
        chips.add(
          Text('$episodes episode${episodes == 1 ? '' : 's'}', style: style),
        );
      }
      return chips;
    }
    return const <Widget>[];
  }

  Widget _buildActions(BuildContext context, ColorScheme cs) {
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
            label: const Text('Retry'),
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
          Text(
            'Already in your library',
            style: Theme.of(
              context,
            ).textTheme.titleMedium?.copyWith(color: cs.primary),
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
      label: const Text('Add to library'),
    );
  }
}
