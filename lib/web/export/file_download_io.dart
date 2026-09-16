import 'dart:typed_data';

import 'package:file_picker/file_picker.dart';

/// Returns true when the file was saved, false if the user cancelled.
Future<bool> saveBytesAsFile({
  required String fileName,
  required Uint8List bytes,
  required String mimeType,
  String dialogTitle = 'Save file',
}) async {
  final extension = fileName.contains('.') ? fileName.split('.').last : '';

  final result = await FilePicker.platform.saveFile(
    dialogTitle: dialogTitle,
    fileName: fileName,
    type: extension.isEmpty ? FileType.any : FileType.custom,
    allowedExtensions: extension.isEmpty ? null : [extension],
    bytes: bytes,
  );

  return result != null;
}
