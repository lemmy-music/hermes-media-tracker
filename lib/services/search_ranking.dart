/// Pure, testable ranking rules for **search hits** (TMDB + OpenLibrary).
///
/// Deliberately free of Flutter / network imports: the whole feature is *in
/// which order should the hits of one source be shown*. Both clients call
/// these functions right after parsing a response, so the UI stays dumb and
/// the behaviour is unit-testable.
///
/// **Why not TMDB's relevance score?** The API's order puts niche material
/// ("Behind the Scenes" featurettes, obscure fan edits) above the films
/// everyone means. Popularity (`vote_count` / `ratings_count`) is a far better
/// proxy — *except* for an exact title, which must never be pushed down by a
/// blockbuster that merely contains the words. Hence the two-tier rule:
///
/// 1. **Title match first:** a hit whose normalized title is *exactly* the
///    query (or *starts with* it) outranks everything else. Exact beats
///    prefix, prefix beats a mere substring hit.
/// 2. **Then popularity, descending.**
/// 3. **Stable:** equal tier *and* popularity keep their original order.
library;

import 'library_filter.dart' show normalizeSearchText;

/// Tier of a hit for the ranking: `0` exact title, `1` title starts with the
/// query, `2` everything else.
int _titleTier(String title, String query) {
  final normalizedTitle = normalizeSearchText(title.trim());
  if (normalizedTitle == query) return 0;
  if (normalizedTitle.startsWith(query)) return 1;
  return 2;
}

/// Returns a **new** list with [results] ordered by the relevance/popularity
/// rule described in the library doc.
///
/// [titleOf] and [popularityOf] keep this generic (TMDB: `title` /
/// `voteCount`, books: `title` / `ratings_count`). [query] is normalized
/// (lowercased, diacritics folded, trimmed), so `"Amélie"` and `"amelie"`
/// behave identically. An empty / whitespace-only query has no title signal
/// and therefore keeps the incoming order untouched. A missing popularity
/// value is `0` — those hits sort to the end of their tier.
List<T> rankSearchResults<T>(
  String query,
  List<T> results, {
  required String Function(T) titleOf,
  required int Function(T) popularityOf,
}) {
  if (results.length < 2) return List<T>.of(results);

  final needle = normalizeSearchText(query.trim());
  if (needle.isEmpty) return List<T>.of(results);

  // Index-decorated sort: List.sort is not stable, the index tie-breaker makes
  // it stable (equal hits keep their original order).
  final order = List<int>.generate(results.length, (index) => index);
  order.sort((a, b) {
    final tierA = _titleTier(titleOf(results[a]), needle);
    final tierB = _titleTier(titleOf(results[b]), needle);
    if (tierA != tierB) return tierA.compareTo(tierB);

    final popularityA = popularityOf(results[a]);
    final popularityB = popularityOf(results[b]);
    if (popularityA != popularityB) return popularityB.compareTo(popularityA);

    return a.compareTo(b);
  });
  return <T>[for (final index in order) results[index]];
}

/// Returns a **new** list with [results] sorted by popularity descending,
/// **stable** on equal values (and on `0` — hits without any popularity
/// signal keep their relative order).
///
/// Used by the book client, where the German-first partition is the *primary*
/// sort (see `OpenLibraryClient.rankForLanguage`) and popularity only orders
/// hits *within* a language group.
List<T> rankByPopularity<T>(
  List<T> results, {
  required int Function(T) popularityOf,
}) {
  if (results.length < 2) return List<T>.of(results);
  final order = List<int>.generate(results.length, (index) => index);
  order.sort((a, b) {
    final popularityA = popularityOf(results[a]);
    final popularityB = popularityOf(results[b]);
    if (popularityA != popularityB) return popularityB.compareTo(popularityA);
    return a.compareTo(b);
  });
  return <T>[for (final index in order) results[index]];
}
