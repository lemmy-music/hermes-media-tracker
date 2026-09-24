/// Why an export file could not be read by the import.
///
/// The import reports these as a *code* rather than a message so the UI can
/// render a localized error — see `AppStrings.importErrorMessage`. Every value
/// describes a file the user picked that is not a readable Media Tracker
/// export; none of them should ever crash the app.
enum ImportErrorCode {
  /// No bytes at all (or only whitespace).
  emptyFile,

  /// The bytes are not valid UTF-8 JSON.
  invalidJson,

  /// The root of the JSON is not an object.
  notJsonObject,

  /// The `format` marker is missing or not `media-tracker-export`.
  wrongFormat,

  /// The `version` field is missing or not a supported export version.
  unsupportedVersion,

  /// `mediaItems` is missing or not a list.
  missingMediaItems,

  /// `episodes` is missing or not a list.
  missingEpisodes,
}

/// Thrown when a picked file is not a readable Media Tracker export.
///
/// Carries only an [ImportErrorCode] — turning it into localized copy is the
/// UI's job.
class ImportFormatException implements Exception {
  const ImportFormatException(this.code);

  final ImportErrorCode code;

  @override
  String toString() => 'ImportFormatException(${code.name})';
}
