/// Where a device gets its Local AI connection settings when nobody has typed
/// them in.
///
/// The address can be compiled into the app (LOCAL_AI_BASE_URL), because it is
/// not a secret. The API key cannot: a web build is a file any visitor can
/// download, so a key inside it would be handed to the whole internet, and the
/// AI server is reachable from the internet now. Equally, asking every person
/// to paste a key into Settings on every phone, tablet and browser they use is
/// not something a real organisation will keep doing.
///
/// So the key is fetched at run time from a single Firestore document that only
/// a signed-in, active account with a known role may read - the same gate that
/// already decides whether that person may see any inventory at all. The
/// document is never writable by a client: an administrator puts the values
/// there once, out of band.
///
/// What this does and does not change about security:
///
///   * The key never reaches the app bundle, and never reaches anyone who is
///     not signed in and active.
///   * It DOES reach the browser of every active account, which is the point -
///     those are the people who are meant to use the assistant. Anyone who can
///     read it could call the AI server directly instead of through the app,
///     so the key handed out here should be a dedicated, revocable one with no
///     document-library access, never the key the LAN and Android apps use.
///   * Firebase authentication, the Firestore rules and the server's own
///     API-key check are all unchanged; this only decides how the key travels.
library;

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart';

/// The connection settings an administrator published for every device.
@immutable
class LocalAiRemoteSettings {
  const LocalAiRemoteSettings({
    required this.baseUrl,
    required this.apiKey,
    required this.certificateFingerprint,
  });

  /// Origin of the server, e.g. `https://laptop.tailnet.ts.net`. No path.
  final String baseUrl;

  final String apiKey;

  /// Normally empty. A public certificate (a Tailscale `.ts.net` name) is
  /// checked against the device's own trust store, and pinning one would break
  /// the connection every time the certificate is renewed. It is carried here
  /// only so a LAN-only deployment can still publish its fingerprint.
  final String certificateFingerprint;

  /// True when there is enough here to connect without anyone typing anything.
  bool get isUsable => baseUrl.isNotEmpty && apiKey.isNotEmpty;

  @override
  String toString() =>
      'LocalAiRemoteSettings(baseUrl: $baseUrl, apiKey: ${apiKey.isEmpty ? 'not set' : 'set'}, '
      'fingerprint: ${certificateFingerprint.isEmpty ? 'none' : 'set'})';
}

/// Reads the published settings. Returns null when there are none to read, or
/// when they could not be read - never throws, because a missing document must
/// leave the rest of the app working exactly as before.
abstract class LocalAiRemoteSetup {
  Future<LocalAiRemoteSettings?> fetch();
}

/// The real source: one document in Firestore, read under the signed-in
/// account's own permissions.
class FirestoreLocalAiRemoteSetup implements LocalAiRemoteSetup {
  FirestoreLocalAiRemoteSetup({FirebaseFirestore? firestore, this.timeout = const Duration(seconds: 8)})
    : _firestore = firestore ?? FirebaseFirestore.instance;

  /// Collection and document the administrator publishes to. A single
  /// well-known path, so there is nothing to discover and nothing per-device.
  static const String collection = 'appConfig';
  static const String document = 'localAi';

  final FirebaseFirestore _firestore;

  /// A device opening the assistant must not sit waiting for Firestore. When
  /// this passes, the screen behaves as it always did when nothing was set up.
  final Duration timeout;

  @override
  Future<LocalAiRemoteSettings?> fetch() async {
    try {
      final snapshot = await _firestore
          .collection(collection)
          .doc(document)
          .get()
          .timeout(timeout);
      final data = snapshot.data();
      if (!snapshot.exists || data == null) return null;
      return LocalAiRemoteSettings(
        baseUrl: _text(data['baseUrl']),
        apiKey: _text(data['apiKey']),
        certificateFingerprint: _text(data['certificateFingerprint']),
      );
    } catch (error) {
      // Not signed in yet, no permission, offline, or no such document. All of
      // them mean "nothing published for this device", not a failure to show.
      debugPrint('Local AI: no published connection settings ($error)');
      return null;
    }
  }

  static String _text(Object? value) => value is String ? value.trim() : '';
}
