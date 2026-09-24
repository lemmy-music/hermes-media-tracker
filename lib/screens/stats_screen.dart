import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../l10n/app_strings.dart';
import '../models/episode.dart';
import '../models/media_item.dart';
import '../repositories/media_repository.dart';
import '../services/stats_calculator.dart';
import '../widgets/media_widgets.dart';
import '../widgets/settings_button.dart';

/// Analytics tab — "Phase 5" stats.
///
/// Two blocks:
///
///  * **Overview** (always visible): how many movies/series/books are tracked,
///    the overall status split as a donut, and the completion rate per kind.
///  * **Time-based** (behind the 1 / 6 / 12 / all switch): completions over
///    time (stacked by category), watch time in minutes and pages read.
///
/// All the math lives in [StatsCalculator] (`services/stats_calculator.dart`)
/// so this file only renders. The screen loads its own data (all items plus
/// all episodes) so a plain pull-to-refresh / refresh button always reflects
/// the current library.
class StatsScreen extends StatefulWidget {
  const StatsScreen({super.key, this.clock});

  /// Injectable clock — production uses [DateTime.now]; widget tests pin it so
  /// the relative ranges resolve deterministically.
  final DateTime Function()? clock;

  @override
  State<StatsScreen> createState() => _StatsScreenState();
}

class _StatsScreenState extends State<StatsScreen> {
  late final StatsCalculator _calculator;

  StatsRange _range = StatsRange.defaultRange;

  List<MediaItem> _items = const <MediaItem>[];
  List<Episode> _episodes = const <Episode>[];
  bool _loading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _calculator = StatsCalculator(clock: widget.clock);
    // Deferred so the first load never notifies during build.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      _load();
    });
  }

  Future<void> _load() async {
    final repository = context.read<MediaRepository>();
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final items = await repository.fetchAll();
      final episodes = await repository.fetchAllEpisodes();
      if (!mounted) return;
      setState(() {
        _items = items;
        _episodes = episodes;
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
        title: Text(strings.stats),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            tooltip: strings.refresh,
            onPressed: _loading ? null : _load,
          ),
          const SettingsButton(),
        ],
      ),
      body: _buildBody(context),
    );
  }

  Widget _buildBody(BuildContext context) {
    final strings = context.strings;

    if (_loading) {
      return const Center(child: CircularProgressIndicator());
    }

    final error = _error;
    if (error != null) {
      return CenteredMessage(
        icon: Icons.cloud_off,
        title: strings.statsLoadErrorTitle,
        message: error,
        scrollable: false,
        action: FilledButton.icon(
          onPressed: _load,
          icon: const Icon(Icons.refresh),
          label: Text(strings.retry),
        ),
      );
    }

    final result = _calculator.calculate(
      items: _items,
      episodes: _episodes,
      range: _range,
    );

    if (result.overview.isEmpty) {
      return CenteredMessage(
        icon: Icons.insights,
        title: strings.statsEmptyTitle,
        message: strings.statsEmptyMessage,
        scrollable: false,
      );
    }

    return RefreshIndicator(
      onRefresh: _load,
      child: LayoutBuilder(
        builder: (context, constraints) {
          // Mobile-first: full width on a phone, capped and centered on a
          // wide desktop browser.
          final width = constraints.maxWidth > 760
              ? 760.0
              : constraints.maxWidth;
          return ListView(
            physics: const AlwaysScrollableScrollPhysics(),
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 32),
            children: [
              Center(
                child: ConstrainedBox(
                  constraints: BoxConstraints(maxWidth: width),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      _OverviewCard(overview: result.overview),
                      const SizedBox(height: 16),
                      _TimeBlockCard(
                        result: result,
                        range: _range,
                        onRangeChanged: (next) => setState(() => _range = next),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          );
        },
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// block 1 — overview
// ─────────────────────────────────────────────────────────────────────────────

class _OverviewCard extends StatelessWidget {
  const _OverviewCard({required this.overview});

  final StatsOverview overview;

  @override
  Widget build(BuildContext context) {
    final strings = context.strings;

    return Card(
      margin: EdgeInsets.zero,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _SectionTitle(strings.statsOverview),
            const SizedBox(height: 12),
            Row(
              children: [
                for (final kind in MediaKind.values) ...[
                  Expanded(
                    child: _TypeCountTile(
                      kind: kind,
                      count: overview.countOf(kind),
                    ),
                  ),
                  if (kind != MediaKind.values.last) const SizedBox(width: 8),
                ],
              ],
            ),
            const SizedBox(height: 24),
            _SectionTitle(strings.statsStatusDistribution),
            const SizedBox(height: 16),
            _StatusDistribution(overview: overview),
            const SizedBox(height: 24),
            _SectionTitle(strings.statsCompletionRate),
            const SizedBox(height: 4),
            for (final kind in MediaKind.values)
              _CompletionRateRow(kind: kind, overview: overview),
          ],
        ),
      ),
    );
  }
}

class _SectionTitle extends StatelessWidget {
  const _SectionTitle(this.text);

  final String text;

  @override
  Widget build(BuildContext context) {
    return Text(
      text,
      style: Theme.of(
        context,
      ).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w600),
    );
  }
}

/// Plural display label for a kind ("Movies" / "Series" / "Books").
String _kindPluralLabel(AppStrings strings, MediaKind kind) =>
    strings.kindPluralLabel(kind);

class _TypeCountTile extends StatelessWidget {
  const _TypeCountTile({required this.kind, required this.count});

  final MediaKind kind;
  final int count;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final strings = context.strings;

    return Container(
      padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 8),
      decoration: BoxDecoration(
        color: cs.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(14),
      ),
      child: Column(
        children: [
          Icon(mediaKindIcon(kind), color: cs.primary),
          const SizedBox(height: 6),
          Text(
            strings.number(count),
            style: theme.textTheme.headlineSmall?.copyWith(
              fontWeight: FontWeight.bold,
            ),
          ),
          const SizedBox(height: 2),
          Text(
            _kindPluralLabel(strings, kind),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            textAlign: TextAlign.center,
            style: theme.textTheme.bodySmall?.copyWith(
              color: cs.onSurfaceVariant,
            ),
          ),
        ],
      ),
    );
  }
}

