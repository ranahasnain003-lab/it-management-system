import 'dart:js_interop';
import 'dart:typed_data';

import 'package:web/web.dart' as web;

/// Triggers a browser download. Always returns true (browsers do not report
/// whether the user kept the file).
Future<bool> saveBytesAsFile({
  required String fileName,
  required Uint8List bytes,
  required String mimeType,
  String dialogTitle = 'Save file',
}) async {
  final blob = web.Blob(
    <JSAny>[bytes.toJS].toJS,
    web.BlobPropertyBag(type: mimeType),
  );

  final url = web.URL.createObjectURL(blob);

  final anchor = web.HTMLAnchorElement()
    ..href = url
    ..download = fileName
    ..style.display = 'none';

  web.document.body?.appendChild(anchor);
  anchor.click();
  anchor.remove();

  // Give the browser a moment to start the download before revoking.
  Future<void>.delayed(const Duration(seconds: 2), () {
    web.URL.revokeObjectURL(url);
  });

  return true;
}
