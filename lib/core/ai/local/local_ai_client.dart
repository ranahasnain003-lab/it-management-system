/// HTTP client for the Local AI server's `/api/v1`.
///
/// Written against the server's own contract (docs/API.md): NDJSON streaming,
/// the documented error codes, `Authorization: Bearer <key>`, and
/// `X-Conversation-Scope` for keeping one device's users apart. Nothing here
/// is guessed.
///
/// It knows nothing about Firebase. No Firebase credential, ID token or email
/// address is ever sent to the Local AI server - the only identity it receives
/// is the API key, plus an opaque scope string the caller supplies. The only
/// app data it carries is the `appContext` the caller built for a question.
library;

import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

import 'local_ai_config.dart';
import 'local_ai_http.dart';
import 'local_ai_models.dart';

/// An answer arriving a piece at a time, with a way to stop it.
class LocalAiStream {
  LocalAiStream({
    required this.events,
    required this._finished,
    required this._requestStop,
    required this._abort,
    required this._conversationId,
  }) {
    _finished.whenComplete(() => _isFinished = true).ignore();
  }

  /// start / sources / delta / done / error, in the contract's order.
  /// `ping` and unknown events are filtered out before they reach here.
  final Stream<LocalAiEvent> events;

  final Future<void> _finished;
  final Future<void> Function(String conversationId) _requestStop;
  final void Function() _abort;
  final String? Function() _conversationId;
  bool _isFinished = false;

  /// How long [stop] waits for the server's own `done` before it drops the
  /// connection instead.
  static const Duration defaultStopGrace = Duration(seconds: 5);

  /// The conversation this answer belongs to, once `start` has arrived.
  String? get conversationId => _conversationId();

  /// True once the stream has ended, for whatever reason.
  bool get isFinished => _isFinished;

  /// Stops the answer and keeps what was written.
  ///
  /// When the conversation is known, the server is told through its stop
  /// endpoint and the stream is left open: the server then ends it with a
  /// `done` event whose status is `stopped` and whose content is the partial
  /// answer, so the app shows exactly what the server saved. Only if that has
  /// not arrived within [grace] - an unreachable laptop, a stop request lost
  /// on the way - is the connection dropped, which the server also treats as
  /// a stop. Before `start` there is no conversation to name, so the
  /// connection is dropped at once.
  ///
  /// Never throws.
  Future<void> stop({Duration grace = defaultStopGrace}) async {
    if (_isFinished) return;

    final id = conversationId;
    if (id == null || id.isEmpty) {
      abort();
      return;
    }

    // Not awaited on its own: the grace period covers the stop request AND
    // the wait for `done`, so a slow network cannot stretch "Stopping…".
    unawaited(() async {
      try {
        await _requestStop(id);
      } catch (error) {
        debugPrint('Local AI: the stop request failed ($error)');
      }
    }());

    var ended = false;
    try {
      await _finished.timeout(grace);
      ended = true;
    } on TimeoutException {
      ended = false;
    } catch (_) {
      ended = true;
    }
    if (!ended) abort();
  }

  /// Drops the connection now. The server notices, stops Ollama and saves
  /// the partial answer as `stopped`; this stream then ends without `done`.
  void abort() => _abort();
}

class LocalAiClient {
  LocalAiClient({http.Client Function(LocalAiConfig config)? clientFactory})
    : _clientFactory =
          clientFactory ??
          ((config) => createLocalAiHttpClient(
            pinnedSha256: config.certificateFingerprint,
          ));

  /// A fresh client for every request, made for that request's configuration
  /// so the certificate pin in force is always the one just saved.
  ///
  /// Injected so tests can drive every path - success, 401, malformed body,
  /// dropped connection - without a server.
  final http.Client Function(LocalAiConfig config) _clientFactory;

  /// How long to wait for the first byte of a reply.
  ///
  /// Generous, because a cold Qwen3 8B on CPU can take a while to load before
  /// it says anything. Once the stream has started the server's own 15s `ping`
  /// keeps it alive, so this is not applied to the whole answer.
  static const Duration connectTimeout = Duration(seconds: 45);

  /// How long to wait between two lines of a stream before giving up.
  ///
  /// Longer than the server's 15s heartbeat, so a healthy but slow answer is
  /// never abandoned - only a genuinely dead connection is.
  static const Duration idleTimeout = Duration(seconds: 40);

  static const Duration _shortTimeout = Duration(seconds: 15);

  // ===========================================================================
  // HEALTH AND MODEL
  // ===========================================================================

  /// `GET /api/v1/health`. Used by the connection test, the status banner,
  /// and to check an address discovery found before it is saved.
  Future<LocalAiHealth> health(LocalAiConfig config) async {
    final json = await _getJson(config, '/health');
    return LocalAiHealth.fromJson(json);
  }

