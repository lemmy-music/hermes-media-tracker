import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../l10n/app_strings.dart';
import '../models/media_item.dart';
import '../providers/library_provider.dart';
import '../repositories/media_repository.dart';
import '../widgets/media_widgets.dart';

/// Full-page detail **and** tracking view for a library entry.
///
/// Phase 3a covers **movies and books**: a percent slider for movies,
/// page-based progress (with a percent fallback) for books, the four statuses
/// and manually editable start / finish timestamps.
///
/// Series entries are shown too, but deliberately without tracking controls —
/// episode tracking lands in Phase 3b, so a notice is displayed instead. The
/// screen never crashes on missing metadata (no cover, description, page count
/// or timestamp).
///
/// Every change is persisted immediately (no save button); failures surface as
/// a snack bar.
class MediaDetailScreen extends StatelessWidget {
  const MediaDetailScreen({super.key, required this.item});

  /// The item as the caller knows it. The screen resolves the live copy from
  /// [LibraryProvider] by id so it always reflects the latest state.
  final MediaItem item;

  // Keys used by the widget tests.
  static const Key deleteButtonKey = Key('media-detail-delete');
  static const Key percentSliderKey = Key('media-detail-percent-slider');
  static const Key pageSliderKey = Key('media-detail-page-slider');
  static const Key pageFieldKey = Key('media-detail-page-field');
  static const Key savePageButtonKey = Key('media-detail-save-page');
  static const Key totalPagesFieldKey = Key('media-detail-total-pages');
  static const Key saveTotalPagesButtonKey = Key(
    'media-detail-save-total-pages',
  );
  static const Key editStartedAtKey = Key('media-detail-edit-started');
  static const Key editCompletedAtKey = Key('media-detail-edit-completed');

  @override
  Widget build(BuildContext context) {
    final library = context.watch<LibraryProvider>();
    final live = library.itemById(item.id) ?? item;
    final strings = context.strings;

    return Scaffold(
      appBar: AppBar(
        title: Text(strings.kindLabel(live.kind)),
        actions: [
          IconButton(
            key: deleteButtonKey,
            icon: const Icon(Icons.delete_outline),
            tooltip: strings.deleteItem,
            onPressed: () => _confirmDelete(context, live),
          ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.only(bottom: 32),
        children: [
          _Header(item: live),
          const Divider(height: 1),
          if (live.kind == MediaKind.series)
            const _SeriesNotice()
          else
            _TrackingSection(item: live),
        ],
      ),
    );
  }

  /// Asks for confirmation, then removes the item and pops back to the list.
  Future<void> _confirmDelete(BuildContext context, MediaItem item) async {
    final strings = AppStrings.read(context);
    final library = context.read<LibraryProvider>();
    final messenger = ScaffoldMessenger.of(context);
    final navigator = Navigator.of(context);

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text(strings.deleteConfirmTitle),
        content: Text(strings.deleteConfirmMessage(item.title)),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: Text(strings.cancel),
          ),
          FilledButton(
            onPressed: () => Navigator.of(dialogContext).pop(true),
            child: Text(strings.delete),
          ),
        ],
      ),
    );
    if (confirmed != true) return;

    try {
      await library.deleteItem(item);
      messenger.showSnackBar(SnackBar(content: Text(strings.itemDeleted)));
      if (navigator.canPop()) navigator.pop();
    } on MediaRepositoryException catch (error) {
      messenger.showSnackBar(SnackBar(content: Text(error.message)));
    }
  }
}

/// Big cover, title, badges, year / pages, authors and the description.
class _Header extends StatelessWidget {
  const _Header({required this.item});

