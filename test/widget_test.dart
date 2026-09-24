import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:media_tracker/l10n/app_language.dart';
import 'package:media_tracker/main.dart';
import 'package:media_tracker/models/media_item.dart';
import 'package:media_tracker/providers/auth_provider.dart';
import 'package:media_tracker/providers/settings_provider.dart';
import 'package:media_tracker/providers/theme_provider.dart';
import 'package:media_tracker/repositories/media_repository.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// In-memory auth provider — no Supabase backend required.
class _FakeAuth extends AuthProvider {
  _FakeAuth({AuthStatus status = AuthStatus.signedIn, String? email})
      : _status = status,
        _email = email ?? (status == AuthStatus.signedIn ? 'me@example.com' : null);

  AuthStatus _status;
  String? _email;

  /// Returned by [sendMagicLink] instead of succeeding.
  String? nextError;

  int sendCount = 0;
  int signOutCount = 0;

  /// Email of the most recent [sendMagicLink] call.
  String? lastRequestedEmail;

  @override
  AuthStatus get status => _status;

  @override
  String? get email => _email;

  @override
  Future<String?> sendMagicLink(String email) async {
    sendCount++;
    final error = nextError;
    if (error != null) return error;
    // Requesting a link does NOT sign the user in — they still have to click
    // the link in their inbox, which the SDK reports via onAuthStateChange.
    lastRequestedEmail = email;
    return null;
  }

  @override
  Future<void> signOut() async {
    signOutCount++;
    _status = AuthStatus.signedOut;
    _email = null;
    notifyListeners();
  }

  void setStatus(AuthStatus status) {
    _status = status;
    notifyListeners();
  }
}

/// Repository stub that never touches Supabase.
class _FakeRepository extends MediaRepository {
  _FakeRepository({this.items = const <MediaItem>[], this.error});

  List<MediaItem> items;

  /// When set, [fetchAll] throws a [MediaRepositoryException] with this text.
  String? error;

  int fetchCount = 0;

  @override
  Future<List<MediaItem>> fetchAll() async {
    fetchCount++;
    final error = this.error;
    if (error != null) throw MediaRepositoryException(error);
    return items;
  }
}

MediaItem _movie(String title) => MediaItem(
      id: 'id-${title.hashCode}',
      kind: MediaKind.movie,
      title: title,
      releaseYear: 2010,
    );

Future<void> _pumpApp(
  WidgetTester tester, {
  required AuthProvider auth,
  MediaRepository? repository,
  SettingsProvider? settings,
}) async {
  await tester.pumpWidget(
    MediaTrackerApp(
      themeProvider: ThemeProvider(),
      // English by default so the string assertions below stay readable and
      // independent of the app default (German). See the dedicated German
      // tests further down.
      settingsProvider: settings ?? SettingsProvider(initial: AppLanguage.en),
      authProvider: auth,
      repository: repository ?? _FakeRepository(),
    ),
  );
  // Let the (immediately resolving) fake fetch settle.
  await tester.pump();
}

