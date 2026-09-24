import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../l10n/app_strings.dart';
import '../models/media_item.dart';
import '../providers/library_provider.dart';
import '../providers/settings_provider.dart';
import '../services/library_filter.dart';
import '../widgets/media_widgets.dart';
import '../widgets/settings_button.dart';
import 'media_detail_screen.dart';

/// Library tab — lists everything the signed-in user tracks.
///
/// Read-only list with loading / empty / error states, a client-side search /
/// filter / sort bar (Phase 5b), manual refresh and the metadata refresh entry
/// point (the automatic one runs while the language changes). Tracking state is
/// shown per row and edited on the detail screen, which opens on a tap.
///
/// **All searching / filtering / sorting happens on the already-loaded list**
/// (no server round-trip, no pagination) and is pure logic in
/// `lib/services/library_filter.dart`. The provider's list is never modified.
class LibraryScreen extends StatefulWidget {
  const LibraryScreen({super.key});

  /// Above this width the posters grow a little (tablet / desktop web).
  static const double wideBreakpoint = 720;

  /// Poster width on phones.
  static const double posterNarrow = 96;

  /// Poster width on wide screens.
  static const double posterWide = 112;

  /// Actions offered by the overflow menu in the AppBar.
  static const String refreshMetadataAction = 'refresh-metadata';

  // Keys for the search / filter / sort controls (used by widget tests).
  static const Key searchToggleKey = Key('library-search-toggle');
  static const Key searchFieldKey = Key('library-search-field');
  static const Key filterToggleKey = Key('library-filter-toggle');
  static const Key sortMenuKey = Key('library-sort-menu');
  static const Key resetFiltersKey = Key('library-reset-filters');
  static const Key noMatchesKey = Key('library-no-matches');

  @override
  State<LibraryScreen> createState() => _LibraryScreenState();
}

class _LibraryScreenState extends State<LibraryScreen> {
  final TextEditingController _searchController = TextEditingController();

  // ── session-only view state ────────────────────────────────────────────────
  //
  // Search text, the two filters, the sort order and the two visibility toggles
  // live for the lifetime of this screen and are deliberately **not**
  // persisted: a fresh app start shows the whole library again. The provider's
  // list stays untouched — the visible list is derived on every build.
  bool _searchVisible = false;
  bool _filtersVisible = false;
  LibraryKindFilter _kindFilter = LibraryKindFilter.all;
  LibraryStatusFilter _statusFilter = LibraryStatusFilter.all;
  LibrarySort _sort = LibrarySort.defaultValue;

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  String get _query => _searchController.text;

  bool get _filtersActive =>
      hasLibraryFilter(query: _query, kind: _kindFilter, status: _statusFilter);

  void _toggleSearch() {
    setState(() {
      _searchVisible = !_searchVisible;
      // Closing the field also clears it — otherwise an invisible query would
      // keep filtering the list with no way to see why.
      if (!_searchVisible) _searchController.clear();
    });
  }

  /// Clears the search text and resets both filters (the sort order stays).
  void _resetFilters() {
    _searchController.clear();
    setState(() {
      _kindFilter = LibraryKindFilter.all;
      _statusFilter = LibraryStatusFilter.all;
      _filtersVisible = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    final strings = context.strings;
    final library = context.watch<LibraryProvider>();
    final items = library.items;

    // The whole view (filter + sort) is a pure function of the provider list
    // and the session-only state above — nothing here mutates `library.items`.
    final visible = applyLibraryView(
      items: items,
      query: _query,
      kind: _kindFilter,
      status: _statusFilter,
      sort: _sort,
    );

    return Scaffold(
      appBar: AppBar(
        title: Text(strings.library),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            tooltip: strings.refresh,
            onPressed: library.loading ? null : library.load,
          ),
          PopupMenuButton<String>(
            tooltip: strings.moreActions,
            onSelected: (action) {
              if (action == LibraryScreen.refreshMetadataAction) {
                _refreshMetadata(context, library);
              }
            },
            itemBuilder: (context) => [
              PopupMenuItem<String>(
                value: LibraryScreen.refreshMetadataAction,
                enabled: !library.refreshingMetadata,
                child: Row(
                  children: [
                    const Icon(Icons.sync),
                    const SizedBox(width: 12),
                    Flexible(child: Text(strings.metadataRefreshAction)),
                  ],
                ),
              ),
            ],
          ),
          const SettingsButton(),
        ],
      ),
      body: Column(
        children: [
          if (library.refreshingMetadata)
            _MetadataRefreshBanner(
              done: library.metadataRefreshDone,
              total: library.metadataRefreshTotal,
            ),
          if (items.isNotEmpty) _buildToolbar(context),
          if (items.isNotEmpty && _searchVisible) _buildSearchField(context),
          if (items.isNotEmpty && _filtersVisible) _buildFilterChips(context),
          if (items.isNotEmpty && _filtersActive)
            _buildResultBar(context, visible.length, items.length),
          Expanded(
            child: RefreshIndicator(
              onRefresh: library.load,
              child: _buildBody(context, library, visible),
            ),
          ),
        ],
      ),
    );
  }

