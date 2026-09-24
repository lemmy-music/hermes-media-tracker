// ignore: avoid_web_libraries_in_flutter, deprecated_member_use
import 'dart:html' as html;
import 'dart:typed_data';

/// Triggers a browser file download on web using a hidden anchor element.
///
/// The bytes are wrapped in an `application/json` Blob, an object URL is
/// created from it and a temporary `<a download>` element is clicked. Both the
/// anchor and the object URL are removed again so nothing leaks.
void downloadOnWeb(String filename, Uint8List bytes) {
  final blob = html.Blob([bytes], 'application/json');
  final url = html.Url.createObjectUrlFromBlob(blob);
  final anchor = html.AnchorElement(href: url)
    ..setAttribute('download', filename)
    ..style.display = 'none';
  html.document.body?.append(anchor);
  anchor.click();
  anchor.remove();
  html.Url.revokeObjectUrl(url);
}
