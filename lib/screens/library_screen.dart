import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../l10n/app_strings.dart';
import '../models/media_item.dart';
import '../providers/library_provider.dart';
import '../providers/settings_provider.dart';
import '../widgets/media_widgets.dart';
import '../widgets/settings_button.dart';
import 'media_detail_screen.dart';

/// Library tab — lists everything the signed-in user tracks.
///
/// Read-only list with loading / empty / error states, manual refresh and the
/// metadata refresh entry point (the automatic one runs while the language
/// changes). Tracking state is shown per row and edited on the detail screen,
/// which opens on a tap.
class LibraryScreen extends StatelessWidget {
  const LibraryScreen({super.key});

  /// Above this width the posters grow a little (tablet / desktop web).
  static const double wideBreakpoint = 720;

  /// Poster width on phones.
  static const double posterNarrow = 96;

  /// Poster width on wide screens.
  static const double posterWide = 112;

  /// Actions offered by the overflow menu in the AppBar.
  static const String refreshMetadataAction = 'refresh-metadata';

  @override
  Widget build(BuildContext context) {
    final strings = context.strings;
    final library = context.watch<LibraryProvider>();

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
              if (action == refreshMetadataAction) {
                _refreshMetadata(context, library);
              }
            },
            itemBuilder: (context) => [
              PopupMenuItem<String>(
                value: refreshMetadataAction,
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
          Expanded(
            child: RefreshIndicator(
              onRefresh: library.load,
              child: _buildBody(context, library),
            ),
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

  Widget _buildBody(BuildContext context, LibraryProvider library) {
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
    return LayoutBuilder(
      builder: (context, constraints) {
        final posterWidth = constraints.maxWidth >= LibraryScreen.wideBreakpoint
            ? LibraryScreen.posterWide
            : LibraryScreen.posterNarrow;
        return ListView.separated(
          physics: const AlwaysScrollableScrollPhysics(),
          padding: const EdgeInsets.symmetric(vertical: 8),
          itemCount: items.length,
          separatorBuilder: (_, _) =>
              Divider(height: 1, indent: 16 + posterWidth + 14),
          itemBuilder: (context, index) =>
              _MediaTile(item: items[index], posterWidth: posterWidth),
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
