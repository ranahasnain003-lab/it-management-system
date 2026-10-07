/// Where the Local AI server is, and the key that opens it.
///
/// Nothing here is ever committed. The address and the key are supplied in one
/// of three ways:
///
///   1. Build time, for a development machine or a managed rollout:
///        flutter run \
///          --dart-define=LOCAL_AI_BASE_URL=http://10.0.2.2:3000 \
///          --dart-define=LOCAL_AI_API_KEY=lai_xxxxxxxx_yyyy
///
///   2. Run time, typed into Settings by an authorised administrator. What is
///      typed wins over the build-time value, so one build serves every
///      laptop without being rebuilt for each address.
///
///   3. Discovery: the app finds the laptop on the local network with the key
///      alone (see local_ai_discovery.dart) and saves the verified address and
///      certificate fingerprint as if they had been typed.
///
/// The address is not a secret and is kept in SharedPreferences. The key IS a
/// secret - it grants use of the model to whoever holds it - so it is kept in
/// the platform's encrypted store and is never written to a log, never put in
/// an error message, and never shown in full on screen.
library;

import 'package:flutter/foundation.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// One resolved configuration.
@immutable
class LocalAiConfig {
  const LocalAiConfig({
    required this.baseUrl,
    required this.apiKey,
    required this.certificateFingerprint,
    required this.source,
  });

  /// Origin of the server, with no trailing slash and no `/api/v1`, e.g.
  /// `http://10.0.2.2:3000` or `https://192.168.1.50:3001`.
  final String baseUrl;

  final String apiKey;

  /// Lower-case hex SHA-256 of the server's certificate (DER), when the LAN
  /// listener uses HTTPS. When set, it is the ONLY certificate accepted - see
  /// local_ai_http.dart. Empty means the platform's normal trust store.
  final String certificateFingerprint;

  /// Where these values came from, for the Settings screen to show.
  final LocalAiConfigSource source;

  /// True when there is enough to attempt a call.
  bool get isConfigured => baseUrl.isNotEmpty;

  /// True when the server will be reached over plain HTTP.
  bool get isCleartext => baseUrl.startsWith('http://');

  bool get isHttps => baseUrl.startsWith('https://');

  /// True when the HTTPS certificate is pinned rather than checked against
  /// the platform's trust store.
  bool get isPinned => certificateFingerprint.isNotEmpty;

  /// The `/api/v1` root every request is built from.
  String get apiRoot => '$baseUrl/api/v1';

  /// True when [baseUrl] names a host that can only be reached from this
  /// network: a private or loopback IPv4 address, an IPv6 loopback or
  /// link-local address, a bare hostname, or an mDNS `.local` name.
  ///
  /// This is what tells a LAN address apart from a public one such as a
  /// tunnel's `https://something.ts.net`. It matters because the UDP discovery
  /// announcements on this network may only ever be allowed to replace a LAN
  /// address: a server found by a broadcast on the office Wi-Fi is not
  /// evidence about where a public address should point, and adopting it would
  /// take a phone that works from anywhere and tie it back to this one
  /// network. See LocalAiProvider._findMovedServer.
  bool get isPrivateHost => hostIsPrivate(Uri.tryParse(baseUrl)?.host ?? '');

