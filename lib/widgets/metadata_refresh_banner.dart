import 'package:flutter/material.dart';

import '../l10n/app_strings.dart';

/// Slim, unobtrusive progress bar shown while metadata is re-fetched.
///
/// Shared by the library landing screen (and its refresh / overflow actions) so
/// the run's progress is visible wherever it was started from.
class MetadataRefreshBanner extends StatelessWidget {
  const MetadataRefreshBanner({
    super.key,
    required this.done,
    required this.total,
  });

  final int done;
  final int total;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final strings = context.strings;
    return Material(
      color: theme.colorScheme.surfaceContainerHighest,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          LinearProgressIndicator(
            value: total == 0 ? null : done / total,
            minHeight: 3,
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            child: Row(
              children: [
                Icon(
                  Icons.sync,
                  size: 16,
                  color: theme.colorScheme.onSurfaceVariant,
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    strings.metadataRefreshing(done, total),
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