  final MediaItem item;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final strings = context.strings;
    final year = item.releaseYear;
    final description = item.overview;
    final totalPages = item.totalPages;

    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Center(
            child: PosterThumbnail(
              url: item.posterUrl,
              placeholderIcon: mediaKindIcon(item.kind),
              width: 180,
              height: 270,
              iconSize: 64,
              borderRadius: 14,
            ),
          ),
          const SizedBox(height: 16),
          Text(
            item.title,
            textAlign: TextAlign.center,
            style: theme.textTheme.headlineSmall?.copyWith(
              fontWeight: FontWeight.bold,
            ),
          ),
          const SizedBox(height: 10),
          Wrap(
            alignment: WrapAlignment.center,
            spacing: 8,
            runSpacing: 6,
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
                Text(
                  '$year',
                  style: theme.textTheme.bodyMedium?.copyWith(
                    color: cs.onSurfaceVariant,
                  ),
                ),
              if (item.kind == MediaKind.book && totalPages != null)
                Text(
                  strings.pages(totalPages),
                  style: theme.textTheme.bodyMedium?.copyWith(
                    color: cs.onSurfaceVariant,
                  ),
                ),
            ],
          ),
          if (item.kind == MediaKind.book && item.authors.isNotEmpty) ...[
            const SizedBox(height: 12),
            Text(
              strings.byAuthors(item.authors.join(', ')),
              textAlign: TextAlign.center,
              style: theme.textTheme.bodyMedium?.copyWith(
                color: cs.onSurfaceVariant,
              ),
            ),
          ],
          const SizedBox(height: 16),
          Text(
            description == null || description.isEmpty
                ? strings.noDescription
                : description,
            style: theme.textTheme.bodyMedium,
          ),
        ],
      ),
    );
  }
}

/// Shown instead of the tracking controls for series (Phase 3b).
class _SeriesNotice extends StatelessWidget {
  const _SeriesNotice();

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final strings = context.strings;

