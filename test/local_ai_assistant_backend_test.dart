/// The floating assistant's model: Qwen3 on the laptop, asked through the
/// app's LocalAiProvider. The server is faked at the HTTP layer, so the real
/// client, provider and adapter all run.
library;

import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart' show VoidCallback;
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

import 'package:it_management_system/core/ai/ai_assistant_panel.dart'
    show modelPlansActions;
import 'package:it_management_system/core/ai/ai_backend.dart';
import 'package:it_management_system/core/ai/local/local_ai_assistant_backend.dart';
import 'package:it_management_system/core/ai/local/local_ai_client.dart';
import 'package:it_management_system/core/ai/local/local_ai_config.dart';
import 'package:it_management_system/core/ai/local/local_ai_context_service.dart';
import 'package:it_management_system/core/ai/local/local_ai_discovery.dart';
import 'package:it_management_system/core/ai/local/local_ai_provider.dart';

const _configured = LocalAiConfig(
  baseUrl: 'https://192.168.1.20:3001',
  apiKey: 'lai_ab12cd34_AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA',
  certificateFingerprint: '',
  source: LocalAiConfigSource.device,
);

class _Settings implements LocalAiSettingsStore {
  _Settings(this.current);

  final LocalAiConfig current;

  @override
  Future<LocalAiConfig> load() async => current;

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _NoDiscovery implements LocalAiDiscovery {
  @override
  bool get isSupported => false;

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _Backend implements AssistantBackend {
  _Backend({required this.enabled});

  @override
  final bool enabled;

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _WordsOnly extends _Backend implements WordsOnlyBackend {
  _WordsOnly() : super(enabled: true);
}

/// The real provider, remembering who is listening to it.
///
/// A streaming ask attaches a listener for the length of one question. One
/// left behind would keep a closed panel alive for the life of the app, and
/// nothing on screen would show it, so the tests count them instead.
class _TrackedProvider extends LocalAiProvider {
  _TrackedProvider({
    super.client,
    super.settings,
    super.discovery,
    super.contextService,
  });

  final Set<VoidCallback> listeners = {};

  @override
  void addListener(VoidCallback listener) {
    listeners.add(listener);
    super.addListener(listener);
  }

  @override
  void removeListener(VoidCallback listener) {
    listeners.remove(listener);
    super.removeListener(listener);
  }
}

/// Inventory data whose question the app can answer by itself.
class _AnsweredByApp implements LocalAiContextService {
  _AnsweredByApp(this.answer);

  final String answer;

  @override
  Future<LocalAiAppContext?> contextFor({
    required String question,
    required String? uid,
    String? previousQuestion,
    required int budgetTokens,
  }) async {
    return LocalAiAppContext(
      source: LocalAiAppContext.defaultSource,
      retrievedAt: DateTime.utc(2026, 9, 28, 17, 5),
      scope: 'Asked by an Admin. Visible: all inventory.',
      sections: const [
        LocalAiContextSection(
          title: 'Inventory totals',
          data: {'headOfficeAvailable': 22},
        ),
      ],
      directAnswer: answer,
    );
  }

  @override
  void reset() {}
}

const _ndjsonHeaders = {'content-type': 'application/x-ndjson; charset=utf-8'};

String _ndjson(List<Map<String, Object?>> lines) =>
    lines.map((l) => '${jsonEncode(l)}\n').join();

/// A server that answers every chat with [lines] (NDJSON events), and
/// records the bodies it was sent.
MockClient _server(List<Map<String, Object?>> lines, List<String> bodies) {
  return MockClient.streaming((request, body) async {
    bodies.add(await body.bytesToString());
    return http.StreamedResponse(
      Stream.value(utf8.encode(_ndjson(lines))),
      200,
      headers: _ndjsonHeaders,
    );
  });
}

/// A server that answers each question with its own [answers], so a test can
/// tell whose words ended up where. A question in [live] is answered down
/// that stream instead, a line at a time, for as long as the test keeps it
/// open.
MockClient _serverByQuestion(
  Map<String, List<Map<String, Object?>>> answers, {
  Map<String, StreamController<List<int>>> live = const {},
}) {
  return MockClient.streaming((request, body) async {
    final sent = jsonDecode(await body.bytesToString()) as Map<String, dynamic>;
    final question = sent['message'] as String;
    return http.StreamedResponse(
      live[question]?.stream ??
          Stream.value(utf8.encode(_ndjson(answers[question]!))),
      200,
      headers: _ndjsonHeaders,
    );
  });
}

_TrackedProvider _provider(
  LocalAiConfig config,
  List<Map<String, Object?>> lines,
  List<String> bodies,
) {
  return _providerFor(config, () => _server(lines, bodies));
}

_TrackedProvider _providerFor(
  LocalAiConfig config,
  http.Client Function() server,
) {
  return _TrackedProvider(
    client: LocalAiClient(clientFactory: (_) => server()),
    settings: _Settings(config),
    discovery: _NoDiscovery(),
  );
}

const _conversation = '3f0c2a64-9b7e-4c55-8a3c-0d5f2b8e1a90';

/// A whole answer as the server streams it: start, one delta per piece, and
/// done with the pieces joined, as the server saves them.
List<Map<String, Object?>> _written(List<String> pieces) => [
  {
    'type': 'start',
    'conversationId': _conversation,
    'messageId': 'm1',
    'title': 'Inventory',
    'model': 'qwen3:4b-instruct-2507-q4_K_M',
  },
  for (final piece in pieces) {'type': 'delta', 'text': piece},
  {
    'type': 'done',
    'conversationId': _conversation,
    'title': 'Inventory',
    'message': {
      'id': 'm1',
      'role': 'assistant',
      'content': pieces.join(),
      'status': 'done',
      'createdAt': 1790000000000,
    },
    'model': 'qwen3:4b-instruct-2507-q4_K_M',
    'usage': {
      'promptTokens': 645,
      'outputTokens': 12,
      'durationMs': 14000,
      'tokensPerSecond': 9,
    },
    'context': {'includedMessages': 1, 'omittedMessages': 0},
    'documents': null,
    'appContext': null,
  },
];

const _answer = [
  {
    'type': 'start',
    'conversationId': '3f0c2a64-9b7e-4c55-8a3c-0d5f2b8e1a90',
    'messageId': 'm1',
    'title': 'Hello',
    'model': 'qwen3:8b',
  },
  {'type': 'delta', 'text': 'Hello! How can I '},
  {'type': 'delta', 'text': 'help you today?'},
  {
    'type': 'done',
    'conversationId': '3f0c2a64-9b7e-4c55-8a3c-0d5f2b8e1a90',
    'title': 'Hello',
    'message': {
      'id': 'm1',
      'role': 'assistant',
      'content': 'Hello! How can I help you today?',
      'status': 'done',
      'createdAt': 1790000000000,
    },
    'model': 'qwen3:8b',
    'usage': {
      'promptTokens': 120,
      'outputTokens': 9,
      'durationMs': 9000,
      'tokensPerSecond': 4.1,
    },
    'context': {'includedMessages': 1, 'omittedMessages': 0},
    'documents': null,
    'appContext': null,
  },
];

Future<BackendReply?> _ask(
  LocalAiAssistantBackend backend,
  String question, {
  List<String>? failures,
}) {
  return backend.ask(
    question: question,
    facts: const {'totals': 'never sent'},
    groundedAnswer: 'Hello! How can I help you with the inventory today?',
    onFailed: failures?.add,
  );
}

void main() {
  group('which backend plans actions', () {
    test('a words-only model (Qwen3) leaves commands to the app', () {
      expect(modelPlansActions(_WordsOnly()), isFalse);
    });

    test('a model that returns intents takes part, when switched on', () {
      expect(modelPlansActions(_Backend(enabled: true)), isTrue);
      expect(modelPlansActions(_Backend(enabled: false)), isFalse);
      expect(modelPlansActions(const AiBackend()), isFalse);
    });

    test('the Local AI backend is words-only', () {
      final provider = _provider(_configured, _answer, []);
      addTearDown(provider.dispose);
      expect(LocalAiAssistantBackend(provider), isA<WordsOnlyBackend>());
    });

    test('only the Local AI backend streams; the Gemini path does not', () {
      final provider = _provider(_configured, _answer, []);
      addTearDown(provider.dispose);
      expect(LocalAiAssistantBackend(provider), isA<StreamingBackend>());
      expect(const AiBackend(), isNot(isA<StreamingBackend>()));
    });
  });

  group('LocalAiAssistantBackend', () {
    test("returns Qwen3's own answer, not the app's fixed reply", () async {
      final bodies = <String>[];
      final provider = _provider(_configured, _answer, bodies);
      addTearDown(provider.dispose);
      provider.bindUser('UserUsman0000000000000000003');

      final reply = await _ask(LocalAiAssistantBackend(provider), 'Hello');

      expect(reply, isNotNull);
      expect(reply!.text, 'Hello! How can I help you today?');
      expect(reply.provider, 'local-ai');
      expect(reply.intent, isNull);

      final sent = jsonDecode(bodies.single) as Map<String, dynamic>;
      expect(sent['message'], 'Hello');
      // Neither the app's facts nor its computed reply go to the server, and
      // nothing identifies the account.
      expect(bodies.single, isNot(contains('never sent')));
      expect(
        bodies.single,
        isNot(contains('How can I help you with the inventory')),
      );
      expect(bodies.single, isNot(contains('UserUsman')));
    });

    test('shares one conversation with the AI Assistant screen', () async {
      final provider = _provider(_configured, _answer, []);
      addTearDown(provider.dispose);
      provider.bindUser('UserUsman0000000000000000003');

      await _ask(LocalAiAssistantBackend(provider), 'Hello');

      expect(provider.messages.map((m) => m.content), [
        'Hello',
        'Hello! How can I help you today?',
      ]);
    });

    test(
      'with no server set up it stays quiet, like a build with no model',
      () async {
        final provider = _provider(LocalAiConfig.empty, _answer, []);
        addTearDown(provider.dispose);
        provider.bindUser('UserUsman0000000000000000003');
        final failures = <String>[];

        final reply = await _ask(
          LocalAiAssistantBackend(provider),
          'Hello',
          failures: failures,
        );

        expect(reply, isNull);
        expect(failures, isEmpty);
      },
    );

    test(
      'a failed answer falls back, and says the reply is the app\'s own',
      () async {
        final provider = _provider(_configured, const [
          {
            'type': 'start',
            'conversationId': '3f0c2a64-9b7e-4c55-8a3c-0d5f2b8e1a90',
            'messageId': 'm1',
            'title': 'Hello',
            'model': 'qwen3:8b',
          },
          {
            'type': 'error',
            'error': {
              'code': 'OLLAMA_UNREACHABLE',
              'message': 'Ollama is not running.',
            },
          },
        ], []);
        addTearDown(provider.dispose);
        provider.bindUser('UserUsman0000000000000000003');
        final failures = <String>[];

        final reply = await _ask(
          LocalAiAssistantBackend(provider),
          'Hello',
          failures: failures,
        );

        expect(reply, isNull);
        expect(failures.single, contains('did not answer'));
        expect(failures.single, contains('worked out by the app itself'));
      },
    );

    test(
      'nobody signed in: nothing is sent, and the fallback is labelled',
      () async {
        final bodies = <String>[];
        final provider = _provider(_configured, _answer, bodies);
        addTearDown(provider.dispose);
        final failures = <String>[];

        final reply = await _ask(
          LocalAiAssistantBackend(provider),
          'Hello',
          failures: failures,
        );

        expect(reply, isNull);
        expect(bodies, isEmpty);
        expect(failures.single, contains('worked out by the app itself'));
      },
    );
  });

  // ===========================================================================
  // STREAMING INTO THE FLOATING PANEL
  //
  // The panel shows what onPartial is given in its thinking bubble, and then
  // swaps in the returned reply. So onPartial must only ever carry this
  // question's own answer, growing, and must stop the moment the ask is over.
  // ===========================================================================

  group('LocalAiAssistantBackend and the app\'s own answers', () {
    test(
      'a plain lookup the app answered itself comes back labelled as such, '
      'with nothing sent to the laptop',
      () async {
        final bodies = <String>[];
        final provider = _TrackedProvider(
          client: LocalAiClient(clientFactory: (_) => _server(_answer, bodies)),
          settings: _Settings(_configured),
          discovery: _NoDiscovery(),
          contextService: _AnsweredByApp(
            'Head Office has 22 units available for use.',
          ),
        );
        addTearDown(provider.dispose);
        provider.bindUser('UserUsman0000000000000000003');

        final partials = <String>[];
        final failures = <String>[];
        final reply = await LocalAiAssistantBackend(provider).askStreaming(
          question: 'head office mein kitne hain',
          facts: const {},
          onFailed: failures.add,
          onPartial: partials.add,
        );

        expect(reply, isNotNull);
        expect(reply!.text, 'Head Office has 22 units available for use.');
        expect(reply.provider, LocalAiAssistantBackend.answeredByApp);
        expect(reply.model, isEmpty);
        expect(bodies, isEmpty);
        expect(partials, isEmpty);
        expect(failures, isEmpty);
        expect(provider.listeners, isEmpty);
      },
    );
  });

  group('LocalAiAssistantBackend streaming', () {
    test('shows the answer as it is written, then returns it whole', () async {
      final provider = _provider(
        _configured,
        // Qwen3 often opens with a blank line; the panel must not show an
        // empty bubble for it, or a bubble whose text then shifts up a line.
        _written(['\n\n', 'There are ', '55 laptops', ' in total.']),
        [],
      );
      addTearDown(provider.dispose);
      provider.bindUser('UserUsman0000000000000000003');
      final partials = <String>[];

      final reply = await LocalAiAssistantBackend(provider).askStreaming(
        question: 'How many laptops?',
        facts: const {},
        onPartial: partials.add,
      );

      expect(partials, [
        'There are',
        'There are 55 laptops',
        'There are 55 laptops in total.',
      ]);
      // The finished answer reads exactly as the last preview did, so the
      // panel swaps one for the other without anything moving.
      expect(reply!.text, partials.last);
      expect(reply.provider, 'local-ai');
      expect(provider.listeners, isEmpty);
    });

    test('ask() is the same question with nobody watching', () async {
      final provider = _provider(
        _configured,
        _written(['There are ', '55 laptops', ' in total.']),
        [],
      );
      addTearDown(provider.dispose);
      provider.bindUser('UserUsman0000000000000000003');

      final reply = await _ask(LocalAiAssistantBackend(provider), 'Laptops?');

      expect(reply!.text, 'There are 55 laptops in total.');
      expect(provider.listeners, isEmpty);
    });

    test(
      'never shows an earlier answer from the shared conversation',
      () async {
        final provider = _providerFor(
          _configured,
          () => _serverByQuestion({
            'Hello': _written(['Hello! How can I ', 'help you today?']),
            'How many laptops?': _written(['There are ', '55 laptops.']),
          }),
        );
        addTearDown(provider.dispose);
        provider.bindUser('UserUsman0000000000000000003');
        // As the AI Assistant screen does when it opens. Without it the
        // provider refuses the earlier question as not configured, and there
        // would be no earlier answer for this test to keep out.
        await provider.loadConfig();

        // Asked earlier on the AI Assistant screen: the same conversation,
        // and the same provider, that the panel's question joins.
        await provider.send('Hello');
        expect(provider.messages.map((m) => m.content), [
          'Hello',
          'Hello! How can I help you today?',
        ]);
        final partials = <String>[];

        await LocalAiAssistantBackend(provider).askStreaming(
          question: 'How many laptops?',
          facts: const {},
          onPartial: partials.add,
        );

        expect(partials, ['There are', 'There are 55 laptops.']);
      },
    );

    test(
      'a conversation thrown away mid-answer: the next question\'s words '
      'never reach the preview, though they land in the same place',
      () async {
        final panelAnswer = StreamController<List<int>>();
        addTearDown(panelAnswer.close);
        void line(Map<String, Object?> event) =>
            panelAnswer.add(utf8.encode('${jsonEncode(event)}\n'));

        final provider = _providerFor(
          _configured,
          () => _serverByQuestion(
            {
              'Is the printer working?': _written([
                'Yes, the printer ',
                'is working.',
              ]),
            },
            live: {'How many laptops?': panelAnswer},
          ),
        );
        addTearDown(provider.dispose);
        provider.bindUser('UserUsman0000000000000000003');

        final partials = <String>[];
        final failures = <String>[];
        final firstWords = Completer<void>();
        final asking = LocalAiAssistantBackend(provider).askStreaming(
          question: 'How many laptops?',
          facts: const {},
          onFailed: failures.add,
          onPartial: (text) {
            partials.add(text);
            if (!firstWords.isCompleted) firstWords.complete();
          },
        );

        line({'type': 'delta', 'text': 'There are '});
        await firstWords.future;

        // Clear on the screen, then a new question there. Its question and
        // answer take the very indexes the panel's did, and stream while the
        // panel's ask is still waiting.
        await provider.clearConversation();
        await provider.send('Is the printer working?');
        expect(provider.messages.last.content, 'Yes, the printer is working.');

        line({'type': 'delta', 'text': '55 laptops.'});
        await panelAnswer.close();

        // Not the printer answer that now ends the conversation: the panel
        // would swap it in for this question's preview. This question was
        // never answered, so the app answers it, and says so.
        expect(await asking, isNull);
        expect(failures.single, contains('did not answer'));
        expect(failures.single, contains('worked out by the app itself'));
        expect(partials, ['There are']);
        expect(provider.listeners, isEmpty);
      },
    );

    test(
      'a conversation emptied mid-answer: the fallback is labelled, and '
      'nothing throws',
      () async {
        final panelAnswer = StreamController<List<int>>();
        addTearDown(panelAnswer.close);

        final provider = _providerFor(
          _configured,
          () => _serverByQuestion(
            {'Hello': _written(['Hello! How can I ', 'help you today?'])},
            live: {'How many laptops?': panelAnswer},
          ),
        );
        addTearDown(provider.dispose);
        provider.bindUser('UserUsman0000000000000000003');
        await provider.loadConfig();

        // An earlier exchange, so the panel's question does not start at the
        // top of the conversation, and "empty" is shorter than where it was
        // asked.
        await provider.send('Hello');
        expect(provider.messages, hasLength(2));

        final partials = <String>[];
        final failures = <String>[];
        final firstWords = Completer<void>();
        final asking = LocalAiAssistantBackend(provider).askStreaming(
          question: 'How many laptops?',
          facts: const {},
          onFailed: failures.add,
          onPartial: (text) {
            partials.add(text);
            if (!firstWords.isCompleted) firstWords.complete();
          },
        );

        panelAnswer.add(
          utf8.encode('${jsonEncode({'type': 'delta', 'text': 'There are '})}\n'),
        );
        await firstWords.future;

        // Clear on the screen, and nothing asked after it.
        await provider.clearConversation();
        expect(provider.messages, isEmpty);
        await panelAnswer.close();

        expect(await asking, isNull);
        expect(failures.single, contains('did not answer'));
        expect(failures.single, contains('worked out by the app itself'));
        expect(partials, ['There are']);
        expect(provider.listeners, isEmpty);
      },
    );

    test(
      'leaves no listener behind, so a later answer never reaches it',
      () async {
        final provider = _providerFor(
          _configured,
          () => _serverByQuestion({
            'How many laptops?': _written(['There are ', '55 laptops.']),
            'And printers?': _written(['There are ', '12 printers.']),
          }),
        );
        addTearDown(provider.dispose);
        provider.bindUser('UserUsman0000000000000000003');
        final partials = <String>[];

        await LocalAiAssistantBackend(provider).askStreaming(
          question: 'How many laptops?',
          facts: const {},
          onPartial: partials.add,
        );
        final shown = List.of(partials);

        // The count is the real evidence: a listener left behind would also
        // be kept quiet by its own check, but it would keep the closed panel
        // alive for the life of the app.
        expect(provider.listeners, isEmpty);

        await provider.send('And printers?');
        expect(partials, shown);
      },
    );

    test(
      'a failure part-way: the preview was only a preview, and the fallback '
      'is labelled as before',
      () async {
        final provider = _provider(_configured, const [
          {
            'type': 'start',
            'conversationId': _conversation,
            'messageId': 'm1',
            'title': 'Inventory',
            'model': 'qwen3:4b-instruct-2507-q4_K_M',
          },
          {'type': 'delta', 'text': 'There are '},
          {'type': 'delta', 'text': '55'},
          {
            'type': 'error',
            'error': {
              'code': 'OLLAMA_UNREACHABLE',
              'message': 'Ollama is not running.',
            },
          },
        ], []);
        addTearDown(provider.dispose);
        provider.bindUser('UserUsman0000000000000000003');
        final partials = <String>[];
        final failures = <String>[];

        final reply = await LocalAiAssistantBackend(provider).askStreaming(
          question: 'How many laptops?',
          facts: const {},
          onFailed: failures.add,
          onPartial: partials.add,
        );

        expect(partials, ['There are', 'There are 55']);
        expect(reply, isNull);
        expect(failures.single, contains('did not answer'));
        expect(failures.single, contains('worked out by the app itself'));
        expect(provider.listeners, isEmpty);
      },
    );

    test('with no server set up it stays quiet and shows nothing', () async {
      final provider = _provider(LocalAiConfig.empty, _answer, []);
      addTearDown(provider.dispose);
      provider.bindUser('UserUsman0000000000000000003');
      final partials = <String>[];
      final failures = <String>[];

      final reply = await LocalAiAssistantBackend(provider).askStreaming(
        question: 'Hello',
        facts: const {},
        onFailed: failures.add,
        onPartial: partials.add,
      );

      expect(reply, isNull);
      expect(partials, isEmpty);
      expect(failures, isEmpty);
      expect(provider.listeners, isEmpty);
    });

    test('nobody signed in: nothing is sent and nothing is shown', () async {
      final bodies = <String>[];
      final provider = _provider(_configured, _answer, bodies);
      addTearDown(provider.dispose);
      final partials = <String>[];
      final failures = <String>[];

      final reply = await LocalAiAssistantBackend(provider).askStreaming(
        question: 'Hello',
        facts: const {},
        onFailed: failures.add,
        onPartial: partials.add,
      );

      expect(reply, isNull);
      expect(bodies, isEmpty);
      expect(partials, isEmpty);
      expect(failures.single, contains('worked out by the app itself'));
      expect(provider.listeners, isEmpty);
    });
  });
}
