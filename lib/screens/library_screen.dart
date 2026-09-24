import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

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
      body: RefreshIndicator(onRefresh: _load, child: _buildBody(context)),
    );
  }

  Widget _buildBody(BuildContext context) {
    if (_loading && _items.isEmpty) {
      return const Center(child: CircularProgressIndicator());
    }
    final error = _error;
    if (error != null) {
      return CenteredMessage(
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
      return const CenteredMessage(
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
      leading: PosterThumbnail(
        url: item.posterUrl,
        placeholderIcon: mediaKindIcon(item.kind),
      ),
      title: Text(item.title, maxLines: 1, overflow: TextOverflow.ellipsis),
      subtitle: Padding(
        padding: const EdgeInsets.only(top: 4),
        child: Wrap(
          spacing: 8,
          runSpacing: 4,
          crossAxisAlignment: WrapCrossAlignment.center,
          children: [
            PillBadge(icon: mediaKindIcon(item.kind), label: item.kind.label),
            if (year != null)
              Text('$year', style: Theme.of(context).textTheme.bodySmall),
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
