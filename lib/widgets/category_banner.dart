import 'package:flutter/material.dart';

import '../services/library_filter.dart';
import 'media_widgets.dart';

/// A tall, premium category banner for the library landing screen.
///
/// Replaces the old small tile: a full-width card (~156 logical px; one column
/// on phones, two from 600 px) whose background is built from the category's
/// newest cover, with one or two older covers *fanned behind* it — decorative,
/// offset up and to the right, tilted and dimmed — and a dark→transparent scrim
/// carrying the white category label, the count and a subtle kind icon.
///
/// A category without any cover (typically OpenLibrary books) renders the very
/// same layout over a calm theme gradient instead — never a broken or empty
/// card. All cover loading goes through the app's shared [CoverImage], so a
/// missing / broken URL simply falls back and can never throw.
///
/// The whole card is the tap target: tapping it opens the reused library list
/// preselected to the category (see `LibraryScreen`).
///
/// **Performance:** the atmospheric background is *not* a blur. A real
/// `ImageFilter.blur` full-bleed on the hero is GPU-heavy (especially with
/// CanvasKit on mobile browsers), so the same cover is instead loaded at a tiny
/// decode size ([cacheWidth] 64) and stretched to fill with `BoxFit.cover` +
/// [FilterQuality.low] — an upscaled thumbnail looks softly blurred for free.
class CategoryBanner extends StatelessWidget {
  const CategoryBanner({
    super.key,
    required this.label,
    required this.countLabel,
    required this.icon,
    required this.artwork,
    required this.onTap,
  });

  /// Banner height in logical pixels (design range ~140–170).
  static const double height = 156;

  static const double _radius = 16;
  static const double _padding = 16;

  /// Reserved width on the right so the label never runs under the fan deck.
  static const double _deckReserve = 112;

  final String label;
  final String countLabel;
  final IconData icon;
  final CategoryArtwork artwork;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;

    return SizedBox(
      height: height,
      child: ClipRRect(
        borderRadius: BorderRadius.circular(_radius),
        child: Material(
          color: Colors.transparent,
          child: Stack(
            fit: StackFit.expand,
            children: [
              _Background(artwork: artwork, icon: icon),
              const Positioned.fill(child: _Scrim()),
              // InkWell last so its ripple paints above the artwork.
              InkWell(
                onTap: onTap,
                child: Padding(
                  padding: const EdgeInsets.all(_padding),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Expanded(child: _content(theme, cs)),
                      if (artwork.hasCover) const SizedBox(width: _deckReserve),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _content(ThemeData theme, ColorScheme cs) {
    final labelStyle = theme.textTheme.titleLarge?.copyWith(
      color: Colors.white,
      fontWeight: FontWeight.w700,
      height: 1.1,
      shadows: const [Shadow(color: Colors.black54, blurRadius: 6)],
    );
    final countStyle = theme.textTheme.titleSmall?.copyWith(
      color: Colors.white.withValues(alpha: 0.9),
      fontWeight: FontWeight.w600,
    );

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Align(
          alignment: Alignment.topLeft,
          child: Container(
            padding: const EdgeInsets.all(6),
            decoration: BoxDecoration(
              color: Colors.white.withValues(alpha: 0.18),
              shape: BoxShape.circle,
            ),
            child: Icon(icon, size: 20, color: Colors.white),
          ),
        ),
        Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: labelStyle,
            ),
            const SizedBox(height: 2),
            Text(
              countLabel,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: countStyle,
            ),
          ],
        ),
      ],
    );
  }
}

/// Background layer: theme gradient, plus — when a cover exists — a dimmed,
/// softly-blurred-looking (but free: tiny decode upscaled) full-bleed hero and
/// the fanned deck of covers on the right.
class _Background extends StatelessWidget {
  const _Background({required this.artwork, required this.icon});

  final CategoryArtwork artwork;
  final IconData icon;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final gradient = BoxDecoration(
      gradient: LinearGradient(
        begin: Alignment.topLeft,
        end: Alignment.bottomRight,
        colors: [cs.primary, cs.primaryContainer],
      ),
    );

    if (!artwork.hasCover) {
      return Stack(
        fit: StackFit.expand,
        children: [
          DecoratedBox(decoration: gradient),
          Align(
            alignment: Alignment.centerRight,
            child: Padding(
              padding: const EdgeInsets.only(right: 28),
              child: Icon(
                icon,
                size: 96,
                color: cs.onPrimary.withValues(alpha: 0.22),
              ),
            ),
          ),
        ],
      );
    }

    return Stack(
      fit: StackFit.expand,
      children: [
        DecoratedBox(decoration: gradient),
        // The newest cover as the atmospheric background. Deliberately *not*
        // blurred: decoding it at 64 px and stretching it to full-bleed with a
        // cheap resample gives the same soft look with no GPU filter cost.
        Positioned.fill(
          child: ColorFiltered(
            colorFilter: ColorFilter.mode(
              Colors.black.withValues(alpha: 0.45),
              BlendMode.darken,
            ),
            child: CoverImage(
              url: artwork.heroUrl,
              cacheWidth: 64,
              filterQuality: FilterQuality.low,
              placeholderBuilder: (_) => const SizedBox.shrink(),
            ),
          ),
        ),
        Align(
          alignment: Alignment.centerRight,
          child: _FanDeck(artwork: artwork),
        ),
      ],
    );
  }
}

/// The static fan: the hero cover in front, with one or two older covers
/// behind it, each offset up / to the right, tilted and dimmed.
///
/// Deliberately static — no animation, no GPU filters. The layers are
/// separated by **position, rotation, a thin bright rim and a faint light
/// wash**, so the stack reads unmistakably as a fanned deck while staying pure
/// paint work (no blur/shader filters, no opacity save-layers). Cards are
/// taller than the banner, so their edges bleed off the top / bottom and are
/// trimmed by the banner's [ClipRRect].
class _FanDeck extends StatelessWidget {
  const _FanDeck({required this.artwork});

