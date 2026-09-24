import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../l10n/app_language.dart';
import '../l10n/app_strings.dart';
import '../providers/auth_provider.dart';
import '../providers/settings_provider.dart';
import '../providers/theme_provider.dart';

/// Central settings entry point (gear icon) shown in every screen's AppBar.
///
/// Opens a modal bottom sheet with the signed-in account (sign out), the
/// Dark-Mode toggle and the language picker.
class SettingsButton extends StatelessWidget {
  const SettingsButton({super.key});

  @override
  Widget build(BuildContext context) {
    return IconButton(
      icon: const Icon(Icons.settings),
      tooltip: context.strings.settings,
      onPressed: () => _openSettings(context),
    );
  }

  Future<void> _openSettings(BuildContext context) {
    return showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      useSafeArea: true,
      constraints: const BoxConstraints(maxWidth: 560),
      builder: (_) => const _SettingsSheet(),
    );
  }
}

class _SettingsSheet extends StatelessWidget {
  const _SettingsSheet();

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final strings = context.strings;
    final themeProvider = context.watch<ThemeProvider>();
    final settingsProvider = context.watch<SettingsProvider>();
    final authProvider = context.watch<AuthProvider>();
    final isDark = themeProvider.effectivelyDark(
      MediaQuery.of(context).platformBrightness,
    );
    final email = authProvider.email;

    return SafeArea(
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(24, 0, 24, 8),
              child: Text(
                strings.settings,
                style: Theme.of(
                  context,
                ).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.bold),
                textAlign: TextAlign.center,
              ),
            ),
            const Divider(height: 1),
            ListTile(
              leading: Icon(Icons.account_circle_outlined, color: cs.primary),
              title: Text(
                email ?? strings.signedIn,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
              subtitle: Text(strings.signedInWithMagicLink),
            ),
            const Divider(height: 1),
            SwitchListTile(
              secondary: Icon(
                isDark ? Icons.dark_mode : Icons.light_mode,
                color: cs.primary,
              ),
              title: Text(strings.darkMode),
              subtitle: Text(isDark ? strings.darkActive : strings.lightActive),
              value: isDark,
              onChanged: (value) => themeProvider.setDark(value),
            ),
            const Divider(height: 1),
            ListTile(
              leading: Icon(Icons.language, color: cs.primary),
              title: Text(strings.languageLabel),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
              child: SegmentedButton<AppLanguage>(
                segments: [
                  for (final language in AppLanguage.values)
                    ButtonSegment<AppLanguage>(
                      value: language,
                      // Native names, identical in every language.
                      label: Text(language.label),
                    ),
                ],
                selected: <AppLanguage>{settingsProvider.language},
                showSelectedIcon: false,
                onSelectionChanged: (selection) =>
                    settingsProvider.setLanguage(selection.first),
              ),
            ),
            const Divider(height: 1),
            ListTile(
              leading: Icon(Icons.logout, color: cs.error),
              title: Text(
                strings.signOut,
                style: TextStyle(color: cs.error),
              ),
              onTap: () {
                // Grab the provider before the sheet (and its context) is gone.
                final auth = context.read<AuthProvider>();
                Navigator.of(context).pop();
                auth.signOut();
              },
            ),
            const Divider(height: 1),
            Padding(
              padding: const EdgeInsets.fromLTRB(24, 12, 24, 0),
              child: Text(
                strings.tmdbAttribution,
                style: Theme.of(
                  context,
                ).textTheme.bodySmall?.copyWith(color: cs.onSurfaceVariant),
                textAlign: TextAlign.center,
              ),
            ),
            const SizedBox(height: 8),
          ],
        ),
      ),
    );
  }
}