    return Padding(
      padding: const EdgeInsets.all(16),
      child: Card(
        color: cs.secondaryContainer,
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(Icons.tv_outlined, color: cs.onSecondaryContainer),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      strings.seriesTrackingTitle,
                      style: theme.textTheme.titleMedium?.copyWith(
                        color: cs.onSecondaryContainer,
                      ),
                    ),
                    const SizedBox(height: 6),
                    Text(
                      strings.seriesTrackingMessage,
                      style: theme.textTheme.bodyMedium?.copyWith(
                        color: cs.onSecondaryContainer,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Status, progress and timestamps of a movie or a book.
class _TrackingSection extends StatefulWidget {
  const _TrackingSection({required this.item});

  final MediaItem item;

  @override
  State<_TrackingSection> createState() => _TrackingSectionState();
}

class _TrackingSectionState extends State<_TrackingSection> {
  /// Draft value of the percent slider while the user drags it. `null` means
  /// "use the stored value".
  double? _percentDraft;

  /// Draft value of the page slider while the user drags it.
  double? _pageDraft;

  final TextEditingController _pageController = TextEditingController();
  final TextEditingController _totalPagesController = TextEditingController();
  final FocusNode _pageFocus = FocusNode();
  final FocusNode _totalPagesFocus = FocusNode();

  MediaItem get item => widget.item;

  @override
  void initState() {
    super.initState();
    _syncControllers();
  }

  @override
  void didUpdateWidget(covariant _TrackingSection oldWidget) {
    super.didUpdateWidget(oldWidget);
    _syncControllers();
  }

  /// Keeps the text fields in sync with the stored values — but never while the
  /// user is typing in them.
  void _syncControllers() {
    if (!_pageFocus.hasFocus) {
      _pageController.text = _pageText();
    }
    if (!_totalPagesFocus.hasFocus) {
      final total = item.totalPages;
      _totalPagesController.text = total == null ? '' : '$total';
    }
  }

  String _pageText() {
    final current = item.progressCurrent;
    return current == null ? '' : '$current';
  }

  @override
  void dispose() {
    _pageController.dispose();
    _totalPagesController.dispose();
    _pageFocus.dispose();
    _totalPagesFocus.dispose();
    super.dispose();
  }

  // ── mutations ──────────────────────────────────────────────────────────────

  /// Runs a persistence action, surfacing any failure as a snack bar.
  Future<void> _run(Future<void> Function() action) async {
    final messenger = ScaffoldMessenger.of(context);
    final strings = AppStrings.read(context);
    try {
      await action();
    } on MediaRepositoryException catch (error) {
      messenger.showSnackBar(SnackBar(content: Text(error.message)));
    } catch (_) {
      messenger.showSnackBar(
        SnackBar(content: Text(strings.trackingSaveError)),
      );
    }
  }

  Future<void> _setStatus(MediaStatus status) {
    if (status == item.status) return Future<void>.value();
    return _run(() => context.read<LibraryProvider>().setStatus(item, status));
  }

  Future<void> _savePercent(double percent) => _run(
    () => context.read<LibraryProvider>().setProgressPercent(item, percent),
  );

  Future<void> _savePage(int? page) async {
    if (page == null || page < 0) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(AppStrings.read(context).invalidPage)),
      );
      return;
    }
    await _run(
      () => context.read<LibraryProvider>().setProgressPage(item, page),
    );
  }

  Future<void> _saveTotalPages(String raw) async {
    final trimmed = raw.trim();
    if (trimmed.isEmpty) {
      await _run(
        () => context.read<LibraryProvider>().setTotalPages(item, null),
      );
      return;
    }
    final value = int.tryParse(trimmed);
    if (value == null || value <= 0) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(AppStrings.read(context).invalidPage)),
      );
      return;
    }
    await _run(
      () => context.read<LibraryProvider>().setTotalPages(item, value),
    );
  }

  Future<void> _editTimestamp(
    DateTime? initial,
    Future<void> Function(DateTime?) apply,
  ) async {
    final picked = await _pickDateTime(context, initial);
    if (picked == null || !mounted) return;
    await apply(picked);
  }

  /// Date **and** time so a back-dated entry can carry the actual moment.
  Future<DateTime?> _pickDateTime(
    BuildContext context,
    DateTime? initial,
  ) async {
    final now = DateTime.now();
    final date = await showDatePicker(
      context: context,
      initialDate: initial ?? now,
      firstDate: DateTime(1900),
      lastDate: DateTime(now.year + 1, 12, 31),
    );
    if (date == null || !context.mounted) return null;
    final time = await showTimePicker(
      context: context,
      initialTime: initial == null
          ? TimeOfDay.now()
          : TimeOfDay.fromDateTime(initial.toLocal()),
    );
    if (time == null) return null;
    return DateTime(date.year, date.month, date.day, time.hour, time.minute);
  }

  String _formatDateTime(BuildContext context, DateTime value) {
    final local = value.toLocal();
    final localizations = MaterialLocalizations.of(context);
    final date = localizations.formatMediumDate(local);
    final time = localizations.formatTimeOfDay(TimeOfDay.fromDateTime(local));
    return '$date, $time';
  }

  // ── build ──────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final strings = context.strings;

    return Padding(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(strings.trackingSection, style: theme.textTheme.titleLarge),
          const SizedBox(height: 12),
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: SegmentedButton<MediaStatus>(
              segments: [
                for (final status in MediaStatus.values)
                  ButtonSegment<MediaStatus>(
                    value: status,
                    label: Text(strings.statusLabel(status)),
                  ),
              ],
              selected: <MediaStatus>{item.status},
              showSelectedIcon: false,
              onSelectionChanged: (selection) => _setStatus(selection.first),
            ),
          ),
          const SizedBox(height: 20),
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: _progressCard(context),
              ),
            ),
          ),
          if (item.kind == MediaKind.book) ...[
            const SizedBox(height: 12),
            _totalPagesRow(context),
          ],
          const SizedBox(height: 20),
          Text(
            strings.startedAt,
            style: theme.textTheme.labelMedium?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
          _timestampRow(
            context,
            value: item.startedAt,
            editKey: MediaDetailScreen.editStartedAtKey,
            apply: (value) => _run(
              () => context.read<LibraryProvider>().setStartedAt(item, value),
            ),
          ),
          const SizedBox(height: 12),
          Text(
            strings.completedAt,
            style: theme.textTheme.labelMedium?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
          _timestampRow(
            context,
            value: item.completedAt,
            editKey: MediaDetailScreen.editCompletedAtKey,
            apply: (value) => _run(
              () => context.read<LibraryProvider>().setCompletedAt(item, value),
            ),
          ),
        ],
      ),
    );
  }

  /// Header row (percent readout), the bar and the kind-specific control.
  List<Widget> _progressCard(BuildContext context) {
    final theme = Theme.of(context);
    final strings = context.strings;
    final percent = _percentDraft ?? (item.progressPercent ?? 0).toDouble();
    final clamped = percent.clamp(0, 100).toDouble();

    return [
      Row(
        children: [
          Expanded(
            child: Text(strings.progress, style: theme.textTheme.titleMedium),
          ),
          Text(
            strings.percentValue(clamped.round()),
            style: theme.textTheme.titleMedium?.copyWith(
              fontWeight: FontWeight.bold,
            ),
          ),
        ],
      ),
      const SizedBox(height: 8),
      LinearProgressIndicator(
        value: clamped / 100,
        minHeight: 6,
        borderRadius: BorderRadius.circular(3),
      ),
      const SizedBox(height: 8),
      ..._progressControls(context),
    ];
  }

  List<Widget> _progressControls(BuildContext context) {
    final total = item.totalPages;
    final hasPageCount =
        item.kind == MediaKind.book && total != null && total > 0;
    if (!hasPageCount) return [_percentSlider(context)];
    return [_pageSlider(context, total), _pageInputRow(context, total)];
  }

  /// Percent slider — movies, and books without a known page count.
  Widget _percentSlider(BuildContext context) {
    final strings = context.strings;
    final value = (_percentDraft ?? (item.progressPercent ?? 0).toDouble())
        .clamp(0, 100)
        .toDouble();
    return Slider(
      key: MediaDetailScreen.percentSliderKey,
      value: value,
      max: 100,
      divisions: 100,
      label: strings.percentValue(value.round()),
      onChanged: (next) => setState(() => _percentDraft = next),
      onChangeEnd: (next) {
        setState(() => _percentDraft = null);
        _savePercent(next);
      },
    );
  }

  /// Page slider — books with a known page count.
  Widget _pageSlider(BuildContext context, int total) {
    final strings = context.strings;
    final value = (_pageDraft ?? (item.progressCurrent ?? 0).toDouble())
        .clamp(0, total.toDouble())
        .toDouble();
    return Slider(
      key: MediaDetailScreen.pageSliderKey,
      value: value,
      max: total.toDouble(),
      divisions: total <= 200 ? total : null,
      label: strings.pageOf(value.round(), total),
      onChanged: (next) => setState(() => _pageDraft = next),
      onChangeEnd: (next) {
        setState(() => _pageDraft = null);
        _savePage(next.round());
      },
    );
  }

  Widget _pageInputRow(BuildContext context, int total) {
    final strings = context.strings;
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Expanded(
          child: TextField(
            key: MediaDetailScreen.pageFieldKey,
            controller: _pageController,
            focusNode: _pageFocus,
            keyboardType: TextInputType.number,
            decoration: InputDecoration(
              labelText: strings.currentPage,
              helperText: strings.pageOf(item.progressCurrent ?? 0, total),
              border: const OutlineInputBorder(),
              isDense: true,
            ),
            onSubmitted: (value) => _savePage(int.tryParse(value.trim())),
          ),
        ),
        const SizedBox(width: 8),
        IconButton(
          key: MediaDetailScreen.savePageButtonKey,
          tooltip: strings.savePage,
          onPressed: () => _savePage(int.tryParse(_pageController.text.trim())),
          icon: const Icon(Icons.check),
        ),
      ],
    );
  }

  /// Editable total page count — lets the user fix a missing OpenLibrary value.
  Widget _totalPagesRow(BuildContext context) {
    final strings = context.strings;
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Expanded(
          child: TextField(
            key: MediaDetailScreen.totalPagesFieldKey,
            controller: _totalPagesController,
            focusNode: _totalPagesFocus,
            keyboardType: TextInputType.number,
            decoration: InputDecoration(
              labelText: strings.totalPages,
              border: const OutlineInputBorder(),
              isDense: true,
            ),
            onSubmitted: _saveTotalPages,
          ),
        ),
        const SizedBox(width: 8),
        IconButton(
          key: MediaDetailScreen.saveTotalPagesButtonKey,
          tooltip: strings.totalPages,
          onPressed: () => _saveTotalPages(_totalPagesController.text),
          icon: const Icon(Icons.check),
        ),
      ],
    );
  }

  /// One timestamp with edit and (when set) clear actions.
  Widget _timestampRow(
    BuildContext context, {
    required DateTime? value,
    required Key editKey,
    required Future<void> Function(DateTime?) apply,
  }) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final strings = context.strings;
    return Row(
      children: [
        Expanded(
          child: Text(
            value == null ? strings.notSet : _formatDateTime(context, value),
            style: theme.textTheme.bodyLarge?.copyWith(
              color: value == null ? cs.onSurfaceVariant : null,
            ),
          ),
        ),
        IconButton(
          key: editKey,
          icon: const Icon(Icons.edit_calendar_outlined),
          tooltip: strings.pickDate,
          onPressed: () => _editTimestamp(value, apply),
        ),
        if (value != null)
          IconButton(
            icon: const Icon(Icons.clear),
            tooltip: strings.clearDate,
            onPressed: () => apply(null),
          ),
      ],
    );
  }
}
