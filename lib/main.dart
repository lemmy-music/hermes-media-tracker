import 'dart:async';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'config/app_config.dart';
import 'providers/auth_provider.dart';
import 'providers/library_provider.dart';
import 'providers/settings_provider.dart';
import 'providers/theme_provider.dart';
import 'repositories/media_repository.dart';
import 'services/openlibrary_client.dart';
import 'services/tmdb_client.dart';
import 'widgets/auth_gate.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  final themeProvider = ThemeProvider();
  final settingsProvider = SettingsProvider();
  await Future.wait([themeProvider.load(), settingsProvider.load()]);

  await Supabase.initialize(
    url: AppConfig.supabaseUrl,
    // The publishable key replaces the legacy "anon" key — public by design.
    publishableKey: AppConfig.supabaseAnonKey,
  );

  final authProvider = SupabaseAuthProvider();
  // Restore the persisted session in the background; the AuthGate shows a
  // loading indicator until that resolves.
  unawaited(authProvider.init());

  runApp(
    MediaTrackerApp(
      themeProvider: themeProvider,
      settingsProvider: settingsProvider,
      authProvider: authProvider,
    ),
  );
}

class MediaTrackerApp extends StatelessWidget {
  const MediaTrackerApp({
    super.key,
    required this.themeProvider,
    required this.settingsProvider,
    required this.authProvider,
    this.repository,
    this.tmdbClient,
    this.openLibraryClient,
  });

  final ThemeProvider themeProvider;
  final SettingsProvider settingsProvider;
  final AuthProvider authProvider;

  /// Overridable so widget tests can run without a live Supabase backend.
  final MediaRepository? repository;

  /// Overridable so widget tests can supply a stub metadata client.
  final TmdbClient? tmdbClient;

  /// Overridable so widget tests can supply a stub book client (no network).
  final OpenLibraryClient? openLibraryClient;

  @override
  Widget build(BuildContext context) {
    return MultiProvider(
      providers: [
        ChangeNotifierProvider<ThemeProvider>.value(value: themeProvider),
        ChangeNotifierProvider<SettingsProvider>.value(value: settingsProvider),
        ChangeNotifierProvider<AuthProvider>.value(value: authProvider),
        Provider<MediaRepository>(
          create: (_) => repository ?? MediaRepository(),
        ),
        Provider<TmdbClient>(create: (_) => tmdbClient ?? TmdbClient()),
        Provider<OpenLibraryClient>(
          create: (_) => openLibraryClient ?? OpenLibraryClient(),
        ),
        // Owns the library list and re-loads stored metadata whenever the
        // language changes (see LibraryProvider).
        ChangeNotifierProvider<LibraryProvider>(
          create: (context) => LibraryProvider(
            repository: context.read<MediaRepository>(),
            tmdbClient: context.read<TmdbClient>(),
            settings: settingsProvider,
          ),
        ),
      ],
      child: Consumer<ThemeProvider>(
        builder: (_, theme, _) => MaterialApp(
          title: 'Media Tracker',
          debugShowCheckedModeBanner: false,
          themeMode: theme.themeMode,
          theme: ThemeData(
            useMaterial3: true,
            colorScheme: ColorScheme.fromSeed(
              seedColor: Colors.deepPurple,
              brightness: Brightness.light,
            ),
          ),
          darkTheme: ThemeData(
            useMaterial3: true,
            colorScheme: ColorScheme.fromSeed(
              seedColor: Colors.deepPurple,
              brightness: Brightness.dark,
            ),
          ),
          home: const AuthGate(),
        ),
      ),
    );
  }
}
