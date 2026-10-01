/// End-to-end check against the REAL Local AI server and the REAL model.
///
/// Skipped unless asked for, because it needs the laptop's server running
/// with Ollama and qwen3:8b, and the API key file:
///
///   flutter test test/live/local_ai_live_test.dart \
///     --dart-define=LOCAL_AI_LIVE=true \
///     --dart-define=LOCAL_AI_KEY_FILE=(path of the key file) \
///     --dart-define=LOCAL_AI_EXPECT_PIN=(certificate SHA-256, hex)
///
/// What runs for real: UDP discovery on the local network (proofs both
/// ways), certificate pinning, the app's LocalAiProvider and LocalAiClient,
/// its automatic re-discovery after a stale address, the permission-scoped
/// context service over the app's own providers and services, NDJSON
/// streaming, and Qwen3's answer. What does not: Firestore itself - the
/// providers read an in-memory Firestore seeded by the context tests'
/// fixtures (Security Rules are not enforced there; the providers' own role
/// scoping is).
///
/// The API key is read from its file into memory only. It is never printed,
/// and the checks below never put it into a failure message.
@TestOn('vm')
library;

import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;

import 'package:it_management_system/core/ai/local/local_ai_config.dart';
import 'package:it_management_system/core/ai/local/local_ai_discovery.dart';
import 'package:it_management_system/core/ai/local/local_ai_http.dart';
import 'package:it_management_system/core/ai/local/local_ai_client.dart';
import 'package:it_management_system/core/ai/local/local_ai_provider.dart';

import '../local_ai_context_test.dart' as fx;

const bool _enabled = bool.fromEnvironment('LOCAL_AI_LIVE');
const String _keyFile = String.fromEnvironment('LOCAL_AI_KEY_FILE');
const String _expectedPin = String.fromEnvironment('LOCAL_AI_EXPECT_PIN');

/// Keeps a copy of every request body, to prove what did (and did not)
/// leave the app.
class _Recording extends http.BaseClient {
  _Recording(this._inner, this.bodies);

  final http.Client _inner;
  final List<String> bodies;

  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) {
    if (request is http.Request) bodies.add(request.body);
    return _inner.send(request);
  }

  @override
  void close() => _inner.close();
}

class _MemorySettings implements LocalAiSettingsStore {
  _MemorySettings(this.current);

