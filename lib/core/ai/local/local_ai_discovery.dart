/// Finding the Local AI laptop on the local network (docs/API.md, section 6;
/// the protocol is the server's shared/discovery.ts).
///
/// The laptop's Wi-Fi address changes whenever DHCP says so - on this network
/// every 50 minutes at worst - and nobody should have to retype it. The app
/// broadcasts one small UDP probe to the LAN API port, and only a server that
/// holds the app's API key can answer it convincingly:
///
///   probe    app -> broadcast   { service, v, type: "discover", keyId, nonce, proof }
///   announce server -> app     { service, v, type: "announce", keyId, nonce, name, scheme,
///                                port, path, addresses, certSha256, proof }
///
/// Both proofs are HMAC-SHA256 keyed with SHA-256(API key) - the 32 raw
/// bytes, which is all the server stores - so the key itself never crosses
/// the network. The nonce is fresh for every search, so an announce recorded
/// earlier cannot be replayed. Nothing in an announce is believed until its
/// proof checks out, and the certificate fingerprint it carries is then
/// trustworthy enough to pin.
///
/// Browsers cannot send UDP, so Flutter Web has no discovery and uses a typed
/// address ([LocalAiDiscovery.isSupported] is false there).
library;

import 'dart:convert';
import 'dart:math';

import 'package:crypto/crypto.dart';
import 'package:flutter/foundation.dart';

import 'local_ai_config.dart';
import 'local_ai_discovery_web.dart'
    if (dart.library.io) 'local_ai_discovery_io.dart'
    as platform;
import 'local_ai_models.dart';

/// A server that answered a probe and proved it holds the API key.
@immutable
class LocalAiDiscoveredServer {
  const LocalAiDiscoveredServer({
    required this.name,
    required this.scheme,
    required this.port,
    required this.addresses,
    required this.certSha256,
  });

  /// The laptop's computer name, for display only.
  final String name;

  /// `http` or `https`.
  final String scheme;

  /// TCP port of the LAN API.
  final int port;

  /// The laptop's LAN IPv4 addresses, the one on this device's subnet first.
  final List<String> addresses;

  /// SHA-256 of the HTTPS certificate (DER), 64 lower-case hex characters;
  /// null for plain HTTP.
  final String? certSha256;

  bool get isSecure => scheme == 'https';

  /// The base URL (no `/api/v1`) for one of [addresses].
  String baseUrlFor(String address) => '$scheme://$address:$port';

  /// Every base URL this server can be reached at, in the order it gave.
  List<String> get baseUrls => [for (final a in addresses) baseUrlFor(a)];

  /// Two announces with the same identity describe the same listener; the
  /// server answers each probe it receives, and a broadcast reaches it by
  /// more than one route. The addresses are compared as a set: the server
  /// lists the one on the asking network first, so a device with two network
  /// adapters hears the same laptop in two orders.
  String get identity {
    final sorted = [...addresses]..sort();
    return '$name|$scheme|$port|${sorted.join(',')}|${certSha256 ?? ''}';
  }

  @override
  bool operator ==(Object other) =>
      other is LocalAiDiscoveredServer && other.identity == identity;

  @override
  int get hashCode => identity.hashCode;
}

/// Searches the local network for the Local AI server.
///
/// A class rather than a function so the provider can be given a fake in
/// tests; the real one has no state.
class LocalAiDiscovery {
  const LocalAiDiscovery();

  /// The LAN API port the server uses unless `API_LAN_PORT` says otherwise.
  static const int defaultPort = 3001;

  /// The browser app's local listener (`PORT`). The LAN API is never on it
  /// (the server refuses that combination), so a saved address on this port
  /// says nothing about where to send a probe.
  static const int _localListenerPort = 3000;

  static const Duration defaultTimeout = Duration(milliseconds: 2500);

  /// False on the web: a browser cannot send UDP.
  bool get isSupported => platform.discoverySupported;

  /// Broadcasts a probe for [apiKey] to UDP [port] and returns every server
  /// that answered with a valid proof within [timeout], without duplicates.
  ///
  /// Throws [LocalAiException] ([LocalAiException.notConfigured]) when the
  /// key is missing or not of the `lai_<id>_<secret>` form, since there is
  /// then nothing to prove. Network problems are not thrown: a network the
  /// probe cannot reach simply yields no servers.
  Future<List<LocalAiDiscoveredServer>> find({
    required String apiKey,
    int port = defaultPort,
    Duration timeout = defaultTimeout,
  }) async {
    final key = apiKey.trim();
    final keyId = LocalAiConfig.keyIdOf(key);
    if (keyId == null) {
      throw const LocalAiException(
        code: LocalAiException.notConfigured,
        message:
            'Finding the server needs the API key created on the laptop '
            '(it starts with lai_). Enter the key first.',
      );
    }
    if (!isSupported) return const [];

    return platform.discover(
      apiKey: key,
      keyId: keyId,
      port: port,
      timeout: timeout,
    );
  }

  /// The UDP port to probe for a server saved at [baseUrl]: its own port
  /// when it names one other than the local listener's, otherwise
  /// [defaultPort].
  static int portFor(String baseUrl) {
    final uri = Uri.tryParse(LocalAiSettingsStore.normaliseUrl(baseUrl));
    if (uri == null || !uri.hasPort) return defaultPort;
    final port = uri.port;
    if (port <= 0 || port > 65535 || port == _localListenerPort) {
      return defaultPort;
    }
    return port;
  }
}

/// The wire format: probes, announces and their proofs, exactly as
/// shared/discovery.ts defines them. Pure functions, so they can be checked
/// against vectors computed by the server's own code.
class LocalAiDiscoveryProtocol {
  const LocalAiDiscoveryProtocol._();

