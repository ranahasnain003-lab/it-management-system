/// Tests for finding the Local AI laptop on the local network.
///
/// The proofs are checked against vectors computed by the server's own code
/// (shared/discovery.ts, run with node's crypto), so a difference in how the
/// app and the server build a proof text - one missing "\n", "3001" written
/// as "3001.0" - fails here rather than as "no server found" on site.
///
/// The last group runs a real UDP responder on 127.0.0.1 and lets find() talk
/// to it, so the socket, the probe and the parsing are exercised together.
library;

import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import 'package:it_management_system/core/ai/local/local_ai_discovery.dart';
import 'package:it_management_system/core/ai/local/local_ai_models.dart';

// =============================================================================
// VECTORS (computed with node from shared/discovery.ts)
// =============================================================================
//
//   const key = 'lai_ab12cd34_' + 'A'.repeat(43);
//   const hkey = createHash('sha256').update(key).digest();
//   createHmac('sha256', hkey).update(probeProofText(...)).digest('hex');

final String _key = 'lai_ab12cd34_${'A' * 43}';
const String _keyId = 'ab12cd34';
const String _nonce = 'bm9uY2Utbm9uY2Utbm9uY2Utbm9uY2U';
const String _cert =
    '0123456789abcdef0123456789abcdef0123456789abcdef0123456789abcdef';

const String _keyHash =
    '694685c89d7fe910e0e5f94e809f101d501ca367462c467ded0156469fdeca9f';
const String _probeProof =
    '6950794ee53be21f4bbff7b2c503b70a3de67ade884e025ed1825e948a5f0535';
const String _announceProof =
    '7f891f632e39a32fab831823e22149f21015eabf793241d40bb25ae168e80205';

/// An HTTP announce with two addresses and no certificate (certSha256 null,
/// which the proof text writes as an empty last line).
const String _httpAnnounceProof =
    'de63250d70fcd03e9faa770014ad36a90f6dc26d9c1d08b6f5b91e9a88916b09';

/// A correctly signed HTTP announce that nonetheless carries a certificate
/// fingerprint (_cert, one address). The server never sends this; it is what
/// someone holding only SHA-256 of the key would send to look like the
/// pinned HTTPS server.
const String _httpWithCertProof =
    'c3346abde2714ecdf12dd6d47feb5865066b9928aab72e3375c2adad9351bab1';

Map<String, dynamic> _announce({
  String keyId = _keyId,
  String nonce = _nonce,
  String name = 'DESKTOP-TEST',
  String scheme = 'https',
  Object port = 3001,
  String path = '/api/v1',
  List<Object> addresses = const ['172.16.20.125'],
  Object? cert = _cert,
  String proof = _announceProof,
  Object service = 'local-ai',
  Object v = 1,
  Object type = 'announce',
}) => {
  'service': service,
  'v': v,
  'type': type,
  'keyId': keyId,
  'nonce': nonce,
  'name': name,
  'scheme': scheme,
  'port': port,
  'path': path,
  'addresses': addresses,
  'certSha256': cert,
  'proof': proof,
};

LocalAiDiscoveredServer? _parse(Object json, {String? apiKey, String? nonce}) =>
    LocalAiDiscoveryProtocol.parseAnnounce(
      utf8.encode(json is String ? json : jsonEncode(json)),
      apiKey: apiKey ?? _key,
      keyId: _keyId,
      nonce: nonce ?? _nonce,
    );