  /// Search / filter / sort controls, directly under the AppBar.
  ///
  /// Kept out of the AppBar on purpose: a phone AppBar already carries refresh,
  /// the overflow menu and settings, and three more icons would crowd it out.
  Widget _buildToolbar(BuildContext context) {
    final strings = context.strings;
    final kindStatusActive =
        _kindFilter != LibraryKindFilter.all ||
        _statusFilter != LibraryStatusFilter.all;

    return Padding(
      padding: const EdgeInsets.fromLTRB(4, 4, 8, 0),
      child: Row(
        children: [
          IconButton(
            key: LibraryScreen.searchToggleKey,
            icon: Icon(_searchVisible ? Icons.search_off : Icons.manage_search),
            tooltip: strings.search,
            isSelected: _searchVisible,
            onPressed: _toggleSearch,
          ),
          IconButton(
            key: LibraryScreen.filterToggleKey,
            icon: Icon(
              _filtersVisible ? Icons.filter_list_off : Icons.filter_list,
            ),
            tooltip: strings.filterLabel,
            isSelected: kindStatusActive,
            onPressed: () => setState(() => _filtersVisible = !_filtersVisible),
          ),
          PopupMenuButton<LibrarySort>(
            key: LibraryScreen.sortMenuKey,
            icon: const Icon(Icons.sort),
            tooltip: strings.sortBy,
            initialValue: _sort,
            onSelected: (value) => setState(() => _sort = value),
            itemBuilder: (context) => [
              for (final sort in LibrarySort.values)
                CheckedPopupMenuItem<LibrarySort>(
                  value: sort,
                  checked: sort == _sort,
                  child: Text(strings.sortLabel(sort)),
                ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildSearchField(BuildContext context) {
    final strings = context.strings;
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 4),
      child: TextField(
        key: LibraryScreen.searchFieldKey,
        controller: _searchController,
        autofocus: true,
        textInputAction: TextInputAction.search,
        // Live filtering: every keystroke re-derives the visible list.
        onChanged: (_) => setState(() {}),
        decoration: InputDecoration(
          hintText: strings.librarySearchHint,
          prefixIcon: const Icon(Icons.search),
          suffixIcon: _query.isEmpty
              ? null
              : IconButton(
                  icon: const Icon(Icons.clear),
                  tooltip: strings.clear,
                  onPressed: () => setState(_searchController.clear),
                ),
          filled: true,
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(12),
            borderSide: BorderSide.none,
          ),
        ),
      ),
    );
  }

  /// Two horizontally scrollable chip rows: media type, then status.
  Widget _buildFilterChips(BuildContext context) {
    final strings = context.strings;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _chipRow(<Widget>[
          for (final kind in LibraryKindFilter.values)
            ChoiceChip(
              label: Text(strings.libraryKindFilterLabel(kind)),
              selected: _kindFilter == kind,
              onSelected: (_) => setState(() => _kindFilter = kind),
            ),
        ]),
        _chipRow(<Widget>[
          for (final status in LibraryStatusFilter.values)
            ChoiceChip(
              label: Text(strings.libraryStatusFilterLabel(status)),
              selected: _statusFilter == status,
              onSelected: (_) => setState(() => _statusFilter = status),
            ),
        ]),
      ],
    );
  }

  Widget _chipRow(List<Widget> chips) {
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      padding: const EdgeInsets.fromLTRB(12, 4, 12, 4),
      child: Row(
        children: [
          for (var i = 0; i < chips.length; i++) ...[
            if (i > 0) const SizedBox(width: 8),
            chips[i],
          ],
        ],
      ),
    );
  }

  /// Result counter + quick reset, shown only while a search / filter is active.
  Widget _buildResultBar(BuildContext context, int shown, int total) {
    final theme = Theme.of(context);
    final strings = context.strings;
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 0, 8, 0),
      child: Row(
        children: [
          Expanded(
            child: Text(
              strings.libraryResultCount(shown, total),
              overflow: TextOverflow.ellipsis,
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
          ),
          TextButton.icon(
            key: LibraryScreen.resetFiltersKey,
            onPressed: _resetFilters,
            icon: const Icon(Icons.filter_alt_off, size: 18),
            label: Text(strings.resetFilters),
          ),
        ],
      ),
    );
  }

