import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../l10n/app_strings.dart';
import '../models/media_item.dart';
import '../repositories/media_repository.dart';
import '../widgets/media_widgets.dart';
import '../widgets/settings_button.dart';

/// Library tab — lists everything the signed-in user tracks.
///
/// Detail and tracking UI arrive in Phase 3; this is a read-only list with
/// loading / empty / error states and manual refresh.
class LibraryScreen extends StatefulWidget {
  const LibraryScreen({super.key});

  /// Above this width the posters grow a little (tablet / desktop web).
  static const double wideBreakpoint = 720;

  /// Poster width on phones.
  static const double posterNarrow = 96;

  /// Poster width on wide screens.
  static const double posterWide = 112;

  @override
  State<LibraryScreen> createState() => _LibraryScreenState();
}

class _LibraryScreenState extends State<LibraryScreen> {
  late final MediaRepository _repository;

  List<MediaItem> _items = const <MediaItem>[];
  bool _loading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _repository = context.read<MediaRepository>();
    _load();
  }

  Future<void> _load() async {
    // On the first call (from initState) we are already in the initial loading
    // state, so there is nothing to setState for.
    if (!_loading || _error != null) {
      setState(() {
        _loading = true;
        _error = null;
      });
    }

    try {
      final items = await _repository.fetchAll();
      if (!mounted) return;
      setState(() {
        _items = items;
        _loading = false;
      });
    } on MediaRepositoryException catch (error) {
      if (!mounted) return;
      setState(() {
        _error = error.message;
        _loading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final strings = context.strings;
    return Scaffold(
      appBar: AppBar(
        title: Text(strings.library),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            tooltip: strings.refresh,
            onPressed: _loading ? null : _load,
          ),
          const SettingsButton(),
        ],
      ),
      body: RefreshIndicator(onRefresh: _load, child: _buildBody(context)),
    );
  }

  Widget _buildBody(BuildContext context) {
    final strings = context.strings;

    if (_loading && _items.isEmpty) {
      return const Center(child: CircularProgressIndicator());
    }
    final error = _error;
    if (error != null) {
      return CenteredMessage(
        icon: Icons.cloud_off,
        title: strings.libraryLoadErrorTitle,
        message: error,
        action: FilledButton.icon(
          onPressed: _load,
          icon: const Icon(Icons.refresh),
          label: Text(strings.retry),
        ),
      );
    }
    if (_items.isEmpty) {
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
          itemCount: _items.length,
          separatorBuilder: (_, _) =>
              Divider(height: 1, indent: 16 + posterWidth + 14),
          itemBuilder: (context, index) =>
              _MediaTile(item: _items[index], posterWidth: posterWidth),
        );
      },
    );
  }
}

/// A single library row: cover thumbnail, title, year, kind badge and status.
class _MediaTile extends StatelessWidget {
  const _MediaTile({required this.item, required this.posterWidth});

  final MediaItem item;
  final double posterWidth;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final strings = context.strings;
    final year = item.releaseYear;
    final posterHeight = posterWidth * 3 / 2;

    return Padding(
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
                    if (year != null)
                      Text('$year', style: theme.textTheme.bodySmall),
                    Text(
                      strings.statusLabel(item.status),
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: theme.colorScheme.onSurfaceVariant,
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
