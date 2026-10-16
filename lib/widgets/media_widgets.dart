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

/// The two "already tracked" states a search hit can carry.
enum LibraryBadgeKind {
  /// The title is in the library (any status).
  inLibrary,

  /// The title is completed (watched / read).
  watched,
}

/// Compact pill marking a search hit as already tracked / watched.
///
/// Deliberately **distinct** from the neutral media-kind [PillBadge] (Film /
/// Serie / Buch) and the plain year text: *in library* uses the primary
/// container with a `bookmark`, *watched* the tertiary (completion) container
/// with a `check_circle` — the same palette [StatusBadge] uses, so the two
/// features read consistently. The label is passed in already localized.
class LibraryBadge extends StatelessWidget {
  const LibraryBadge({super.key, required this.kind, required this.label});

  final LibraryBadgeKind kind;

  /// Localized badge text (`AppStrings.badgeInLibrary` / `.badgeWatched`).
  final String label;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;

    final (Color background, Color foreground, IconData icon) = switch (kind) {
      LibraryBadgeKind.inLibrary => (
        cs.primaryContainer,
        cs.onPrimaryContainer,
        Icons.bookmark,
      ),
      LibraryBadgeKind.watched => (
        cs.tertiaryContainer,
        cs.onTertiaryContainer,
        Icons.check_circle,
      ),
    };

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
      decoration: BoxDecoration(
        color: background,
        borderRadius: BorderRadius.circular(999),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 12, color: foreground),
          const SizedBox(width: 4),
          Text(
            label,
            style: theme.textTheme.labelSmall?.copyWith(
              color: foreground,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }
}

/// A pill that colour-codes a media item's tracking status.
///
/// The label is passed in already localized (see `AppStrings.statusLabel`).
class StatusBadge extends StatelessWidget {
  const StatusBadge({super.key, required this.status, required this.label});

  final MediaStatus status;

  /// Localized status text.
  final String label;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;

    // A subtle, theme-aware palette per status — planned is neutral, progress
    // is the accent, completed is positive and dropped reads as a warning.
    final (Color background, Color foreground) = switch (status) {
      MediaStatus.planned => (cs.surfaceContainerHighest, cs.onSurfaceVariant),
      MediaStatus.inProgress => (cs.primaryContainer, cs.onPrimaryContainer),
      MediaStatus.completed => (cs.tertiaryContainer, cs.onTertiaryContainer),
      MediaStatus.dropped => (cs.errorContainer, cs.onErrorContainer),
    };

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
      decoration: BoxDecoration(
        color: background,
        borderRadius: BorderRadius.circular(999),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(_icon, size: 12, color: foreground),
          const SizedBox(width: 4),
          Text(
            label,
            style: theme.textTheme.labelSmall?.copyWith(
              color: foreground,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }

  IconData get _icon => switch (status) {
    MediaStatus.planned => Icons.bookmark_border,
    MediaStatus.inProgress => Icons.play_arrow,
    MediaStatus.completed => Icons.check,
    MediaStatus.dropped => Icons.close,
  };
}

/// A network cover image that never throws on a missing / broken URL.
///
/// The **single source of truth** for cover loading in the app: a `null` /
/// empty [url] *and* any image error (bad URL, 404, offline) both hand over to
/// [placeholderBuilder] instead of throwing. [PosterThumbnail] and the category
/// banners (`CategoryBanner`) both build on this, so cover handling can never
/// drift between the two.
///
/// **[cacheWidth]** bounds the decode size: the network bytes are decoded (and
/// held in memory) at most [cacheWidth] physical pixels wide — the height
/// follows from the file's aspect ratio. Without it Flutter decodes every cover
/// at its **full file resolution**, however small it is painted, which is the
/// single biggest scroll-jank source in long lists. Callers should pass roughly
/// **2× the displayed width** (a retina reserve — never more).
///
/// [filterQuality] defaults to [FilterQuality.low]: for the small thumbnails
/// this widget is used for, the cheap resample is indistinguishable on screen
/// but markedly cheaper to raster than `medium`/`high`.
class CoverImage extends StatelessWidget {
  const CoverImage({
    super.key,
    required this.url,
    required this.placeholderBuilder,
    this.fit = BoxFit.cover,
    this.cacheWidth,
    this.filterQuality = FilterQuality.low,
  });

  final String? url;

  /// Rendered when [url] is missing / empty **or** the image fails to load.
  final WidgetBuilder placeholderBuilder;

  final BoxFit fit;

  /// Bounded decode width in physical pixels; `null` keeps the file resolution.
  final int? cacheWidth;

  /// Resample quality — cheap by default (see the class docs).
  final FilterQuality filterQuality;

  @override
  Widget build(BuildContext context) {
    final value = url;
    if (value == null || value.isEmpty) return placeholderBuilder(context);
    return Image.network(
      value,
      fit: fit,
      cacheWidth: cacheWidth,
      filterQuality: filterQuality,
      errorBuilder: (context, _, _) => placeholderBuilder(context),
    );
  }
}

/// A network poster with a kind-specific placeholder.
///
/// Never throws on a missing / broken image: [url] `null` or an image error
/// both render [placeholderIcon] on a muted surface (via [CoverImage]).
class PosterThumbnail extends StatelessWidget {
  const PosterThumbnail({
    super.key,
    required this.url,
    required this.placeholderIcon,
    this.width = 48,
    this.height = 64,
    this.iconSize = 24,
    this.borderRadius = 8,
    this.cacheWidth,
  });

  final String? url;
  final IconData placeholderIcon;
  final double width;
  final double height;
  final double iconSize;
  final double borderRadius;

  /// Optional bounded decode width (physical px). When omitted it is derived
  /// from [width] with a fixed 2× retina reserve, so **every** poster decode is
  /// bounded by default — no call site can accidentally fall back to decoding
  /// the full file. Pass an explicit value only to deviate (e.g. a poster that
  /// is drawn much larger than [width]).
  final int? cacheWidth;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final decodeWidth = cacheWidth ?? (width * 2).round();

    return ClipRRect(
      borderRadius: BorderRadius.circular(borderRadius),
      child: SizedBox(
        width: width,
        height: height,
        child: CoverImage(
          url: url,
          cacheWidth: decodeWidth,
          placeholderBuilder: (_) => _placeholder(cs),
        ),
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
