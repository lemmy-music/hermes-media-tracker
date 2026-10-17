import 'package:flutter/material.dart';

import '../services/library_filter.dart';
import 'media_widgets.dart';

/// A tall, premium category banner for the library landing screen.
///
/// Replaces the old small tile: a full-width card (~156 logical px; one column
/// on phones, two from 600 px) whose background is a calm theme gradient, with
/// the category's newest cover and one or two older covers *fanned* on the
/// right — decorative, offset up and to the right, tilted and dimmed — and a
/// dark→transparent scrim carrying the white category label, the count and a
/// subtle kind icon.
///
/// The gradient is the whole background on purpose: an earlier version laid a
/// blurred, full-bleed copy of the newest cover behind the fan, but a Gaussian
/// blur over the full card is re-rastered on every repaint and measurably cost
/// frames while scrolling the library. The theme gradient looks the same at a
/// fraction of the cost.
///
/// A category without any cover (typically OpenLibrary books) renders the very
/// same layout over a calm theme gradient instead — never a broken or empty
/// card. All cover loading goes through the app's shared [CoverImage], so a
/// missing / broken URL simply falls back and can never throw.
///
/// The whole card is the tap target: tapping it opens the reused library list
/// preselected to the category (see `LibraryScreen`).
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

/// Background layer: the theme gradient, plus — when a cover exists — the
/// fanned deck of covers on the right (otherwise a large kind icon).
class _Background extends StatelessWidget {
  const _Background({required this.artwork, required this.icon});

  final CategoryArtwork artwork;
  final IconData icon;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;

    return Stack(
      fit: StackFit.expand,
      children: [
        DecoratedBox(
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [cs.primary, cs.primaryContainer],
            ),
          ),
        ),
        if (!artwork.hasCover)
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
          )
        else
          Align(
            alignment: Alignment.centerRight,
            child: _FanDeck(artwork: artwork),
          ),
      ],
    );
  }
}

/// The static fan: the hero cover in front, with one or two older covers
/// behind it, each offset up / to the right, slightly tilted and dimmed.
///
/// Deliberately static — no animation. Cards are taller than the banner, so
/// their edges bleed off the top / bottom and are trimmed by the banner's
/// [ClipRRect].
class _FanDeck extends StatelessWidget {
  const _FanDeck({required this.artwork});

  static const double _cardWidth = 104;
  static const double _cardHeight = 176;
  static const double _deckWidth = 148;

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
    // Behind-cards are dimmed and pushed right + up, so only their top / right
    // edges peek past the crisp hero; the banner clips whatever leaves the box.
    // The dim is a plain black overlay *inside* the rounded clip — same pixels
    // as a darken colour filter, without a save-layer per card.
    final dim = depth == 0 ? 0.0 : (depth == 1 ? 0.35 : 0.55);

    final card = ClipRRect(
      borderRadius: BorderRadius.circular(12),
      child: SizedBox(
        width: _cardWidth,
        height: _cardHeight,
        child: Stack(
          fit: StackFit.expand,
          children: [
            CoverImage(
              url: url,
              placeholderBuilder: (_) => const SizedBox.shrink(),
            ),
            if (dim > 0) ColoredBox(color: Colors.black.withValues(alpha: dim)),
          ],
        ),
      ),
    );

    return Positioned(
      right: -depth * 14.0,
      bottom: depth * 10.0,
      child: Transform.rotate(angle: depth * 0.08, child: card),
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
