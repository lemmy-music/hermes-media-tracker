import 'package:flutter_test/flutter_test.dart';

import 'package:media_tracker/main.dart';
import 'package:media_tracker/providers/theme_provider.dart';

void main() {
  testWidgets('App shell renders the three navigation tabs',
      (WidgetTester tester) async {
    await tester.pumpWidget(MediaTrackerApp(themeProvider: ThemeProvider()));

    // Library is the start tab.
    expect(find.text('Your library is empty'), findsOneWidget);

    // All three destinations are present.
    expect(find.text('Library'), findsWidgets);
    expect(find.text('Search'), findsOneWidget);
    expect(find.text('Stats'), findsOneWidget);
  });

  testWidgets('Bottom navigation switches to the Search tab',
      (WidgetTester tester) async {
    await tester.pumpWidget(MediaTrackerApp(themeProvider: ThemeProvider()));

    await tester.tap(find.text('Search'));
    await tester.pumpAndSettle();

    expect(find.text('Find something to track'), findsOneWidget);
  });
}