  /// `GET /api/v1/model`.
  Future<LocalAiModelInfo> model(LocalAiConfig config) async {
    final json = await _getJson(config, '/model');
    return LocalAiModelInfo.fromJson(json);
  }

  // ===========================================================================
  // CHAT
  // ===========================================================================

  /// Asks a question and streams the answer.
  ///
  /// [scope] is the opaque per-user value sent as `X-Conversation-Scope`. The
  /// server makes (key, scope) the owner of a conversation, so a different
  /// scope cannot list, continue, read or delete it - that is what keeps two
  /// people signed in on the same device apart.
  ///
  /// [appContext] is the IT Inventory data for this question
  /// (`LocalAiAppContext.toJson()`), sent as-is.
  LocalAiStream ask({
    required LocalAiConfig config,
    required String message,
    required String scope,
    String? conversationId,
    LocalAiDocumentsMode documents = LocalAiDocumentsMode.off,
    Map<String, dynamic>? appContext,
  }) {
    final controller = StreamController<LocalAiEvent>();
    final client = _clientFactory(config);
    var aborted = false;
    String? startedConversation;

    void abort() {
      if (aborted) return;
      aborted = true;
      // Closing the client aborts the request. The contract says the server
      // notices the disconnect, stops Ollama and saves the partial answer.
      client.close();
    }

    final finished = _runStream(
      client: client,
      controller: controller,
      config: config,
      message: message,
      scope: scope,
      conversationId: conversationId,
      documents: documents,
      appContext: appContext,
      wasAborted: () => aborted,
      onStart: (id) => startedConversation = id,
    );

    return LocalAiStream(
      events: controller.stream,
      finished: finished,
      requestStop: (id) =>
          stopAnswer(config: config, conversationId: id, scope: scope),
      abort: abort,
      conversationId: () => startedConversation,
    );
  }

  Future<void> _runStream({
    required http.Client client,
    required StreamController<LocalAiEvent> controller,
    required LocalAiConfig config,
    required String message,
    required String scope,
    required String? conversationId,
    required LocalAiDocumentsMode documents,
    required Map<String, dynamic>? appContext,
    required bool Function() wasAborted,
    required void Function(String conversationId) onStart,
  }) async {
    try {
      _requireConfigured(config);

      final request = http.Request('POST', Uri.parse('${config.apiRoot}/ai/chat'))
        ..headers.addAll(_headers(config, scope))
        ..headers['accept'] = 'application/x-ndjson'
        ..body = jsonEncode({
          'message': message,
          'stream': true,
          'documents': documents.wire,
          'conversationId': ?conversationId,
          'appContext': ?appContext,
        });

      final response = await client.send(request).timeout(connectTimeout);

      // Anything that goes wrong BEFORE the stream starts arrives as a normal
      // JSON error, per the contract. Only once 200 is returned do failures
      // arrive in-band as error events.
      if (response.statusCode != 200) {
        final body = await response.stream.bytesToString().timeout(_shortTimeout);
        throw _errorFromBody(response.statusCode, body, response.headers);
      }

      await for (final line in _lines(response.stream)) {
        if (controller.isClosed) break;

        final event = _decodeLine(line);
        if (event == null) continue;

        // The heartbeat exists to hold the socket open through a long pause;
        // it carries nothing, so it never reaches the caller. Unknown events
        // are dropped for the same reason: the contract requires that a client
        // tolerate events added after it was written.
        if (event is LocalAiPingEvent || event is LocalAiUnknownEvent) continue;

        if (event is LocalAiStartEvent) onStart(event.conversationId);
        controller.add(event);
      }
    } on LocalAiException catch (error) {
      if (!wasAborted() && !controller.isClosed) controller.addError(error);
    } on TimeoutException {
      if (!wasAborted() && !controller.isClosed) {
        controller.addError(
          const LocalAiException(
            code: LocalAiException.timedOut,
            message:
                'The Local AI server did not reply in time. It may be loading '
                'the model, or busy with another answer.',
          ),
        );
      }
    } catch (error) {
      // A closed client during a deliberate stop surfaces here as a socket
      // error. That is not a failure: the user asked for it.
      if (!wasAborted() && !controller.isClosed) {
        controller.addError(_transportError(error, config));
      }
    } finally {
      client.close();
      if (!controller.isClosed) await controller.close();
    }
  }