/// Colour code shared by the donut slices and the legend.
Color _statusColor(MediaStatus status, ColorScheme cs) => switch (status) {
  MediaStatus.planned => cs.outline,
  MediaStatus.inProgress => cs.primary,
  MediaStatus.completed => cs.tertiary,
  MediaStatus.dropped => cs.error,
};

/// Donut of the overall status distribution plus a legend.
///
/// It is the *overall* split (the brief allows either); the per-kind
/// breakdown lives right below it as the completion rates.
class _StatusDistribution extends StatelessWidget {
  const _StatusDistribution({required this.overview});

  final StatsOverview overview;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final strings = context.strings;
    final total = overview.total;

    final donut = SizedBox(
      width: 148,
      height: 148,
      child: Stack(
        alignment: Alignment.center,
        children: [
          PieChart(
            PieChartData(
              sectionsSpace: 2,
              centerSpaceRadius: 42,
              startDegreeOffset: -90,
              sections: [
                for (final status in MediaStatus.values)
                  if (overview.statusCount(status) > 0)
                    PieChartSectionData(
                      value: overview.statusCount(status).toDouble(),
                      color: _statusColor(status, cs),
                      radius: 26,
                      showTitle: false,
                    ),
              ],
            ),
          ),
          Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                strings.number(total),
                style: theme.textTheme.titleLarge?.copyWith(
                  fontWeight: FontWeight.bold,
                ),
              ),
              Text(
                strings.library,
                style: theme.textTheme.labelSmall?.copyWith(
                  color: cs.onSurfaceVariant,
                ),
              ),
            ],
          ),
        ],
      ),
    );

    final legend = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        for (final status in MediaStatus.values)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 3),
            child: Row(
              children: [
                Container(
                  width: 12,
                  height: 12,
                  decoration: BoxDecoration(
                    color: _statusColor(status, cs),
                    borderRadius: BorderRadius.circular(3),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    strings.statusLabel(status),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: theme.textTheme.bodyMedium,
                  ),
                ),
                const SizedBox(width: 8),
                Text(
                  strings.number(overview.statusCount(status)),
                  style: theme.textTheme.bodyMedium?.copyWith(
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ),
          ),
      ],
    );

    return LayoutBuilder(
      builder: (context, constraints) {
        // Side by side when there is room; stacked on a narrow phone.
        if (constraints.maxWidth >= 360) {
          return Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              donut,
              const SizedBox(width: 20),
              Expanded(child: legend),
            ],
          );
        }
        return Column(children: [donut, const SizedBox(height: 16), legend]);
      },
    );
  }
}

class _CompletionRateRow extends StatelessWidget {
  const _CompletionRateRow({required this.kind, required this.overview});

