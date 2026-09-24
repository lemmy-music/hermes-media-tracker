import 'package:flutter/material.dart';

import '../l10n/app_strings.dart';
import '../widgets/settings_button.dart';

/// Placeholder Stats tab — analytics arrive in Phase 5.
class StatsScreen extends StatelessWidget {
  const StatsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final strings = context.strings;
    return Scaffold(
      appBar: AppBar(
        title: Text(strings.stats),
        actions: const [SettingsButton()],
      ),
      body: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.insights, size: 64, color: cs.primary),
            const SizedBox(height: 16),
            Text(
              strings.statsComingSoon,
              style: Theme.of(context).textTheme.titleMedium,
            ),
            const SizedBox(height: 8),
            Text(
              strings.statsDescription,
              style: Theme.of(context)
                  .textTheme
                  .bodyMedium
                  ?.copyWith(color: cs.onSurfaceVariant),
              textAlign: TextAlign.center,
            ),
          ],
        ),
      ),
    );
  }
}