  /// `POST /api/v1/ai/conversations/:id/stop`.
  ///
  /// Preferred over simply dropping the connection when the conversation id is
  /// known: on a phone, aborting mid-TLS is not always noticed promptly, while
  /// this tells the server in as many words. Returns whether an answer was
  /// being generated.
  ///
  /// Every failure is a [LocalAiException]; a dropped connection or a timeout
  /// never escapes as a raw transport error.
  Future<bool> stopAnswer({
    required LocalAiConfig config,
    required String conversationId,
    required String scope,
  }) {
    return _guard(config, () async {
      final client = _clientFactory(config);
      try {
        final response = await client
            .post(
              Uri.parse(
                '${config.apiRoot}/ai/conversations/'
                '${Uri.encodeComponent(conversationId)}/stop',
              ),
              headers: _headers(config, scope),
            )
            .timeout(_shortTimeout);

        if (response.statusCode == 404) return false;
        if (response.statusCode >= 400) {
          throw _errorFromBody(response.statusCode, response.body, response.headers);
        }

        final json = _decodeObject(response.body);
        return json['stopped'] == true;
      } finally {
        client.close();
      }
    });
  }

  /// `DELETE /api/v1/ai/conversations/:id`.
  ///
  /// Every failure is a [LocalAiException], as for [stopAnswer].
  Future<void> deleteConversation({
    required LocalAiConfig config,
    required String conversationId,
    required String scope,
  }) {
    return _guard(config, () async {
      final client = _clientFactory(config);
      try {
        final response = await client
            .delete(
              Uri.parse(
                '${config.apiRoot}/ai/conversations/'
                '${Uri.encodeComponent(conversationId)}',
              ),
              headers: _headers(config, scope),
            )
            .timeout(_shortTimeout);

        // 404 means it is already gone, or belongs to another scope. Either way
        // there is nothing left to delete, so it is not an error here.
        if (response.statusCode == 404 || response.statusCode < 400) return;

        throw _errorFromBody(response.statusCode, response.body, response.headers);
      } finally {
        client.close();
      }
    });
  }

  // ===========================================================================
  // PLUMBING
  // ===========================================================================

  Future<Map<String, dynamic>> _getJson(LocalAiConfig config, String path) {
    return _guard(config, () async {
      final client = _clientFactory(config);
      try {
        final response = await client
            .get(Uri.parse('${config.apiRoot}$path'), headers: _headers(config, null))
            .timeout(_shortTimeout);

        if (response.statusCode >= 400) {
          throw _errorFromBody(response.statusCode, response.body, response.headers);
        }

        return _decodeObject(response.body);
      } finally {
        client.close();
      }
    });
  }

  /// Runs one short request and turns whatever goes wrong into a
  /// [LocalAiException], so no caller ever has to know what a
  /// SocketException, a ClientException or a HandshakeException is.
  Future<T> _guard<T>(LocalAiConfig config, Future<T> Function() request) async {
    try {
      _requireConfigured(config);
      return await request();
    } on LocalAiException {
      rethrow;
    } on TimeoutException {
      throw const LocalAiException(
        code: LocalAiException.timedOut,
        message: 'The Local AI server did not reply in time.',
      );
    } catch (error) {
      throw _transportError(error, config);
    }
  }

  Map<String, String> _headers(LocalAiConfig config, String? scope) {
    return {
      'content-type': 'application/json',
      if (config.apiKey.isNotEmpty) 'authorization': 'Bearer ${config.apiKey}',
      // Opaque, and never a Firebase uid, token or address - see
      // LocalAiScope, which derives it before anything leaves the app.
      if (scope != null && scope.isNotEmpty) 'x-conversation-scope': scope,
    };
  }

  void _requireConfigured(LocalAiConfig config) {
    if (!config.isConfigured) {
      throw const LocalAiException(
        code: LocalAiException.notConfigured,
        message:
            'No Local AI server address is configured. An administrator can '
            'set one in Settings > AI Assistant server.',
      );
    }
  }

  /// Splits a byte stream into NDJSON lines.
  ///
  /// A chunk boundary can fall anywhere, including inside a multi-byte UTF-8
  /// character, so the bytes are decoded as a stream rather than per chunk -
  /// otherwise Urdu text would break apart at random. The contract guarantees
  /// every line ends with `\n`, including the last, so no partial line is left
  /// over at the end.
  Stream<String> _lines(http.ByteStream body) {
    return body
        .transform(utf8.decoder)
        .transform(const LineSplitter())
        .timeout(
          idleTimeout,
          onTimeout: (sink) => sink.addError(
            const LocalAiException(
              code: LocalAiException.timedOut,
              message:
                  'The Local AI server stopped responding part-way through the '
                  'answer. The connection may have been lost.',
            ),
          ),
        );
  }

  /// One line to one event, or null for a blank or unreadable line.
  ///
  /// An unreadable line is skipped rather than thrown, because a single bad
  /// line must not throw away an answer that is otherwise arriving fine.
  LocalAiEvent? _decodeLine(String line) {
    final trimmed = line.trim();
    if (trimmed.isEmpty) return null;

    try {
      final decoded = jsonDecode(trimmed);
      if (decoded is! Map) return null;
      return LocalAiEvent.fromJson(Map<String, dynamic>.from(decoded));
    } on FormatException {
      debugPrint('Local AI: skipped an unreadable stream line');
      return null;
    }
  }

