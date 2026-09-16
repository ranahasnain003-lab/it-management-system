import 'dart:convert';
import 'dart:js_interop';

import 'package:web/web.dart' as web;

Future<Map<String, dynamic>> emulatorRequest(
  String method,
  Uri uri, {
  Object? body,
  bool owner = true,
}) async {
  final headers = web.Headers()..append('Content-Type', 'application/json');

  if (owner) {
    headers.append('Authorization', 'Bearer owner');
  }

  final response = await web.window
      .fetch(
        uri.toString().toJS,
        web.RequestInit(
          method: method,
          headers: headers,
          body: body == null ? null : jsonEncode(body).toJS,
        ),
      )
      .toDart;

  final text = (await response.text().toDart).toDart;

  if (response.status >= 300) {
    throw StateError('$method $uri -> ${response.status}: $text');
  }

  return text.trim().isEmpty ? <String, dynamic>{} : jsonDecode(text) as Map<String, dynamic>;
}