  /// See [isPrivateHost]. Public by name so the provider and its tests can ask
  /// about a host that is not the configured one.
  static bool hostIsPrivate(String host) {
    final name = host.trim().toLowerCase();
    if (name.isEmpty) return false;

    // IPv6 arrives from Uri.host without its brackets.
    if (name.contains(':')) {
      if (name == '::1') return true;
      // fe80::/10 (link-local) and fc00::/7 (unique local).
      return name.startsWith('fe8') ||
          name.startsWith('fe9') ||
          name.startsWith('fea') ||
          name.startsWith('feb') ||
          name.startsWith('fc') ||
          name.startsWith('fd');
    }

    final octets = name.split('.');
    final numbers = [for (final o in octets) int.tryParse(o)];
    final isIpv4 = octets.length == 4 && !numbers.contains(null);
    if (isIpv4) {
      final [a, b, _, _] = [for (final n in numbers) n!];
      if (a == 127 || a == 10) return true;
      if (a == 192 && b == 168) return true;
      if (a == 172 && b >= 16 && b <= 31) return true;
      // 169.254.0.0/16 link-local, and the Android emulator's host alias.
      if (a == 169 && b == 254) return true;
      return false;
    }

    // Names: localhost, an mDNS name, or a single-label host that only a local
    // resolver can answer. Anything with a public suffix is treated as public.
    if (name == 'localhost') return true;
    if (name.endsWith('.local') || name.endsWith('.localhost')) return true;
    return !name.contains('.');
  }

  /// The public id of the key (the `<id>` of `lai_<id>_<secret>`), or null
  /// for a key of any other shape. Discovery sends it, so the server can tell
  /// which key the proof was made with without the key crossing the network.
  String? get keyId => keyIdOf(apiKey);

  /// See [keyId].
  static String? keyIdOf(String apiKey) {
    final match = _keyPattern.firstMatch(apiKey.trim());
    return match?.group(1);
  }

  /// `lai_` + an 8-character id + `_` + the secret. The secret is base64url,
  /// so it may itself contain `_` and `-`; only the id is anchored.
  static final RegExp _keyPattern = RegExp(r'^lai_([a-z0-9]{8})_[A-Za-z0-9_-]+$');

  /// The key with its secret hidden, safe to show and to log.
  ///
  /// The contract's key format is `lai_<id>_<secret>`, where the id is a public
  /// identifier and only the secret is sensitive, so the id is shown to make
  /// the configured key identifiable at a glance without revealing it.
  String get redactedApiKey {
    if (apiKey.isEmpty) return 'not set';

    final parts = apiKey.split('_');
    if (parts.length >= 3 && parts.first == 'lai') {
      return 'lai_${parts[1]}_${'•' * 8}';
    }

    // Some other shape: show nothing but its length.
    return '${'•' * 8} (${apiKey.length} characters)';
  }

  /// The fingerprint shortened for display: enough to compare by eye with
  /// what `create-certificate.ps1` printed, without a 64-character line.
  String get shortFingerprint => shortenFingerprint(certificateFingerprint);

  /// See [shortFingerprint].
  static String shortenFingerprint(String fingerprint) {
    if (fingerprint.length <= 20) return fingerprint;
    return '${fingerprint.substring(0, 12)}…'
        '${fingerprint.substring(fingerprint.length - 8)}';
  }

  LocalAiConfig copyWith({
    String? baseUrl,
    String? apiKey,
    String? certificateFingerprint,
    LocalAiConfigSource? source,
  }) {
    return LocalAiConfig(
      baseUrl: baseUrl ?? this.baseUrl,
      apiKey: apiKey ?? this.apiKey,
      certificateFingerprint:
          certificateFingerprint ?? this.certificateFingerprint,
      source: source ?? this.source,
    );
  }

  /// True when [other] would send the same requests to the same server with
  /// the same key and the same pin. Used to notice that the configuration
  /// changed while something slow (discovery) was in progress.
  bool sameConnectionAs(LocalAiConfig other) =>
      baseUrl == other.baseUrl &&
      apiKey == other.apiKey &&
      certificateFingerprint == other.certificateFingerprint;

  static const LocalAiConfig empty = LocalAiConfig(
    baseUrl: '',
    apiKey: '',
    certificateFingerprint: '',
    source: LocalAiConfigSource.none,
  );
}

/// Which layer supplied the configuration currently in use.
enum LocalAiConfigSource {
  /// Nothing configured; the assistant cannot be used yet.
  none,

  /// Compiled in with --dart-define.
  build,

  /// Typed into Settings (or found by discovery) on this device.
  device,
}

