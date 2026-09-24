import 'dart:typed_data';

/// Stub implementation for non-web platforms.
///
/// Native platforms cannot download through the browser — `DataPortService`
/// uses the `file_picker` save dialog there, so this is never called.
void downloadOnWeb(String filename, Uint8List bytes) {
  throw UnsupportedError('Web download is only available on web.');
}
