/// ISBN detection and validation for the search field (Phase 6a).
///
/// Pure functions — no Flutter, no network — so the search screen can decide
/// *before* a request whether the typed text is an ISBN and, if so, run the
/// ISBN lookup instead of the normal title search.
library;

/// The two ISBN formats the app understands.
enum IsbnFormat {
  /// 10 characters: 9 digits plus a check digit (`0-9` or `X`).
  isbn10,

  /// 13 digits, the modern EAN-based format (usually prefixed `978` / `979`).
  isbn13,
}

/// A successfully parsed ISBN: the normalized digits plus the detected format.
class Isbn {
  const Isbn({required this.value, required this.format});

  /// Normalized ISBN — separators and the `ISBN` prefix removed. For ISBN-10 a
  /// trailing check character `X` is upper-cased (e.g. `097522980X`).
  final String value;

  final IsbnFormat format;

  @override
  String toString() => 'Isbn($value, ${format.name})';

  @override
  bool operator ==(Object other) =>
      other is Isbn && other.value == value && other.format == format;

  @override
  int get hashCode => Object.hash(value, format);
}

/// In-range separators tolerated in user input (ASCII + typographic dashes).
final RegExp _separators = RegExp(r'[\s\u00a0\-–—]');

/// Tolerated `ISBN` / `ISBN-10:` / `ISBN 13` prefix before the digits.
final RegExp _prefix = RegExp(r'^ISBN(\s*[-–]?\s*(10|13))?\s*:?\s*');

final RegExp _isbn10Body = RegExp(r'^\d{9}[\dX]$');
final RegExp _isbn13Body = RegExp(r'^\d{13}$');

/// Removes separators and the optional `ISBN` prefix, upper-cases the text and
/// returns only the candidate digits / `X`.
///
/// Used both for validation and to build the OpenLibrary request path. Returns
/// an empty string when nothing usable remains.
String cleanIsbn(String input) {
  var text = input.trim().toUpperCase();
  text = text.replaceFirst(_prefix, '');
  text = text.replaceAll(_separators, '');
  return text;
}

/// Parses [input] as an ISBN-10 or ISBN-13, **including the check digit**.
///
/// Returns `null` for anything that is not a valid ISBN — an empty string, the
/// wrong length, illegal characters or a broken check digit.
///
/// The check digit is deliberately verified: without it every ordinary
/// 10- or 13-digit number (order numbers, phone numbers, article ids…) would be
/// treated as an ISBN and hijack a normal search. The check digit makes those
/// false positives essentially impossible, so the caller can safely fall back
/// to a plain text search.
Isbn? parseIsbn(String input) {
  final clean = cleanIsbn(input);

  if (_isbn13Body.hasMatch(clean) && _isbn13Valid(clean)) {
    return Isbn(value: clean, format: IsbnFormat.isbn13);
  }
  if (_isbn10Body.hasMatch(clean) && _isbn10Valid(clean)) {
    return Isbn(value: clean, format: IsbnFormat.isbn10);
  }
  return null;
}

/// Whether [input] is a valid ISBN (10 or 13) — shorthand for `parseIsbn`.
bool isIsbn(String input) => parseIsbn(input) != null;

/// ISBN-10 checksum: Σ digitᵢ · (10 − i) ≡ 0 (mod 11), `X` counts as 10.
bool _isbn10Valid(String value) {
  var sum = 0;
  for (var i = 0; i < 10; i++) {
    final char = value[i];
    final digit = char == 'X' ? 10 : int.parse(char);
    sum += digit * (10 - i);
  }
  return sum % 11 == 0;
}

/// ISBN-13 checksum (EAN): alternating weights 1/3, Σ ≡ 0 (mod 10).
bool _isbn13Valid(String value) {
  var sum = 0;
  for (var i = 0; i < 13; i++) {
    final digit = int.parse(value[i]);
    sum += digit * (i.isEven ? 1 : 3);
  }
  return sum % 10 == 0;
}
