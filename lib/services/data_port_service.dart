import 'dart:convert';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/foundation.dart';

import '../models/episode.dart';
import '../models/import_error.dart';
import '../models/media_item.dart';
import '../repositories/media_repository.dart';
import 'download_helper.dart';

/// The `format` marker written into (and required from) an export file.
///
/// Import refuses anything that does not carry it, so a random JSON file
/// cannot silently be interpreted as a backup.
const String kExportFormat = 'media-tracker-export';

/// The export schema version this build reads and writes.
///
/// A file from a newer version is rejected with a clear message instead of
/// being half-imported.
const int kExportVersion = 1;

/// How an [DataPortService.exportData] run ended.
enum ExportStatus { success, cancelled, failure }

/// Outcome of an export run.
@immutable
class ExportResult {
  const ExportResult._(this.status, this.error);

  /// The file was written / the download started.
  const ExportResult.success() : this._(ExportStatus.success, null);

  /// The user dismissed the native save dialog — nothing was written.
  const ExportResult.cancelled() : this._(ExportStatus.cancelled, null);

  /// The export could not be built or written; [error] holds the cause.
  const ExportResult.failure(Object error)
    : this._(ExportStatus.failure, error);

  final ExportStatus status;
  final Object? error;

  bool get isSuccess => status == ExportStatus.success;
}

/// Counters of one import run.
///
/// [itemsAdded] / [itemsSkipped] / [errors] describe **media items**
/// (skipped = merge mode found the item already in the library), the whole
/// operation fails hard only through the optional [error] (e.g. the backend
/// could not be reached); individual bad rows are counted in [errors] and
/// never abort the run.
@immutable
class ImportResult {
  const ImportResult({
    this.itemsAdded = 0,
    this.itemsSkipped = 0,
    this.episodesAdded = 0,
    this.errors = 0,
    this.error,
  });

  /// Media items inserted (with fresh ids).
  final int itemsAdded;

  /// Media items left untouched because they were already tracked (merge).
  final int itemsSkipped;

  /// Episodes inserted for the newly added items.
  final int episodesAdded;

  /// Entries that could not be read or written.
  final int errors;

  /// A hard failure that aborted the run before/while writing, or `null`.
  final String? error;

  bool get isSuccess => error == null;

  @override
  String toString() =>
      'ImportResult(itemsAdded: $itemsAdded, itemsSkipped: $itemsSkipped, '
      'episodesAdded: $episodesAdded, errors: $errors, error: $error)';
}

/// Loads the raw bytes of a picked file, or `null` when the user cancels.
typedef FileBytesLoader = Future<Uint8List?> Function();

/// Writes [bytes] to [filename]; `false` when the user cancels the dialog.
typedef FileSaver = Future<bool> Function(String filename, Uint8List bytes);

/// JSON export and import of the signed-in user's whole library.
///
/// The export reads `media_items` + `episodes` (RLS restricts both to the
/// owner) and writes a versioned JSON document:
///
/// ```json
/// {
///   "format": "media-tracker-export",
///   "version": 1,
///   "exportedAt": "2026-09-24T11:30:00Z",
///   "mediaItems": [ … ],
///   "episodes": [ … ]
/// }
/// ```
///
/// The import re-creates the rows with **fresh** ids: the exported
/// `id`/`user_id`/`created_at`/`updated_at` are never taken over, `user_id`
/// becomes the currently signed-in user, and episodes are re-linked to their
/// parent through a mapping built from the exported item ids. The watch state
/// (`watched`, `watched_at`) of an episode is preserved.
///
/// Everything that reaches the outside world (the file picker, the download
/// and the repository) is injectable, so the service is fully testable
/// without a browser, a network or a live Supabase.
class DataPortService {
  DataPortService({
    required MediaRepository repository,
    DateTime Function()? clock,
    FileBytesLoader? fileBytesLoader,
    FileSaver? fileSaver,
    bool? isWeb,
  }) : // The repository parameter name must stay public, so an initializing
       // formal is impossible here — the lint is a false positive (same
       // pattern as LibraryProvider).
       // ignore: prefer_initializing_formals
       _repository = repository,
       _clock = clock ?? DateTime.now,
       _loadFileBytes = fileBytesLoader ?? _pickJsonBytes,
       _saveFile =
           fileSaver ?? ((isWeb ?? kIsWeb) ? _downloadOnWeb : _saveOnNative);

  final MediaRepository _repository;

  /// Injectable clock — production uses [DateTime.now]; tests pin it so the
  /// file name and `exportedAt` are deterministic.
  final DateTime Function() _clock;

  final FileBytesLoader _loadFileBytes;
  final FileSaver _saveFile;

  // ───────────────────────────────────────────────────────────────────────────
  // export
  // ───────────────────────────────────────────────────────────────────────────

