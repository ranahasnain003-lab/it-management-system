// Saves generated files (reports, templates) on every platform.
//
// Web: browser download via Blob (file_picker's saveFile is not implemented
// on web in the version this project uses).
// Other platforms: the existing file_picker save dialog.
export 'file_download_io.dart'
    if (dart.library.js_interop) 'file_download_web.dart';
