import 'package:flutter/material.dart';

import '../models/media_item.dart';
import '../models/tmdb_result.dart';

/// Canonical icon for a [MediaKind].
IconData mediaKindIcon(MediaKind kind) => switch (kind) {
  MediaKind.movie => Icons.movie_outlined,
  MediaKind.series => Icons.tv_outlined,
  MediaKind.book => Icons.menu_book_outlined,
};

/// Canonical icon for a [TmdbMediaType].
IconData tmdbTypeIcon(TmdbMediaType type) => switch (type) {
  TmdbMediaType.movie => Icons.movie_outlined,
  TmdbMediaType.tv => Icons.tv_outlined,
};

/// Compact pill with a leading icon and a label.
///
/// Used for the media-kind badge in both the library and the search results.
class PillBadge extends StatelessWidget {
  const PillBadge({super.key, required this.icon, required this.label});

  final IconData icon;
  final String label;

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
          Icon(icon, size: 12, color: cs.onSecondaryContainer),
          const SizedBox(width: 4),
          Text(
            label,
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

/// A network poster with a kind-specific placeholder.
///
/// Never throws on a missing / broken image: [url] `null` or an image error
/// both render [placeholderIcon] on a muted surface.
class PosterThumbnail extends StatelessWidget {
  const PosterThumbnail({
    super.key,
    required this.url,
    required this.placeholderIcon,
    this.width = 48,
    this.height = 64,
    this.iconSize = 24,
    this.borderRadius = 8,
  });

  final String? url;
  final IconData placeholderIcon;
  final double width;
  final double height;
  final double iconSize;
  final double borderRadius;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final hasUrl = url != null && url!.isNotEmpty;

    return ClipRRect(
      borderRadius: BorderRadius.circular(borderRadius),
      child: SizedBox(
        width: width,
        height: height,
        child: hasUrl
            ? Image.network(
                url!,
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
      child: Icon(placeholderIcon, color: cs.onSurfaceVariant, size: iconSize),
    );
  }
}

/// Empty / error placeholder that optionally supports pull-to-refresh.
class CenteredMessage extends StatelessWidget {
  const CenteredMessage({
    super.key,
    required this.icon,
    required this.title,
    required this.message,
    this.action,
    this.scrollable = true,
  });

  final IconData icon;
  final String title;
  final String message;
  final Widget? action;

  /// When `true` the content is wrapped so a pull-to-refresh still works.
  final bool scrollable;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;

    final content = Padding(
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
            style: theme.textTheme.bodyMedium?.copyWith(
              color: cs.onSurfaceVariant,
            ),
            textAlign: TextAlign.center,
          ),
          if (action != null) ...[const SizedBox(height: 20), action!],
        ],
      ),
    );

    if (!scrollable) return Center(child: content);

    return LayoutBuilder(
      builder: (context, constraints) => SingleChildScrollView(
        physics: const AlwaysScrollableScrollPhysics(),
        child: ConstrainedBox(
          constraints: BoxConstraints(minHeight: constraints.maxHeight),
          child: Center(child: content),
        ),
      ),
    );
  }
}
