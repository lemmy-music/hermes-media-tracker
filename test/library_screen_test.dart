import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:media_tracker/l10n/app_language.dart';
import 'package:media_tracker/main.dart';
import 'package:media_tracker/models/media_item.dart';
import 'package:media_tracker/providers/auth_provider.dart';
import 'package:media_tracker/providers/settings_provider.dart';
import 'package:media_tracker/providers/theme_provider.dart';
import 'package:media_tracker/repositories/media_repository.dart';
import 'package:media_tracker/screens/library_screen.dart';

// ─────────────────────────────────────────────────────────────────────────────
// fakes — no Supabase, no network
// ─────────────────────────────────────────────────────────────────────────────

/// Always signed in.
class _FakeAuth extends AuthProvider {
  @override
  AuthStatus get status => AuthStatus.signedIn;

  @override
  String? get email => 'me@example.com';

  @override
  Future<String?> sendMagicLink(String email) async => null;

  @override
  Future<void> signOut() async {}
}

/// In-memory repository; [fetchAll] never touches the network.
class _FakeRepository extends MediaRepository {
  _FakeRepository({this.items = const <MediaItem>[]});

  List<MediaItem> items;

  @override
  Future<List<MediaItem>> fetchAll() async => items;
}

MediaItem _movie({
  required String title,
  String? id,
  MediaStatus status = MediaStatus.planned,
  DateTime? createdAt,
}) => MediaItem(
  id: id ?? 'movie-$title',
  kind: MediaKind.movie,
  title: title,
  status: status,
  createdAt: createdAt,
);

MediaItem _book({
  required String title,
  String? id,
  List<String> authors = const <String>[],
  MediaStatus status = MediaStatus.planned,
}) => MediaItem(
  id: id ?? 'book-$title',
  kind: MediaKind.book,
  title: title,
  authors: authors,
  status: status,
);

Future<void> _pumpLibrary(
  WidgetTester tester, {
  required List<MediaItem> items,
  AppLanguage language = AppLanguage.en,
}) async {
  await tester.pumpWidget(
    MediaTrackerApp(
      themeProvider: ThemeProvider(),
      settingsProvider: SettingsProvider(initial: language),
      authProvider: _FakeAuth(),
      repository: _FakeRepository(items: items),
    ),
  );
  // Let the (immediately resolving) fake fetch settle.
  await tester.pumpAndSettle();
}

Finder _chip(String label) => find.widgetWithText(ChoiceChip, label);