void main() {
  // ===========================================================================
  // THE PROTOCOL, AGAINST THE SERVER'S OWN VECTORS
  // ===========================================================================

  group('proofs match the server', () {
    test('the HMAC key is SHA-256 of the API key', () {
      final hex = LocalAiDiscoveryProtocol.proofKey(_key)
          .map((b) => b.toRadixString(16).padLeft(2, '0'))
          .join();

      expect(hex, _keyHash);
    });

    test('probe proof', () {
      expect(
        LocalAiDiscoveryProtocol.probeProofText(_keyId, _nonce),
        'local-ai/discover/v1\n$_keyId\n$_nonce',
      );
      expect(
        LocalAiDiscoveryProtocol.proof(
          _key,
          LocalAiDiscoveryProtocol.probeProofText(_keyId, _nonce),
        ),
        _probeProof,
      );
    });

    test('announce proof (https, with a certificate)', () {
      final text = LocalAiDiscoveryProtocol.announceProofText(
        keyId: _keyId,
        nonce: _nonce,
        name: 'DESKTOP-TEST',
        scheme: 'https',
        port: 3001,
        path: '/api/v1',
        addresses: const ['172.16.20.125'],
        certSha256: _cert,
      );

      expect(
        text,
        'local-ai/announce/v1\n$_keyId\n$_nonce\nDESKTOP-TEST\nhttps\n3001\n'
        '/api/v1\n172.16.20.125\n$_cert',
      );
      expect(LocalAiDiscoveryProtocol.proof(_key, text), _announceProof);
    });

    test('announce proof (http, two addresses, no certificate)', () {
      final text = LocalAiDiscoveryProtocol.announceProofText(
        keyId: _keyId,
        nonce: _nonce,
        name: 'DESKTOP-TEST',
        scheme: 'http',
        port: 3001,
        path: '/api/v1',
        addresses: const ['192.168.1.20', '10.0.0.5'],
        certSha256: null,
      );

      expect(text.endsWith('\n192.168.1.20,10.0.0.5\n'), isTrue);
      expect(LocalAiDiscoveryProtocol.proof(_key, text), _httpAnnounceProof);
    });

    test('the probe datagram is exactly the contract\'s shape', () {
      final probe = jsonDecode(
        utf8.decode(
          LocalAiDiscoveryProtocol.encodeProbe(apiKey: _key, keyId: _keyId, nonce: _nonce),
        ),
      ) as Map<String, dynamic>;

      expect(probe, {
        'service': 'local-ai',
        'v': 1,
        'type': 'discover',
        'keyId': _keyId,
        'nonce': _nonce,
        'proof': _probeProof,
      });
      // The key itself never crosses the network.
      expect(jsonEncode(probe), isNot(contains(_key)));
      expect(jsonEncode(probe), isNot(contains('A' * 43)));
    });

    test('a fresh nonce is 24 random bytes of unpadded base64url', () {
      final a = LocalAiDiscoveryProtocol.newNonce();
      final b = LocalAiDiscoveryProtocol.newNonce();

      expect(a, matches(RegExp(r'^[A-Za-z0-9_-]{32}$')));
      expect(a, isNot(b));
    });
  });

  // ===========================================================================
  // READING AN ANNOUNCE
  // ===========================================================================

  group('an announce is believed only with a valid proof', () {
    test('a genuine announce is accepted', () {
      final server = _parse(_announce());

      expect(server, isNotNull);
      expect(server!.name, 'DESKTOP-TEST');
      expect(server.scheme, 'https');
      expect(server.port, 3001);
      expect(server.addresses, ['172.16.20.125']);
      expect(server.certSha256, _cert);
      expect(server.isSecure, isTrue);
      expect(server.baseUrlFor('172.16.20.125'), 'https://172.16.20.125:3001');
      expect(server.baseUrls, ['https://172.16.20.125:3001']);
    });

    test('an http announce with a null certificate is accepted', () {
      final server = _parse(
        _announce(
          scheme: 'http',
          addresses: const ['192.168.1.20', '10.0.0.5'],
          cert: null,
          proof: _httpAnnounceProof,
        ),
      );

      expect(server, isNotNull);
      expect(server!.certSha256, isNull);
      expect(server.isSecure, isFalse);
      expect(server.baseUrls, ['http://192.168.1.20:3001', 'http://10.0.0.5:3001']);
    });

    test('anything changed after signing is rejected', () {
      // Each of these is what an impostor, or a replay, would try.
      expect(_parse(_announce(name: 'DESKTOP-EVIL')), isNull);
      expect(_parse(_announce(addresses: const ['172.16.20.126'])), isNull);
      expect(_parse(_announce(cert: 'f' * 64)), isNull);
      expect(_parse(_announce(port: 3002)), isNull);
      expect(_parse(_announce(scheme: 'http')), isNull);
      expect(_parse(_announce(cert: null)), isNull);
    });

    test('a proof made with another key is rejected', () {
      expect(_parse(_announce(), apiKey: 'lai_ab12cd34_${'B' * 43}'), isNull);
    });

    test('an answer to another search (old nonce) is rejected', () {
      expect(_parse(_announce(), nonce: 'b3RoZXItbm9uY2Utb3RoZXItbm9uY2U'), isNull);
    });

    test('another key id, service, version or type is rejected', () {
      expect(_parse(_announce(keyId: 'zz99yy88')), isNull);
      expect(_parse(_announce(service: 'other')), isNull);
      expect(_parse(_announce(v: 2)), isNull);
      expect(_parse(_announce(type: 'discover')), isNull);
    });

    test('malformed fields are rejected before the proof is even checked', () {
      expect(_parse(_announce(path: '/api/v2')), isNull);
      expect(_parse(_announce(port: '3001')), isNull);
      expect(_parse(_announce(addresses: const [])), isNull);
      expect(_parse(_announce(addresses: const ['not-an-ip'])), isNull);
      expect(_parse(_announce(addresses: const ['300.1.1.1'])), isNull);
      expect(_parse(_announce(cert: 'ABC')), isNull);
      expect(_parse(_announce(proof: 'nothex')), isNull);
      expect(_parse('not json at all'), isNull);
      expect(_parse('[1,2,3]'), isNull);
    });

    test('an HTTP announce carrying a fingerprint is rejected, even correctly signed', () {
      expect(
        _parse(_announce(scheme: 'http', cert: _cert, proof: _httpWithCertProof)),
        isNull,
      );
    });

    test('the same server heard with its addresses in another order is one server', () {
      // The server lists the address on the asking network first, so a
      // device with two adapters hears both orders.
      const first = LocalAiDiscoveredServer(
        name: 'DESKTOP-TEST',
        scheme: 'https',
        port: 3001,
        addresses: ['192.168.1.20', '10.0.0.5'],
        certSha256: _cert,
      );
      const second = LocalAiDiscoveredServer(
        name: 'DESKTOP-TEST',
        scheme: 'https',
        port: 3001,
        addresses: ['10.0.0.5', '192.168.1.20'],
        certSha256: _cert,
      );
      const other = LocalAiDiscoveredServer(
        name: 'DESKTOP-TEST',
        scheme: 'https',
        port: 3001,
        addresses: ['10.0.0.5'],
        certSha256: _cert,
      );

      expect(first.identity, second.identity);
      expect(first, second);
      expect({first, second}, hasLength(1));
      expect(first.identity, isNot(other.identity));
      // The order the server gave is kept for trying the addresses.
      expect(first.baseUrls.first, 'https://192.168.1.20:3001');
    });

    test('an oversized datagram is ignored', () {
      final big = _announce()..['padding'] = 'x' * 1100;
      expect(_parse(big), isNull);
    });
  });

  // ===========================================================================
  // CHOOSING THE PORT
  // ===========================================================================

  group('which port to probe', () {
    test('the saved address\'s port, except the local listener\'s', () {
      expect(LocalAiDiscovery.portFor('https://192.168.1.20:3001'), 3001);
      expect(LocalAiDiscovery.portFor('https://192.168.1.20:4443'), 4443);
      expect(LocalAiDiscovery.portFor('http://10.0.2.2:3000'), 3001);
      expect(LocalAiDiscovery.portFor('http://192.168.1.20'), 3001);
      expect(LocalAiDiscovery.portFor(''), 3001);
    });

    test('a key that is not lai_<id>_<secret> cannot search', () async {
      try {
        await const LocalAiDiscovery().find(apiKey: 'not-a-key');
        fail('expected a LocalAiException');
      } on LocalAiException catch (error) {
        expect(error.code, LocalAiException.notConfigured);
      }
    });

    test('discovery is available on this platform', () {
      expect(const LocalAiDiscovery().isSupported, isTrue);
    });
  });

  // ===========================================================================
  // END TO END OVER UDP
  // ===========================================================================

  group('find() over a real UDP socket', () {
    late RawDatagramSocket responder;
    late StreamSubscription<RawSocketEvent> subscription;
    var probes = 0;

    /// Starts a stand-in for the server on 127.0.0.1 that checks each probe's
    /// proof the way the server does and answers with [announceFor].
    Future<void> respond(
      Map<String, dynamic>? Function(Map<String, dynamic> probe) announceFor,
    ) async {
      probes = 0;
      responder = await RawDatagramSocket.bind(InternetAddress.loopbackIPv4, 0);
      subscription = responder.listen((event) {
        if (event != RawSocketEvent.read) return;
        final datagram = responder.receive();
        if (datagram == null) return;

        final probe = jsonDecode(utf8.decode(datagram.data)) as Map<String, dynamic>;
        final expected = LocalAiDiscoveryProtocol.proof(
          _key,
          LocalAiDiscoveryProtocol.probeProofText(
            probe['keyId'] as String,
            probe['nonce'] as String,
          ),
        );
        if (probe['service'] != 'local-ai' ||
            probe['type'] != 'discover' ||
            probe['proof'] != expected) {
          return; // the server stays silent
        }
        probes++;

        final announce = announceFor(probe);
        if (announce == null) return;
        responder.send(utf8.encode(jsonEncode(announce)), datagram.address, datagram.port);
      });
    }

    tearDown(() async {
      await subscription.cancel();
      responder.close();
    });

    Map<String, dynamic> signed(Map<String, dynamic> probe, {String apiKey = '', String name = 'DESKTOP-TEST'}) {
      final nonce = probe['nonce'] as String;
      final text = LocalAiDiscoveryProtocol.announceProofText(
        keyId: _keyId,
        nonce: nonce,
        name: name,
        scheme: 'https',
        port: 3001,
        path: '/api/v1',
        addresses: const ['127.0.0.1'],
        certSha256: _cert,
      );
      return _announce(
        nonce: nonce,
        name: name,
        addresses: const ['127.0.0.1'],
        proof: LocalAiDiscoveryProtocol.proof(apiKey.isEmpty ? _key : apiKey, text),
      );
    }

    test('a server that proves it holds the key is found, once', () async {
      await respond((probe) => signed(probe));

      final servers = await const LocalAiDiscovery().find(
        apiKey: _key,
        port: responder.port,
        timeout: const Duration(milliseconds: 600),
      );

      // The probe is sent twice against packet loss; both answers are the
      // same server.
      expect(probes, greaterThanOrEqualTo(1));
      expect(servers, hasLength(1));
      expect(servers.single.name, 'DESKTOP-TEST');
      expect(servers.single.certSha256, _cert);
      expect(servers.single.baseUrlFor('127.0.0.1'), 'https://127.0.0.1:3001');
    });

    test('an answer with a forged proof is ignored', () async {
      await respond((probe) => signed(probe, apiKey: 'lai_ab12cd34_${'B' * 43}'));

      final servers = await const LocalAiDiscovery().find(
        apiKey: _key,
        port: responder.port,
        timeout: const Duration(milliseconds: 400),
      );

      expect(probes, greaterThanOrEqualTo(1));
      expect(servers, isEmpty);
    });

    test('silence is an empty result, not an error', () async {
      await respond((_) => null);

      final servers = await const LocalAiDiscovery().find(
        apiKey: _key,
        port: responder.port,
        timeout: const Duration(milliseconds: 300),
      );

      expect(servers, isEmpty);
    });
  });
}