  static const double _cardWidth = 104;
  static const double _cardHeight = 176;
  static const double _deckWidth = 156;

  final CategoryArtwork artwork;

  @override
  Widget build(BuildContext context) {
    final layers = artwork.layerUrls;
    return SizedBox(
      width: _deckWidth,
      height: _cardHeight,
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          // Furthest layers first so the hero ends up on top.
          for (var i = layers.length - 1; i >= 0; i--)
            _card(url: layers[i], depth: i + 1),
          _card(url: artwork.heroUrl, depth: 0),
        ],
      ),
    );
  }

  Widget _card({required String? url, required int depth}) {
    final radius = BorderRadius.circular(12);
    final image = CoverImage(
      url: url,
      cacheWidth: 208, // 2× the 104 px deck card
      placeholderBuilder: (_) => const SizedBox.shrink(),
    );

    // The crisp hero, front and centred.
    if (depth == 0) {
      return Positioned(
        right: 0,
        bottom: 0,
        child: ClipRRect(
          borderRadius: radius,
          child: SizedBox(width: _cardWidth, height: _cardHeight, child: image),
        ),
      );
    }

    // Behind-cards: pushed further right + up and tilted harder, so the stack
    // clearly reads as a *fan*. The thin bright rim + faint light wash keep
    // each layer's edge legible behind the front card.
    return Positioned(
      right: -depth * 16.0,
      bottom: depth * 14.0,
      child: Transform.rotate(
        angle: depth * 0.12,
        child: SizedBox(
          width: _cardWidth,
          height: _cardHeight,
          child: Stack(
            fit: StackFit.expand,
            children: [
              ClipRRect(
                borderRadius: radius,
                child: ColorFiltered(
                  colorFilter: ColorFilter.mode(
                    Colors.black.withValues(alpha: depth == 1 ? 0.30 : 0.48),
                    BlendMode.darken,
                  ),
                  child: image,
                ),
              ),
              // Light wash (cheap blended fill, not an opacity layer) + bright
              // rim drawn on top so the stacked edge stays visible.
              DecoratedBox(
                decoration: BoxDecoration(
                  color: Colors.white.withValues(
                    alpha: depth == 1 ? 0.06 : 0.10,
                  ),
                  borderRadius: radius,
                  border: Border.all(
                    color: Colors.white.withValues(alpha: 0.65),
                    width: 1.5,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Bottom-heavy dark gradient so the white label / count stay readable on any
/// cover.
class _Scrim extends StatelessWidget {
  const _Scrim();

  @override
  Widget build(BuildContext context) {
    return const DecoratedBox(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.bottomCenter,
          end: Alignment.topCenter,
          colors: [
            Color(0xB8000000), // 72% black at the text baseline…
            Color(0x40000000), // …fading through
            Color(0x0F000000), // …to a light wash at the top.
          ],
          stops: [0.0, 0.55, 1.0],
        ),
      ),
    );
  }
}
