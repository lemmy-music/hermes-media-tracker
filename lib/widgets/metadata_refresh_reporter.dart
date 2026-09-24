import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../l10n/app_strings.dart';
import '../providers/library_provider.dart';

/// Reports the outcome of a completed metadata refresh with a localized
/// snack bar — **exactly once per run**.
///
/// [LibraryProvider.metadataRefreshRuns] increments when a run finishes
/// (the automatic one after a language switch as well as the manual one). This
/// widget remembers the last reported run, so a rebuild of the surrounding
/// tree never re-reports a run and no run is reported twice.
///
/// Wrap the root [Scaffold] of the signed-in shell so the snack bar is shown
/// from every tab. Runs without any TMDB candidate are ignored here — the
/// manual "nothing to refresh" feedback belongs to the caller.
class MetadataRefreshReporter extends StatefulWidget {
  const MetadataRefreshReporter({super.key, required this.child});

  final Widget child;

  @override
  State<MetadataRefreshReporter> createState() =>
      _MetadataRefreshReporterState();
}

class _MetadataRefreshReporterState extends State<MetadataRefreshReporter> {
  /// The value of [LibraryProvider.metadataRefreshRuns] we already reported.
  late int _reportedRuns;

  @override
  void initState() {
    super.initState();
    // Runs that finished before this widget existed must not be re-reported
    // (e.g. when the shell is remounted after a sign-in).
    _reportedRuns = context.read<LibraryProvider>().metadataRefreshRuns;
  }

  @override
  Widget build(BuildContext context) {
    final library = context.watch<LibraryProvider>();
    final runs = library.metadataRefreshRuns;
    if (runs != _reportedRuns) {
      _reportedRuns = runs;
      final result = library.lastMetadataRefresh;
      if (result != null && result.hadCandidates) {
        // Defer the snack bar until after this frame — never show it during
        // build.
        WidgetsBinding.instance.addPostFrameCallback((_) => _report(result));
      }
    }
    return widget.child;
  }

  void _report(MetadataRefreshResult result) {
    if (!mounted) return;
    final strings = AppStrings.read(context);
    final message = result.hadFailures
        ? strings.metadataRefreshPartial(
            result.updated,
            result.total,
            result.failed,
          )
        : strings.metadataRefreshed(result.updated, result.total);
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(message)));
  }
}
