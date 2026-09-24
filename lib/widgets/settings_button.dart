import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../providers/auth_provider.dart';
import '../providers/theme_provider.dart';

/// Central settings entry point (gear icon) shown in every screen's AppBar.
///
/// Opens a modal bottom sheet with the signed-in account (sign out) and the
/// Dark-Mode toggle.
class SettingsButton extends StatelessWidget {
  const SettingsButton({super.key});

  @override
  Widget build(BuildContext context) {
    return IconButton(
      icon: const Icon(Icons.settings),
      tooltip: 'Settings',
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
    final themeProvider = context.watch<ThemeProvider>();
    final authProvider = context.watch<AuthProvider>();
    final isDark =
        themeProvider.effectivelyDark(MediaQuery.of(context).platformBrightness);
    final email = authProvider.email;

    return SafeArea(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(24, 0, 24, 8),
            child: Text(
              'Settings',
              style: Theme.of(context)
                  .textTheme
                  .titleLarge
                  ?.copyWith(fontWeight: FontWeight.bold),
              textAlign: TextAlign.center,
            ),
          ),
          const Divider(height: 1),
          ListTile(
            leading: Icon(Icons.account_circle_outlined, color: cs.primary),
            title: Text(
              email ?? 'Signed in',
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
            subtitle: const Text('Signed in with a magic link'),
          ),
          const Divider(height: 1),
          SwitchListTile(
            secondary: Icon(
              isDark ? Icons.dark_mode : Icons.light_mode,
              color: cs.primary,
            ),
            title: const Text('Dark Mode'),
            subtitle: Text(
              isDark ? 'Dark color scheme active' : 'Light color scheme active',
            ),
            value: isDark,
            onChanged: (value) => themeProvider.setDark(value),
          ),
          const Divider(height: 1),
          ListTile(
            leading: Icon(Icons.logout, color: cs.error),
            title: Text(
              'Sign out',
              style: TextStyle(color: cs.error),
            ),
            onTap: () {
              // Grab the provider before the sheet (and its context) is gone.
              final auth = context.read<AuthProvider>();
              Navigator.of(context).pop();
              auth.signOut();
            },
          ),
          const SizedBox(height: 8),
        ],
      ),
    );
  }
}
