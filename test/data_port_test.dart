import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:media_tracker/l10n/app_language.dart';
import 'package:media_tracker/l10n/app_strings.dart';
import 'package:media_tracker/main.dart';
import 'package:media_tracker/models/episode.dart';
import 'package:media_tracker/models/import_error.dart';
import 'package:media_tracker/models/media_item.dart';
import 'package:media_tracker/providers/auth_provider.dart';
import 'package:media_tracker/providers/settings_provider.dart';
import 'package:media_tracker/providers/theme_provider.dart';
import 'package:media_tracker/repositories/media_repository.dart';
import 'package:media_tracker/services/data_port_service.dart';

// ─────────────────────────────────────────────────────────────────────────────
// fakes
// ─────────────────────────────────────────────────────────────────────────────

/// In-memory repository. Every write assigns a fresh id — exactly like the
/// database does — so the import can be checked for id remapping.
class _FakeRepository extends MediaRepository {
  _FakeRepository({
    List<MediaItem>? items,
    List<Episode>? episodes,
    this.failFetchAll = false,
    this.failDeleteAll = false,
    this.failInsert = false,
    this.failUpsert = false,
  }) : items = List<MediaItem>.of(items ?? const <MediaItem>[]),
       episodes = List<Episode>.of(episodes ?? const <Episode>[]);

  final List<MediaItem> items;
  final List<Episode> episodes;
  bool failFetchAll;
  bool failDeleteAll;
  bool failInsert;
  bool failUpsert;

  int _idCounter = 0;
  int deleteAllCalls = 0;
  int fetchEpisodesCalls = 0;

  /// The exact payloads handed to [insert] (before an id is assigned).
  final List<MediaItem> insertInputs = <MediaItem>[];

  /// Every batch handed to [upsertEpisodes].
  final List<List<Episode>> upsertBatches = <List<Episode>>[];

  String _newId() => 'new-${++_idCounter}';

  @override
  Future<List<MediaItem>> fetchAll() async {
    if (failFetchAll) {
      throw const MediaRepositoryException('Could not load your library.');
    }
    return List<MediaItem>.of(items);
  }

  @override
  Future<List<Episode>> fetchAllEpisodes() async {
    fetchEpisodesCalls++;
    return List<Episode>.of(episodes);
  }

  @override
  Future<void> deleteAll() async {
    deleteAllCalls++;
    if (failDeleteAll) {
      throw const MediaRepositoryException('Could not delete your data.');
    }
    items.clear();
    episodes.clear();
  }

  @override
  Future<MediaItem> insert(MediaItem item) async {
    insertInputs.add(item);
    if (failInsert) {
      throw const MediaRepositoryException('Could not add the item.');
    }
    final stored = item.copyWith(id: _newId());
    items.add(stored);
    return stored;
  }

  @override
  Future<List<Episode>> upsertEpisodes(List<Episode> episodes) async {
    upsertBatches.add(List<Episode>.of(episodes));
    if (failUpsert) {
      throw const MediaRepositoryException('Could not save the episodes.');
    }
    final saved = <Episode>[];
    for (final episode in episodes) {
      final stored = episode.copyWith(id: 'saved-${++_idCounter}');
      this.episodes.add(stored);
      saved.add(stored);
    }
    return saved;
  }
}

/// Always signed in — no Supabase backend needed.
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

// ─────────────────────────────────────────────────────────────────────────────
// helpers
// ─────────────────────────────────────────────────────────────────────────────

final DateTime _fixedNow = DateTime.utc(2026, 9, 24, 11, 30);

DataPortService _service(
  MediaRepository repository, {
  DateTime? now,
  FileBytesLoader? fileBytesLoader,
  FileSaver? fileSaver,
  bool isWeb = true,
}) => DataPortService(
  repository: repository,
  clock: () => now ?? _fixedNow,
  fileBytesLoader: fileBytesLoader,
  fileSaver: fileSaver,
  isWeb: isWeb,
);

MediaItem _series({
  String id = 'item-1',
  String tmdbId = '705',
  String title = 'Dark',
}) => MediaItem(
  id: id,
  kind: MediaKind.series,
  title: title,
  externalSource: 'tmdb',
  externalId: tmdbId,
  totalSeasons: 1,
  status: MediaStatus.inProgress,
  progressPercent: 40,
  createdAt: DateTime.utc(2026, 1, 1),
  updatedAt: DateTime.utc(2026, 1, 2),
);