void main() {
  // The language toggle persists via SharedPreferences — give it a mock store.
  setUp(() => SharedPreferences.setMockInitialValues(<String, Object>{}));

  testWidgets('shows a loading indicator while the session is restored',
      (WidgetTester tester) async {
    final auth = _FakeAuth(status: AuthStatus.unknown);
    await _pumpApp(tester, auth: auth);

    expect(find.byType(CircularProgressIndicator), findsOneWidget);
    expect(find.text('Send magic link'), findsNothing);

    auth.setStatus(AuthStatus.signedOut);
    await tester.pump();

    expect(find.text('Send magic link'), findsOneWidget);
  });

  testWidgets('signed out: shows the magic-link login screen',
      (WidgetTester tester) async {
    await _pumpApp(tester, auth: _FakeAuth(status: AuthStatus.signedOut));

    expect(find.text('Email address'), findsOneWidget);
    expect(find.text('Send magic link'), findsOneWidget);
    expect(find.text('Library'), findsNothing);
  });

  testWidgets('reacts to an auth state change (magic-link redirect)',
      (WidgetTester tester) async {
    final auth = _FakeAuth(status: AuthStatus.signedOut);
    await _pumpApp(tester, auth: auth);
    expect(find.text('Send magic link'), findsOneWidget);

    // Simulates the SDK reporting the session after the user clicked the
    // link in their inbox (`onAuthStateChange`).
    auth.setStatus(AuthStatus.signedIn);
    await tester.pump();
    await tester.pump(); // let the library fetch resolve

    expect(find.text('Send magic link'), findsNothing);
    expect(find.text('Your library is empty'), findsOneWidget);
  });

  testWidgets('login: validates the email and shows the confirmation view',
      (WidgetTester tester) async {
    final auth = _FakeAuth(status: AuthStatus.signedOut);
    await _pumpApp(tester, auth: auth);

    // Invalid address → client-side validation, nothing sent.
    await tester.enterText(find.byType(TextFormField), 'not-an-email');
    await tester.tap(find.text('Send magic link'));
    await tester.pump();
    expect(find.text('Please enter a valid email address.'), findsOneWidget);
    expect(auth.sendCount, 0);

    // Valid address → confirmation view.
    await tester.enterText(find.byType(TextFormField), 'daniel@example.com');
    await tester.tap(find.text('Send magic link'));
    await tester.pump();
    await tester.pump();

    expect(auth.sendCount, 1);
    expect(auth.lastRequestedEmail, 'daniel@example.com');
    expect(find.text('Check your inbox'), findsOneWidget);
    expect(
      find.textContaining('daniel@example.com'),
      findsOneWidget,
    );
  });

  testWidgets('login: surfaces a provider error message',
      (WidgetTester tester) async {
    final auth = _FakeAuth(status: AuthStatus.signedOut)
      ..nextError = 'Too many requests. Please wait a few minutes.';
    await _pumpApp(tester, auth: auth);

    await tester.enterText(find.byType(TextFormField), 'daniel@example.com');
    await tester.tap(find.text('Send magic link'));
    await tester.pump();
    await tester.pump();

    expect(
      find.text('Too many requests. Please wait a few minutes.'),
      findsOneWidget,
    );
    expect(find.text('Check your inbox'), findsNothing);
  });

  testWidgets('signed in: renders the three navigation tabs',
      (WidgetTester tester) async {
    await _pumpApp(tester, auth: _FakeAuth());

    expect(find.text('Your library is empty'), findsOneWidget);
    expect(find.text('Library'), findsWidgets);
    expect(find.text('Search'), findsOneWidget);
    expect(find.text('Stats'), findsOneWidget);
  });

  testWidgets('bottom navigation switches to the Search tab',
      (WidgetTester tester) async {
    await _pumpApp(tester, auth: _FakeAuth());

    await tester.tap(find.text('Search'));
    await tester.pumpAndSettle();

    expect(find.text('Find something to track'), findsOneWidget);
  });

  testWidgets('library lists the loaded items', (WidgetTester tester) async {
    await _pumpApp(
      tester,
      auth: _FakeAuth(),
      repository: _FakeRepository(
        items: [_movie('Inception'), _movie('Arrival')],
      ),
    );

    expect(find.text('Inception'), findsOneWidget);
    expect(find.text('Arrival'), findsOneWidget);
    expect(find.text('Your library is empty'), findsNothing);
    expect(find.text('Movie'), findsNWidgets(2));
    expect(find.text('Planned'), findsNWidgets(2));
  });

  testWidgets('library shows an error state with a working retry',
      (WidgetTester tester) async {
    final repository = _FakeRepository(error: 'Could not load your library.');
    await _pumpApp(tester, auth: _FakeAuth(), repository: repository);

    expect(find.text('Could not load your library'), findsOneWidget);
    expect(find.text('Retry'), findsOneWidget);

    // Backend recovers → retry loads the list.
    repository
      ..error = null
      ..items = [_movie('Inception')];

    await tester.tap(find.text('Retry'));
    await tester.pump();
    await tester.pump();

    expect(repository.fetchCount, 2);
    expect(find.text('Inception'), findsOneWidget);
  });

  testWidgets('settings sheet shows the account and signs out',
      (WidgetTester tester) async {
    final auth = _FakeAuth(email: 'daniel@example.com');
    await _pumpApp(tester, auth: auth);

    await tester.tap(find.byIcon(Icons.settings));
    await tester.pumpAndSettle();

    expect(find.text('daniel@example.com'), findsOneWidget);
    expect(find.text('Sign out'), findsOneWidget);

    // The sheet grew with the language row — scroll the sign-out row into view.
    await tester.ensureVisible(find.text('Sign out'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Sign out'));
    await tester.pumpAndSettle();

    expect(auth.signOutCount, 1);
    // AuthGate swapped back to the login screen.
    expect(find.text('Send magic link'), findsOneWidget);
  });

  testWidgets('defaults to German when nothing is stored',
      (WidgetTester tester) async {
    // A provider with the default initial value == first launch, no prefs.
    await _pumpApp(
      tester,
      auth: _FakeAuth(),
      settings: SettingsProvider(),
    );

    expect(find.text('Deine Bibliothek ist leer'), findsOneWidget);
    expect(find.text('Bibliothek'), findsWidgets);
    expect(find.text('Suche'), findsOneWidget);
    expect(find.text('Statistik'), findsOneWidget);
    expect(find.text('Your library is empty'), findsNothing);
  });

  testWidgets('German covers the login screen too',
      (WidgetTester tester) async {
    await _pumpApp(
      tester,
      auth: _FakeAuth(status: AuthStatus.signedOut),
      settings: SettingsProvider(),
    );

    expect(find.text('Anmelde-Link senden'), findsOneWidget);
    expect(find.text('E-Mail-Adresse'), findsOneWidget);
    expect(find.text('Send magic link'), findsNothing);
  });

  testWidgets('settings sheet toggles the language immediately',
      (WidgetTester tester) async {
    await _pumpApp(tester, auth: _FakeAuth());

    await tester.tap(find.byIcon(Icons.settings));
    await tester.pumpAndSettle();
    expect(find.text('Settings'), findsOneWidget);

    // Switch to German — the whole UI (and this sheet) must update at once.
    await tester.tap(find.text('Deutsch'));
    await tester.pumpAndSettle();
    expect(find.text('Einstellungen'), findsOneWidget);
    expect(find.text('Abmelden'), findsOneWidget);
    expect(find.text('Sprache'), findsOneWidget);

    // …and back to English.
    await tester.tap(find.text('English'));
    await tester.pumpAndSettle();
    expect(find.text('Settings'), findsOneWidget);
    expect(find.text('Sign out'), findsOneWidget);
  });
}
