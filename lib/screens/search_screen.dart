import 'dart:async';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../l10n/app_strings.dart';
import '../models/book_result.dart';
import '../models/media_item.dart';
import '../models/tmdb_result.dart';
import '../providers/settings_provider.dart';
import '../services/openlibrary_client.dart';
import '../services/tmdb_client.dart';
import '../widgets/detail_sheets.dart';
import '../widgets/media_widgets.dart';
import '../widgets/settings_button.dart';

/// One row in the (possibly merged) result list.
///
/// The screen combines two metadata sources — TMDB (movies / series) and
/// OpenLibrary (books) — behind a single list, so every row is wrapped in one
/// of these hits and rendered generically.
sealed class SearchHit {
  const SearchHit();
}

/// A movie or series hit from TMDB.
class TmdbHit extends SearchHit {
  const TmdbHit(this.result);

  final TmdbSearchResult result;
}

/// A book (work) hit from OpenLibrary.
class BookHit extends SearchHit {
  const BookHit(this.result);

  final BookResult result;
}

/// Search tab — finds movies, series (TMDB) and books (OpenLibrary).
///
/// The filter chips are driven by [TmdbSearchScope]: `all` queries **both**
/// sources and interleaves the hits, the typed values query one source only.
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
  List<SearchHit> _results = const <SearchHit>[];
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
        _results = const <SearchHit>[];
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
    final tmdb = context.read<TmdbClient>();
    final books = context.read<OpenLibraryClient>();
    final strings = AppStrings.read(context);
    final language = context.read<SettingsProvider>().language;
    final requestId = ++_requestId;
    final scope = _scope;

    // `all` hits both sources, `books` only OpenLibrary, the rest only TMDB.
    final wantsTmdb = scope != TmdbSearchScope.books;
    final wantsBooks =
        scope == TmdbSearchScope.books || scope == TmdbSearchScope.all;

    if (wantsTmdb && !tmdb.hasToken) {
      setState(() {
        _loading = false;
        _error = strings.searchMissingToken;
      });
      return;
    }

    setState(() => _loading = true);

    var tmdbHits = const <SearchHit>[];
    var bookHits = const <SearchHit>[];
    String? firstError;

    final requests = <Future<void>>[];
    if (wantsTmdb) {
      requests.add(() async {
        try {
          final results = await tmdb.search(
            query,
            scope: scope,
            language: language.tmdbCode,
          );
          tmdbHits = results.map<SearchHit>(TmdbHit.new).toList();
        } on TmdbException catch (error) {
          firstError ??= error.message;
        }
      }());
    }
    if (wantsBooks) {
      requests.add(() async {
        try {
          // OpenLibrary has no localized metadata — `language` only ranks
          // German editions first on a German UI.
          final results = await books.search(query, language: language);
          bookHits = results.map<SearchHit>(BookHit.new).toList();
        } on OpenLibraryException catch (error) {
          firstError ??= error.message;
        }
      }());
    }
    await Future.wait(requests);

    if (!mounted || requestId != _requestId) return;
    final merged = _interleave(tmdbHits, bookHits);
    setState(() {
      _results = merged;
      _loading = false;
      // A single failing source only matters when it left nothing to show.
      _error = merged.isEmpty ? firstError : null;
    });
  }

  void _openDetail(SearchHit hit) {
    showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      isScrollControlled: true,
      useSafeArea: true,
      constraints: const BoxConstraints(maxWidth: 640),
      builder: (_) => switch (hit) {
        TmdbHit(:final result) => TmdbDetailSheet(result: result),
        BookHit(:final result) => BookDetailSheet(result: result),
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final strings = context.strings;
    return Scaffold(
      appBar: AppBar(
        title: Text(strings.search),
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
        final posterWidth = constraints.maxWidth >= SearchScreen.wideBreakpoint
            ? SearchScreen.posterWide
            : SearchScreen.posterNarrow;
        return ListView.separated(
          padding: const EdgeInsets.only(bottom: 16),
          itemCount: _results.length,
          separatorBuilder: (_, _) =>
              Divider(height: 1, indent: 16 + posterWidth + 14),
          itemBuilder: (context, index) {
            final hit = _results[index];
            return _SearchResultTile(
              hit: hit,
              posterWidth: posterWidth,
              onTap: () => _openDetail(hit),
            );
          },
        );
      },
    );
  }
}

/// Round-robin merge of the two sources so neither dominates the top of the
/// merged "All" list while keeping each source's own ranking intact.
List<SearchHit> _interleave(List<SearchHit> first, List<SearchHit> second) {
  if (first.isEmpty) return second;
  if (second.isEmpty) return first;
  final merged = <SearchHit>[];
  final length = first.length > second.length ? first.length : second.length;
  for (var i = 0; i < length; i++) {
    if (i < first.length) merged.add(first[i]);
    if (i < second.length) merged.add(second[i]);
  }
  return merged;
}

/// One hit in the search results: cover, title, year, kind badge, teaser.
class _SearchResultTile extends StatelessWidget {
  const _SearchResultTile({
    required this.hit,
    required this.posterWidth,
    required this.onTap,
  });

  final SearchHit hit;
  final double posterWidth;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final strings = context.strings;
    final posterHeight = posterWidth * 3 / 2;

    final (
      String title,
      int? year,
      String badge,
      IconData icon,
      String? teaser,
      String? imageUrl,
    ) = switch (hit) {
      TmdbHit(:final result) => (
        result.title,
        result.year,
        strings.typeLabel(result.type),
        tmdbTypeIcon(result.type),
        result.shortOverview,
        result.posterUrl,
      ),
      BookHit(:final result) => (
        result.title,
        result.firstPublishYear,
        strings.kindLabel(MediaKind.book),
        Icons.menu_book_outlined,
        result.authors.isEmpty
            ? null
            : strings.byAuthors(result.authors.join(', ')),
        result.coverUrl,
      ),
    };

    return InkWell(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            PosterThumbnail(
              url: imageUrl,
              placeholderIcon: icon,
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
                    title,
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
                      PillBadge(icon: icon, label: badge),
                      if (year != null)
                        Text('$year', style: theme.textTheme.bodySmall),
                    ],
                  ),
                  if (teaser != null) ...[
                    const SizedBox(height: 6),
                    Text(
                      teaser,
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
