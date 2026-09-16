// Minimal JSON HTTP client for the Firebase emulator REST APIs, usable from
// both on-device (dart:io) and in-browser (fetch) integration tests.
export 'emulator_http_io.dart'
    if (dart.library.js_interop) 'emulator_http_web.dart';
