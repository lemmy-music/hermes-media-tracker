import 'package:flutter_test/flutter_test.dart';

import 'package:media_tracker/services/search_ranking.dart';

/// Minimal hit shape for the pure ranking tests — the function is generic, so
/// no TMDB / OpenLibrary model is needed here.
class _Hit {
  const _Hit(this.title, [this.votes = 0]);

  final String title;
  final int votes;

  @override
  String toString() => '$_Hit($title, $votes)';
}

List<_Hit> _rank(String query, List<_Hit> hits) => rankSearchResults(
  query,
  hits,
  titleOf: (hit) => hit.title,
  popularityOf: (hit) => hit.votes,
);

List<String> _titles(List<_Hit> hits) => [for (final hit in hits) hit.title];

void main() {
  group('rankSearchResults', () {
    test('an exact title hit beats a far more popular non-match', () {
      final ranked = _rank('star wars', const [
        _Hit('Star Wars: Behind the Scenes', 50000),
        _Hit('Star Wars', 120),
      ]);

      expect(_titles(ranked), ['Star Wars', 'Star Wars: Behind the Scenes']);
    });

    test('a title starting with the query is preferred over the rest', () {
      final ranked = _rank('star wars', const [
        _Hit('The Making of Star Wars', 90000),
        _Hit('A Star Wars Story: Rogue One', 700),
        _Hit('Star Wars: A New Hope', 3000),
      ]);

      // Exact/prefix tier first (prefix sorted by votes), then everything else.
      expect(_titles(ranked), [
        'Star Wars: A New Hope',
        'The Making of Star Wars',
        'A Star Wars Story: Rogue One',
      ]);
    });

    test('otherwise sorts by vote count descending', () {
      final ranked = _rank('dune', const [
        _Hit('Dune Messiah', 100),
        _Hit('Dune', 800),
        _Hit('Dune: Part Two', 400),
      ]);

      // All three are prefix hits → within the tier the vote count decides.
      expect(_titles(ranked), ['Dune', 'Dune: Part Two', 'Dune Messiah']);
    });

    test('a missing vote count counts as 0 and lands at the back', () {
      final ranked = _rank('dune', const [
        _Hit('Dune: Part Two'),
        _Hit('Dune Messiah', 3),
      ]);

      // Missing popularity must never push a hit above a rated one.
      expect(_titles(ranked), ['Dune Messiah', 'Dune: Part Two']);
    });

    test('is stable for equal tier and equal votes', () {
      final ranked = _rank('dune', const [
        _Hit('Dune: Part Two', 100),
        _Hit('Dune Messiah', 100),
      ]);

      expect(_titles(ranked), ['Dune: Part Two', 'Dune Messiah']);
    });

    test('normalizes case, diacritics and surrounding whitespace', () {
      final ranked = _rank('  AMÉLIE  ', const [
        _Hit('Amelie: The Making Of', 9000),
        _Hit('Amélie', 40),
      ]);

      // "Amélie" normalizes to "amelie" → exact hit, independent of votes.
      expect(_titles(ranked), ['Amélie', 'Amelie: The Making Of']);
    });

    test('folds umlauts and ß on both sides', () {
      final ranked = _rank('grosse fuge', const [
        _Hit('Große Fuge — Analyse', 400),
        _Hit('Grosse Fuge', 3),
      ]);

      expect(_titles(ranked), ['Grosse Fuge', 'Große Fuge — Analyse']);
    });

    test('an empty list stays empty', () {
      expect(_rank('star wars', const []), isEmpty);
    });

    test('an empty / blank query keeps the incoming order', () {
      const hits = [_Hit('Zeta', 1), _Hit('Alpha', 99)];
      expect(_titles(_rank('   ', hits)), ['Zeta', 'Alpha']);
    });

    test('does not mutate the input list', () {
      final hits = [_Hit('B', 1), _Hit('A', 2)];
      final ranked = _rank('x', hits);
      expect(_titles(hits), ['B', 'A']);
      expect(_titles(ranked), ['A', 'B']);
    });
  });

  group('rankByPopularity', () {
    test('sorts by popularity, stable on ties and on 0', () {
      final ranked = rankByPopularity(const [
        _Hit('A'),
        _Hit('B', 7),
        _Hit('C', 3),
        _Hit('D'),
      ], popularityOf: (hit) => hit.votes);

      expect(_titles(ranked), ['B', 'C', 'A', 'D']);
    });

    test('an empty list stays empty', () {
      expect(
        rankByPopularity(const <_Hit>[], popularityOf: (h) => h.votes),
        isEmpty,
      );
    });
  });
}
