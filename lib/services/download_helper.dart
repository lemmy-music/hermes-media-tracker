/// Cross-platform file download helper.
///
/// On **web** the JSON export is handed to the browser as a Blob download; on
/// **native** platforms that is impossible and a save dialog is used instead
/// (see `DataPortService.exportData`). The conditional import below keeps
/// `dart:html` out of the mobile build entirely, so the same service compiles
/// for Android later on.
library;

import 'dart:typed_data';

import 'download_helper_stub.dart'
    if (dart.library.html) 'download_helper_web.dart';

/// Triggers a browser download of [bytes] under [filename].
///
/// Only functional on web; the stub throws [UnsupportedError] elsewhere, so
/// callers must pick this path for the web only (`kIsWeb`).
void triggerWebDownload(String filename, Uint8List bytes) =>
    downloadOnWeb(filename, bytes);