/// Reads and writes the configuration.
///
/// Split out from the provider so tests can drive it without platform
/// channels, and so nothing else in the app has to know that the key lives
/// somewhere different from the address.
class LocalAiSettingsStore {
  LocalAiSettingsStore({
    FlutterSecureStorage? secureStorage,
    Future<SharedPreferences> Function()? preferences,
  }) : _secure = secureStorage ?? const FlutterSecureStorage(),
       _preferences = preferences ?? SharedPreferences.getInstance;

  final FlutterSecureStorage _secure;
  final Future<SharedPreferences> Function() _preferences;

  // --- build-time defaults ---------------------------------------------------

  /// Compiled-in address, empty unless the build passed one.
  static const String buildBaseUrl = String.fromEnvironment(
    'LOCAL_AI_BASE_URL',
    defaultValue: '',
  );

  /// Compiled-in key. Intended for a development build only; a release build
  /// should leave it out and have the key typed in Settings instead, so the
  /// key is not sitting inside an APK that can be copied off a device.
  static const String buildApiKey = String.fromEnvironment(
    'LOCAL_AI_API_KEY',
    defaultValue: '',
  );

  /// Compiled-in certificate fingerprint for pinning the LAN listener's
  /// self-signed certificate.
  static const String buildFingerprint = String.fromEnvironment(
    'LOCAL_AI_CERT_SHA256',
    defaultValue: '',
  );

  static const String _urlKey = 'local_ai.base_url';
  static const String _fingerprintKey = 'local_ai.cert_sha256';
  static const String _secretKey = 'local_ai.api_key';

  /// The configuration to use now: what was typed on this device, falling back
  /// to what the build supplied.
  Future<LocalAiConfig> load() async {
    final prefs = await _preferences();

    final deviceUrl = (prefs.getString(_urlKey) ?? '').trim();
    final deviceFingerprint = (prefs.getString(_fingerprintKey) ?? '').trim();

    String deviceKey = '';
    try {
      deviceKey = (await _secure.read(key: _secretKey))?.trim() ?? '';
    } catch (error) {
      // A locked keystore, or a platform without one. The assistant can still
      // run on the build-time key; it must not take the whole screen down.
      debugPrint('Local AI: secure storage unavailable ($error)');
    }

    final baseUrl = normaliseUrl(
      deviceUrl.isNotEmpty ? deviceUrl : buildBaseUrl,
    );
    final apiKey = deviceKey.isNotEmpty ? deviceKey : buildApiKey;
    final fingerprint = deviceFingerprint.isNotEmpty
        ? deviceFingerprint
        : buildFingerprint;

    return LocalAiConfig(
      baseUrl: baseUrl,
      apiKey: apiKey,
      certificateFingerprint: normaliseFingerprint(fingerprint),
      source: baseUrl.isEmpty
          ? LocalAiConfigSource.none
          : (deviceUrl.isNotEmpty || deviceKey.isNotEmpty
                ? LocalAiConfigSource.device
                : LocalAiConfigSource.build),
    );
  }

  /// Stores what an administrator typed. An empty [apiKey] clears the stored
  /// key rather than storing an empty one, so the build-time value can be
  /// fallen back to deliberately.
  Future<void> save({
    required String baseUrl,
    required String apiKey,
    String certificateFingerprint = '',
  }) async {
    await saveAddress(
      baseUrl: baseUrl,
      certificateFingerprint: certificateFingerprint,
    );

    try {
      if (apiKey.trim().isEmpty) {
        await _secure.delete(key: _secretKey);
      } else {
        await _secure.write(key: _secretKey, value: apiKey.trim());
      }
    } catch (error) {
      // Deliberately does not include the key in the message.
      debugPrint('Local AI: could not write the API key to secure storage ($error)');
      rethrow;
    }
  }