  final MediaKind kind;
  final StatsOverview overview;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final strings = context.strings;
    final total = overview.countOf(kind);
    final completed = overview.statusesFor(kind)[MediaStatus.completed] ?? 0;

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        children: [
          Icon(mediaKindIcon(kind), size: 18, color: cs.onSurfaceVariant),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              _kindPluralLabel(strings, kind),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: theme.textTheme.bodyMedium,
            ),
          ),
          Text(
            '$completed/$total',
            style: theme.textTheme.bodySmall?.copyWith(
              color: cs.onSurfaceVariant,
            ),
          ),
          const SizedBox(width: 12),
          SizedBox(
            width: 56,
            child: Text(
              strings.ratePercent(overview.completionRate(kind)),
              textAlign: TextAlign.right,
              style: theme.textTheme.titleSmall?.copyWith(
                fontWeight: FontWeight.bold,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// block 2 — time-based
// ─────────────────────────────────────────────────────────────────────────────

class _TimeBlockCard extends StatelessWidget {
  const _TimeBlockCard({
    required this.result,
    required this.range,
    required this.onRangeChanged,
  });

  final StatsResult result;
  final StatsRange range;
  final ValueChanged<StatsRange> onRangeChanged;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final strings = context.strings;

    return Card(
      margin: EdgeInsets.zero,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: SegmentedButton<StatsRange>(
                segments: [
                  for (final value in StatsRange.values)
                    ButtonSegment<StatsRange>(
                      value: value,
                      label: Text(strings.rangeLabel(value)),
                    ),
                ],
                selected: <StatsRange>{range},
                showSelectedIcon: false,
                onSelectionChanged: (selection) =>
                    onRangeChanged(selection.first),
              ),
            ),
            const SizedBox(height: 20),
            _SectionTitle(strings.statsOverTime),
            const SizedBox(height: 4),
            Text(
              strings.statsOverTimeHint,
              style: theme.textTheme.bodySmall?.copyWith(
                color: cs.onSurfaceVariant,
              ),
            ),
            const SizedBox(height: 12),
            _CompletionsChart(series: result.completions),
            const SizedBox(height: 8),
            Wrap(
              spacing: 16,
              runSpacing: 4,
              children: [
                _LegendEntry(
                  color: cs.primary,
                  label: _kindPluralLabel(strings, MediaKind.movie),
                ),
                _LegendEntry(
                  color: cs.secondary,
                  label: _kindPluralLabel(strings, MediaKind.series),
                ),
                _LegendEntry(
                  color: cs.tertiary,
                  label: _kindPluralLabel(strings, MediaKind.book),
                ),
              ],
            ),
            const SizedBox(height: 24),
            LayoutBuilder(
              builder: (context, constraints) {
                final watch = _MetricTile(
                  title: strings.statsWatchTime,
                  value: result.watchTime.hasData
                      ? strings.watchTime(result.watchTime.totalMinutes)
                      : null,
                  missingValue: strings.statsWatchTimeNoData,
                  subtitle: strings.statsWatchTimeHint,
                );
                final pages = _MetricTile(
                  title: strings.statsPages,
                  value: strings.pagesCount(result.pagesRead),
                  subtitle: strings.statsPagesHint,
                );
                if (constraints.maxWidth >= 420) {
                  return Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Expanded(child: watch),
                      const SizedBox(width: 12),
                      Expanded(child: pages),
                    ],
                  );
                }
                return Column(
                  children: [watch, const SizedBox(height: 12), pages],
                );
              },
            ),
          ],
        ),
      ),
    );
  }
}

class _LegendEntry extends StatelessWidget {
  const _LegendEntry({required this.color, required this.label});

  final Color color;
  final String label;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 12,
          height: 12,
          decoration: BoxDecoration(
            color: color,
            borderRadius: BorderRadius.circular(3),
          ),
        ),
        const SizedBox(width: 6),
        Text(label, style: theme.textTheme.bodySmall),
      ],
    );
  }
}

/// Stacked bar chart of the completions per bucket.
class _CompletionsChart extends StatelessWidget {
  const _CompletionsChart({required this.series});

  final CompletionsSeries series;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final strings = context.strings;
    final buckets = series.buckets;

    // `all` with nothing in the library → no buckets to draw.
    if (buckets.isEmpty || series.isEmpty) {
      return SizedBox(
        height: 160,
        child: Center(
          child: Text(
            strings.statsNoCompletions,
            textAlign: TextAlign.center,
            style: theme.textTheme.bodyMedium?.copyWith(
              color: cs.onSurfaceVariant,
            ),
          ),
        ),
      );
    }

    final movieColor = cs.primary;
    final seriesColor = cs.secondary;
    final bookColor = cs.tertiary;

    final maxTotal = series.maxTotal;
    final maxY = maxTotal <= 0 ? 1.0 : maxTotal.toDouble();
    final leftInterval = (maxY / 4).ceil().clamp(1, 1000).toDouble();
    // Keep at most ~6 labels on the axis so they never overlap on a phone.
    final labelStep = (buckets.length / 6).ceil().clamp(1, buckets.length);

