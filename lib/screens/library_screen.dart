import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../models/media_item.dart';
import '../repositories/media_repository.dart';
import '../widgets/settings_button.dart';

/// Library tab — lists everything the signed-in user tracks.
///
/// Detail and tracking UI arrive in Phase 3; this is a read-only list with
/// loading / empty / error states and manual refresh.
class LibraryScreen extends StatefulWidget {
  const LibraryScreen({super.key});

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
    return Scaffold(
      appBar: AppBar(
        title: const Text('Library'),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            tooltip: 'Refresh',
            onPressed: _loading ? null : _load,
          ),
          const SettingsButton(),
        ],
      ),
      body: RefreshIndicator(
        onRefresh: _load,
        child: _buildBody(context),
      ),
    );
  }

  Widget _buildBody(BuildContext context) {
    if (_loading && _items.isEmpty) {
      return const Center(child: CircularProgressIndicator());
    }
    final error = _error;
    if (error != null) {
      return _CenteredMessage(
        icon: Icons.cloud_off,
        title: 'Could not load your library',
        message: error,
        action: FilledButton.icon(
          onPressed: _load,
          icon: const Icon(Icons.refresh),
          label: const Text('Retry'),
        ),
      );
    }
    if (_items.isEmpty) {
      return const _CenteredMessage(
        icon: Icons.video_library_outlined,
        title: 'Your library is empty',
        message: 'Movies, series and books you track will show up here.',
      );
    }
    return ListView.separated(
      physics: const AlwaysScrollableScrollPhysics(),
      padding: const EdgeInsets.symmetric(vertical: 8),
      itemCount: _items.length,
      separatorBuilder: (_, _) => const Divider(height: 1, indent: 80),
      itemBuilder: (context, index) => _MediaTile(item: _items[index]),
    );
  }
}

/// A single library row: cover thumbnail, title, year, kind badge and status.
class _MediaTile extends StatelessWidget {
  const _MediaTile({required this.item});

  final MediaItem item;

  @override
  Widget build(BuildContext context) {
    final year = item.releaseYear;

    return ListTile(
      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
      leading: _Cover(item: item),
      title: Text(
        item.title,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
      ),
      subtitle: Padding(
        padding: const EdgeInsets.only(top: 4),
        child: Wrap(
          spacing: 8,
          runSpacing: 4,
          crossAxisAlignment: WrapCrossAlignment.center,
          children: [
            _KindBadge(kind: item.kind),
            if (year != null)
              Text(
                '$year',
                style: Theme.of(context).textTheme.bodySmall,
              ),
            Text(
              item.status.label,
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: Theme.of(context).colorScheme.onSurfaceVariant,
                  ),
            ),
          ],
        ),
      ),
    );
  }
}

/// 48×64 poster thumbnail, falling back to a kind icon.
class _Cover extends StatelessWidget {
  const _Cover({required this.item});

  final MediaItem item;

  static const double _width = 48;
  static const double _height = 64;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;

    return ClipRRect(
      borderRadius: BorderRadius.circular(8),
      child: SizedBox(
        width: _width,
        height: _height,
        child: item.hasPoster
            ? Image.network(
                item.posterUrl!,
                fit: BoxFit.cover,
                errorBuilder: (_, _, _) => _placeholder(cs),
              )
            : _placeholder(cs),
      ),
    );
  }

  Widget _placeholder(ColorScheme cs) {
    return ColoredBox(
      color: cs.surfaceContainerHighest,
      child: Icon(
        _iconForKind(item.kind),
        color: cs.onSurfaceVariant,
        size: 24,
      ),
    );
  }
}

/// Compact pill showing the media kind.
class _KindBadge extends StatelessWidget {
  const _KindBadge({required this.kind});

  final MediaKind kind;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
      decoration: BoxDecoration(
        color: cs.secondaryContainer,
        borderRadius: BorderRadius.circular(999),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(_iconForKind(kind), size: 12, color: cs.onSecondaryContainer),
          const SizedBox(width: 4),
          Text(
            kind.label,
            style: theme.textTheme.labelSmall?.copyWith(
              color: cs.onSecondaryContainer,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }
}

/// Empty / error placeholder that still supports pull-to-refresh.
class _CenteredMessage extends StatelessWidget {
  const _CenteredMessage({
    required this.icon,
    required this.title,
    required this.message,
    this.action,
  });

  final IconData icon;
  final String title;
  final String message;
  final Widget? action;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;

    return LayoutBuilder(
      builder: (context, constraints) => SingleChildScrollView(
        physics: const AlwaysScrollableScrollPhysics(),
        child: ConstrainedBox(
          constraints: BoxConstraints(minHeight: constraints.maxHeight),
          child: Center(
            child: Padding(
              padding: const EdgeInsets.all(24),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(icon, size: 64, color: cs.primary),
                  const SizedBox(height: 16),
                  Text(
                    title,
                    style: theme.textTheme.titleMedium,
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: 8),
                  Text(
                    message,
                    style: theme.textTheme.bodyMedium
                        ?.copyWith(color: cs.onSurfaceVariant),
                    textAlign: TextAlign.center,
                  ),
                  if (action != null) ...[
                    const SizedBox(height: 20),
                    action!,
                  ],
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

IconData _iconForKind(MediaKind kind) => switch (kind) {
      MediaKind.movie => Icons.movie_outlined,
      MediaKind.series => Icons.tv_outlined,
      MediaKind.book => Icons.menu_book_outlined,
    };
