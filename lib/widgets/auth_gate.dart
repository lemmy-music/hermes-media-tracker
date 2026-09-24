import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../l10n/app_strings.dart';
import '../providers/auth_provider.dart';
import '../providers/library_provider.dart';
import '../screens/login_screen.dart';
import '../screens/library_screen.dart';
import '../screens/search_screen.dart';
import '../screens/stats_screen.dart';
import 'metadata_refresh_reporter.dart';

/// Decides what the user sees based on the current [AuthProvider] state.
///
/// Rebuilds automatically whenever `onAuthStateChange` fires, which is what
/// makes the web redirect after a magic-link click land on the app instead of
/// the login screen.
class AuthGate extends StatelessWidget {
  const AuthGate({super.key});

  @override
  Widget build(BuildContext context) {
    final status = context.select<AuthProvider, AuthStatus>((a) => a.status);

    return switch (status) {
      AuthStatus.unknown => const _StartupScreen(),
      AuthStatus.signedOut => const LoginScreen(),
      AuthStatus.signedIn => const MainNavigation(),
    };
  }
}

/// Shown while the persisted session is being restored.
class _StartupScreen extends StatelessWidget {
  const _StartupScreen();

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Scaffold(
      body: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.movie_filter_outlined, size: 56, color: cs.primary),
            const SizedBox(height: 24),
            const SizedBox(
              width: 28,
              height: 28,
              child: CircularProgressIndicator(strokeWidth: 2.5),
            ),
            const SizedBox(height: 16),
            Text(
              context.strings.loadingLibrary,
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                    color: cs.onSurfaceVariant,
                  ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Root shell with the three bottom-navigation tabs.
class MainNavigation extends StatefulWidget {
  const MainNavigation({super.key});

  @override
  State<MainNavigation> createState() => _MainNavigationState();
}

class _MainNavigationState extends State<MainNavigation> {
  // Library is the start tab.
  int _selectedIndex = 0;

  static const List<Widget> _screens = [
    LibraryScreen(),
    SearchScreen(),
    StatsScreen(),
  ];

  @override
  void initState() {
    super.initState();
    // `LibraryScreen` is stateless and the provider starts in the loading
    // state, so the initial load has to be kicked off here — exactly once,
    // when the shell mounts (i.e. right after sign-in). Deferred to after the
    // first frame so it never notifies during build.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      context.read<LibraryProvider>().load();
    });
  }

  @override
  Widget build(BuildContext context) {
    final strings = context.strings;
    return MetadataRefreshReporter(
      child: Scaffold(
        body: _screens[_selectedIndex],
        bottomNavigationBar: NavigationBar(
          selectedIndex: _selectedIndex,
          onDestinationSelected: (index) =>
              setState(() => _selectedIndex = index),
          destinations: [
            NavigationDestination(
              icon: const Icon(Icons.video_library_outlined),
              selectedIcon: const Icon(Icons.video_library),
              label: strings.library,
            ),
            NavigationDestination(
              icon: const Icon(Icons.search),
              selectedIcon: const Icon(Icons.search),
              label: strings.search,
            ),
            NavigationDestination(
              icon: const Icon(Icons.insights_outlined),
              selectedIcon: const Icon(Icons.insights),
              label: strings.stats,
            ),
          ],
        ),
      ),
    );
  }
}
