/// Tests for the Local AI integration.
///
/// Everything is driven through a fake http.Client, so the whole contract -
/// streaming, stopping, 401, 403, an unreachable laptop, a timeout, a
/// malformed reply - is exercised with no server, no Ollama and no network.
/// Stream shapes are copied from the server's own contract (docs/API.md and
/// shared/api.ts), not from what this client happens to accept.
///
/// The cases that matter most are the isolation groups: an answer must never
/// cross from one signed-in account to another, signing out must leave
/// nothing behind, and nothing that identifies the person may reach the
/// server.
library;

import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:intl/intl.dart';

import 'package:it_management_system/core/ai/local/local_ai_client.dart';
import 'package:it_management_system/core/ai/local/local_ai_config.dart';
import 'package:it_management_system/core/ai/local/local_ai_context_service.dart';
import 'package:it_management_system/core/ai/local/local_ai_discovery.dart';
import 'package:it_management_system/core/ai/local/local_ai_http.dart';
import 'package:it_management_system/core/ai/local/local_ai_models.dart';
import 'package:it_management_system/core/ai/local/local_ai_provider.dart';
import 'package:it_management_system/core/ai/local/local_ai_remote_setup.dart';
import 'package:it_management_system/core/ai/local/widgets/local_ai_composer.dart';
import 'package:it_management_system/core/ai/local/widgets/local_ai_message_bubble.dart';

// =============================================================================
// TEST DOUBLES
// =============================================================================

const LocalAiConfig _config = LocalAiConfig(
  baseUrl: 'http://10.0.2.2:3000',
  apiKey: 'lai_abcd1234_secretsecretsecret',
  certificateFingerprint: '',
  source: LocalAiConfigSource.device,
);

/// The key and uid the cross-language scope vector was computed with (by
/// node's crypto.createHmac, see the report of this change).
final String _vectorKey = 'lai_ab12cd34_${'A' * 43}';

const String _fingerprintA =
    'aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa';
const String _fingerprintB =
    'bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb';

/// A streamed reply whose lines the test sends one at a time, and which
/// stays open until the test ends it or the client drops the connection.
class _Live {
  final StreamController<List<int>> controller = StreamController<List<int>>();

  void line(String line) {
    if (!controller.isClosed) controller.add(utf8.encode('$line\n'));
  }

  void end() {
    if (!controller.isClosed) controller.close();
  }

  /// What a dropped connection looks like to the http package.
  void drop() {
    if (controller.isClosed) return;
    controller.addError(http.ClientException('Connection closed while receiving data'));
    controller.close();
  }
}

/// One canned reply.
class _Reply {
  const _Reply({
    this.status = 200,
    this.body = '{}',
    this.lines,
    this.headers = const {'content-type': 'application/json'},
    this.throws,
    this.delay,
    this.live,
    this.errorAfter,
    this.onRequest,
  });

  final int status;
  final String body;

  /// NDJSON lines, sent one at a time, for a streaming reply.
  final List<String>? lines;

  final Map<String, String> headers;

  /// Raised instead of replying, for transport failures.
  final Object? throws;

  /// Held before the reply begins, for timeout tests.
  final Duration? delay;

  /// A stream the test drives itself.
  final _Live? live;

  /// Raised after [lines], as a connection lost part-way through.
  final Object? errorAfter;

  /// Called when the request arrives, e.g. to push `done` down a live stream
  /// when the stop endpoint is called.
  final void Function(http.BaseRequest request)? onRequest;
}

String _error(String code, [String message = 'Refused.']) =>
    jsonEncode({'error': {'code': code, 'message': message}});

/// The server: routes keyed by "METHOD /path" or "METHOD origin/path". A
/// route given a list answers with its replies in turn, repeating the last.
class _FakeServer {
  _FakeServer(Map<String, Object> routes)
    : _routes = {
        for (final entry in routes.entries)
          entry.key: entry.value is List<_Reply>
              ? List<_Reply>.of(entry.value as List<_Reply>)
              : [entry.value as _Reply],
      };

  final Map<String, List<_Reply>> _routes;
  final List<http.BaseRequest> requests = [];

  /// The configuration each HTTP client was made for (so the pin in force
  /// can be checked).
  final List<LocalAiConfig> configs = [];
  final List<_FakeClient> clients = [];

  _Reply replyFor(http.BaseRequest request) {
    final full = '${request.method} ${request.url.origin}${request.url.path}';
    final short = '${request.method} ${request.url.path}';
    final queue = _routes[full] ?? _routes[short];
    if (queue == null || queue.isEmpty) {
      return _Reply(status: 404, body: _error('NOT_FOUND', 'No such route.'));
    }
    return queue.length > 1 ? queue.removeAt(0) : queue.first;
  }

  LocalAiClient client() => LocalAiClient(
    clientFactory: (config) {
      configs.add(config);
      final client = _FakeClient(this);
      clients.add(client);
      return client;
    },
  );

  List<http.Request> requestsTo(String pathSuffix) => [
    for (final r in requests)
      if (r.url.path.endsWith(pathSuffix)) r as http.Request,
  ];

  List<Map<String, dynamic>> get chatBodies => [
    for (final r in requestsTo('/ai/chat'))
      jsonDecode(r.body) as Map<String, dynamic>,
  ];
}

/// An http.Client that answers from the fake server and records what it was
/// sent.
class _FakeClient extends http.BaseClient {
  _FakeClient(this._server);

  final _FakeServer _server;
  final List<http.BaseRequest> requests = [];
  bool closed = false;
  _Live? _live;

  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) async {
    requests.add(request);
    _server.requests.add(request);

    final reply = _server.replyFor(request);
    reply.onRequest?.call(request);

    if (reply.delay != null) await Future<void>.delayed(reply.delay!);
    if (reply.throws != null) throw reply.throws!;

    if (reply.live != null) {
      _live = reply.live;
      return http.StreamedResponse(
        reply.live!.controller.stream,
        200,
        headers: {'content-type': 'application/x-ndjson'},
        request: request,
      );
    }

    if (reply.lines != null) {
      return http.StreamedResponse(
        _ndjson(reply.lines!, reply.errorAfter),
        reply.status,
        headers: {'content-type': 'application/x-ndjson'},
        request: request,
      );
    }

    final bytes = utf8.encode(reply.body);
    return http.StreamedResponse(
      Stream.value(bytes),
      reply.status,
      contentLength: bytes.length,
      headers: reply.headers,
      request: request,
    );
  }

  Stream<List<int>> _ndjson(List<String> lines, Object? errorAfter) async* {
    for (final line in lines) {
      if (closed) return;
      // Every line ends with \n, including the last - the contract guarantees
      // it, and the client relies on it.
      yield utf8.encode('$line\n');
      await Future<void>.delayed(Duration.zero);
    }
    if (errorAfter != null) throw errorAfter;
  }

  @override
  void close() {
    closed = true;
    // Closing a real client mid-stream breaks the response off.
    _live?.drop();
    super.close();
  }
}

String _startLine([String id = 'conv-1']) => jsonEncode({
  'type': 'start',
  'conversationId': id,
  'messageId': 'm1',
  'title': 'A question',
  'model': 'qwen3:8b',
});

String _deltaLine(String text) => jsonEncode({'type': 'delta', 'text': text});

String _doneLine({
  String content = 'Hello.',
  String status = 'done',
  String conversationId = 'conv-1',
  Map<String, dynamic>? appContext,
}) => jsonEncode({
  'type': 'done',
  'conversationId': conversationId,
  'title': 'A question',
  'message': {
    'id': 'm1',
    'role': 'assistant',
    'content': content,
    'status': status,
    'createdAt': 1790000000000,
  },
  'model': 'qwen3:8b',
  'usage': {'promptTokens': 10, 'outputTokens': 5, 'durationMs': 900, 'tokensPerSecond': 8.4},
  'context': {'includedMessages': 1, 'omittedMessages': 0},
  'documents': null,
  'appContext': appContext,
});

List<String> _answer(String text, {String conversationId = 'conv-1'}) => [
  _startLine(conversationId),
  _deltaLine(text),
  _doneLine(content: text, conversationId: conversationId),
];

String _healthBody({List<String>? scopes = const ['chat']}) => jsonEncode({
  'status': 'ok',
  'ollama': {'reachable': true, 'version': '0.34.4'},
  'model': {'name': 'qwen3:8b', 'available': true},
  'documents': {'embeddingModel': 'embeddinggemma', 'available': true, 'indexedDocuments': 3},
  'queue': {'running': 0, 'waiting': 0, 'maxConcurrent': 1},
  'problem': null,
  if (scopes != null)
    'client': {'id': 'abcd1234', 'name': 'IT Management System', 'scopes': scopes},
});

String _modelBody({int maxMessageTokens = 4096, int? maxAppContextTokens = 2867}) =>
    jsonEncode({
      'model': 'qwen3:8b',
      'available': true,
      'parameterSize': '8.2B',
      'quantization': 'Q4_K_M',
      'contextWindow': 8192,
      'maxMessageTokens': maxMessageTokens,
      'replyReserveTokens': 2048,
      'thinking': false,
      'embeddingModel': 'embeddinggemma',
      'embeddingAvailable': true,
      'maxAppContextTokens': ?maxAppContextTokens,
    });

/// A settings store that answers from memory.
/// Stands in for the Firestore document an administrator publishes.
class _FakeRemoteSetup implements LocalAiRemoteSetup {
  _FakeRemoteSetup(this.settings, {this.throws = false});

  final LocalAiRemoteSettings? settings;

  /// A read that fails: not signed in, no permission, or offline.
  final bool throws;

  /// False while the document cannot be read yet (nobody signed in).
  bool available = true;

  int calls = 0;

  @override
  Future<LocalAiRemoteSettings?> fetch() async {
    calls++;
    if (throws) throw StateError('permission denied');
    if (!available) return null;
    return settings;
  }
}

class _FakeSettings implements LocalAiSettingsStore {
  _FakeSettings(this.current, {this.buildDefaults = LocalAiConfig.empty});

  LocalAiConfig current;

  /// What the build supplies, which a reset falls back to.
  final LocalAiConfig buildDefaults;
  int addressSaves = 0;

  @override
  Future<LocalAiConfig> load() async => current;

  @override
  Future<void> save({
    required String baseUrl,
    required String apiKey,
    String certificateFingerprint = '',
  }) async {
    current = current.copyWith(
      baseUrl: baseUrl,
      apiKey: apiKey,
      certificateFingerprint: certificateFingerprint,
    );
  }

  @override
  Future<void> saveAddress({
    required String baseUrl,
    String certificateFingerprint = '',
  }) async {
    addressSaves++;
    current = current.copyWith(
      baseUrl: baseUrl,
      certificateFingerprint: certificateFingerprint,
    );
  }

