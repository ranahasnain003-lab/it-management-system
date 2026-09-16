import 'dart:convert';
import 'dart:io';

Future<Map<String, dynamic>> emulatorRequest(
  String method,
  Uri uri, {
  Object? body,
  bool owner = true,
}) async {
  final client = HttpClient();

  try {
    final request = await client.openUrl(method, uri);
    request.headers.contentType = ContentType.json;

    if (owner) {
      request.headers.set('Authorization', 'Bearer owner');
    }

    if (body != null) {
      request.write(jsonEncode(body));
    }

    final response = await request.close();
    final text = await response.transform(utf8.decoder).join();

    if (response.statusCode >= 300) {
      throw StateError('$method $uri -> ${response.statusCode}: $text');
    }

    return text.trim().isEmpty ? <String, dynamic>{} : jsonDecode(text) as Map<String, dynamic>;
  } finally {
    client.close(force: true);
  }
}