  Map<String, dynamic> _decodeObject(String body) {
    try {
      final decoded = jsonDecode(body);
      if (decoded is Map) return Map<String, dynamic>.from(decoded);
    } on FormatException {
      // Falls through to the throw below.
    }

    throw const LocalAiException(
      code: LocalAiException.malformed,
      message:
          'The Local AI server sent a reply this app could not read. Check that '
          'the address points at the Local AI server and not something else.',
    );
  }

  /// Builds the exception for a non-2xx response, preferring the server's own
  /// code and message over anything invented here.
  LocalAiException _errorFromBody(
    int status,
    String body,
    Map<String, String> headers,
  ) {
    String code;
    String message;

    try {
      final decoded = jsonDecode(body);
      final error = decoded is Map ? decoded['error'] : null;
      code = error is Map && error['code'] is String
          ? error['code'] as String
          : _codeForStatus(status);
      message = error is Map && error['message'] is String
          ? error['message'] as String
          : _messageForStatus(status);
    } on FormatException {
      // Not JSON at all: usually something that is not the Local AI server.
      code = _codeForStatus(status);
      message = _messageForStatus(status);
    }

    final retryAfter = int.tryParse((headers['retry-after'] ?? '').trim());

    return LocalAiException(
      code: code,
      message: message,
      status: status,
      retryAfter: retryAfter == null || retryAfter < 0
          ? null
          : Duration(seconds: retryAfter),
    );
  }

  /// The code for a reply without the contract's error body. Every error the
  /// Local AI server sends has one, so this mostly names what a proxy or some
  /// other program at the address said - never a conversation-specific code,
  /// which would send the app off retrying the wrong thing.
  String _codeForStatus(int status) {
    switch (status) {
      case 400:
        return LocalAiException.invalidRequest;
      case 401:
        return LocalAiException.unauthorized;
      case 403:
        return LocalAiException.invalidApiKey;
      case 404:
        return LocalAiException.notFound;
      case 409:
        return LocalAiException.conflict;
      case 413:
        return LocalAiException.payloadTooLarge;
      case 429:
        return LocalAiException.rateLimited;
      case 500:
        return LocalAiException.internalError;
      case 503:
        return LocalAiException.serverBusy;
      default:
        return LocalAiException.malformed;
    }
  }

  String _messageForStatus(int status) {
    switch (status) {
      case 400:
        return 'The Local AI server could not read this request.';
      case 401:
        return 'The Local AI server needs an API key. An administrator can set '
            'one in Settings > AI Assistant server.';
      case 403:
        return 'The Local AI server rejected this API key.';
      case 404:
        return 'Nothing at this address answers like the Local AI server. '
            'Check the address in Settings > AI Assistant server.';
      case 413:
        return 'The question and its inventory data are too large to send.';
      case 429:
        return 'Too many questions at once. Please wait a moment.';
      case 500:
        return 'The Local AI server hit an unexpected error.';
      case 503:
        return 'The Local AI server is busy. Please try again shortly.';
      default:
        return 'The Local AI server returned an unexpected response ($status).';
    }
  }

  /// A failure that never reached the server: laptop off, Wi-Fi changed,
  /// wrong address, certificate refused.
  LocalAiException _transportError(Object error, LocalAiConfig config) {
    final text = error.toString();

    if (text.contains('CERTIFICATE') || text.contains('HandshakeException')) {
      return LocalAiException(
        code: LocalAiException.unreachable,
        message: config.isPinned
            ? 'The Local AI server\'s certificate does not match the pinned '
                  'fingerprint, so the connection was refused. If the '
                  'certificate was re-created on the laptop, update the '
                  'fingerprint in Settings > AI Assistant server.'
            : 'The Local AI server\'s HTTPS certificate is not trusted by this '
                  'device. Enter its SHA-256 fingerprint (printed by '
                  'create-certificate.ps1) in Settings > AI Assistant server, '
                  'or use "Find server on this network".',
      );
    }

    // A browser reports a refused origin, an untrusted certificate and a
    // switched-off laptop all as the same opaque network error, so the web
    // message has to name all three.
    if (kIsWeb) {
      return LocalAiException(
        code: LocalAiException.unreachable,
        message:
            'The Local AI server at ${config.baseUrl} could not be reached '
            'from this browser. Three things make this happen: the laptop is '
            'switched off or the server is not running; this computer has not '
            'had the server\'s certificate authority installed (ca.crt from '
            'the laptop); or this page\'s address is not allowed on the '
            'server. Nothing else in the app is affected.',
      );
    }

    return LocalAiException(
      code: LocalAiException.unreachable,
      message:
          'The Local AI server at ${config.baseUrl} could not be reached. Check '
          'that the laptop is on, the server is running, and this device is on '
          'the same network.',
    );
  }
}