  @override
  Future<void> clearDeviceConfig() async {
    current = buildDefaults;
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

/// Stands in for the IT Inventory context service: records what it was asked
/// and answers with fixed test data.
class _FakeContext implements LocalAiContextService {
  _FakeContext({this.throws, this.delay, this.hold, List<String?>? directAnswers})
    : directAnswers = [...?directAnswers];

  final Object? throws;
  final Duration? delay;

  /// When set, contextFor waits for it, so a test can look at the screen
  /// while the data is still being read.
  final Completer<void>? hold;

  /// The direct answer for each question in turn; none once used up.
  final List<String?> directAnswers;

  final List<int> budgets = [];
  final List<String?> previousQuestions = [];
  final List<String?> uids = [];
  int resets = 0;

  @override
  Future<LocalAiAppContext?> contextFor({
    required String question,
    required String? uid,
    String? previousQuestion,
    required int budgetTokens,
  }) async {
    budgets.add(budgetTokens);
    previousQuestions.add(previousQuestion);
    uids.add(uid);
    if (hold != null) await hold!.future;
    if (delay != null) await Future<void>.delayed(delay!);
    if (throws != null) throw throws!;

    return LocalAiAppContext(
      source: LocalAiAppContext.defaultSource,
      retrievedAt: DateTime.utc(2026, 9, 28, 17, 5),
      scope: 'Asked by an Admin. Visible: all inventory.',
      sections: const [
        LocalAiContextSection(
          title: 'Inventory totals',
          data: {'assetRecords': 120, 'headOfficeAvailable': 42},
        ),
      ],
      notes: const ['Requests were not loaded.'],
      directAnswer: directAnswers.isEmpty ? null : directAnswers.removeAt(0),
    );
  }

  @override
  void reset() => resets++;
}

class _FakeDiscovery extends LocalAiDiscovery {
  _FakeDiscovery(this.servers, {this.supported = true, this.hold});

  final List<LocalAiDiscoveredServer> servers;
  final bool supported;

  /// When set, the search does not finish until it completes.
  final Completer<void>? hold;
  int calls = 0;
  int? lastPort;

  @override
  bool get isSupported => supported;

  @override
  Future<List<LocalAiDiscoveredServer>> find({
    required String apiKey,
    int port = LocalAiDiscovery.defaultPort,
    Duration timeout = LocalAiDiscovery.defaultTimeout,
  }) async {
    calls++;
    lastPort = port;
    await hold?.future;
    return servers;
  }
}

/// Stands in for a dropped connection without importing dart:io, so the test
/// also runs under the web test runner.
class SocketishException implements Exception {
  const SocketishException();

  @override
  String toString() => 'SocketException: connection failed';
}

LocalAiProvider _provider(
  _FakeServer server, {
  LocalAiConfig config = _config,
  _FakeSettings? settings,
  LocalAiContextService? context,
  LocalAiDiscovery? discovery,
  LocalAiRemoteSetup? remoteSetup,
  Duration stopGrace = const Duration(milliseconds: 60),
  Duration contextTimeout = const Duration(seconds: 2),
  Duration monitorInterval = const Duration(seconds: 30),
}) {
  return LocalAiProvider(
    client: server.client(),
    settings: settings ?? _FakeSettings(config),
    contextService: context,
    discovery: discovery ?? _FakeDiscovery(const [], supported: false),
    remoteSetup: remoteSetup,
    stopGrace: stopGrace,
    contextTimeout: contextTimeout,
    monitorInterval: monitorInterval,
  );
}

/// Waits (briefly) until [condition] holds.
Future<void> _until(bool Function() condition) async {
  for (var i = 0; i < 400; i++) {
    if (condition()) return;
    await Future<void>.delayed(const Duration(milliseconds: 5));
  }
  fail('condition not reached');
}

Future<LocalAiException> _errorFrom(Future<void> Function() action) async {
  try {
    await action();
  } on LocalAiException catch (error) {
    return error;
  }
  fail('expected a LocalAiException');
}

Future<LocalAiException> _errorFromStream(LocalAiStream stream) async {
  try {
    await stream.events.toList();
  } on LocalAiException catch (error) {
    return error;
  }
  fail('expected a LocalAiException');
}

void main() {
  // ===========================================================================
  // A SUCCESSFUL REQUEST
  // ===========================================================================

  group('a successful request', () {
    test('health is read and reported, with what the key may do', () async {
      final server = _FakeServer({
        'GET /api/v1/health': _Reply(body: _healthBody(scopes: ['chat', 'documents'])),
      });

      final health = await server.client().health(_config);

      expect(health.isHealthy, isTrue);
      expect(health.modelName, 'qwen3:8b');
      expect(health.ollamaVersion, '0.34.4');
      expect(health.indexedDocuments, 3);
      expect(health.clientName, 'IT Management System');
      expect(health.allowsDocuments, isTrue);
    });

    test('model limits are read, including maxAppContextTokens', () async {
      final server = _FakeServer({'GET /api/v1/model': _Reply(body: _modelBody())});

      final model = await server.client().model(_config);

      expect(model.maxMessageTokens, 4096);
      expect(model.maxAppContextTokens, 2867);
      expect(model.contextWindow, 8192);
    });

    test('the API key and conversation scope are sent, and nothing else', () async {
      final server = _FakeServer({
        'POST /api/v1/ai/chat': _Reply(lines: _answer('hi')),
      });

      await server.client()
          .ask(config: _config, message: 'hello', scope: 'scope-a')
          .events
          .toList();

      final request = server.requestsTo('/ai/chat').single;
      expect(request.headers['authorization'], 'Bearer ${_config.apiKey}');
      expect(request.headers['x-conversation-scope'], 'scope-a');
      expect(
        request.headers.keys.toSet(),
        {'content-type', 'accept', 'authorization', 'x-conversation-scope'},
      );

      // No Firebase credential of any kind may reach the Local AI server.
      final everything = '${request.headers}${request.body}';
      expect(everything.toLowerCase(), isNot(contains('firebase')));
      expect(everything, isNot(contains('idToken')));
    });

    test('a successful answer sets the status to ready', () async {
      final server = _FakeServer({
        'POST /api/v1/ai/chat': _Reply(lines: _answer('Fine.')),
      });
      final provider = _provider(server);
      await provider.loadConfig();
      provider.bindUser('uid-a');
      expect(provider.status, LocalAiStatus.unknown);

      await provider.send('hello');

      expect(provider.status, LocalAiStatus.ready);
      expect(provider.messages.last.status, 'done');
      expect(provider.messages.last.content, 'Fine.');
      expect(provider.lastError, isNull);
    });
  });

  // ===========================================================================
  // STREAMING
  // ===========================================================================

  group('streaming', () {
    test('deltas arrive in order and the answer completes', () async {
      final server = _FakeServer({
        'POST /api/v1/ai/chat': _Reply(
          lines: [
            _startLine(),
            _deltaLine('Total '),
            _deltaLine('inventory '),
            _deltaLine('57 units.'),
            _doneLine(content: 'Total inventory 57 units.'),
          ],
        ),
      });

      final events = await server.client()
          .ask(config: _config, message: 'total inventory kitni hai?', scope: 's')
          .events
          .toList();

      expect(events.whereType<LocalAiStartEvent>().length, 1);
      expect(
        events.whereType<LocalAiDeltaEvent>().map((e) => e.text).join(),
        'Total inventory 57 units.',
      );
      expect(events.last, isA<LocalAiDoneEvent>());
    });

    test('a ping heartbeat is swallowed rather than shown', () async {
      // The server sends these through long pauses so a NAT does not drop the
      // socket. They carry nothing, so they must never reach the screen.
      final server = _FakeServer({
        'POST /api/v1/ai/chat': _Reply(
          lines: [
            _startLine(),
            jsonEncode({'type': 'ping'}),
            _deltaLine('Hi'),
            jsonEncode({'type': 'ping'}),
            _doneLine(content: 'Hi'),
          ],
        ),
      });

      final events = await server.client()
          .ask(config: _config, message: 'hi', scope: 's')
          .events
          .toList();

      expect(events.any((e) => e is LocalAiPingEvent), isFalse);
      expect(events.length, 3);
    });

    test('an event type this version does not know is ignored, not fatal', () async {
      // The contract requires clients to tolerate events added later.
      final server = _FakeServer({
        'POST /api/v1/ai/chat': _Reply(
          lines: [
            _startLine(),
            jsonEncode({'type': 'something-invented-next-year', 'x': 1}),
            _deltaLine('still fine'),
            _doneLine(content: 'still fine'),
          ],
        ),
      });

      final events = await server.client()
          .ask(config: _config, message: 'hi', scope: 's')
          .events
          .toList();

      expect(events.last, isA<LocalAiDoneEvent>());
      expect(events.whereType<LocalAiDeltaEvent>().single.text, 'still fine');
    });

    test('document citations arrive in the server\'s real sources shape', () async {
      // {"type":"sources","documents":{mode,used,sources,note,searchedAs?}} -
      // exactly what server/api/chat.ts writes.
      final server = _FakeServer({
        'POST /api/v1/ai/chat': _Reply(
          lines: [
            _startLine(),
            jsonEncode({
              'type': 'sources',
              'documents': {
                'mode': 'auto',
                'used': true,
                'sources': [
                  {'n': 1, 'name': 'policy.pdf', 'location': 'page 2', 'snippet': '…', 'score': 0.8},
                ],
                'note': null,
                'searchedAs': 'laptop issue policy',
              },
            }),
            _doneLine(content: 'See [1].'),
          ],
        ),
      });

      final events = await server.client()
          .ask(
            config: _config,
            message: 'policy kya kehti hai?',
            scope: 's',
            documents: LocalAiDocumentsMode.auto,
          )
          .events
          .toList();

      final searched = events.whereType<LocalAiSourcesEvent>().single;
      expect(searched.documents.mode, 'auto');
      expect(searched.documents.used, isTrue);
      expect(searched.documents.searchedAs, 'laptop issue policy');
      expect(searched.sources.single.name, 'policy.pdf');
      expect(searched.sources.single.location, 'page 2');
    });

    test('the sources reach the answer bubble', () async {
      final server = _FakeServer({
        'GET /api/v1/health': _Reply(body: _healthBody(scopes: ['chat', 'documents'])),
        'POST /api/v1/ai/chat': _Reply(
          lines: [
            _startLine(),
            jsonEncode({
              'type': 'sources',
              'documents': {
                'mode': 'auto',
                'used': true,
                'sources': [
                  {'n': 1, 'name': 'policy.pdf', 'location': 'page 2', 'snippet': 's', 'score': 0.8},
                ],
                'note': null,
              },
            }),
            _deltaLine('See [1].'),
            _doneLine(content: 'See [1].'),
          ],
        ),
      });
      final provider = _provider(server);
      await provider.loadConfig();
      provider.bindUser('uid-a');
      await provider.testConnection();

      await provider.send('what does the policy say?');

      expect(provider.messages.last.sources.single.name, 'policy.pdf');
    });

    test('a single unreadable line does not abandon the answer', () async {
      final server = _FakeServer({
        'POST /api/v1/ai/chat': _Reply(
          lines: [_startLine(), 'this is not json at all', _deltaLine('ok'), _doneLine(content: 'ok')],
        ),
      });

      final events = await server.client()
          .ask(config: _config, message: 'hi', scope: 's')
          .events
          .toList();

      expect(events.last, isA<LocalAiDoneEvent>());
    });
  });

  // ===========================================================================
  // STOPPING
  // ===========================================================================

  group('stopping an answer', () {
    test('stop asks the server and shows the stopped answer it sends back', () async {
      final live = _Live();
      final server = _FakeServer({
        'POST /api/v1/ai/chat': _Reply(live: live),
        'POST /api/v1/ai/conversations/conv-1/stop': _Reply(
          body: '{"stopped":true}',
          onRequest: (_) {
            // What the server does: the answer's own stream ends with `done`,
            // status stopped, carrying what was generated so far.
            live.line(_doneLine(content: 'half an ans', status: 'stopped'));
            live.end();
          },
        ),
      });
      final provider = _provider(server, stopGrace: const Duration(seconds: 5));
      await provider.loadConfig();
      provider.bindUser('uid-a');

      final sending = provider.send('a long question');
      live.line(_startLine());
      live.line(_deltaLine('half an ans'));
      await _until(() => provider.messages.last.content == 'half an ans');

      expect(provider.canStop, isTrue);
      await provider.stop();
      await sending;

      final answer = provider.messages.last;
      expect(answer.status, 'stopped');
      expect(answer.content, 'half an ans');
      // The server's own `done` ended it (its message id), not the fallback
      // of dropping the connection.
      expect(answer.id, 'm1');
      expect(provider.isSending, isFalse);
      expect(
        server.requestsTo('/stop').single.headers['x-conversation-scope'],
        LocalAiScope.forUser('uid-a', apiKey: _config.apiKey),
      );
    });

    test('when the server never confirms, the connection is dropped and the answer still ends as stopped', () async {
      final live = _Live();
      final server = _FakeServer({
        'POST /api/v1/ai/chat': _Reply(live: live),
        'POST /api/v1/ai/conversations/conv-1/stop': const _Reply(
          throws: SocketishException(),
        ),
      });
      final provider = _provider(server, stopGrace: const Duration(milliseconds: 60));
      await provider.loadConfig();
      provider.bindUser('uid-a');

      final sending = provider.send('a long question');
      live.line(_startLine());
      live.line(_deltaLine('partial'));
      await _until(() => provider.messages.last.content == 'partial');

      await provider.stop();
      await sending;

      expect(provider.messages.last.status, 'stopped');
      expect(provider.messages.last.content, 'partial');
      expect(provider.isSending, isFalse);
      expect(provider.lastError, isNull);
    });

    test('stop before the answer has started drops the connection at once', () async {
      final server = _FakeServer({
        'POST /api/v1/ai/chat': _Reply(live: _Live()),
      });

      final stream = server.client().ask(config: _config, message: 'q', scope: 's');
      await _until(() => server.clients.isNotEmpty && server.requests.isNotEmpty);
      await stream.stop();

      expect(server.clients.single.closed, isTrue);
      expect(server.requestsTo('/stop'), isEmpty);
    });

    test('stop while the inventory data is being read sends nothing', () async {
      final hold = Completer<void>();
      final server = _FakeServer({'POST /api/v1/ai/chat': _Reply(lines: _answer('no'))});
      final provider = _provider(server, context: _FakeContext(hold: hold));
      await provider.loadConfig();
      provider.bindUser('uid-a');

      final sending = provider.send('question');
      expect(provider.canStop, isTrue);
      await provider.stop();
      // Stop ends it at once; the read is not waited for.
      await sending;

      expect(server.requestsTo('/ai/chat'), isEmpty);
      expect(provider.messages.last.status, 'stopped');
      expect(provider.isSending, isFalse);

      // The read finishing late changes nothing.
      hold.complete();
      await Future<void>.delayed(Duration.zero);
      expect(server.requestsTo('/ai/chat'), isEmpty);
      expect(provider.messages.last.status, 'stopped');
    });

    test('the explicit stop endpoint is called with the key and scope', () async {
      final server = _FakeServer({
        'POST /api/v1/ai/conversations/conv-1/stop': const _Reply(body: '{"stopped":true}'),
      });

      final stopped = await server.client().stopAnswer(
        config: _config,
        conversationId: 'conv-1',
        scope: 'scope-a',
      );

      expect(stopped, isTrue);
      expect(server.requests.single.headers['x-conversation-scope'], 'scope-a');
    });

    test('a stopped answer still ends with done, marked stopped', () async {
      final server = _FakeServer({
        'POST /api/v1/ai/chat': _Reply(
          lines: [_startLine(), _deltaLine('half an ans'), _doneLine(content: 'half an ans', status: 'stopped')],
        ),
      });

      final events = await server.client()
          .ask(config: _config, message: 'hi', scope: 's')
          .events
          .toList();

      final done = events.last as LocalAiDoneEvent;
      expect(done.answer.status, 'stopped');
      expect(done.answer.content, 'half an ans');
    });
  });

  // ===========================================================================
  // TRANSPORT ERRORS NEVER ESCAPE RAW
  // ===========================================================================

  group('transport errors are wrapped', () {
    test('stopAnswer: a dropped connection becomes SERVER_UNREACHABLE', () async {
      final server = _FakeServer({
        'POST /api/v1/ai/conversations/c/stop': const _Reply(throws: SocketishException()),
      });

      final error = await _errorFrom(
        () => server.client().stopAnswer(config: _config, conversationId: 'c', scope: 's'),
      );

      expect(error.code, LocalAiException.unreachable);
    });

    test('stopAnswer: an http ClientException becomes SERVER_UNREACHABLE', () async {
      final server = _FakeServer({
        'POST /api/v1/ai/conversations/c/stop': _Reply(
          throws: http.ClientException('Connection refused'),
        ),
      });

      final error = await _errorFrom(
        () => server.client().stopAnswer(config: _config, conversationId: 'c', scope: 's'),
      );

      expect(error.code, LocalAiException.unreachable);
    });

    test('deleteConversation: a timeout becomes TIMED_OUT', () async {
      final server = _FakeServer({
        'DELETE /api/v1/ai/conversations/c': _Reply(throws: TimeoutException('slow')),
      });

      final error = await _errorFrom(
        () => server.client().deleteConversation(config: _config, conversationId: 'c', scope: 's'),
      );

      expect(error.code, LocalAiException.timedOut);
    });

    test('deleteConversation: a dropped connection becomes SERVER_UNREACHABLE', () async {
      final server = _FakeServer({
        'DELETE /api/v1/ai/conversations/c': const _Reply(throws: SocketishException()),
      });

      final error = await _errorFrom(
        () => server.client().deleteConversation(config: _config, conversationId: 'c', scope: 's'),
      );

      expect(error.code, LocalAiException.unreachable);
    });

    test('provider.stop and clearConversation never throw', () async {
      final live = _Live();
      final server = _FakeServer({
        'POST /api/v1/ai/chat': _Reply(live: live),
        'POST /api/v1/ai/conversations/conv-1/stop': const _Reply(throws: SocketishException()),
        'DELETE /api/v1/ai/conversations/conv-1': const _Reply(throws: SocketishException()),
      });
      final provider = _provider(server);
      await provider.loadConfig();
      provider.bindUser('uid-a');

      final sending = provider.send('q');
      live.line(_startLine());
      await _until(() => provider.conversationId == 'conv-1');

      await provider.stop();
      await sending;
      await provider.clearConversation();

      expect(provider.messages, isEmpty);
      expect(provider.conversationId, isNull);
      expect(server.requestsTo('/ai/conversations/conv-1'), hasLength(1));
    });
  });

  // ===========================================================================
  // AUTHENTICATION FAILURE
  // ===========================================================================

  group('authentication failure', () {
    test('401 is reported as UNAUTHORIZED, meaning no key was accepted', () async {
      final server = _FakeServer({
        'GET /api/v1/health': _Reply(status: 401, body: _error('UNAUTHORIZED', 'This server requires an API key.')),
      });

      final error = await _errorFrom(() => server.client().health(_config));

      expect(error.code, LocalAiException.unauthorized);
      expect(error.isConfiguration, isTrue);
    });

    test('403 is reported as INVALID_API_KEY, which is a different fix', () async {
      // "You sent nothing" and "your key is wrong" send an administrator to
      // different places, so they must not collapse into one message.
      final server = _FakeServer({
        'GET /api/v1/health': _Reply(status: 403, body: _error('INVALID_API_KEY', 'That API key is not valid.')),
      });

      final error = await _errorFrom(() => server.client().health(_config));

      expect(error.code, LocalAiException.invalidApiKey);
      expect(error.isTransient, isFalse);
    });

    test('a missing documents scope is reported as such', () async {
      final server = _FakeServer({
        'POST /api/v1/ai/chat': _Reply(status: 403, body: _error('FORBIDDEN_SCOPE', 'This key may not use documents.')),
      });

      final error = await _errorFromStream(
        server.client().ask(
          config: _config,
          message: 'hi',
          scope: 's',
          documents: LocalAiDocumentsMode.only,
        ),
      );

      expect(error.code, LocalAiException.forbiddenScope);
    });

    test('an error body never contains the API key', () async {
      final server = _FakeServer({
        'GET /api/v1/health': _Reply(status: 401, body: _error('UNAUTHORIZED', 'no key')),
      });

      final error = await _errorFrom(() => server.client().health(_config));

      expect(error.toString(), isNot(contains(_config.apiKey)));
      expect(error.userMessage, isNot(contains(_config.apiKey)));
    });
  });

  // ===========================================================================
  // ERROR CODES
  // ===========================================================================

  group('error codes', () {
    test('every server code is known, and classified sensibly', () {
      LocalAiException e(String code) => LocalAiException(code: code, message: 'm');

      for (final code in [
        LocalAiException.unreachable,
        LocalAiException.timedOut,
        LocalAiException.serverBusy,
        LocalAiException.rateLimited,
        LocalAiException.conflict,
        LocalAiException.ollamaUnreachable,
        LocalAiException.ollamaError,
      ]) {
        expect(e(code).isTransient, isTrue, reason: code);
        expect(e(code).isConfiguration, isFalse, reason: code);
      }

      for (final code in [
        LocalAiException.notConfigured,
        LocalAiException.unauthorized,
        LocalAiException.invalidApiKey,
        LocalAiException.forbiddenScope,
        LocalAiException.forbiddenNetwork,
        LocalAiException.forbiddenOrigin,
        LocalAiException.modelNotFound,
      ]) {
        expect(e(code).isConfiguration, isTrue, reason: code);
        expect(e(code).isTransient, isFalse, reason: code);
      }

      // A bug in the request, or in the server: neither retrying nor
      // changing Settings fixes it.
      for (final code in [
        LocalAiException.invalidRequest,
        LocalAiException.payloadTooLarge,
        LocalAiException.messageTooLong,
        LocalAiException.contextTooLarge,
        LocalAiException.notFound,
        LocalAiException.storageError,
        LocalAiException.internalError,
      ]) {
        expect(e(code).isTransient, isFalse, reason: code);
        expect(e(code).isConfiguration, isFalse, reason: code);
      }

      expect(LocalAiException.forbiddenOrigin, 'FORBIDDEN_ORIGIN');
      expect(LocalAiException.payloadTooLarge, 'PAYLOAD_TOO_LARGE');
      expect(LocalAiException.invalidRequest, 'INVALID_REQUEST');
      expect(LocalAiException.notFound, 'NOT_FOUND');
      expect(LocalAiException.ollamaError, 'OLLAMA_ERROR');
      expect(LocalAiException.storageError, 'STORAGE_ERROR');
      expect(LocalAiException.internalError, 'INTERNAL_ERROR');
      expect(LocalAiException.contextTooLarge, 'CONTEXT_TOO_LARGE');
    });

    test('the server\'s own code wins over the HTTP status', () async {
      final server = _FakeServer({
        'POST /api/v1/ai/chat': _Reply(status: 413, body: _error('PAYLOAD_TOO_LARGE', 'Over 128 KB.')),
      });

      final error = await _errorFromStream(
        server.client().ask(config: _config, message: 'q', scope: 's'),
      );

      expect(error.code, LocalAiException.payloadTooLarge);
      expect(error.message, 'Over 128 KB.');
    });

    test('a bare 404 is NOT_FOUND, never a lost conversation', () async {
      // Otherwise a wrong address would send the app off retrying as a new
      // conversation instead of saying the address is wrong.
      final server = _FakeServer({
        'GET /api/v1/health': const _Reply(status: 404, body: '<html>Not Found</html>'),
      });

      final error = await _errorFrom(() => server.client().health(_config));

      expect(error.code, LocalAiException.notFound);
    });

    test('Retry-After becomes a clear "try again in" message', () {
      const busy = LocalAiException(
        code: LocalAiException.serverBusy,
        message: 'The queue is full.',
        retryAfter: Duration(seconds: 20),
      );
      const limited = LocalAiException(
        code: LocalAiException.rateLimited,
        message: 'Too many requests',
        retryAfter: Duration(seconds: 1),
      );

      expect(busy.userMessage, 'The queue is full. Try again in 20 seconds.');
      expect(limited.userMessage, 'Too many requests. Try again in 1 second.');
    });
  });

  // ===========================================================================
  // SERVER UNAVAILABLE, TIMEOUT, MALFORMED
  // ===========================================================================

  group('the server is not usable', () {
    test('an unreachable laptop is named as such, not as a server error', () async {
      final server = _FakeServer({
        'GET /api/v1/health': const _Reply(throws: SocketishException()),
      });

      final error = await _errorFrom(() => server.client().health(_config));

      expect(error.code, LocalAiException.unreachable);
      expect(error.isTransient, isTrue);
      // The message has to say where it tried, or nobody can fix it.
      expect(error.message, contains(_config.baseUrl));
    });

    test('a request with no address configured never leaves the app', () async {
      final server = _FakeServer({});

      final error = await _errorFrom(() => server.client().health(LocalAiConfig.empty));

      expect(error.code, LocalAiException.notConfigured);
      expect(server.requests, isEmpty);
    });

    test('a reply that is not the Local AI server is reported as malformed', () async {
      // e.g. the address points at a router's web page.
      final server = _FakeServer({
        'GET /api/v1/health': const _Reply(body: '<html><body>Router login</body></html>'),
      });

      final error = await _errorFrom(() => server.client().health(_config));

      expect(error.code, LocalAiException.malformed);
    });

    test('a busy server carries its Retry-After through', () async {
      final server = _FakeServer({
        'GET /api/v1/health': _Reply(
          status: 503,
          body: _error('SERVER_BUSY', 'Busy.'),
          headers: const {'content-type': 'application/json', 'retry-after': '12'},
        ),
      });

      final error = await _errorFrom(() => server.client().health(_config));

      expect(error.code, LocalAiException.serverBusy);
      expect(error.retryAfter, const Duration(seconds: 12));
      expect(error.isTransient, isTrue);
      expect(error.userMessage, contains('Try again in 12 seconds'));
    });

    test('a rate limit is transient, not a configuration problem', () async {
      final server = _FakeServer({
        'GET /api/v1/health': _Reply(status: 429, body: _error('RATE_LIMITED', 'Slow down.')),
      });

      final error = await _errorFrom(() => server.client().health(_config));

      expect(error.code, LocalAiException.rateLimited);
      expect(error.isTransient, isTrue);
      expect(error.isConfiguration, isFalse);
    });

    test('an in-stream error ends the answer with the server\'s message', () async {
      final server = _FakeServer({
        'POST /api/v1/ai/chat': _Reply(
          lines: [
            _startLine(),
            jsonEncode({'type': 'error', 'error': {'code': 'OLLAMA_ERROR', 'message': 'Ollama crashed.'}}),
          ],
        ),
      });
      final provider = _provider(server);
      await provider.loadConfig();
      provider.bindUser('uid-a');

      await provider.send('q');

      expect(provider.messages.last.status, 'error');
      expect(provider.messages.last.error, 'Ollama crashed.');
      expect(provider.lastError!.code, LocalAiException.ollamaError);
      expect(provider.isSending, isFalse);
    });
  });

  // ===========================================================================
  // DOCUMENTS AND THE KEY'S SCOPES
  // ===========================================================================

  group('documents follow what the key may do', () {
    test('documents are off by default and cannot be switched on with a chat-only key', () async {
      final server = _FakeServer({
        'GET /api/v1/health': _Reply(body: _healthBody(scopes: ['chat'])),
        'POST /api/v1/ai/chat': _Reply(lines: _answer('ok')),
      });
      final provider = _provider(server);
      await provider.loadConfig();
      provider.bindUser('uid-a');
      await provider.testConnection();

      expect(provider.documentsMode, LocalAiDocumentsMode.off);
      expect(provider.documentsAllowed, isFalse);

      provider.setDocumentsMode(LocalAiDocumentsMode.auto);
      expect(provider.documentsMode, LocalAiDocumentsMode.off);

      await provider.send('q');
      expect(server.chatBodies.single['documents'], 'off');
    });

    test('a server that does not report the key\'s scopes gets documents off', () async {
      final server = _FakeServer({
        'GET /api/v1/health': _Reply(body: _healthBody(scopes: null)),
      });
      final provider = _provider(server);
      await provider.loadConfig();
      await provider.testConnection();

      expect(provider.health!.hasClientInfo, isFalse);
      expect(provider.documentsAllowed, isFalse);
    });

    test('FORBIDDEN_SCOPE falls back to documents off and asks once more', () async {
      final server = _FakeServer({
        'GET /api/v1/health': _Reply(body: _healthBody(scopes: ['chat', 'documents'])),
        'POST /api/v1/ai/chat': [
          _Reply(status: 403, body: _error('FORBIDDEN_SCOPE', 'This key may not use documents.')),
          _Reply(lines: _answer('Answered without documents.')),
        ],
      });
      final provider = _provider(server);
      await provider.loadConfig();
      provider.bindUser('uid-a');
      await provider.testConnection();
      provider.setDocumentsMode(LocalAiDocumentsMode.auto);
      expect(provider.documentsMode, LocalAiDocumentsMode.auto);

      await provider.send('q');

      final bodies = server.chatBodies;
      expect(bodies, hasLength(2));
      expect(bodies[0]['documents'], 'auto');
      expect(bodies[1]['documents'], 'off');
      expect(provider.documentsMode, LocalAiDocumentsMode.off);
      expect(provider.documentsAllowed, isFalse);
      expect(provider.messages.last.status, 'done');
      expect(provider.messages.last.content, 'Answered without documents.');
    });
  });

  // ===========================================================================
  // APP DATA (appContext)
  // ===========================================================================

  group('IT Inventory data (appContext)', () {
    test('is sent with the question, and nothing that identifies the person is', () async {
      final context = _FakeContext();
      final server = _FakeServer({
        'POST /api/v1/ai/chat': _Reply(lines: _answer('42 at Head Office.')),
      });
      final provider = _provider(server, context: context);
      await provider.loadConfig();
      provider.bindUser('uid-secret-123');

      await provider.send('How many assets are at Head Office?');

      final request = server.requestsTo('/ai/chat').single;
      final body = jsonDecode(request.body) as Map<String, dynamic>;
      expect(body.keys.toSet(), {'message', 'stream', 'documents', 'appContext'});

      final appContext = body['appContext'] as Map<String, dynamic>;
      expect(appContext['source'], LocalAiAppContext.defaultSource);
      expect(appContext['retrievedAt'], '2026-09-28T17:05:00.000Z');
      expect((appContext['sections'] as List).single['title'], 'Inventory totals');
      expect(appContext['notes'], ['Requests were not loaded.']);

      // The uid is only used on the device (to ask the context service and
      // to derive the scope); it never appears on the wire. Nor does any
      // token, password or e-mail address.
      final wire = '${request.headers}${request.body}';
      expect(wire, isNot(contains('uid-secret-123')));
      expect(wire.toLowerCase(), isNot(contains('token')));
      expect(wire.toLowerCase(), isNot(contains('password')));
      expect(wire, isNot(contains('@')));
      // "Firebase" appears only as the name of the data's source.
      final withoutSource = wire.replaceAll(LocalAiAppContext.defaultSource, '');
      expect(withoutSource.toLowerCase(), isNot(contains('firebase')));

      expect(context.uids.single, 'uid-secret-123');
    });

    test('the budget is the smaller of the server\'s limit and the preferred size', () async {
      final context = _FakeContext();
      final server = _FakeServer({
        'GET /api/v1/health': _Reply(body: _healthBody()),
        'GET /api/v1/model': _Reply(body: _modelBody(maxAppContextTokens: 1000)),
        'POST /api/v1/ai/chat': _Reply(lines: _answer('ok')),
      });
      final provider = _provider(server, context: context);
      await provider.loadConfig();
      provider.bindUser('uid-a');

      await provider.send('first'); // model not read yet: the fallback
      await provider.testConnection();
      await provider.send('second');

      expect(LocalAiProvider.preferredContextTokens, 1600);
      expect(context.budgets, [1600, 1000]);
      expect(context.previousQuestions, [null, 'first']);
    });

    test('while it is read, the bubble says so', () async {
      final hold = Completer<void>();
      final server = _FakeServer({'POST /api/v1/ai/chat': _Reply(lines: _answer('ok'))});
      final provider = _provider(server, context: _FakeContext(hold: hold));
      await provider.loadConfig();
      provider.bindUser('uid-a');

      final sending = provider.send('q');
      expect(provider.messages.last.isStreaming, isTrue);
      expect(provider.messages.last.progress, 'Reading your inventory data…');

      hold.complete();
      await sending;
      expect(provider.messages.last.progress, isNull);
    });

    test('when the data cannot be read, the question says so instead of guessing', () async {
      final server = _FakeServer({'POST /api/v1/ai/chat': _Reply(lines: _answer('I could not retrieve that.'))});
      final provider = _provider(server, context: _FakeContext(throws: StateError('permission-denied')));
      await provider.loadConfig();
      provider.bindUser('uid-a');

      await provider.send('q');

      final appContext = server.chatBodies.single['appContext'] as Map<String, dynamic>;
      expect(appContext['sections'], isEmpty);
      expect(appContext['notes'], [LocalAiProvider.unreadableContextNote]);
      expect(appContext['source'], LocalAiAppContext.defaultSource);
      expect(appContext.containsKey('scope'), isFalse);
      expect(provider.messages.last.status, 'done');
    });

    test('a context service that hangs is given up on after the timeout', () async {
      final server = _FakeServer({'POST /api/v1/ai/chat': _Reply(lines: _answer('ok'))});
      final provider = _provider(
        server,
        context: _FakeContext(delay: const Duration(seconds: 5)),
        contextTimeout: const Duration(milliseconds: 30),
      );
      await provider.loadConfig();
      provider.bindUser('uid-a');

      await provider.send('q');

      final appContext = server.chatBodies.single['appContext'] as Map<String, dynamic>;
      expect(appContext['notes'], [LocalAiProvider.unreadableContextNote]);
    });

    test('CONTEXT_TOO_LARGE rebuilds it with half the budget and asks once more', () async {
      final context = _FakeContext();
      final server = _FakeServer({
        'POST /api/v1/ai/chat': [
          _Reply(status: 413, body: _error('CONTEXT_TOO_LARGE', 'The app data is 2100 tokens; 1500 fit.')),
          _Reply(lines: _answer('ok')),
        ],
      });
      final provider = _provider(server, context: context);
      await provider.loadConfig();
      provider.bindUser('uid-a');

      await provider.send('q');

      expect(context.budgets, [1600, 800]);
      expect(server.chatBodies, hasLength(2));
      expect(server.chatBodies.every((b) => b.containsKey('appContext')), isTrue);
      expect(provider.messages.last.status, 'done');
    });

    test('a second CONTEXT_TOO_LARGE is shown, not retried for ever', () async {
      final context = _FakeContext();
      final server = _FakeServer({
        'POST /api/v1/ai/chat': _Reply(status: 413, body: _error('CONTEXT_TOO_LARGE', 'Too large.')),
      });
      final provider = _provider(server, context: context);
      await provider.loadConfig();
      provider.bindUser('uid-a');

      await provider.send('q');

      expect(server.chatBodies, hasLength(2));
      expect(provider.messages.last.status, 'error');
      expect(provider.lastError!.code, LocalAiException.contextTooLarge);
    });

    test('the answer records what the data contributed', () async {
      final server = _FakeServer({
        'POST /api/v1/ai/chat': _Reply(
          lines: [
            _startLine(),
            _deltaLine('42.'),
            _doneLine(
              content: '42.',
              appContext: {
                'used': true,
                'source': LocalAiAppContext.defaultSource,
                'retrievedAt': '2026-09-28T17:05:00.000Z',
                'sections': 2,
                'tokens': 610,
              },
            ),
          ],
        ),
      });
      final provider = _provider(server, context: _FakeContext());
      await provider.loadConfig();
      provider.bindUser('uid-a');

      await provider.send('q');

      final answer = provider.messages.last;
      expect(answer.usedAppData, isTrue);
      expect(answer.appContext!.sections, 2);
      expect(answer.appContext!.tokens, 610);
      expect(answer.appContext!.retrievedAt, DateTime.utc(2026, 9, 28, 17, 5));
    });

    test('a lookup the app answered itself is shown at once, and the server is not asked', () async {
      final server = _FakeServer({'POST /api/v1/ai/chat': _Reply(lines: _answer('model'))});
      final provider = _provider(
        server,
        context: _FakeContext(directAnswers: ['Head Office has 42 units available for use.']),
      );
      await provider.loadConfig();
      provider.bindUser('uid-a');

      await provider.send('head office mein kitne hain');

      expect(server.requestsTo('/ai/chat'), isEmpty);
      expect(provider.isSending, isFalse);
      expect(provider.messages, hasLength(2));

      final answer = provider.messages.last;
      expect(answer.isUser, isFalse);
      expect(answer.status, 'done');
      expect(answer.content, 'Head Office has 42 units available for use.');
      expect(answer.answeredByApp, isTrue);
      expect(answer.appContext!.retrievedAt, DateTime.utc(2026, 9, 28, 17, 5));
      expect(answer.appContext!.sections, 1);
    });

    test('the next question still goes to the model, and knows the one before it', () async {
      final context = _FakeContext(directAnswers: ['Laptop category: 16 units.', null]);
      final server = _FakeServer({'POST /api/v1/ai/chat': _Reply(lines: _answer('Because...'))});
      final provider = _provider(server, context: context);
      await provider.loadConfig();
      provider.bindUser('uid-a');

      await provider.send('How many laptops do we have?');
      await provider.send('why so many?');

      expect(server.chatBodies, hasLength(1));
      expect(server.chatBodies.single['message'], 'why so many?');
      // The instant answer is never sent, even as part of the data.
      expect(jsonEncode(server.chatBodies.single), isNot(contains('16 units')));
      expect(context.previousQuestions, [null, 'How many laptops do we have?']);
      expect(provider.messages.last.content, 'Because...');
      expect(provider.messages.last.answeredByApp, isFalse);
    });

    test('Stop pressed while the records are read wins over an instant answer', () async {
      final hold = Completer<void>();
      final server = _FakeServer({'POST /api/v1/ai/chat': _Reply(lines: _answer('model'))});
      final provider = _provider(
        server,
        context: _FakeContext(hold: hold, directAnswers: ['42 units.']),
      );
      await provider.loadConfig();
      provider.bindUser('uid-a');

      final sending = provider.send('q');
      await provider.stop();
      hold.complete();
      await sending;

      expect(server.requestsTo('/ai/chat'), isEmpty);
      expect(provider.messages.last.status, 'stopped');
      expect(provider.messages.last.content, isEmpty);
    });

    test('without a context service no appContext is sent at all', () async {
      final server = _FakeServer({'POST /api/v1/ai/chat': _Reply(lines: _answer('ok'))});
      final provider = _provider(server);
      await provider.loadConfig();
      provider.bindUser('uid-a');

      await provider.send('q');

      expect(server.chatBodies.single.containsKey('appContext'), isFalse);
    });
  });

  // ===========================================================================
  // CONVERSATIONS
  // ===========================================================================

  group('conversations', () {
    test('a conversation the server no longer has is started again, once', () async {
      final server = _FakeServer({
        'POST /api/v1/ai/chat': [
          _Reply(lines: _answer('first answer')),
          _Reply(status: 404, body: _error('CONVERSATION_NOT_FOUND', 'Unknown conversation.')),
          _Reply(lines: _answer('second answer', conversationId: 'conv-2')),
        ],
      });
      final provider = _provider(server);
      await provider.loadConfig();
      provider.bindUser('uid-a');

      await provider.send('first');
      expect(provider.conversationId, 'conv-1');

      await provider.send('second');

      final bodies = server.chatBodies;
      expect(bodies, hasLength(3));
      expect(bodies[1]['conversationId'], 'conv-1');
      expect(bodies[2].containsKey('conversationId'), isFalse);
      expect(provider.conversationId, 'conv-2');
      expect(provider.messages.last.content, 'second answer');
      expect(provider.messages.last.status, 'done');
    });

    test('a question too long for the model is refused before sending', () async {
      final server = _FakeServer({
        'GET /api/v1/health': _Reply(body: _healthBody()),
        'GET /api/v1/model': _Reply(body: _modelBody(maxMessageTokens: 10)),
        'POST /api/v1/ai/chat': _Reply(lines: _answer('ok')),
      });
      final provider = _provider(server);
      await provider.loadConfig();
      provider.bindUser('uid-a');
      await provider.testConnection();

      final question = 'a' * 40; // 14 at 3 characters each, 16 with the margin
      expect(provider.validateQuestion(question), contains('too long'));

      await provider.send(question);

      expect(server.requestsTo('/ai/chat'), isEmpty);
      expect(provider.lastError!.code, LocalAiException.messageTooLong);
      expect(provider.messages, isEmpty);
      expect(provider.validateQuestion('short'), isNull);
    });

    test('the token estimate is conservative for English and Urdu', () {
      expect(LocalAiProvider.estimateTokens('abcdef'), 3);
      expect(LocalAiProvider.estimateTokens('سلام'), 5);
      expect(LocalAiProvider.estimateTokens(''), 0);
    });

    // The server's counts, from shared/tokens.ts run with node. The app's
    // estimate must never be below them, or a question it lets through is
    // refused by the server as MESSAGE_TOO_LONG after the box was cleared.
    final serverCounts = <String, (String, int)>{
      'serial numbers': (
        List.generate(
          300,
          (i) => 'SN-${(100000 + i * 7919).toString().padLeft(8, '0')}',
        ).join('\n'),
        3629,
      ),
      'digits': ('1' * 3800, 4180),
      'Devanagari': ('क' * 3200, 4400),
      'Urdu': ('کمپیوٹر ' * 100, 655),
      'English': (
        'How many laptops are assigned to the finance department? ' * 10,
        165,
      ),
      'base64': ('aB3dE5fG7hJ9kL1mN2pQ4rS6tU8vW0xY' * 10, 282),
      'emoji': ('\u{1F600}\u{1FA70} ok', 7),
      'mixed': (
        'Laptop HP-840 G5 (S/N: 5CG1234XYZ), RAM 16GB; assigned 2024-03-01.\n'
            '  - Owner: Ali',
        52,
      ),
    };
    for (final entry in serverCounts.entries) {
      test('the token estimate is never below the server\'s: ${entry.key}', () {
        final (text, server) = entry.value;
        expect(LocalAiProvider.estimateTokens(text), greaterThanOrEqualTo(server));
      });
    }

    test('a digit-heavy question the server would refuse is refused in the app', () async {
      final server = _FakeServer({
        'GET /api/v1/health': _Reply(body: _healthBody()),
        'GET /api/v1/model': _Reply(body: _modelBody(maxMessageTokens: 4096)),
        'POST /api/v1/ai/chat': _Reply(lines: _answer('ok')),
      });
      final provider = _provider(server);
      await provider.loadConfig();
      provider.bindUser('uid-a');
      await provider.testConnection();

      // 3 800 characters, 4 180 tokens on the server: over 4 096.
      final question = '1' * 3800;
      expect(provider.validateQuestion(question), contains('too long'));

      await provider.send(question);

      expect(server.requestsTo('/ai/chat'), isEmpty);
      expect(provider.lastError!.code, LocalAiException.messageTooLong);
    });
  });

  // ===========================================================================
  // CERTIFICATE PINNING
  // ===========================================================================

  group('certificate pinning', () {
    final der = Uint8List.fromList(utf8.encode('certificate-der-bytes'));
    // sha256 of those bytes, computed with node's crypto for comparison.
    const derSha = '1b8ab3140f654654fa329b8a50d48e0e0f8aef9b615978692cc24e3b28095830';

    test('only the pinned certificate matches', () {
      expect(certificateMatchesPin(der, derSha), isTrue);
      expect(certificateMatchesPin(der, _fingerprintA), isFalse);
      expect(
        certificateMatchesPin(Uint8List.fromList(utf8.encode('another certificate')), derSha),
        isFalse,
      );
    });

    test('the pin may be typed with colons and in capitals', () {
      final colons = [
        for (var i = 0; i < derSha.length; i += 2) derSha.substring(i, i + 2),
      ].join(':').toUpperCase();

      expect(certificateMatchesPin(der, colons), isTrue);
    });

    test('an empty or malformed pin never matches anything', () {
      expect(certificateMatchesPin(der, ''), isFalse);
      expect(certificateMatchesPin(der, derSha.substring(0, 40)), isFalse);
      expect(certificateMatchesPin(Uint8List(0), derSha), isFalse);
    });

    test('pinning is available on this platform, and a pinned transport can be made', () {
      expect(localAiSupportsCertificatePinning, isTrue);
      final client = createLocalAiHttpClient(pinnedSha256: derSha);
      expect(client, isA<http.Client>());
      client.close();
    });

    test('every request is made with the configured pin', () async {
      final server = _FakeServer({'GET /api/v1/health': _Reply(body: _healthBody())});
      const pinned = LocalAiConfig(
        baseUrl: 'https://192.168.1.20:3001',
        apiKey: 'lai_abcd1234_secretsecretsecret',
        certificateFingerprint: derSha,
        source: LocalAiConfigSource.device,
      );

      await server.client().health(pinned);

      expect(server.configs.single.certificateFingerprint, derSha);
    });
  });

  // ===========================================================================
  // AUTOMATIC RE-DISCOVERY
  // ===========================================================================

  group('the laptop moved to another address', () {
    const oldConfig = LocalAiConfig(
      baseUrl: 'http://10.0.0.5:3001',
      apiKey: 'lai_abcd1234_secretsecretsecret',
      certificateFingerprint: '',
      source: LocalAiConfigSource.device,
    );

    LocalAiDiscoveredServer moved({
      String scheme = 'http',
      String? cert,
      List<String> addresses = const ['10.0.0.9'],
    }) => LocalAiDiscoveredServer(
      name: 'DESKTOP-TEST',
      scheme: scheme,
      port: 3001,
      addresses: addresses,
      certSha256: cert,
    );

    test('it is found, saved, announced, and the question is asked again', () async {
      final discovery = _FakeDiscovery([moved()]);
      final settings = _FakeSettings(oldConfig);
      final server = _FakeServer({
        'POST http://10.0.0.5:3001/api/v1/ai/chat': const _Reply(throws: SocketishException()),
        'GET http://10.0.0.9:3001/api/v1/health': _Reply(body: _healthBody()),
        'POST http://10.0.0.9:3001/api/v1/ai/chat': _Reply(lines: _answer('Found you.')),
      });
      final provider = _provider(server, settings: settings, discovery: discovery);
      await provider.loadConfig();
      provider.bindUser('uid-a');

      await provider.send('q');

      expect(discovery.calls, 1);
      expect(discovery.lastPort, 3001);
      expect(settings.current.baseUrl, 'http://10.0.0.9:3001');
      expect(settings.current.apiKey, oldConfig.apiKey);
      expect(provider.config.baseUrl, 'http://10.0.0.9:3001');
      expect(provider.takeNotice(), 'The AI server moved to 10.0.0.9; reconnected.');
      expect(provider.messages.last.content, 'Found you.');
      expect(provider.messages.last.status, 'done');
      expect(provider.status, LocalAiStatus.ready);
    });

    test('an HTTPS server found with no pin yet has its proven fingerprint pinned', () async {
      final discovery = _FakeDiscovery([moved(scheme: 'https', cert: _fingerprintB)]);
      final settings = _FakeSettings(oldConfig);
      final server = _FakeServer({
        'GET http://10.0.0.5:3001/api/v1/health': const _Reply(throws: SocketishException()),
        'GET https://10.0.0.9:3001/api/v1/health': _Reply(body: _healthBody()),
      });
      final provider = _provider(server, settings: settings, discovery: discovery);
      await provider.loadConfig();

      final healthy = await provider.testConnection();

      expect(healthy, isTrue);
      expect(settings.current.baseUrl, 'https://10.0.0.9:3001');
      expect(settings.current.certificateFingerprint, _fingerprintB);
      // The check at the new address was already made with that pin.
      expect(
        server.configs
            .where((c) => c.baseUrl == 'https://10.0.0.9:3001')
            .every((c) => c.certificateFingerprint == _fingerprintB),
        isTrue,
      );
    });

    test('a server with a different certificate is never switched to', () async {
      const pinned = LocalAiConfig(
        baseUrl: 'https://10.0.0.5:3001',
        apiKey: 'lai_abcd1234_secretsecretsecret',
        certificateFingerprint: _fingerprintA,
        source: LocalAiConfigSource.device,
      );
      final discovery = _FakeDiscovery([moved(scheme: 'https', cert: _fingerprintB)]);
      final settings = _FakeSettings(pinned);
      final server = _FakeServer({
        'POST https://10.0.0.5:3001/api/v1/ai/chat': const _Reply(throws: SocketishException()),
        'GET https://10.0.0.9:3001/api/v1/health': _Reply(body: _healthBody()),
      });
      final provider = _provider(server, settings: settings, discovery: discovery);
      await provider.loadConfig();
      provider.bindUser('uid-a');

      await provider.send('q');

      expect(discovery.calls, 1);
      expect(settings.addressSaves, 0);
      expect(settings.current.baseUrl, 'https://10.0.0.5:3001');
      expect(server.requests.where((r) => r.url.host == '10.0.0.9'), isEmpty);
      expect(provider.messages.last.status, 'error');
      expect(provider.lastError!.code, LocalAiException.unreachable);
      expect(provider.status, LocalAiStatus.unreachable);
    });

    test('the same pinned certificate at a new address is followed', () async {
      const pinned = LocalAiConfig(
        baseUrl: 'https://10.0.0.5:3001',
        apiKey: 'lai_abcd1234_secretsecretsecret',
        certificateFingerprint: _fingerprintA,
        source: LocalAiConfigSource.device,
      );
      final discovery = _FakeDiscovery([moved(scheme: 'https', cert: _fingerprintA)]);
      final settings = _FakeSettings(pinned);
      final server = _FakeServer({
        'POST https://10.0.0.5:3001/api/v1/ai/chat': const _Reply(throws: SocketishException()),
        'GET https://10.0.0.9:3001/api/v1/health': _Reply(body: _healthBody()),
        'POST https://10.0.0.9:3001/api/v1/ai/chat': _Reply(lines: _answer('ok')),
      });
      final provider = _provider(server, settings: settings, discovery: discovery);
      await provider.loadConfig();
      provider.bindUser('uid-a');

      await provider.send('q');

      expect(settings.current.baseUrl, 'https://10.0.0.9:3001');
      expect(settings.current.certificateFingerprint, _fingerprintA);
      expect(provider.messages.last.status, 'done');
    });

    test('a pinned HTTPS setup is never moved to plain HTTP, whatever it claims', () async {
      const pinned = LocalAiConfig(
        baseUrl: 'https://10.0.0.5:3001',
        apiKey: 'lai_abcd1234_secretsecretsecret',
        certificateFingerprint: _fingerprintA,
        source: LocalAiConfigSource.device,
      );
      // Proof-valid (it is only SHA-256 of the key), with the pinned
      // fingerprint copied in, but plain HTTP: the pin could not be checked
      // and the key would travel unencrypted.
      final discovery = _FakeDiscovery([moved(scheme: 'http', cert: _fingerprintA)]);
      final settings = _FakeSettings(pinned);
      final server = _FakeServer({
        'POST https://10.0.0.5:3001/api/v1/ai/chat': const _Reply(throws: SocketishException()),
        'GET http://10.0.0.9:3001/api/v1/health': _Reply(body: _healthBody()),
        'POST http://10.0.0.9:3001/api/v1/ai/chat': _Reply(lines: _answer('leaked')),
      });
      final provider = _provider(server, settings: settings, discovery: discovery);
      await provider.loadConfig();
      provider.bindUser('uid-a');

      await provider.send('q');

      expect(discovery.calls, 1);
      expect(settings.addressSaves, 0);
      expect(settings.current.baseUrl, 'https://10.0.0.5:3001');
      expect(server.requests.where((r) => r.url.host == '10.0.0.9'), isEmpty);
      expect(provider.messages.last.status, 'error');
      expect(provider.lastError!.code, LocalAiException.unreachable);
    });

    test('an unpinned HTTPS setup is not downgraded to plain HTTP either', () async {
      const secure = LocalAiConfig(
        baseUrl: 'https://10.0.0.5:3001',
        apiKey: 'lai_abcd1234_secretsecretsecret',
        certificateFingerprint: '',
        source: LocalAiConfigSource.device,
      );
      final discovery = _FakeDiscovery([moved(scheme: 'http')]);
      final settings = _FakeSettings(secure);
      final server = _FakeServer({
        'GET https://10.0.0.5:3001/api/v1/health': const _Reply(throws: SocketishException()),
        'GET http://10.0.0.9:3001/api/v1/health': _Reply(body: _healthBody()),
      });
      final provider = _provider(server, settings: settings, discovery: discovery);
      await provider.loadConfig();

      expect(await provider.testConnection(), isFalse);
      expect(discovery.calls, 1);
      expect(settings.addressSaves, 0);
      expect(server.requests.where((r) => r.url.host == '10.0.0.9'), isEmpty);
    });

    test('Stop during the search ends the answer as stopped, not as an error', () async {
      final hold = Completer<void>();
      final discovery = _FakeDiscovery([moved()], hold: hold);
      final server = _FakeServer({
        'POST http://10.0.0.5:3001/api/v1/ai/chat': const _Reply(throws: SocketishException()),
        'GET http://10.0.0.9:3001/api/v1/health': _Reply(body: _healthBody()),
        'POST http://10.0.0.9:3001/api/v1/ai/chat': _Reply(lines: _answer('late')),
      });
      final provider = _provider(
        server,
        settings: _FakeSettings(oldConfig),
        discovery: discovery,
      );
      await provider.loadConfig();
      provider.bindUser('uid-a');

      final sending = provider.send('q');
      await _until(() => discovery.calls == 1);
      await provider.stop();
      // Not held up by the search, which is still running.
      await sending;

      expect(provider.messages.last.status, 'stopped');
      expect(provider.lastError, isNull);
      expect(provider.isSending, isFalse);

      // The search finishing afterwards may save the new address, but the
      // question is not asked again.
      hold.complete();
      await _until(() => provider.config.baseUrl == 'http://10.0.0.9:3001');
      expect(
        server.requestsTo('/ai/chat').where((r) => r.url.host == '10.0.0.9'),
        isEmpty,
      );
      expect(provider.messages.last.status, 'stopped');
    });

    test('no retry once part of the answer has been shown', () async {
      final discovery = _FakeDiscovery([moved()]);
      final server = _FakeServer({
        'POST http://10.0.0.5:3001/api/v1/ai/chat': _Reply(
          lines: [_startLine(), _deltaLine('Half')],
          errorAfter: http.ClientException('Connection closed while receiving data'),
        ),
      });
      final provider = _provider(
        server,
        settings: _FakeSettings(oldConfig),
        discovery: discovery,
      );
      await provider.loadConfig();
      provider.bindUser('uid-a');

      await provider.send('q');

      expect(discovery.calls, 0);
      expect(server.chatBodies, hasLength(1));
      expect(provider.messages.last.status, 'error');
      expect(provider.messages.last.content, 'Half');
    });

    test('web builds (no discovery) simply report the laptop unreachable', () async {
      final discovery = _FakeDiscovery([moved()], supported: false);
      final server = _FakeServer({
        'GET http://10.0.0.5:3001/api/v1/health': const _Reply(throws: SocketishException()),
      });
      final provider = _provider(server, settings: _FakeSettings(oldConfig), discovery: discovery);
      await provider.loadConfig();

      expect(await provider.testConnection(), isFalse);
      expect(discovery.calls, 0);
      expect(provider.status, LocalAiStatus.unreachable);
    });

    // A reachable-from-anywhere address (a tunnel's public hostname) must never be
    // traded for a LAN one: discovery only ever hears from this network, so a reply
    // to it says nothing about where the public address should point. Following one
    // would pin the device to the LAN certificate and leave it unable to reach the
    // server from outside until somebody retyped the address.
    group('a public address is never replaced by a LAN one', () {
      const remoteConfig = LocalAiConfig(
        baseUrl: 'https://desktop-test.tailnet-1234.ts.net',
        apiKey: 'lai_abcd1234_secretsecretsecret',
        certificateFingerprint: '',
        source: LocalAiConfigSource.device,
      );

      test('the search is not even started, and the saved settings are left alone', () async {
        final discovery = _FakeDiscovery([moved(scheme: 'https', cert: _fingerprintA)]);
        final settings = _FakeSettings(remoteConfig);
        final server = _FakeServer({
          'GET https://desktop-test.tailnet-1234.ts.net/api/v1/health': const _Reply(throws: SocketishException()),
        });
        final provider = _provider(server, settings: settings, discovery: discovery);
        await provider.loadConfig();

        expect(await provider.testConnection(), isFalse);
        expect(discovery.calls, 0, reason: 'a public address must not trigger a LAN search at all');
        expect(settings.current.baseUrl, remoteConfig.baseUrl);
        expect(settings.current.certificateFingerprint, isEmpty, reason: 'the LAN certificate must not be adopted');
        expect(provider.config.baseUrl, remoteConfig.baseUrl);
        expect(provider.status, LocalAiStatus.unreachable);
      });

      test('a question that fails reports the server unreachable instead of moving', () async {
        final discovery = _FakeDiscovery([moved(scheme: 'https', cert: _fingerprintA)]);
        final settings = _FakeSettings(remoteConfig);
        final server = _FakeServer({
          'POST https://desktop-test.tailnet-1234.ts.net/api/v1/ai/chat': const _Reply(throws: SocketishException()),
        });
        final provider = _provider(server, settings: settings, discovery: discovery);
        await provider.loadConfig();
        provider.bindUser('uid-a');

        await provider.send('q');

        expect(discovery.calls, 0);
        expect(settings.current.baseUrl, remoteConfig.baseUrl);
        expect(provider.messages.last.status, 'error');
      });

      test('a LAN address is still moved, so nothing about the existing setup changes', () async {
        final discovery = _FakeDiscovery([moved()]);
        final settings = _FakeSettings(oldConfig);
        final server = _FakeServer({
          'GET http://10.0.0.5:3001/api/v1/health': const _Reply(throws: SocketishException()),
          'GET http://10.0.0.9:3001/api/v1/health': _Reply(body: _healthBody()),
        });
        final provider = _provider(server, settings: settings, discovery: discovery);
        await provider.loadConfig();

        expect(await provider.testConnection(), isTrue);
        expect(discovery.calls, 1);
        expect(settings.current.baseUrl, 'http://10.0.0.9:3001');
      });

      test('a reply offering a public address is ignored even from a LAN setup', () async {
        final discovery = _FakeDiscovery([moved(addresses: const ['ai.example.com'])]);
        final settings = _FakeSettings(oldConfig);
        final server = _FakeServer({
          'GET http://10.0.0.5:3001/api/v1/health': const _Reply(throws: SocketishException()),
          'GET http://ai.example.com:3001/api/v1/health': _Reply(body: _healthBody()),
        });
        final provider = _provider(server, settings: settings, discovery: discovery);
        await provider.loadConfig();

        expect(await provider.testConnection(), isFalse);
        expect(settings.current.baseUrl, oldConfig.baseUrl);
      });
    });
  });

  // ===========================================================================
  // MONITORING
  // ===========================================================================

  group('monitoring', () {
    test('health is polled while monitoring, and not after it stops', () async {
      final server = _FakeServer({
        'GET /api/v1/health': _Reply(body: _healthBody()),
        'GET /api/v1/model': _Reply(body: _modelBody()),
      });
      final provider = _provider(server, monitorInterval: const Duration(milliseconds: 20));
      await provider.loadConfig();

      provider.startMonitoring();
      await _until(() => server.requestsTo('/health').length >= 2);
      provider.stopMonitoring();
      final count = server.requestsTo('/health').length;
      await Future<void>.delayed(const Duration(milliseconds: 80));

      expect(server.requestsTo('/health').length, count);
      expect(provider.status, LocalAiStatus.ready);
      expect(provider.isMonitoring, isFalse);
    });

    test('Retry-After pauses the polling', () async {
      final server = _FakeServer({
        'GET /api/v1/health': _Reply(
          status: 429,
          body: _error('RATE_LIMITED', 'Too many requests.'),
          headers: const {'content-type': 'application/json', 'retry-after': '60'},
        ),
      });
      final provider = _provider(server, monitorInterval: const Duration(milliseconds: 15));
      await provider.loadConfig();

      provider.startMonitoring();
      await _until(() => server.requestsTo('/health').isNotEmpty);
      await Future<void>.delayed(const Duration(milliseconds: 90));
      provider.stopMonitoring();

      expect(server.requestsTo('/health'), hasLength(1));
      expect(provider.lastError!.userMessage, 'Too many requests. Try again in 60 seconds.');
    });
  });

  // ===========================================================================
  // CONFIGURATION
  // ===========================================================================

  // ===========================================================================
  // SETTINGS PUBLISHED FOR EVERY DEVICE
  // ===========================================================================

  group('settings published by an administrator', () {
    const published = LocalAiRemoteSettings(
      baseUrl: 'https://desktop-test.tailnet-1234.ts.net',
      apiKey: 'lai_remote01_publishedsecret',
      certificateFingerprint: '',
    );

    test('a device with nothing set up connects without anyone typing anything', () async {
      final settings = _FakeSettings(LocalAiConfig.empty);
      final server = _FakeServer({
        'GET https://desktop-test.tailnet-1234.ts.net/api/v1/health': _Reply(body: _healthBody()),
      });
      final provider = _provider(server, settings: settings, remoteSetup: _FakeRemoteSetup(published));

      await provider.loadConfig();

      expect(provider.config.baseUrl, published.baseUrl);
      expect(provider.config.apiKey, published.apiKey);
      expect(provider.status, isNot(LocalAiStatus.notConfigured));
      // Saved, so the next start needs no fetch at all.
      expect(settings.current.baseUrl, published.baseUrl);
      expect(await provider.testConnection(), isTrue);
    });

    test('what an administrator typed on this device is never overwritten', () async {
      const typed = LocalAiConfig(
        baseUrl: 'https://172.16.20.246:3001',
        apiKey: 'lai_typed001_chosenbyhand',
        certificateFingerprint: _fingerprintA,
        source: LocalAiConfigSource.device,
      );
      final settings = _FakeSettings(typed);
      final remote = _FakeRemoteSetup(published);
      final provider = _provider(_FakeServer(const {}), settings: settings, remoteSetup: remote);

      await provider.loadConfig();

      expect(provider.config.baseUrl, typed.baseUrl);
      expect(provider.config.apiKey, typed.apiKey);
      expect(provider.config.certificateFingerprint, _fingerprintA);
      expect(remote.calls, 0, reason: 'a device that is already set up has no reason to ask');
    });

    test('only the missing half is filled in', () async {
      // An address compiled into the build, but no key anywhere: take the key.
      const addressOnly = LocalAiConfig(
        baseUrl: 'https://compiled-in.tailnet-1234.ts.net',
        apiKey: '',
        certificateFingerprint: '',
        source: LocalAiConfigSource.build,
      );
      final settings = _FakeSettings(addressOnly);
      final provider = _provider(_FakeServer(const {}), settings: settings, remoteSetup: _FakeRemoteSetup(published));

      await provider.loadConfig();

      expect(provider.config.baseUrl, addressOnly.baseUrl, reason: 'the build chose this address');
      expect(provider.config.apiKey, published.apiKey);
    });

    test('a published fingerprint is not attached to an address chosen elsewhere', () async {
      const addressOnly = LocalAiConfig(
        baseUrl: 'https://compiled-in.tailnet-1234.ts.net',
        apiKey: '',
        certificateFingerprint: '',
        source: LocalAiConfigSource.build,
      );
      final settings = _FakeSettings(addressOnly);
      final provider = _provider(
        _FakeServer(const {}),
        settings: settings,
        remoteSetup: _FakeRemoteSetup(const LocalAiRemoteSettings(
          baseUrl: 'https://somewhere-else.tailnet-1234.ts.net',
          apiKey: 'lai_remote01_publishedsecret',
          certificateFingerprint: _fingerprintB,
        )),
      );

      await provider.loadConfig();

      expect(provider.config.certificateFingerprint, isEmpty);
    });

    test('nothing published, or a half-filled document, leaves the device as it was', () async {
      for (final source in [
        _FakeRemoteSetup(null),
        _FakeRemoteSetup(const LocalAiRemoteSettings(baseUrl: 'https://x.ts.net', apiKey: '', certificateFingerprint: '')),
        _FakeRemoteSetup(const LocalAiRemoteSettings(baseUrl: '', apiKey: 'lai_remote01_secret', certificateFingerprint: '')),
      ]) {
        final provider = _provider(_FakeServer(const {}), settings: _FakeSettings(LocalAiConfig.empty), remoteSetup: source);
        await provider.loadConfig();
        expect(provider.config.isConfigured, isFalse);
        expect(provider.status, LocalAiStatus.notConfigured);
      }
    });

    test('a rubbish address in the document is refused rather than saved', () async {
      final settings = _FakeSettings(LocalAiConfig.empty);
      final provider = _provider(
        _FakeServer(const {}),
        settings: settings,
        remoteSetup: _FakeRemoteSetup(const LocalAiRemoteSettings(
          baseUrl: 'not-a-url/with a path',
          apiKey: 'lai_remote01_secret',
          certificateFingerprint: '',
        )),
      );

      await provider.loadConfig();

      expect(provider.config.isConfigured, isFalse);
      expect(settings.current.baseUrl, isEmpty);
    });

    test('a failure to read is silent: the screen behaves as if nothing were published', () async {
      final provider = _provider(
        _FakeServer(const {}),
        settings: _FakeSettings(LocalAiConfig.empty),
        remoteSetup: _FakeRemoteSetup(null, throws: true),
      );

      await provider.loadConfig();

      expect(provider.config.isConfigured, isFalse);
      expect(provider.status, LocalAiStatus.notConfigured);
    });

    test('signing in is a fresh chance to fetch, so the first screen is already connected', () async {
      final settings = _FakeSettings(LocalAiConfig.empty);
      final remote = _FakeRemoteSetup(published);
      final provider = _provider(_FakeServer(const {}), settings: settings, remoteSetup: remote);

      // Before anyone has signed in, Firestore refuses the read.
      remote.available = false;
      await provider.loadConfig();
      expect(provider.config.isConfigured, isFalse);

      // Signing in makes it readable, and the provider asks again by itself.
      remote.available = true;
      provider.bindUser('uid-a');
      await pumpEventQueue();

      expect(provider.config.baseUrl, published.baseUrl);
      expect(provider.config.apiKey, published.apiKey);
    });

    test('it is asked at most once per sign-in, not once per screen', () async {
      final remote = _FakeRemoteSetup(published);
      final provider = _provider(_FakeServer(const {}), settings: _FakeSettings(LocalAiConfig.empty), remoteSetup: remote);

      await provider.loadConfig();
      await provider.loadConfig();
      await provider.loadConfig();

      expect(remote.calls, 1);
    });

    test('a build that publishes nothing behaves exactly as before', () async {
      final provider = _provider(_FakeServer(const {}), settings: _FakeSettings(LocalAiConfig.empty));

      await provider.loadConfig();

      expect(provider.config.isConfigured, isFalse);
      expect(provider.status, LocalAiStatus.notConfigured);
    });
  });

  group('configuration', () {
    test('a LAN address is told apart from a public one', () {
      // What decides whether a UDP discovery reply may replace the saved address.
      for (final host in [
        '10.0.0.5',
        '172.16.20.246',
        '172.31.255.254',
        '192.168.1.50',
        '127.0.0.1',
        '169.254.1.1',
        '10.0.2.2', // the Android emulator's alias for the host machine
        'localhost',
        'DESKTOP-KS31F63',
        'DESKTOP-KS31F63.local',
        '::1',
        'fe80::1',
        'fd00::1',
      ]) {
        expect(LocalAiConfig.hostIsPrivate(host), isTrue, reason: '$host is reachable only on this network');
      }

      for (final host in [
        'desktop-test.tailnet-1234.ts.net',
        'ai.example.com',
        '8.8.8.8',
        '172.15.0.1', // just below the private 172.16/12 block
        '172.32.0.1', // just above it
        '192.167.1.1',
        '11.0.0.1',
        '2001:db8::1',
        '',
      ]) {
        expect(LocalAiConfig.hostIsPrivate(host), isFalse, reason: '$host is not a LAN address');
      }
    });

    test('a configuration knows whether its own address is a LAN one', () {
      const remote = LocalAiConfig(
        baseUrl: 'https://desktop-test.tailnet-1234.ts.net',
        apiKey: 'lai_abcd1234_secretsecretsecret',
        certificateFingerprint: '',
        source: LocalAiConfigSource.device,
      );
      expect(remote.isPrivateHost, isFalse);
      expect(_config.isPrivateHost, isTrue);
    });

    test('the API key is never shown in full', () {
      expect(_config.redactedApiKey, 'lai_abcd1234_••••••••');
      expect(_config.redactedApiKey, isNot(contains('secretsecretsecret')));
    });

    test('a key of an unexpected shape is still not revealed', () {
      const other = LocalAiConfig(
        baseUrl: 'http://x',
        apiKey: 'some-other-format-key',
        certificateFingerprint: '',
        source: LocalAiConfigSource.device,
      );

      expect(other.redactedApiKey, isNot(contains('some-other-format-key')));
      expect(other.keyId, isNull);
    });

    test('the key id is read from lai_<id>_<secret>', () {
      expect(_config.keyId, 'abcd1234');
      expect(LocalAiConfig.keyIdOf(_vectorKey), 'ab12cd34');
      expect(LocalAiConfig.keyIdOf('lai_ab12cd34_se_cr-et'), 'ab12cd34');
      expect(LocalAiConfig.keyIdOf('lai_AB12CD34_secret'), isNull);
    });

    test('an address with /api/v1 pasted on is corrected, not doubled', () {
      // Otherwise every call would go to /api/v1/api/v1/... and 404.
      expect(
        LocalAiSettingsStore.normaliseUrl(' http://10.0.2.2:3000/api/v1/ '),
        'http://10.0.2.2:3000',
      );
      expect(_config.apiRoot, 'http://10.0.2.2:3000/api/v1');
    });

    test('addresses are checked for scheme and host', () {
      expect(LocalAiSettingsStore.addressProblem(''), isNull);
      expect(LocalAiSettingsStore.addressProblem('https://192.168.1.20:3001'), isNull);
      expect(LocalAiSettingsStore.addressProblem('http://10.0.2.2:3000/api/v1'), isNull);
      expect(LocalAiSettingsStore.addressProblem('192.168.1.20:3001'), isNotNull);
      expect(LocalAiSettingsStore.addressProblem('ftp://192.168.1.20'), isNotNull);
      expect(LocalAiSettingsStore.addressProblem('https://'), isNotNull);
      expect(LocalAiSettingsStore.addressProblem('https://host/other'), isNotNull);
      expect(LocalAiSettingsStore.addressProblem('https://u:p@host'), isNotNull);
    });

    test('fingerprints are accepted with colons and must be 64 hex characters', () {
      expect(LocalAiSettingsStore.fingerprintProblem(''), isNull);
      expect(LocalAiSettingsStore.fingerprintProblem(_fingerprintA), isNull);
      expect(
        LocalAiSettingsStore.fingerprintProblem(
          [for (var i = 0; i < 64; i += 2) 'AB'].join(':'),
        ),
        isNull,
      );
      expect(LocalAiSettingsStore.fingerprintProblem('abcd'), isNotNull);
      expect(LocalAiSettingsStore.fingerprintProblem('zz${'a' * 62}'), isNotNull);
    });

    test('plain HTTP is recognised, so the UI can warn about it', () {
      expect(_config.isCleartext, isTrue);
    });

    test('saving checks the address before anything is stored', () async {
      final settings = _FakeSettings(_config);
      final provider = _provider(_FakeServer({}), settings: settings);
      await provider.loadConfig();

      final error = await _errorFrom(() => provider.saveConfig(baseUrl: 'not an address'));

      expect(error.code, LocalAiException.notConfigured);
      expect(settings.current.baseUrl, _config.baseUrl);
    });

    test('saving without a key keeps the stored key', () async {
      final settings = _FakeSettings(_config);
      final server = _FakeServer({'GET /api/v1/health': _Reply(body: _healthBody())});
      final provider = _provider(server, settings: settings);
      await provider.loadConfig();

      await provider.saveConfig(baseUrl: 'http://192.168.1.30:3001');

      expect(settings.current.baseUrl, 'http://192.168.1.30:3001');
      expect(settings.current.apiKey, _config.apiKey);
      expect(settings.addressSaves, 1);
    });

    test('reset to defaults forgets the device settings', () async {
      final settings = _FakeSettings(_config);
      final provider = _provider(_FakeServer({}), settings: settings);
      await provider.loadConfig();

      await provider.resetConfig();

      expect(provider.isConfigured, isFalse);
      expect(provider.status, LocalAiStatus.notConfigured);
    });

    test('reset clears the conversation even when the build supplies the same key', () async {
      // Same key after the reset, so the scope does not change; the reset
      // must still clear the conversation, as its confirmation promises.
      final settings = _FakeSettings(_config, buildDefaults: _config);
      final context = _FakeContext();
      final server = _FakeServer({
        'GET /api/v1/health': _Reply(body: _healthBody()),
        'POST /api/v1/ai/chat': _Reply(lines: _answer('ok')),
      });
      final provider = _provider(server, settings: settings, context: context);
      await provider.loadConfig();
      provider.bindUser('uid-a');
      await provider.send('q');
      expect(provider.hasConversation, isTrue);
      expect(provider.conversationId, isNotNull);

      await provider.resetConfig();

      expect(provider.isConfigured, isTrue);
      expect(provider.hasConversation, isFalse);
      expect(provider.conversationId, isNull);
      expect(context.resets, greaterThan(0));
    });
  });

  // ===========================================================================
  // USER AND SESSION ISOLATION
  // ===========================================================================

  group('user and session isolation', () {
    test('the scope is HMAC-SHA256 of the uid, keyed with the API key', () {
      // Computed with node: crypto.createHmac('sha256', key)
      //   .update('psba-it-inventory:local-ai:v2:' + uid).digest('hex')
      expect(
        LocalAiScope.forUser('uid-aaa', apiKey: _vectorKey),
        '78575836dd520e7dfdf15e26ed5547f60e97302aab6d5eeed2d41faa6e61cc7a',
      );
      expect(
        LocalAiScope.forUser('AbCdEf123456uid', apiKey: _vectorKey),
        '28739080dbd49ded730aadaa4636e2d7b9ccbdb73e5ba9280192ec4c46d42825',
      );
    });

    test('two accounts get different scopes, and one account keeps its own', () {
      final a = LocalAiScope.forUser('uid-aaa', apiKey: _config.apiKey);
      final b = LocalAiScope.forUser('uid-bbb', apiKey: _config.apiKey);

      expect(a, isNotEmpty);
      expect(a, isNot(b));
      // The same person always gets the same scope, so their conversation
      // survives a restart.
      expect(LocalAiScope.forUser('uid-aaa', apiKey: _config.apiKey), a);
      // A new key is a new scope.
      expect(LocalAiScope.forUser('uid-aaa', apiKey: _vectorKey), isNot(a));
    });

    test('the scope never contains the Firebase uid', () {
      // The server has no business knowing who the user is; it only needs a
      // value that is stable per person and different between people.
      const uid = 'AbCdEf123456uid';
      final scope = LocalAiScope.forUser(uid, apiKey: _config.apiKey);

      expect(scope, isNot(contains(uid)));
      expect(scope, matches(RegExp(r'^[0-9a-f]{64}$')));
    });

    test('nobody signed in, or no key, means no scope at all', () {
      expect(LocalAiScope.forUser(null, apiKey: _config.apiKey), isEmpty);
      expect(LocalAiScope.forUser('  ', apiKey: _config.apiKey), isEmpty);
      expect(LocalAiScope.forUser('uid-a', apiKey: ''), isEmpty);
    });

    test('the request carries the scope for the signed-in account', () async {
      final server = _FakeServer({'POST /api/v1/ai/chat': _Reply(lines: _answer('ok'))});
      final provider = _provider(server);
      await provider.loadConfig();
      provider.bindUser('uid-a');

      await provider.send('q');

      expect(
        server.requestsTo('/ai/chat').single.headers['x-conversation-scope'],
        LocalAiScope.forUser('uid-a', apiKey: _config.apiKey),
      );
    });

    test('nothing is sent while nobody is signed in', () async {
      final server = _FakeServer({'POST /api/v1/ai/chat': _Reply(lines: _answer('ok'))});
      final provider = _provider(server, context: _FakeContext());
      await provider.loadConfig();

      await provider.send('hello?');

      expect(server.requests, isEmpty);
      expect(provider.lastError!.code, LocalAiException.notSignedIn);
      expect(provider.messages, isEmpty);
      expect(provider.validateQuestion('hello?'), isNotNull);
    });

    test('a new API key starts a new conversation', () async {
      final settings = _FakeSettings(_config);
      final context = _FakeContext();
      final server = _FakeServer({'POST /api/v1/ai/chat': _Reply(lines: _answer('ok'))});
      final provider = _provider(server, settings: settings, context: context);
      await provider.loadConfig();
      provider.bindUser('uid-a');
      await provider.send('hello');
      expect(provider.messages, isNotEmpty);
      final resets = context.resets;

      settings.current = settings.current.copyWith(apiKey: _vectorKey);
      await provider.loadConfig();

      expect(provider.messages, isEmpty);
      expect(provider.conversationId, isNull);
      expect(context.resets, resets + 1);
    });

    test('a new address with the same key keeps the conversation', () async {
      final settings = _FakeSettings(_config);
      final server = _FakeServer({'POST /api/v1/ai/chat': _Reply(lines: _answer('ok'))});
      final provider = _provider(server, settings: settings);
      await provider.loadConfig();
      provider.bindUser('uid-a');
      await provider.send('hello');

      settings.current = settings.current.copyWith(baseUrl: 'http://192.168.1.9:3001');
      await provider.loadConfig();

      expect(provider.messages, isNotEmpty);
      expect(provider.conversationId, 'conv-1');
    });

    test('switching account discards the previous conversation', () async {
      final context = _FakeContext();
      final server = _FakeServer({'POST /api/v1/ai/chat': _Reply(lines: _answer('ok'))});
      final provider = _provider(server, context: context);
      await provider.loadConfig();
      provider.bindUser('uid-a');
      await provider.send('hello');

      provider.bindUser('uid-b');

      expect(provider.messages, isEmpty);
      expect(provider.conversationId, isNull);
      expect(context.resets, greaterThan(0));
    });

    test('an answer in flight when the account changes is never shown to the next one', () async {
      // The case this exists for: User A asks something, walks away, User B
      // signs in before the laptop replies.
      final server = _FakeServer({
        'POST /api/v1/ai/chat': _Reply(
          lines: _answer('User A private answer'),
          delay: const Duration(milliseconds: 40),
        ),
      });
      final provider = _provider(server);
      await provider.loadConfig();
      provider.bindUser('uid-a');

      final pending = provider.send('something private');
      provider.bindUser('uid-b');
      await pending;

      expect(provider.messages, isEmpty);
      expect(provider.isSending, isFalse);
    });
  });

  // ===========================================================================
  // LOGOUT CLEANUP
  // ===========================================================================

  group('logout cleanup', () {
    test('logout clears the conversation but keeps the device configuration', () async {
      final server = _FakeServer({'POST /api/v1/ai/chat': _Reply(lines: _answer('hi'))});
      final provider = _provider(server);

      await provider.loadConfig();
      provider.bindUser('uid-a');
      await provider.send('hello');

      expect(provider.messages, isNotEmpty);

      provider.clearForLogout();

      expect(provider.messages, isEmpty);
      expect(provider.conversationId, isNull);
      expect(provider.health, isNull);
      // The address and key belong to the device and were set by an
      // administrator, so signing out must not wipe them.
      expect(provider.config.baseUrl, _config.baseUrl);
      expect(provider.isConfigured, isTrue);
    });

    test('the auth stream drives it, so no sign-out path can be missed', () async {
      final auth = StreamController<String?>();
      final server = _FakeServer({'POST /api/v1/ai/chat': _Reply(lines: _answer('hi'))});
      final provider = _provider(server)..attachUserStream(auth.stream);

      await provider.loadConfig();
      auth.add('uid-a');
      await Future<void>.delayed(Duration.zero);
      await provider.send('hello');
      expect(provider.messages, isNotEmpty);

      // Whatever route the sign-out took, the auth state is what changes.
      auth.add(null);
      await Future<void>.delayed(Duration.zero);

      expect(provider.messages, isEmpty);
      await auth.close();
    });
  });

  // ===========================================================================
  // WIDGETS
  // ===========================================================================

  group('widgets', () {
    Widget host(Widget child) => MaterialApp(home: Scaffold(body: child));

    testWidgets('an answer grounded in the inventory says so, with the time', (tester) async {
      final at = DateTime.utc(2026, 9, 28, 17, 5);
      await tester.pumpWidget(
        host(
          LocalAiMessageBubble(
            message: LocalAiMessage(
              id: 'm1',
              role: 'assistant',
              content: '42 at Head Office.',
              appContext: LocalAiAppContextUsage(
                used: true,
                source: LocalAiAppContext.defaultSource,
                retrievedAt: at,
                sections: 2,
                tokens: 610,
              ),
            ),
          ),
        ),
      );

      expect(
        find.text(
          'Based on your IT Inventory data · as of '
          '${DateFormat('HH:mm').format(at.toLocal())}',
        ),
        findsOneWidget,
      );
    });

    testWidgets('a stopped answer is labelled Stopped and keeps its text', (tester) async {
      await tester.pumpWidget(
        host(
          const LocalAiMessageBubble(
            message: LocalAiMessage(
              id: 'm1',
              role: 'assistant',
              content: 'Half an',
              status: 'stopped',
            ),
          ),
        ),
      );

      expect(find.text('Stopped'), findsOneWidget);
      expect(find.text('Half an'), findsOneWidget);
      expect(find.textContaining('Based on your IT Inventory'), findsNothing);
    });

    testWidgets('the pending bubble shows what is happening', (tester) async {
      await tester.pumpWidget(
        host(
          const LocalAiMessageBubble(
            message: LocalAiMessage(
              id: 'pending',
              role: 'assistant',
              content: '',
              status: 'streaming',
              progress: 'Reading your inventory data…',
            ),
          ),
        ),
      );

      expect(find.text('Reading your inventory data…'), findsOneWidget);
    });

    testWidgets('the documents chip is hidden when the key may not use documents', (tester) async {
      Widget composer({required bool documents}) => host(
        LocalAiComposer(
          enabled: true,
          sending: false,
          canStop: false,
          documentsMode: LocalAiDocumentsMode.off,
          documentsAvailable: documents,
          onChangedDocumentsMode: (_) {},
          onSend: (_) {},
          onStop: () {},
        ),
      );

      await tester.pumpWidget(composer(documents: false));
      expect(find.text('Docs: off'), findsNothing);

      await tester.pumpWidget(composer(documents: true));
      expect(find.text('Docs: off'), findsOneWidget);
    });

    testWidgets('a refused question stays in the box', (tester) async {
      final sent = <String>[];
      await tester.pumpWidget(
        host(
          LocalAiComposer(
            enabled: true,
            sending: false,
            canStop: false,
            documentsMode: LocalAiDocumentsMode.off,
            onChangedDocumentsMode: (_) {},
            onSend: sent.add,
            onStop: () {},
            validate: (_) => 'This question is too long.',
          ),
        ),
      );

      await tester.enterText(find.byType(TextField), 'a very long question');
      await tester.tap(find.byTooltip('Send'));
      await tester.pump();

      expect(sent, isEmpty);
      expect(find.text('a very long question'), findsOneWidget);
      expect(find.text('This question is too long.'), findsOneWidget);
    });
  });
}