  /// The file name of an export taken at [now]:
  /// `media_tracker_export_<YYYY-MM-DD_HHmm>.json`.
  static String exportFileName(DateTime now) {
    String pad(int value, [int width = 2]) =>
        value.toString().padLeft(width, '0');
    final date = '${pad(now.year, 4)}-${pad(now.month)}-${pad(now.day)}';
    final time = '${pad(now.hour)}${pad(now.minute)}';
    return 'media_tracker_export_${date}_$time.json';
  }

  /// Builds the export document from already-loaded rows.
  ///
  /// Pure and synchronous so tests can assert the structure without touching
  /// Supabase. Items / episodes are serialised with their PostgREST column
  /// names (the same shape [MediaItem.fromMap] / [Episode.fromMap] read), so
  /// an export is also a faithful snapshot of the database.
  Map<String, dynamic> buildExportMap(
    List<MediaItem> items,
    List<Episode> episodes,
  ) {
    return <String, dynamic>{
      'format': kExportFormat,
      'version': kExportVersion,
      'exportedAt': _clock().toUtc().toIso8601String(),
      'mediaItems': <Map<String, dynamic>>[
        for (final item in items) item.toMap(),
      ],
      'episodes': <Map<String, dynamic>>[
        for (final episode in episodes) episode.toMap(),
      ],
    };
  }

  /// Pretty-printed JSON of [buildExportMap] — what actually lands in the
  /// file.
  String buildExportJson(List<MediaItem> items, List<Episode> episodes) =>
      const JsonEncoder.withIndent(
        '  ',
      ).convert(buildExportMap(items, episodes));

  /// Fetches the whole library and builds the export document.
  Future<Map<String, dynamic>> buildExportMapFromRepository() async {
    final items = await _repository.fetchAll();
    final episodes = await _repository.fetchAllEpisodes();
    return buildExportMap(items, episodes);
  }

  /// Exports the library as a JSON file.
  ///
  /// On **web** this starts a browser download (Blob + anchor); on **native**
  /// platforms it opens a save dialog. Never throws.
  Future<ExportResult> exportData() async {
    try {
      final map = await buildExportMapFromRepository();
      final json = const JsonEncoder.withIndent('  ').convert(map);
      final bytes = Uint8List.fromList(utf8.encode(json));
      final filename = exportFileName(_clock());
      final saved = await _saveFile(filename, bytes);
      return saved
          ? const ExportResult.success()
          : const ExportResult.cancelled();
    } catch (error) {
      return ExportResult.failure(error);
    }
  }

  /// Web: hand the bytes to the browser.
  static Future<bool> _downloadOnWeb(String filename, Uint8List bytes) async {
    triggerWebDownload(filename, bytes);
    return true;
  }

  /// Native: open a save dialog through `file_picker`.
  static Future<bool> _saveOnNative(String filename, Uint8List bytes) async {
    final uri = await FilePicker.saveFile(
      dialogTitle: 'iwatched',
      fileName: filename,
      bytes: bytes,
      mimeType: 'application/json',
      type: FileType.custom,
      allowedExtensions: const <String>['json'],
    );
    return uri != null;
  }

  // ───────────────────────────────────────────────────────────────────────────
  // import — reading the file
  // ───────────────────────────────────────────────────────────────────────────

  /// Opens the file picker and parses the chosen file.
  ///
  /// Returns `null` when the user cancels. Throws [ImportFormatException] with
  /// an [ImportErrorCode] when the file is not a readable export — the caller
  /// turns the code into localized copy.
  Future<Map<String, dynamic>?> pickAndParseJson() async {
    final bytes = await _loadFileBytes();
    if (bytes == null) return null;
    return parseExport(bytes);
  }

  /// Validates and decodes the raw bytes of a picked file.
  ///
  /// Throws [ImportFormatException] for every structural problem; a missing
  /// optional field inside a row is *not* a problem (see [importData]).
  Map<String, dynamic> parseExport(Uint8List bytes) {
    if (bytes.isEmpty) {
      throw const ImportFormatException(ImportErrorCode.emptyFile);
    }

    final String text;
    try {
      text = utf8.decode(bytes);
    } on FormatException {
      throw const ImportFormatException(ImportErrorCode.invalidJson);
    }
    if (text.trim().isEmpty) {
      throw const ImportFormatException(ImportErrorCode.emptyFile);
    }

    final Object? decoded;
    try {
      decoded = jsonDecode(text);
    } on FormatException {
      throw const ImportFormatException(ImportErrorCode.invalidJson);
    }
    if (decoded is! Map<String, dynamic>) {
      throw const ImportFormatException(ImportErrorCode.notJsonObject);
    }

    _validateExport(decoded);
    return decoded;
  }

