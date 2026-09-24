import 'dart:async';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'config/app_config.dart';
import 'providers/auth_provider.dart';
import 'providers/theme_provider.dart';
import 'repositories/media_repository.dart';
import 'widgets/auth_gate.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  final themeProvider = ThemeProvider();
  await themeProvider.load();

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
      authProvider: authProvider,
    ),
  );
}

class MediaTrackerApp extends StatelessWidget {
  const MediaTrackerApp({
    super.key,
    required this.themeProvider,
    required this.authProvider,
    this.repository,
  });

  final ThemeProvider themeProvider;
  final AuthProvider authProvider;

  /// Overridable so widget tests can run without a live Supabase backend.
  final MediaRepository? repository;

  @override
  Widget build(BuildContext context) {
    return MultiProvider(
      providers: [
        ChangeNotifierProvider<ThemeProvider>.value(value: themeProvider),
        ChangeNotifierProvider<AuthProvider>.value(value: authProvider),
        Provider<MediaRepository>(
          create: (_) => repository ?? MediaRepository(),
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