  LocalAiConfig current;

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
    current = current.copyWith(
      baseUrl: baseUrl,
      certificateFingerprint: certificateFingerprint,
    );
  }

  @override
  Future<void> clearDeviceConfig() async {
    current = LocalAiConfig.empty;
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

/// Every number in [text], as written.
Set<String> _numbers(String text) => RegExp(
  r'\d[\d,]*',
).allMatches(text).map((m) => m.group(0)!.replaceAll(',', '')).toSet();

void main() {
  final skip = _enabled ? false : 'set --dart-define=LOCAL_AI_LIVE=true to run';

  late String apiKey;

  setUpAll(() {
    if (!_enabled) return;
    apiKey = File(_keyFile).readAsStringSync().trim();
    // Only the key's shape is checked, so a failure never shows the key.
    expect(
      LocalAiConfig.keyIdOf(apiKey),
      isNotNull,
      reason: 'the key file does not hold an API key',
    );
  });

  test(
    'discovery finds the laptop, proves it, and delivers the pinned certificate',
    () async {
      final found = await const LocalAiDiscovery().find(apiKey: apiKey);

      expect(found, isNotEmpty, reason: 'no verified announce came back');
      final server = found.first;
      expect(server.scheme, 'https');
      expect(server.port, 3001);
      expect(server.certSha256, _expectedPin);
      expect(server.addresses, isNotEmpty);
      // ignore: avoid_print
      print(
        'Discovered ${server.name} at ${server.addresses.join(', ')} (secure: ${server.isSecure})',
      );

      // The discovered address answers /health through the pinned certificate.
      final client = LocalAiClient();
      final health = await client.health(
        LocalAiConfig(
          baseUrl: server.baseUrlFor(server.addresses.first),
          apiKey: apiKey,
          certificateFingerprint: server.certSha256!,
          source: LocalAiConfigSource.device,
        ),
      );
      expect(health.isHealthy, isTrue);
      expect(health.modelName, 'qwen3:8b');
    },
    skip: skip,
    timeout: const Timeout(Duration(seconds: 60)),
  );

  test(
    'a wrong certificate pin is refused before the key is sent',
    () async {
      final found = await const LocalAiDiscovery().find(apiKey: apiKey);
      final server = found.first;
      final wrongPin = 'ab' * 32;

      final error = await LocalAiClient()
          .health(
            LocalAiConfig(
              baseUrl: server.baseUrlFor(server.addresses.first),
              apiKey: apiKey,
              certificateFingerprint: wrongPin,
              source: LocalAiConfigSource.device,
            ),
          )
          .then<Object?>((_) => null, onError: (Object e) => e);

      expect(
        error,
        isNotNull,
        reason: 'a server with another certificate was accepted',
      );
      expect(error.toString().contains(apiKey), isFalse);
    },
    skip: skip,
    timeout: const Timeout(Duration(seconds: 60)),
  );

  test(
    'a greeting gets a short natural reply, and no inventory data is sent',
    () async {
      final server = (await const LocalAiDiscovery().find(
        apiKey: apiKey,
      )).first;
      final world = await fx.World.signedInAs(fx.adminAUid);
      addTearDown(world.dispose);

      final bodies = <String>[];
      final provider = LocalAiProvider(
        client: LocalAiClient(
          clientFactory: (config) => _Recording(
            createLocalAiHttpClient(
              pinnedSha256: config.certificateFingerprint,
            ),
            bodies,
          ),
        ),
        settings: _MemorySettings(
          LocalAiConfig(
            baseUrl: server.baseUrlFor(server.addresses.first),
            apiKey: apiKey,
            certificateFingerprint: server.certSha256!,
            source: LocalAiConfigSource.device,
          ),
        ),
        contextService: world.service,
      );
      addTearDown(provider.dispose);

      provider.bindUser(fx.adminAUid);
      await provider.loadConfig();

      for (final greeting in ['Hello', 'Assalam o Alaikum']) {
        await provider.send(greeting);
        final answer = provider.messages.last;

        expect(answer.status, 'done', reason: 'error: ${answer.error}');
        expect(answer.usedAppData, isFalse);
        expect(answer.content.length, lessThan(400), reason: answer.content);
        expect(
          RegExp(r'\d').hasMatch(answer.content),
          isFalse,
          reason: answer.content,
        );
        // ignore: avoid_print
        print('$greeting -> ${answer.content}');
      }

      final sent = bodies
          .map(jsonDecode)
          .whereType<Map>()
          .where((b) => b.containsKey('appContext'));
      expect(sent, hasLength(2));
      for (final body in sent) {
        expect(body['appContext']['sections'], isEmpty);
      }
    },
    skip: skip,
    timeout: const Timeout(Duration(minutes: 4)),
  );

  test(
    'app -> LAN API -> Qwen3 with Firebase-derived context, streamed back, '
    'after re-discovering a stale address',
    () async {
      final world = await fx.World.signedInAs(fx.adminAUid);
      addTearDown(world.dispose);

      final bodies = <String>[];
      final settings = _MemorySettings(
        LocalAiConfig(
          // A stale address, as after a DHCP change: the app must find the
          // laptop again by itself.
          baseUrl: 'https://192.0.2.1:3001',
          apiKey: apiKey,
          certificateFingerprint: _expectedPin,
          source: LocalAiConfigSource.device,
        ),
      );
      final provider = LocalAiProvider(
        client: LocalAiClient(
          clientFactory: (config) => _Recording(
            createLocalAiHttpClient(
              pinnedSha256: config.certificateFingerprint,
            ),
            bodies,
          ),
        ),
        settings: settings,
        contextService: world.service,
      );
      addTearDown(provider.dispose);

      provider.bindUser(fx.adminAUid);
      await provider.loadConfig();

      // "Explain" keeps this one with the model: the plain lookup is answered
      // by the app itself (checked at the end of this test).
      final watch = Stopwatch()..start();
      await provider.send(
        'Explain in one line how many units are available at Head Office '
        'right now.',
      );
      watch.stop();

      final answer = provider.messages.last;
      expect(answer.status, 'done', reason: 'error: ${answer.error}');
      expect(
        settings.current.baseUrl,
        isNot('https://192.0.2.1:3001'),
        reason: 'the moved server was not re-discovered',
      );
      expect(answer.usedAppData, isTrue);

      // The number the model gave is the one the app read from its data.
      final sent = bodies
          .map(jsonDecode)
          .whereType<Map>()
          .firstWhere((b) => b.containsKey('appContext'));
      final totals = (sent['appContext']['sections'] as List).firstWhere(
        (s) => (s['title'] as String).startsWith('Inventory totals'),
      );
      final headOffice =
          '${(totals['data'] as Map)['atHeadOffice'] ?? (totals['data'] as Map)['headOfficeAvailable']}';
      expect(
        _numbers(answer.content),
        contains(headOffice),
        reason: 'answer: ${answer.content}',
      );

      // Nothing identifying left the app: no uid, e-mail, token or key.
      for (final body in bodies) {
        for (final uid in fx.allUids) {
          expect(body.contains(uid), isFalse, reason: 'a uid was sent');
        }
        expect(
          body.contains('@psba.gov.pk'),
          isFalse,
          reason: 'an e-mail address was sent',
        );
        expect(
          body.contains(apiKey),
          isFalse,
          reason: 'the API key was sent in a body',
        );
        expect(
          RegExp(r'eyJ[A-Za-z0-9_-]{10,}\.').hasMatch(body),
          isFalse,
          reason: 'a token was sent',
        );
      }

      // A follow-up in the same conversation, about another kind of data.
      await provider.send('Explain which requests are pending.');
      final second = provider.messages.last;
      expect(second.status, 'done', reason: 'error: ${second.error}');
      expect(second.usedAppData, isTrue);
      expect(second.answeredByApp, isFalse);

      // The plain lookup is answered by the app itself, from the same data,
      // with nothing sent to the laptop.
      final sentBefore = bodies.length;
      final instant = Stopwatch()..start();
      await provider.send(
        'How many units are available at Head Office right now?',
      );
      instant.stop();
      final direct = provider.messages.last;
      expect(direct.answeredByApp, isTrue);
      expect(_numbers(direct.content), contains(headOffice));
      expect(bodies, hasLength(sentBefore));

      // ignore: avoid_print
      print(
        'Now at ${settings.current.baseUrl}. First answer in ${watch.elapsed.inSeconds}s:\n'
        '${answer.content}\n---\n${second.content}\n---\n'
        'Answered by the app in ${instant.elapsedMilliseconds} ms:\n'
        '${direct.content}',
      );
    },
    skip: skip,
    timeout: const Timeout(Duration(minutes: 8)),
  );
}