Episode _episode({
  String id = 'ep-1',
  String mediaItemId = 'item-1',
  int season = 1,
  int episode = 2,
  bool watched = true,
}) => Episode(
  id: id,
  mediaItemId: mediaItemId,
  seasonNumber: season,
  episodeNumber: episode,
  name: 'Episode $season-$episode',
  watched: watched,
  watchedAt: watched ? DateTime.utc(2026, 2, 1) : null,
  createdAt: DateTime.utc(2026, 1, 5),
);

Uint8List _bytes(Object json) =>
    Uint8List.fromList(utf8.encode(json is String ? json : jsonEncode(json)));

Matcher _throwsCode(ImportErrorCode code) => throwsA(
  isA<ImportFormatException>().having((error) => error.code, 'code', code),
);

// ─────────────────────────────────────────────────────────────────────────────
// tests
// ─────────────────────────────────────────────────────────────────────────────

void main() {
  setUp(() => SharedPreferences.setMockInitialValues(<String, Object>{}));

  group('export', () {
    test('builds the versioned JSON document with all items and episodes', () {
      final service = _service(_FakeRepository());
      final map = service.buildExportMap(
        [_series()],
        [_episode(), _episode(id: 'ep-2', episode: 3, watched: false)],
      );

      expect(map['format'], 'media-tracker-export');
      expect(map['version'], 1);
      expect(map['exportedAt'], '2026-09-24T11:30:00.000Z');
      expect(map['mediaItems'], hasLength(1));
      expect(map['episodes'], hasLength(2));

      final item = (map['mediaItems'] as List).single as Map<String, dynamic>;
      expect(item['id'], 'item-1');
      expect(item['kind'], 'series');
      expect(item['external_source'], 'tmdb');
      expect(item['status'], 'in_progress');

      final episodes = map['episodes'] as List;
      final first = episodes.first as Map<String, dynamic>;
      expect(first['media_item_id'], 'item-1');
      expect(first['watched'], isTrue);
      expect(first['watched_at'], isNotNull);
      final second = episodes.last as Map<String, dynamic>;
      expect(second['watched'], isFalse);
      expect(second.containsKey('watched_at'), isFalse);
    });

    test('serialises an empty library without crashing', () {
      final service = _service(_FakeRepository());
      final map = service.buildExportMap(
        const <MediaItem>[],
        const <Episode>[],
      );
      expect(map['mediaItems'], isEmpty);
      expect(map['episodes'], isEmpty);
    });

    test('file name follows media_tracker_export_<date>_<time>.json', () {
      expect(
        DataPortService.exportFileName(DateTime(2026, 9, 24, 11, 30)),
        'media_tracker_export_2026-09-24_1130.json',
      );
      expect(
        DataPortService.exportFileName(DateTime(2026, 1, 5, 9, 7)),
        'media_tracker_export_2026-01-05_0907.json',
      );
    });

    test('exportData hands the JSON to the injected saver', () async {
      final repository = _FakeRepository(
        items: [_series()],
        episodes: [_episode()],
      );
      String? fileName;
      Uint8List? fileBytes;
      final service = _service(
        repository,
        fileSaver: (name, bytes) async {
          fileName = name;
          fileBytes = bytes;
          return true;
        },
      );

      final result = await service.exportData();

      expect(result.isSuccess, isTrue);
      expect(repository.fetchEpisodesCalls, 1);
      expect(fileName, 'media_tracker_export_2026-09-24_1130.json');
      final decoded =
          jsonDecode(utf8.decode(fileBytes!)) as Map<String, dynamic>;
      expect(decoded['format'], 'media-tracker-export');
      expect(decoded['mediaItems'], hasLength(1));
      expect(decoded['episodes'], hasLength(1));
    });

    test('a cancelled save reports cancelled', () async {
      final service = _service(
        _FakeRepository(),
        fileSaver: (_, _) async => false,
      );
      final result = await service.exportData();
      expect(result.status, ExportStatus.cancelled);
    });

    test('a failing load is reported, never thrown', () async {
      final service = _service(_FakeRepository(failFetchAll: true));
      final result = await service.exportData();
      expect(result.status, ExportStatus.failure);
      expect(result.error, isNotNull);
    });
  });

  group('import — reading the file', () {
    test('parses a valid export', () {
      final service = _service(_FakeRepository());
      final valid = service.buildExportMap([_series()], [_episode()]);
      final parsed = service.parseExport(_bytes(valid));
      expect(parsed['format'], 'media-tracker-export');
    });

    test('returns null when the picker is cancelled', () async {
      final service = _service(
        _FakeRepository(),
        fileBytesLoader: () async => null,
      );
      expect(await service.pickAndParseJson(), isNull);
    });

    test('pickAndParseJson decodes the picked bytes', () async {
      final service = _service(
        _FakeRepository(),
        fileBytesLoader: () async => _bytes(
          jsonEncode(<String, dynamic>{
            'format': 'media-tracker-export',
            'version': 1,
            'mediaItems': <Object?>[],
            'episodes': <Object?>[],
          }),
        ),
      );
      final parsed = await service.pickAndParseJson();
      expect(parsed, isNotNull);
      expect(parsed!['version'], 1);
    });

    test('rejects an empty file', () {
      final service = _service(_FakeRepository());
      expect(
        () => service.parseExport(Uint8List(0)),
        _throwsCode(ImportErrorCode.emptyFile),
      );
      expect(
        () => service.parseExport(_bytes('   \n ')),
        _throwsCode(ImportErrorCode.emptyFile),
      );
    });

    test('rejects invalid JSON and invalid UTF-8', () {
      final service = _service(_FakeRepository());
      expect(
        () => service.parseExport(_bytes('not json at all')),
        _throwsCode(ImportErrorCode.invalidJson),
      );
      expect(
        () => service.parseExport(Uint8List.fromList(<int>[0xff, 0xfe, 0xfd])),
        _throwsCode(ImportErrorCode.invalidJson),
      );
    });

    test('rejects a non-object root', () {
      final service = _service(_FakeRepository());
      expect(
        () => service.parseExport(_bytes('[1, 2, 3]')),
        _throwsCode(ImportErrorCode.notJsonObject),
      );
    });

    test('rejects a wrong format marker', () {
      final service = _service(_FakeRepository());
      final map = <String, dynamic>{
        'format': 'habit-doc-export',
        'version': 1,
        'mediaItems': <Object?>[],
        'episodes': <Object?>[],
      };
      expect(
        () => service.parseExport(_bytes(map)),
        _throwsCode(ImportErrorCode.wrongFormat),
      );
    });

    test('rejects an unsupported version', () {
      final service = _service(_FakeRepository());
      for (final version in <Object?>[2, '2', null]) {
        final map = <String, dynamic>{
          'format': 'media-tracker-export',
          'version': version,
          'mediaItems': <Object?>[],
          'episodes': <Object?>[],
        };
        expect(
          () => service.parseExport(_bytes(map)),
          _throwsCode(ImportErrorCode.unsupportedVersion),
          reason: 'version: $version',
        );
      }
    });

    test('rejects missing lists', () {
      final service = _service(_FakeRepository());
      expect(
        () => service.parseExport(
          _bytes(<String, dynamic>{
            'format': 'media-tracker-export',
            'version': 1,
            'episodes': <Object?>[],
          }),
        ),
        _throwsCode(ImportErrorCode.missingMediaItems),
      );
      expect(
        () => service.parseExport(
          _bytes(<String, dynamic>{
            'format': 'media-tracker-export',
            'version': 1,
            'mediaItems': <Object?>[],
          }),
        ),
        _throwsCode(ImportErrorCode.missingEpisodes),
      );
      expect(
        () => service.parseExport(
          _bytes(<String, dynamic>{
            'format': 'media-tracker-export',
            'version': 1,
            'mediaItems': 'oops',
            'episodes': <Object?>[],
          }),
        ),
        _throwsCode(ImportErrorCode.missingMediaItems),
      );
    });
  });

  group('import — writing the data', () {
    test('merge adds everything and remaps ids + episode links', () async {
      final seed = _service(_FakeRepository());
      final export = seed.buildExportMap(
        [_series()],
        [_episode(), _episode(id: 'ep-2', season: 1, episode: 3)],
      );

      final repository = _FakeRepository();
      final service = _service(repository);
      final result = await service.importData(export, overwrite: false);

      expect(result.isSuccess, isTrue);
      expect(result.itemsAdded, 1);
      expect(result.itemsSkipped, 0);
      expect(result.episodesAdded, 2);
      expect(result.errors, 0);

      // The exported id / user_id / timestamps are never carried over.
      expect(repository.insertInputs.single.id, isNull);
      expect(repository.insertInputs.single.createdAt, isNull);
      expect(repository.insertInputs.single.updatedAt, isNull);

      // The stored item got a fresh id…
      expect(repository.items.single.id, 'new-1');
      expect(repository.items.single.externalId, '705');

      // …and both episodes point at it, with the watch state preserved.
      final batch = repository.upsertBatches.single;
      expect(batch, hasLength(2));
      for (final episode in batch) {
        expect(episode.id, isNull);
        expect(episode.mediaItemId, 'new-1');
        expect(episode.watched, isTrue);
        expect(episode.watchedAt, DateTime.utc(2026, 2, 1).toLocal());
      }
    });

    test('merge skips items already tracked by external id', () async {
      final repository = _FakeRepository(items: [_series(id: 'existing')]);
      final export = _service(
        _FakeRepository(),
      ).buildExportMap([_series()], [_episode()]);

      final result = await _service(
        repository,
      ).importData(export, overwrite: false);

      expect(result.itemsAdded, 0);
      expect(result.itemsSkipped, 1);
      // The skipped item's episodes have nowhere to go.
      expect(result.episodesAdded, 0);
      expect(repository.insertInputs, isEmpty);
      expect(repository.upsertBatches, isEmpty);
      expect(repository.items, hasLength(1));
    });

    test('merge always adds items without external ids', () async {
      final repository = _FakeRepository();
      final export = _service(_FakeRepository()).buildExportMap([
        const MediaItem(kind: MediaKind.book, title: 'Dune'),
      ], const <Episode>[]);

      final result = await _service(
        repository,
      ).importData(export, overwrite: false);

      expect(result.itemsAdded, 1);
      expect(result.itemsSkipped, 0);
      expect(repository.items.single.title, 'Dune');
    });

    test('overwrite deletes everything first', () async {
      final repository = _FakeRepository(
        items: [_series(id: 'old-1', tmdbId: '999')],
        episodes: [_episode(id: 'old-ep', mediaItemId: 'old-1')],
      );
      final export = _service(
        _FakeRepository(),
      ).buildExportMap([_series()], [_episode()]);

      final result = await _service(
        repository,
      ).importData(export, overwrite: true);

      expect(repository.deleteAllCalls, 1);
      expect(result.itemsAdded, 1);
      expect(result.itemsSkipped, 0);
      expect(result.episodesAdded, 1);
      // The old item is gone, only the freshly imported one remains.
      expect(repository.items.single.id, 'new-1');
      expect(repository.items.single.externalId, '705');
    });

    test('remaps two items and routes each episode correctly', () async {
      final export = _service(_FakeRepository()).buildExportMap(
        [
          _series(id: 'old-a', tmdbId: '1', title: 'A'),
          _series(id: 'old-b', tmdbId: '2', title: 'B'),
        ],
        [
          _episode(id: 'ep-a', mediaItemId: 'old-a', watched: true),
          _episode(id: 'ep-b', mediaItemId: 'old-b', watched: false),
        ],
      );

      final repository = _FakeRepository();
      final result = await _service(
        repository,
      ).importData(export, overwrite: false);

      expect(result.itemsAdded, 2);
      final byExternal = <String, MediaItem>{
        for (final item in repository.items) item.externalId!: item,
      };
      expect(byExternal.keys, containsAll(<String>['1', '2']));

      final batch = repository.upsertBatches.single;
      final watchState = <String, bool>{
        for (final episode in batch) episode.mediaItemId: episode.watched,
      };
      expect(watchState[byExternal['1']!.id], isTrue);
      expect(watchState[byExternal['2']!.id], isFalse);
    });

    test('counts bad rows as errors instead of crashing', () async {
      final repository = _FakeRepository();
      final service = _service(repository);
      final result = await service.importData(<String, dynamic>{
        'format': 'media-tracker-export',
        'version': 1,
        'mediaItems': <Object?>[
          'not an object',
          <String, dynamic>{'kind': 'podcast', 'title': 'Unknown kind'},
          <String, dynamic>{'kind': 'movie', 'title': 'Inception'},
        ],
        'episodes': <Object?>[
          42,
          <String, dynamic>{
            'media_item_id': 'not-in-export',
            'season_number': 1,
            'episode_number': 1,
          },
        ],
      }, overwrite: false);

      expect(result.isSuccess, isTrue);
      expect(result.itemsAdded, 1);
      // The non-object, the unknown kind and the non-object episode.
      expect(result.errors, 3);
      // The orphan episode is silently skipped (its parent is not there).
      expect(result.episodesAdded, 0);
    });

    test('a hard failure is reported, not thrown', () async {
      final service = _service(_FakeRepository(failDeleteAll: true));
      final export = service.buildExportMap([_series()], const <Episode>[]);
      final result = await service.importData(export, overwrite: true);
      expect(result.isSuccess, isFalse);
      expect(result.error, contains('delete'));
    });

    test('a failing insert counts as an error', () async {
      final repository = _FakeRepository(failInsert: true);
      final export = _service(
        _FakeRepository(),
      ).buildExportMap([_series()], [_episode()]);
      final result = await _service(
        repository,
      ).importData(export, overwrite: false);
      expect(result.itemsAdded, 0);
      expect(result.errors, 1);
      expect(result.episodesAdded, 0);
      expect(result.isSuccess, isTrue);
    });

    test('a failing episode batch is counted as an error', () async {
      final repository = _FakeRepository(failUpsert: true);
      final export = _service(
        _FakeRepository(),
      ).buildExportMap([_series()], [_episode()]);
      final result = await _service(
        repository,
      ).importData(export, overwrite: false);
      expect(result.itemsAdded, 1);
      expect(result.episodesAdded, 0);
      expect(result.errors, 1);
      expect(result.isSuccess, isTrue);
    });
  });

  group('localization', () {
    const de = AppStrings(AppLanguage.de);
    const en = AppStrings(AppLanguage.en);

    test('every import error code has localized copy in both languages', () {
      for (final code in ImportErrorCode.values) {
        final german = de.importErrorMessage(code);
        final english = en.importErrorMessage(code);
        expect(german.trim(), isNotEmpty, reason: code.name);
        expect(english.trim(), isNotEmpty, reason: code.name);
        expect(german, isNot(code.name), reason: code.name);
        expect(german, isNot(english), reason: code.name);
      }
    });

    test('the summary string injects the counters', () {
      expect(en.importSummary(12, 3, 0), '12 added, 3 skipped, 0 errors');
      expect(
        de.importSummary(12, 3, 0),
        '12 hinzugefügt, 3 übersprungen, 0 Fehler',
      );
    });

    test('the new settings strings differ between the languages', () {
      final pairs = <(String, String)>[
        (de.dataExport, en.dataExport),
        (de.dataExportSubtitle, en.dataExportSubtitle),
        (de.dataImport, en.dataImport),
        (de.dataImportSubtitle, en.dataImportSubtitle),
        (de.exporting, en.exporting),
        (de.exportDone, en.exportDone),
        (de.exportFailedTitle, en.exportFailedTitle),
        (de.exportCancelled, en.exportCancelled),
        (de.importing, en.importing),
        (de.importModeTitle, en.importModeTitle),
        (de.importModeMessage, en.importModeMessage),
        (de.importMerge, en.importMerge),
        (de.importOverwrite, en.importOverwrite),
        (de.importOverwriteConfirmTitle, en.importOverwriteConfirmTitle),
        (de.importOverwriteConfirmMessage, en.importOverwriteConfirmMessage),
        (de.importOverwriteConfirmAction, en.importOverwriteConfirmAction),
        (de.importFailedTitle, en.importFailedTitle),
        (de.importUnknownError, en.importUnknownError),
      ];
      for (final (german, english) in pairs) {
        expect(german.trim(), isNotEmpty);
        expect(english.trim(), isNotEmpty);
        expect(german, isNot(english));
      }
      expect(de.dataExport, 'Daten exportieren');
      expect(en.dataExport, 'Export data');
      expect(de.importMerge, 'Zusammenführen');
      expect(en.importOverwrite, 'Overwrite');
    });
  });

  group('settings sheet', () {
    testWidgets('offers export and import', (tester) async {
      await tester.pumpWidget(
        MediaTrackerApp(
          themeProvider: ThemeProvider(),
          settingsProvider: SettingsProvider(initial: AppLanguage.en),
          authProvider: _FakeAuth(),
          repository: _FakeRepository(),
        ),
      );
      await tester.pump();

      await tester.tap(find.byIcon(Icons.settings));
      await tester.pumpAndSettle();

      expect(find.text('Export data'), findsOneWidget);
      expect(find.text('Import data'), findsOneWidget);
    });

    testWidgets('renders the German labels too', (tester) async {
      await tester.pumpWidget(
        MediaTrackerApp(
          themeProvider: ThemeProvider(),
          settingsProvider: SettingsProvider(),
          authProvider: _FakeAuth(),
          repository: _FakeRepository(),
        ),
      );
      await tester.pump();

      await tester.tap(find.byIcon(Icons.settings));
      await tester.pumpAndSettle();

      expect(find.text('Daten exportieren'), findsOneWidget);
      expect(find.text('Daten importieren'), findsOneWidget);
    });
  });
}