  void _validateExport(Map<String, dynamic> data) {
    if (data['format'] != kExportFormat) {
      throw const ImportFormatException(ImportErrorCode.wrongFormat);
    }
    final version = data['version'];
    final parsedVersion = version is num
        ? version.toInt()
        : int.tryParse('$version');
    if (parsedVersion != kExportVersion) {
      throw const ImportFormatException(ImportErrorCode.unsupportedVersion);
    }
    if (data['mediaItems'] is! List) {
      throw const ImportFormatException(ImportErrorCode.missingMediaItems);
    }
    if (data['episodes'] is! List) {
      throw const ImportFormatException(ImportErrorCode.missingEpisodes);
    }
  }

  /// Default picker: a single `*.json` file via `file_picker`.
  ///
  /// `readAsBytes` works on web too (the browser `File` is read lazily), so no
  /// `withData`-style eager load is needed here.
  static Future<Uint8List?> _pickJsonBytes() async {
    final file = await FilePicker.pickFile(
      dialogTitle: 'iwatched',
      type: FileType.custom,
      allowedExtensions: const <String>['json'],
    );
    if (file == null) return null;
    return file.readAsBytes();
  }

  // ───────────────────────────────────────────────────────────────────────────
  // import — writing the data
  // ───────────────────────────────────────────────────────────────────────────

  /// Re-creates the parsed export.
  ///
  /// [overwrite] = `true` deletes **every** media item of the user first
  /// (episodes cascade), then imports everything.
  /// [overwrite] = `false` (merge) keeps the library and skips every imported
  /// item whose `external_source` + `external_id` is already tracked; items
  /// without external ids are always added.
  ///
  /// Never throws: per-entry problems are counted in [ImportResult.errors], a
  /// hard failure is reported through [ImportResult.error].
  Future<ImportResult> importData(
    Map<String, dynamic> data, {
    required bool overwrite,
  }) async {
    final rawItems = (data['mediaItems'] as List?) ?? const <Object?>[];
    final rawEpisodes = (data['episodes'] as List?) ?? const <Object?>[];

    try {
      if (overwrite) await _repository.deleteAll();

      // Merge: remember which external ids are already tracked, so a second
      // import of the same file does not duplicate anything.
      final existingKeys = <String>{};
      if (!overwrite) {
        final existing = await _repository.fetchAll();
        for (final item in existing) {
          final key = _externalKey(item.externalSource, item.externalId);
          if (key != null) existingKeys.add(key);
        }
      }

      var itemsAdded = 0;
      var itemsSkipped = 0;
      var episodesAdded = 0;
      var errors = 0;

      // Old exported item id → new database id, so episodes can be re-linked.
      final Map<String, String> idMap = <String, String>{};

      for (final raw in rawItems) {
        if (raw is! Map) {
          errors++;
          continue;
        }
        final MediaItem parsed;
        try {
          parsed = MediaItem.fromMap(Map<String, dynamic>.from(raw));
        } catch (_) {
          errors++;
          continue;
        }

        final key = _externalKey(parsed.externalSource, parsed.externalId);
        if (!overwrite && key != null && existingKeys.contains(key)) {
          itemsSkipped++;
          continue;
        }

        try {
          final stored = await _repository.insert(parsed.asNew());
          final oldId = parsed.id;
          if (oldId != null && stored.id != null) {
            idMap[oldId] = stored.id!;
          }
          itemsAdded++;
        } catch (_) {
          errors++;
        }
      }

      // Episodes are collected and written in one batch. An episode whose
      // parent was skipped or failed is skipped too — it has nowhere to go.
      final toInsert = <Episode>[];
      for (final raw in rawEpisodes) {
        if (raw is! Map) {
          errors++;
          continue;
        }
        final Episode parsed;
        try {
          parsed = Episode.fromMap(Map<String, dynamic>.from(raw));
        } catch (_) {
          errors++;
          continue;
        }
        final newItemId = idMap[parsed.mediaItemId];
        if (newItemId == null) continue;
        toInsert.add(parsed.asNew().copyWith(mediaItemId: newItemId));
      }

      if (toInsert.isNotEmpty) {
        try {
          final saved = await _repository.upsertEpisodes(toInsert);
          // A repository may return the stored rows; fall back to the payload
          // size when a test double returns nothing.
          episodesAdded = saved.isEmpty ? toInsert.length : saved.length;
        } catch (_) {
          errors++;
        }
      }

      return ImportResult(
        itemsAdded: itemsAdded,
        itemsSkipped: itemsSkipped,
        episodesAdded: episodesAdded,
        errors: errors,
      );
    } on MediaRepositoryException catch (error) {
      return ImportResult(error: error.message);
    } catch (error) {
      // Never let an unexpected error reach the UI as a crash.
      return ImportResult(error: error.toString());
    }
  }

  /// `'<source>|<id>'` when both parts are present, else `null` — the identity
  /// used to recognise an already-tracked item during a merge.
  static String? _externalKey(String? source, String? id) {
    if (source == null || source.isEmpty) return null;
    if (id == null || id.isEmpty) return null;
    return '$source|$id';
  }
}
