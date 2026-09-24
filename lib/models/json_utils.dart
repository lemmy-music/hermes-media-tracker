/// Tolerant converters between PostgREST JSON values and Dart types.
///
/// PostgREST returns `numeric` / `int8` columns as either JSON numbers or
/// strings depending on the column type, and timestamps as ISO-8601 strings.
/// Every converter therefore accepts both numbers and strings and never
/// throws on unexpected input.
library;

/// Parses [value] as an `int`, accepting numbers and numeric strings.
int? jsonInt(Object? value) {
  if (value == null) return null;
  if (value is int) return value;
  if (value is num) return value.toInt();
  if (value is String) return int.tryParse(value);
  return null;
}

/// Parses [value] as a `double`, accepting numbers and numeric strings.
double? jsonDouble(Object? value) {
  if (value == null) return null;
  if (value is double) return value;
  if (value is num) return value.toDouble();
  if (value is String) return double.tryParse(value);
  return null;
}

/// Parses [value] as a `String`.
String? jsonString(Object? value) {
  if (value == null) return null;
  return value.toString();
}

/// Parses a `timestamptz` / `date` value and converts it to local time.
DateTime? jsonDateTime(Object? value) {
  if (value == null) return null;
  if (value is DateTime) return value.toLocal();
  if (value is String) return DateTime.tryParse(value)?.toLocal();
  return null;
}

/// Parses a Postgres `text[]` column.
List<String> jsonStringList(Object? value) {
  if (value is List) {
    final result = <String>[];
    for (final entry in value) {
      if (entry == null) continue;
      final text = entry.toString();
      if (text.isNotEmpty) result.add(text);
    }
    return result;
  }
  return const <String>[];
}

/// Serialises a `timestamptz` column value (UTC, ISO-8601).
String? isoDateTime(DateTime? value) => value?.toUtc().toIso8601String();

/// Serialises a `date` column value as `YYYY-MM-DD`.
///
/// Uses the date's own calendar fields (no timezone conversion) so a date
/// parsed from `2024-01-01` round-trips unchanged.
String dateOnly(DateTime value) {
  final year = value.year.toString().padLeft(4, '0');
  final month = value.month.toString().padLeft(2, '0');
  final day = value.day.toString().padLeft(2, '0');
  return '$year-$month-$day';
}