    return SizedBox(
      height: 200,
      child: BarChart(
        BarChartData(
          maxY: maxY,
          minY: 0,
          alignment: BarChartAlignment.spaceAround,
          barTouchData: BarTouchData(enabled: false),
          gridData: FlGridData(
            drawVerticalLine: false,
            horizontalInterval: leftInterval,
            getDrawingHorizontalLine: (_) => FlLine(
              color: cs.outlineVariant.withValues(alpha: 0.4),
              strokeWidth: 1,
            ),
          ),
          borderData: FlBorderData(show: false),
          titlesData: FlTitlesData(
            topTitles: const AxisTitles(
              sideTitles: SideTitles(showTitles: false),
            ),
            rightTitles: const AxisTitles(
              sideTitles: SideTitles(showTitles: false),
            ),
            leftTitles: AxisTitles(
              sideTitles: SideTitles(
                showTitles: true,
                reservedSize: 30,
                interval: leftInterval,
                getTitlesWidget: (value, meta) => Text(
                  value.toInt().toString(),
                  style: theme.textTheme.labelSmall?.copyWith(
                    color: cs.onSurfaceVariant,
                  ),
                ),
              ),
            ),
            bottomTitles: AxisTitles(
              sideTitles: SideTitles(
                showTitles: true,
                reservedSize: 30,
                interval: labelStep.toDouble(),
                getTitlesWidget: (value, meta) {
                  final index = value.toInt();
                  if (index < 0 || index >= buckets.length) {
                    return const SizedBox.shrink();
                  }
                  return Padding(
                    padding: const EdgeInsets.only(top: 6),
                    child: Text(
                      _bucketLabel(buckets[index], strings),
                      style: theme.textTheme.labelSmall?.copyWith(
                        color: cs.onSurfaceVariant,
                      ),
                    ),
                  );
                },
              ),
            ),
          ),
          barGroups: [
            for (var i = 0; i < buckets.length; i++)
              _barGroup(
                index: i,
                bucket: buckets[i],
                movieColor: movieColor,
                seriesColor: seriesColor,
                bookColor: bookColor,
              ),
          ],
        ),
      ),
    );
  }

  String _bucketLabel(StatsBucket bucket, AppStrings strings) {
    if (bucket.granularity == BucketGranularity.year) {
      return '${bucket.start.year}';
    }
    final shortYear = bucket.start.year % 100;
    return '${strings.monthShort(bucket.start.month)} $shortYear';
  }

  BarChartGroupData _barGroup({
    required int index,
    required StatsBucket bucket,
    required Color movieColor,
    required Color seriesColor,
    required Color bookColor,
  }) {
    final stack = <BarChartRodStackItem>[];
    var from = 0.0;
    if (bucket.movies > 0) {
      stack.add(BarChartRodStackItem(from, from + bucket.movies, movieColor));
      from += bucket.movies;
    }
    if (bucket.books > 0) {
      stack.add(BarChartRodStackItem(from, from + bucket.books, bookColor));
      from += bucket.books;
    }
    if (bucket.episodes > 0) {
      stack.add(
        BarChartRodStackItem(from, from + bucket.episodes, seriesColor),
      );
      from += bucket.episodes;
    }

    return BarChartGroupData(
      x: index,
      barRods: [
        BarChartRodData(
          toY: bucket.total.toDouble(),
          width: 14,
          borderRadius: BorderRadius.circular(3),
          color: Colors.transparent,
          rodStackItems: stack,
        ),
      ],
    );
  }
}

/// One metric: a title, a prominent value (or a "no data" hint) and a caption.
class _MetricTile extends StatelessWidget {
  const _MetricTile({
    required this.title,
    required this.value,
    required this.subtitle,
    this.missingValue,
  });

  final String title;

  /// The formatted value, or `null` when there is nothing to show.
  final String? value;

  /// Shown in place of [value] when it is `null`.
  final String? missingValue;

  final String subtitle;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final shown = value;

    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: cs.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(14),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title,
            style: theme.textTheme.labelLarge?.copyWith(
              color: cs.onSurfaceVariant,
            ),
          ),
          const SizedBox(height: 6),
          if (shown != null)
            Text(
              shown,
              style: theme.textTheme.headlineSmall?.copyWith(
                fontWeight: FontWeight.bold,
              ),
            )
          else
            Text(
              missingValue ?? '',
              style: theme.textTheme.bodyMedium?.copyWith(
                color: cs.onSurfaceVariant,
              ),
            ),
          const SizedBox(height: 6),
          Text(
            subtitle,
            style: theme.textTheme.bodySmall?.copyWith(
              color: cs.onSurfaceVariant,
            ),
          ),
        ],
      ),
    );
  }
}