  /// Manual refresh with the currently selected language.
  Future<void> _refreshMetadata(
    BuildContext context,
    LibraryProvider library,
  ) async {
    final strings = AppStrings.read(context);
    final language = context.read<SettingsProvider>().language;
    final messenger = ScaffoldMessenger.of(context);

    final result = await library.refreshMetadata(language: language);
    // The completed run with candidates is reported centrally (it may have
    // been started from the settings sheet, i.e. not from this screen); only
    // the "nothing to do" case needs feedback here.
    if (!result.hadCandidates) {
      messenger.showSnackBar(
        SnackBar(content: Text(strings.metadataRefreshEmpty)),
      );
    }
  }

  Widget _buildBody(
    BuildContext context,
    LibraryProvider library,
    List<MediaItem> visible,
  ) {
    final strings = context.strings;
    final items = library.items;

    if (library.loading && items.isEmpty) {
      return const Center(child: CircularProgressIndicator());
    }
    final error = library.error;
    if (error != null && items.isEmpty) {
      return CenteredMessage(
        icon: Icons.cloud_off,
        title: strings.libraryLoadErrorTitle,
        message: error,
        action: FilledButton.icon(
          onPressed: library.load,
          icon: const Icon(Icons.refresh),
          label: Text(strings.retry),
        ),
      );
    }
    if (items.isEmpty) {
      return CenteredMessage(
        icon: Icons.video_library_outlined,
        title: strings.libraryEmptyTitle,
        message: strings.libraryEmptyMessage,
      );
    }
    // The library has items, but the search / filters excluded all of them —
    // a *different* state than "empty library", with its own reset action.
    if (visible.isEmpty) {
      return CenteredMessage(
        key: LibraryScreen.noMatchesKey,
        icon: Icons.search_off,
        title: strings.libraryNoMatchesTitle,
        message: strings.libraryNoMatchesMessage,
        action: FilledButton.icon(
          onPressed: _resetFilters,
          icon: const Icon(Icons.filter_alt_off),
          label: Text(strings.resetFilters),
        ),
      );
    }
    return LayoutBuilder(
      builder: (context, constraints) {
        final posterWidth = constraints.maxWidth >= LibraryScreen.wideBreakpoint
            ? LibraryScreen.posterWide
            : LibraryScreen.posterNarrow;
        return ListView.separated(
          physics: const AlwaysScrollableScrollPhysics(),
          padding: const EdgeInsets.symmetric(vertical: 8),
          itemCount: visible.length,
          separatorBuilder: (_, _) =>
              Divider(height: 1, indent: 16 + posterWidth + 14),
          itemBuilder: (context, index) =>
              _MediaTile(item: visible[index], posterWidth: posterWidth),
        );
      },
    );
  }
}

/// Slim, unobtrusive progress bar shown while metadata is re-fetched.
class _MetadataRefreshBanner extends StatelessWidget {
  const _MetadataRefreshBanner({required this.done, required this.total});

  final int done;
  final int total;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final strings = context.strings;
    return Material(
      color: theme.colorScheme.surfaceContainerHighest,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          LinearProgressIndicator(
            value: total == 0 ? null : done / total,
            minHeight: 3,
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            child: Row(
              children: [
                Icon(
                  Icons.sync,
                  size: 16,
                  color: theme.colorScheme.onSurfaceVariant,
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    strings.metadataRefreshing(done, total),
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// A single library row: cover thumbnail, title, kind + status badges and a
/// progress bar. Tapping it opens the detail screen.
///
/// Series rows show a progress bar too: their status/progress is derived from
/// the checked-off episodes (Phase 3b) and persisted on `media_items`, so the
/// list needs no episode data of its own.
class _MediaTile extends StatelessWidget {
  const _MediaTile({required this.item, required this.posterWidth});

  final MediaItem item;
  final double posterWidth;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final strings = context.strings;
    final year = item.releaseYear;
    final posterHeight = posterWidth * 3 / 2;

    return InkWell(
      onTap: () => Navigator.of(context).push(
        MaterialPageRoute<void>(builder: (_) => MediaDetailScreen(item: item)),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            PosterThumbnail(
              url: item.posterUrl,
              placeholderIcon: mediaKindIcon(item.kind),
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
                    item.title,
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
                        icon: mediaKindIcon(item.kind),
                        label: strings.kindLabel(item.kind),
                      ),
                      StatusBadge(
                        status: item.status,
                        label: strings.statusLabel(item.status),
                      ),
                      if (year != null)
                        Text('$year', style: theme.textTheme.bodySmall),
                    ],
                  ),
                  const SizedBox(height: 10),
                  Row(
                    children: [
                      Expanded(
                        child: LinearProgressIndicator(
                          value:
                              (item.progressPercent ?? 0).clamp(0, 100) / 100,
                          minHeight: 5,
                          borderRadius: BorderRadius.circular(3),
                        ),
                      ),
                      const SizedBox(width: 8),
                      Text(
                        strings.percentValue(
                          (item.progressPercent ?? 0).round(),
                        ),
                        style: theme.textTheme.labelSmall?.copyWith(
                          color: cs.onSurfaceVariant,
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