  static const String service = 'local-ai';
  static const int version = 1;

  /// Datagrams larger than this are ignored (a real announce is a few
  /// hundred bytes).
  static const int maxBytes = 1024;

  static final RegExp _noncePattern = RegExp(r'^[A-Za-z0-9_-]{22,64}$');
  static final RegExp _keyIdPattern = RegExp(r'^[a-z0-9]{8}$');
  static final RegExp _hex64 = RegExp(r'^[0-9a-f]{64}$');
  static final RegExp _ipv4 = RegExp(
    r'^(25[0-5]|2[0-4]\d|1\d\d|[1-9]?\d)(\.(25[0-5]|2[0-4]\d|1\d\d|[1-9]?\d)){3}$',
  );

  /// 24 random bytes as unpadded base64url (32 characters): fresh for every
  /// search, so an old announce cannot be replayed.
  static String newNonce([Random? random]) {
    final source = random ?? Random.secure();
    final bytes = Uint8List.fromList(
      List<int>.generate(24, (_) => source.nextInt(256)),
    );
    return base64Url.encode(bytes).replaceAll('=', '');
  }

  /// The HMAC key both proofs use: SHA-256 of the API key, as raw bytes.
  static List<int> proofKey(String apiKey) =>
      sha256.convert(utf8.encode(apiKey)).bytes;

  static String probeProofText(String keyId, String nonce) =>
      ['local-ai/discover/v1', keyId, nonce].join('\n');

  static String announceProofText({
    required String keyId,
    required String nonce,
    required String name,
    required String scheme,
    required int port,
    required String path,
    required List<String> addresses,
    required String? certSha256,
  }) {
    return [
      'local-ai/announce/v1',
      keyId,
      nonce,
      name,
      scheme,
      '$port',
      path,
      addresses.join(','),
      certSha256 ?? '',
    ].join('\n');
  }

  /// Lower-case hex HMAC-SHA256 of [text] under [apiKey]'s proof key.
  static String proof(String apiKey, String text) =>
      Hmac(sha256, proofKey(apiKey)).convert(utf8.encode(text)).toString();

  /// The probe datagram for one search.
  static Uint8List encodeProbe({
    required String apiKey,
    required String keyId,
    required String nonce,
  }) {
    return Uint8List.fromList(
      utf8.encode(
        jsonEncode({
          'service': service,
          'v': version,
          'type': 'discover',
          'keyId': keyId,
          'nonce': nonce,
          'proof': proof(apiKey, probeProofText(keyId, nonce)),
        }),
      ),
    );
  }

  /// Reads one datagram as an announce answering the probe made with
  /// [keyId] and [nonce], or returns null when it is anything else: too
  /// large, not JSON, another service or version, another key or search, a
  /// malformed field, or - above all - a proof that does not match.
  ///
  /// Nothing about the datagram is trusted before the proof has been checked,
  /// and the proof covers every field that is used.
  static LocalAiDiscoveredServer? parseAnnounce(
    List<int> datagram, {
    required String apiKey,
    required String keyId,
    required String nonce,
  }) {
    if (datagram.isEmpty || datagram.length > maxBytes) return null;

    final Object? decoded;
    try {
      decoded = jsonDecode(utf8.decode(datagram));
    } on FormatException {
      return null;
    }
    if (decoded is! Map) return null;

    final m = decoded;
    if (m['service'] != service || m['v'] != version || m['type'] != 'announce') {
      return null;
    }
    if (m['keyId'] != keyId || !_keyIdPattern.hasMatch(keyId)) return null;
    if (m['nonce'] != nonce || !_noncePattern.hasMatch(nonce)) return null;

    final name = m['name'];
    final scheme = m['scheme'];
    final port = m['port'];
    final path = m['path'];
    final addresses = m['addresses'];
    final cert = m['certSha256'];
    final proofValue = m['proof'];

    if (name is! String || name.length > 255) return null;
    if (scheme != 'http' && scheme != 'https') return null;
    if (port is! int || port < 1 || port > 65535) return null;
    // The app builds every URL as <base>/api/v1; a server announcing another
    // path is not one this app can talk to.
    if (path != '/api/v1') return null;
    if (addresses is! List || addresses.isEmpty || addresses.length > 16) {
      return null;
    }
    final list = <String>[];
    for (final a in addresses) {
      if (a is! String || !_ipv4.hasMatch(a)) return null;
      list.add(a);
    }
    if (cert != null && (cert is! String || !_hex64.hasMatch(cert))) return null;
    // A fingerprint belongs to HTTPS only (the server never announces one
    // for plain HTTP). One on an HTTP announce could only be there to make
    // it look like the pinned server, so it is not believed.
    if (scheme == 'http' && cert != null) return null;
    if (proofValue is! String || !_hex64.hasMatch(proofValue)) return null;

    final expected = proof(
      apiKey,
      announceProofText(
        keyId: keyId,
        nonce: nonce,
        name: name,
        scheme: scheme as String,
        port: port,
        path: path as String,
        addresses: list,
        certSha256: cert as String?,
      ),
    );
    if (!_sameHex(expected, proofValue)) return null;

    return LocalAiDiscoveredServer(
      name: name,
      scheme: scheme,
      port: port,
      addresses: List.unmodifiable(list),
      certSha256: cert,
    );
  }

  /// Compares two equal-length hex strings without stopping early.
  static bool _sameHex(String a, String b) {
    if (a.length != b.length) return false;
    var difference = 0;
    for (var i = 0; i < a.length; i++) {
      difference |= a.codeUnitAt(i) ^ b.codeUnitAt(i);
    }
    return difference == 0;
  }
}