void main() {
  setUp(() => SharedPreferences.setMockInitialValues(<String, Object>{}));

  testWidgets('the search field filters the list live and shows a counter', (
    tester,
  ) async {
    await _pumpLibrary(
      tester,
      items: [
        _movie(title: 'Inception'),
        _movie(title: 'Arrival'),
      ],
    );

    // No search / filter UI clutter until it is asked for.
    expect(find.byKey(LibraryScreen.searchFieldKey), findsNothing);
    expect(find.text('1 result of 2'), findsNothing);

    await tester.tap(find.byKey(LibraryScreen.searchToggleKey));
    await tester.pump();
    expect(find.byKey(LibraryScreen.searchFieldKey), findsOneWidget);

    await tester.enterText(find.byKey(LibraryScreen.searchFieldKey), 'incep');
    await tester.pump();

    expect(find.text('Inception'), findsOneWidget);
    expect(find.text('Arrival'), findsNothing);
    expect(find.text('1 result of 2'), findsOneWidget);
  });

  testWidgets('the search also matches a book author', (tester) async {
    await _pumpLibrary(
      tester,
      items: [
        _book(title: 'Dune', authors: const ['Frank Herbert']),
        _movie(title: 'Inception'),
      ],
    );

    await tester.tap(find.byKey(LibraryScreen.searchToggleKey));
    await tester.pump();
    await tester.enterText(find.byKey(LibraryScreen.searchFieldKey), 'herbert');
    await tester.pump();

    expect(find.text('Dune'), findsOneWidget);
    expect(find.text('Inception'), findsNothing);
  });

  testWidgets('the filter chips narrow by media type and status', (
    tester,
  ) async {
    await _pumpLibrary(
      tester,
      items: [
        _movie(title: 'Inception'),
        _book(title: 'Dune', status: MediaStatus.completed),
      ],
    );

    await tester.tap(find.byKey(LibraryScreen.filterToggleKey));
    await tester.pump();

    await tester.tap(_chip('Movies'));
    await tester.pump();
    expect(find.text('Inception'), findsOneWidget);
    expect(find.text('Dune'), findsNothing);
    expect(find.text('1 result of 2'), findsOneWidget);

    await tester.tap(_chip('Books'));
    await tester.pump();
    expect(find.text('Dune'), findsOneWidget);
    expect(find.text('Inception'), findsNothing);

    // Books + planned → nothing left, and it must be the "no matches" state.
    await tester.tap(_chip('Planned'));
    await tester.pump();
    expect(find.byKey(LibraryScreen.noMatchesKey), findsOneWidget);
    expect(find.text('No matches'), findsOneWidget);
    expect(find.text('Your library is empty'), findsNothing);
  });

  testWidgets('resetting clears the search and every filter', (tester) async {
    await _pumpLibrary(
      tester,
      items: [
        _movie(title: 'Inception'),
        _book(title: 'Dune'),
      ],
    );

    await tester.tap(find.byKey(LibraryScreen.filterToggleKey));
    await tester.pump();
    await tester.tap(_chip('Books'));
    await tester.pump();
    expect(find.text('Dune'), findsOneWidget);
    expect(find.text('Inception'), findsNothing);

    await tester.tap(find.byKey(LibraryScreen.resetFiltersKey));
    await tester.pump();

    expect(find.text('Inception'), findsOneWidget);
    expect(find.text('Dune'), findsOneWidget);
    // The counter disappears once nothing is filtered, and the chips collapse.
    expect(find.text('1 result of 2'), findsNothing);
    expect(find.byType(ChoiceChip), findsNothing);
  });

  testWidgets('"no matches" is distinct from the empty-library state', (
    tester,
  ) async {
    await _pumpLibrary(tester, items: [_movie(title: 'Inception')]);

    await tester.tap(find.byKey(LibraryScreen.searchToggleKey));
    await tester.pump();
    await tester.enterText(find.byKey(LibraryScreen.searchFieldKey), 'zzz');
    await tester.pump();

    expect(find.byKey(LibraryScreen.noMatchesKey), findsOneWidget);
    expect(find.text('No matches'), findsOneWidget);
    expect(find.text('Your library is empty'), findsNothing);
    // The reset action is offered right there.
    expect(find.text('Reset filters'), findsWidgets);

    await tester.tap(find.byKey(LibraryScreen.resetFiltersKey));
    await tester.pump();
    expect(find.text('Inception'), findsOneWidget);
    expect(find.byKey(LibraryScreen.noMatchesKey), findsNothing);
  });

  testWidgets('an empty library keeps the plain empty state (no controls)', (
    tester,
  ) async {
    await _pumpLibrary(tester, items: const <MediaItem>[]);

    expect(find.text('Your library is empty'), findsOneWidget);
    expect(find.byKey(LibraryScreen.searchToggleKey), findsNothing);
    expect(find.byKey(LibraryScreen.filterToggleKey), findsNothing);
    expect(find.byKey(LibraryScreen.noMatchesKey), findsNothing);
  });

  testWidgets('the sort menu reorders the list', (tester) async {
    await _pumpLibrary(
      tester,
      items: [
        // Newer → "recently added" puts Zebra first…
        _movie(title: 'Zebra', createdAt: DateTime(2026, 1, 1)),
        _movie(title: 'Apple', createdAt: DateTime(2024, 1, 1)),
      ],
    );

    expect(
      tester.getTopLeft(find.text('Zebra')).dy <
          tester.getTopLeft(find.text('Apple')).dy,
      isTrue,
    );

    // …while "Title A–Z" puts Apple first.
    await tester.tap(find.byKey(LibraryScreen.sortMenuKey));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Title A–Z'));
    await tester.pumpAndSettle();

    expect(
      tester.getTopLeft(find.text('Apple')).dy <
          tester.getTopLeft(find.text('Zebra')).dy,
      isTrue,
    );
  });

  testWidgets('the new controls are localized in German', (tester) async {
    await _pumpLibrary(
      tester,
      items: [
        _movie(title: 'Inception'),
        _movie(title: 'Arrival'),
      ],
      language: AppLanguage.de,
    );

    await tester.tap(find.byKey(LibraryScreen.searchToggleKey));
    await tester.pump();
    expect(find.text('Titel durchsuchen'), findsOneWidget);

    await tester.enterText(find.byKey(LibraryScreen.searchFieldKey), 'incep');
    await tester.pump();
    expect(find.text('1 Treffer von 2'), findsOneWidget);

    await tester.tap(find.byKey(LibraryScreen.filterToggleKey));
    await tester.pump();
    expect(_chip('Filme'), findsOneWidget);
    expect(_chip('Bücher'), findsOneWidget);
    expect(find.text('Filter zurücksetzen'), findsWidgets);
  });
}
