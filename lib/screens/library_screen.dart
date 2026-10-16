import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../l10n/app_strings.dart';
import '../models/media_item.dart';
import '../providers/library_provider.dart';
import '../providers/settings_provider.dart';
import '../services/library_filter.dart';
import '../widgets/category_banner.dart';
import '../widgets/library_view.dart';
import '../widgets/media_widgets.dart';
import '../widgets/metadata_refresh_banner.dart';
import '../widgets/settings_button.dart';

/// Landing screen of the library tab — the category banners in front of the list.
///
/// A library with hundreds of tracked titles buried the list; opening the tab
/// now shows four fixed **category banners** (Movies / Series / Books / All)
/// with their counts. Each banner is a tall (~156 px) card whose background is
/// the category's newest cover with a fanned deck of older covers (`CategoryBanner`).
/// Tapping one pushes [LibraryListView] with the matching media-type filter
/// preselected, which reuses the whole search / filter / sort machinery — no
/// second implementation.
///
/// The AppBar keeps the library actions: refresh, the overflow menu with the
/// metadata refresh and the settings gear. Loading / error / empty states are
/// unchanged: an empty library shows the friendly empty state instead of four
/// banners with `0`.
class LibraryScreen extends StatelessWidget {
  const LibraryScreen({super.key});

  /// Actions offered by the overflow menu in the AppBar.
  static const String refreshMetadataAction = 'refresh-metadata';

  // Banner keys for the four categories (used by widget tests).
  static const Key movieTileKey = Key('library-tile-movies');
  static const Key seriesTileKey = Key('library-tile-series');
  static const Key bookTileKey = Key('library-tile-books');
  static const Key allTileKey = Key('library-tile-all');

  /// The banner key for [filter].
  static Key tileKeyFor(LibraryKindFilter filter) => switch (filter) {
    LibraryKindFilter.movies => movieTileKey,
    LibraryKindFilter.series => seriesTileKey,
    LibraryKindFilter.books => bookTileKey,
    LibraryKindFilter.all => allTileKey,
  };

  /// The categories shown as banners, in display order.
  static const List<LibraryKindFilter> tiles = <LibraryKindFilter>[
    LibraryKindFilter.movies,
    LibraryKindFilter.series,
    LibraryKindFilter.books,
    LibraryKindFilter.all,
  ];

  @override
  Widget build(BuildContext context) {
    final strings = context.strings;
    final library = context.watch<LibraryProvider>();
    final items = library.items;

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
            MetadataRefreshBanner(
              done: library.metadataRefreshDone,
              total: library.metadataRefreshTotal,
            ),
          Expanded(
            child: RefreshIndicator(
              onRefresh: library.load,
              child: _buildBody(context, library, items),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildBody(
    BuildContext context,
    LibraryProvider library,
    List<MediaItem> items,
  ) {
    final strings = context.strings;

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
    return _buildTiles(context, items);
  }

  /// The responsive grid of category banners, backed by the loaded list.
  Widget _buildTiles(BuildContext context, List<MediaItem> items) {
    final theme = Theme.of(context);
    final strings = context.strings;

    // Counts come straight from the already-loaded provider list — no extra
    // DB / network query.
    final counts = <LibraryKindFilter, int>{
      for (final filter in LibraryScreen.tiles)
        filter: items.where(filter.allows).length,
    };

    return LayoutBuilder(
      builder: (context, constraints) {
        // The banners need width, so at most two columns — one on phones.
        final columns = constraints.maxWidth >= 600 ? 2 : 1;
        return CustomScrollView(
          physics: const AlwaysScrollableScrollPhysics(),
          slivers: [
            SliverPadding(
              padding: const EdgeInsets.fromLTRB(16, 16, 16, 4),
              sliver: SliverToBoxAdapter(
                child: Text(
                  strings.libraryTilesSubtitle,
                  style: theme.textTheme.bodyMedium?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
              ),
            ),
            SliverPadding(
              padding: const EdgeInsets.all(16),
              sliver: SliverGrid(
                gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                  crossAxisCount: columns,
                  mainAxisSpacing: 12,
                  crossAxisSpacing: 12,
                  // A fixed banner height instead of an aspect ratio, so the
                  // cards stay tall whatever the column width.
                  mainAxisExtent: CategoryBanner.height,
                ),
                delegate: SliverChildBuilderDelegate((context, index) {
                  final filter = LibraryScreen.tiles[index];
                  return CategoryBanner(
                    key: LibraryScreen.tileKeyFor(filter),
                    icon: filter.kind == null
                        ? Icons.video_library_outlined
                        : mediaKindIcon(filter.kind!),
                    label: strings.libraryTileLabel(filter),
                    countLabel: strings.libraryTileCount(
                      filter,
                      counts[filter] ?? 0,
                    ),
                    artwork: selectCategoryArtwork(items, filter: filter),
                    onTap: () => _openList(context, filter),
                  );
                }, childCount: LibraryScreen.tiles.length),
              ),
            ),
          ],
        );
      },
    );
  }

  /// Pushes the reused library list preselected to [filter].
  void _openList(BuildContext context, LibraryKindFilter filter) {
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => LibraryListView(initialKind: filter),
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
}