  /// Stores a new address and fingerprint and leaves the key exactly where it
  /// is - in secure storage, or in the build. Used when discovery finds the
  /// laptop at a new address: copying a build-time key into storage just to
  /// move the address would outlive the build it came with.
  Future<void> saveAddress({
    required String baseUrl,
    String certificateFingerprint = '',
  }) async {
    final prefs = await _preferences();
    final url = normaliseUrl(baseUrl);

    if (url.isEmpty) {
      await prefs.remove(_urlKey);
    } else {
      await prefs.setString(_urlKey, url);
    }

    final fingerprint = normaliseFingerprint(certificateFingerprint);
    if (fingerprint.isEmpty) {
      await prefs.remove(_fingerprintKey);
    } else {
      await prefs.setString(_fingerprintKey, fingerprint);
    }
  }

  /// Forgets everything configured on this device.
  Future<void> clearDeviceConfig() async {
    final prefs = await _preferences();
    await prefs.remove(_urlKey);
    await prefs.remove(_fingerprintKey);
    try {
      await _secure.delete(key: _secretKey);
    } catch (error) {
      debugPrint('Local AI: could not clear the API key ($error)');
    }
  }

  // --- validation and normalisation -----------------------------------------

  /// Trims, drops a trailing slash, and removes a `/api/v1` suffix somebody
  /// pasted in - a very easy mistake, and one that would otherwise produce
  /// `/api/v1/api/v1/health` and a baffling 404.
  static String normaliseUrl(String raw) {
    var url = raw.trim();
    if (url.isEmpty) return '';

    while (url.endsWith('/')) {
      url = url.substring(0, url.length - 1);
    }
    if (url.toLowerCase().endsWith('/api/v1')) {
      url = url.substring(0, url.length - '/api/v1'.length);
    }
    while (url.endsWith('/')) {
      url = url.substring(0, url.length - 1);
    }

    return url;
  }

  /// Accepts a fingerprint with or without colons, in any case, and returns
  /// bare lower-case hex. `create-certificate.ps1` prints it colon-separated.
  static String normaliseFingerprint(String raw) {
    return raw.replaceAll(RegExp(r'[^0-9a-fA-F]'), '').toLowerCase();
  }

  /// Why [raw] is not a usable server address, or null when it is (or when it
  /// is empty, which means "use the build's address, if any").
  ///
  /// Written as the person should read it, because this is shown under the
  /// field as they type.
  static String? addressProblem(String raw) {
    final url = normaliseUrl(raw);
    if (url.isEmpty) return null;

    final uri = Uri.tryParse(url);
    if (uri == null || !url.contains('://')) {
      return 'Start with http:// or https://, e.g. https://192.168.1.20:3001';
    }
    if (uri.scheme != 'http' && uri.scheme != 'https') {
      return 'Only http:// and https:// addresses are supported.';
    }
    if (uri.host.isEmpty) {
      return 'Add the laptop\'s IP address or name after ${uri.scheme}://';
    }
    if (uri.userInfo.isNotEmpty) {
      return 'Leave out any user name or password; the API key is entered '
          'separately.';
    }
    if (uri.hasQuery || uri.hasFragment || (uri.path.isNotEmpty && uri.path != '/')) {
      return 'Enter only the address and port, e.g. https://192.168.1.20:3001 '
          '(the app adds /api/v1 itself).';
    }
    if (uri.hasPort && (uri.port < 1 || uri.port > 65535)) {
      return 'The port must be between 1 and 65535.';
    }
    return null;
  }

  /// Why [raw] is not a usable certificate fingerprint, or null when it is
  /// (or is empty: no pinning).
  static String? fingerprintProblem(String raw) {
    if (raw.trim().isEmpty) return null;

    // Anything but hex digits and the usual separators is a paste of the
    // wrong thing, not a formatting difference.
    if (RegExp(r'[^0-9a-fA-F:\s-]').hasMatch(raw)) {
      return 'Use the SHA-256 fingerprint: 64 hexadecimal characters, with or '
          'without colons.';
    }
    final hex = normaliseFingerprint(raw);
    if (hex.length != 64) {
      return 'A SHA-256 fingerprint has 64 hexadecimal characters; this has '
          '${hex.length}.';
    }
    return null;
  }
}
