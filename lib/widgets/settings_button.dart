import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../l10n/app_language.dart';
import '../l10n/app_strings.dart';
import '../models/import_error.dart';
import '../providers/auth_provider.dart';
import '../providers/library_provider.dart';
import '../providers/settings_provider.dart';
import '../providers/theme_provider.dart';
import '../repositories/media_repository.dart';
import '../services/data_port_service.dart';

/// Central settings entry point (gear icon) shown in every screen's AppBar.
///
/// Opens a modal bottom sheet with the signed-in account (sign out), the
/// Dark-Mode toggle, the language picker and the JSON export / import
/// triggers.
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
              leading: Icon(Icons.upload_file, color: cs.primary),
              title: Text(strings.dataExport),
              subtitle: Text(strings.dataExportSubtitle),
              onTap: () => _exportData(context),
            ),
            ListTile(
              leading: Icon(Icons.download_for_offline, color: cs.primary),
              title: Text(strings.dataImport),
              subtitle: Text(strings.dataImportSubtitle),
              onTap: () => _importData(context),
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

  // ─── export ────────────────────────────────────────────────────────────────

  Future<void> _exportData(BuildContext context) async {
    final strings = AppStrings.read(context);
    final service = DataPortService(
      repository: context.read<MediaRepository>(),
    );
    final messenger = ScaffoldMessenger.of(context);

    _showProgress(messenger, strings.exporting);
    final result = await service.exportData();
    messenger.hideCurrentSnackBar();

    switch (result.status) {
      case ExportStatus.success:
        messenger.showSnackBar(SnackBar(content: Text(strings.exportDone)));
      case ExportStatus.cancelled:
        messenger.showSnackBar(
          SnackBar(content: Text(strings.exportCancelled)),
        );
      case ExportStatus.failure:
        if (!context.mounted) return;
        _showErrorDialog(
          context,
          strings.exportFailedTitle,
          result.error?.toString() ?? strings.importUnknownError,
          strings.ok,
        );
    }
  }

  // ─── import ────────────────────────────────────────────────────────────────

  Future<void> _importData(BuildContext context) async {
    final strings = AppStrings.read(context);
    final service = DataPortService(
      repository: context.read<MediaRepository>(),
    );

    // 1. Pick & parse the file.
    Map<String, dynamic>? parsed;
    try {
      parsed = await service.pickAndParseJson();
    } on ImportFormatException catch (error) {
      if (!context.mounted) return;
      _showErrorDialog(
        context,
        strings.importFailedTitle,
        strings.importErrorMessage(error.code),
        strings.ok,
      );
      return;
    } catch (error) {
      if (!context.mounted) return;
      _showErrorDialog(
        context,
        strings.importFailedTitle,
        error.toString(),
        strings.ok,
      );
      return;
    }
    if (parsed == null) return; // user cancelled
    if (!context.mounted) return;

    // 2. Merge or overwrite?
    final mode = await _showImportModeDialog(context, strings);
    if (mode == null) return;

    final overwrite = mode == _ImportMode.overwrite;
    if (overwrite) {
      if (!context.mounted) return;
      final confirmed = await _showOverwriteConfirm(context, strings);
      if (confirmed != true) return;
    }

    // 3. Write. The library is reloaded afterwards so the new rows show up.
    if (!context.mounted) return;
    final messenger = ScaffoldMessenger.of(context);
    _showProgress(messenger, strings.importing);
    final result = await service.importData(parsed, overwrite: overwrite);
    messenger.hideCurrentSnackBar();

    if (!result.isSuccess) {
      if (!context.mounted) return;
      _showErrorDialog(
        context,
        strings.importFailedTitle,
        result.error ?? strings.importUnknownError,
        strings.ok,
      );
      return;
    }

    if (!context.mounted) return;
    await context.read<LibraryProvider>().load();
    messenger.showSnackBar(
      SnackBar(
        content: Text(
          strings.importSummary(
            result.itemsAdded,
            result.itemsSkipped,
            result.errors,
          ),
        ),
        duration: const Duration(seconds: 5),
      ),
    );
  }

  // ─── dialogs ───────────────────────────────────────────────────────────────

  void _showProgress(ScaffoldMessengerState messenger, String message) {
    messenger.showSnackBar(
      SnackBar(
        content: Row(
          children: [
            const SizedBox(
              width: 18,
              height: 18,
              child: CircularProgressIndicator(
                strokeWidth: 2,
                color: Colors.white,
              ),
            ),
            const SizedBox(width: 12),
            Expanded(child: Text(message)),
          ],
        ),
        duration: const Duration(minutes: 1),
      ),
    );
  }

  void _showErrorDialog(
    BuildContext context,
    String title,
    String message,
    String okLabel,
  ) {
    showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        icon: Icon(
          Icons.error_outline,
          color: Theme.of(ctx).colorScheme.error,
          size: 40,
        ),
        title: Text(title),
        content: Text(message),
        actions: [
          FilledButton(
            onPressed: () => Navigator.pop(ctx),
            child: Text(okLabel),
          ),
        ],
      ),
    );
  }

  Future<_ImportMode?> _showImportModeDialog(
    BuildContext context,
    AppStrings strings,
  ) {
    return showDialog<_ImportMode>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(strings.importModeTitle),
        content: Text(strings.importModeMessage),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: Text(strings.cancel),
          ),
          OutlinedButton(
            onPressed: () => Navigator.pop(ctx, _ImportMode.merge),
            child: Text(strings.importMerge),
          ),
          FilledButton(
            style: FilledButton.styleFrom(
              backgroundColor: Theme.of(ctx).colorScheme.error,
            ),
            onPressed: () => Navigator.pop(ctx, _ImportMode.overwrite),
            child: Text(strings.importOverwrite),
          ),
        ],
      ),
    );
  }

  Future<bool?> _showOverwriteConfirm(
    BuildContext context,
    AppStrings strings,
  ) {
    return showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        icon: Icon(
          Icons.warning_amber_rounded,
          color: Theme.of(ctx).colorScheme.error,
          size: 40,
        ),
        title: Text(strings.importOverwriteConfirmTitle),
        content: Text(strings.importOverwriteConfirmMessage),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: Text(strings.cancel),
          ),
          FilledButton(
            style: FilledButton.styleFrom(
              backgroundColor: Theme.of(ctx).colorScheme.error,
            ),
            onPressed: () => Navigator.pop(ctx, true),
            child: Text(strings.importOverwriteConfirmAction),
          ),
        ],
      ),
    );
  }
}

enum _ImportMode { merge, overwrite }
