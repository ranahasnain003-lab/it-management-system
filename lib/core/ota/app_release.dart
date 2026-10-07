/// What an administrator publishes when a new Android build is ready.
///
/// This app is installed as an APK rather than from Play, so nothing tells a
/// phone that a newer build exists. One Firestore document carries that fact.
///
/// It holds no secret. The APK URL is a public HTTPS address and the version
/// numbers are not sensitive, so this travels under the rule that already
/// governs `appConfig`: readable by a signed-in active account, never writable
/// by any client. An administrator puts the values there out of band.
library;

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart';

/// True only for an absolute `https://` URL with a host.
///
/// An APK is executable code, so it is never fetched over plain HTTP: that
/// would let anyone between the phone and the server replace the download.
bool isSecureApkUrl(String url) {
  final uri = Uri.tryParse(url.trim());
  if (uri == null) return false;
  return uri.isAbsolute && uri.scheme == 'https' && uri.host.isNotEmpty;
}

/// A build an administrator has published.
@immutable
class AppRelease {
  const AppRelease({
    required this.versionCode,
    required this.versionName,
    required this.apkUrl,
    this.notes = '',
    this.mandatory = false,
    this.sha256 = '',
  });

  /// The only number compared against the installed build. It is an integer
  /// that must increase with every release, which is what makes "is this
  /// newer?" a question with one unambiguous answer - unlike a display name
  /// such as "1.10" versus "1.9".
  final int versionCode;

  /// Shown to the person, e.g. "1.2.0". Display only; never compared.
  final String versionName;

  /// Where the APK is downloaded from. Must be HTTPS.
  final String apkUrl;

  /// Optional "what changed" text for the prompt.
  final String notes;

  /// When true the prompt cannot be dismissed. Defaults to false, so an
  /// update is only ever forced when somebody deliberately sets this.
  final bool mandatory;

  /// Optional lowercase hex SHA-256 of the APK. When present the downloaded
  /// file is checked against it before the installer is opened, so a corrupt
  /// or substituted download is refused rather than installed.
  final String sha256;

  /// True when there is enough here to offer an update at all.
  bool get isUsable => versionCode > 0 && isSecureApkUrl(apkUrl);

  @override
  String toString() =>
      'AppRelease(versionCode: $versionCode, versionName: $versionName, '
      'mandatory: $mandatory, sha256: ${sha256.isEmpty ? 'none' : 'set'})';
}

/// Reads the published release. Returns null when there is nothing to read or
/// it could not be read - never throws, because being unable to check for an
/// update must leave the app working exactly as it did before.
abstract class AppReleaseSource {
  Future<AppRelease?> fetch();
}

/// The real source: one well-known Firestore document, read under the
/// signed-in account's own permissions.
class FirestoreAppReleaseSource implements AppReleaseSource {
  FirestoreAppReleaseSource({
    FirebaseFirestore? firestore,
    this.timeout = const Duration(seconds: 8),
  }) : _firestore = firestore ?? FirebaseFirestore.instance;

  static const String collection = 'appConfig';
  static const String document = 'androidRelease';

  final FirebaseFirestore _firestore;

  /// Nobody waits on an update check. When this passes, the app carries on as
  /// though no release had been published.
  final Duration timeout;

  @override
  Future<AppRelease?> fetch() async {
    try {
      final snapshot = await _firestore
          .collection(collection)
          .doc(document)
          .get()
          .timeout(timeout);
      final data = snapshot.data();
      if (!snapshot.exists || data == null) return null;
      return AppRelease(
        versionCode: _whole(data['versionCode']),
        versionName: _text(data['versionName']),
        apkUrl: _text(data['apkUrl']),
        notes: _text(data['notes']),
        mandatory: data['mandatory'] == true,
        sha256: _text(data['sha256']).toLowerCase(),
      );
    } catch (error) {
      // Offline, not signed in, no permission, or no such document. Every one
      // of them means "no update to offer", not an error to put on screen.
      debugPrint('OTA: no published release ($error)');
      return null;
    }
  }

  static String _text(Object? value) => value is String ? value.trim() : '';

  /// Firestore hands back numbers as int or double depending on how they were
  /// written, and a hand-edited console field can arrive as a string.
  static int _whole(Object? value) {
    if (value is int) return value;
    if (value is double) return value.truncate();
    if (value is String) return int.tryParse(value.trim()) ?? 0;
    return 0;
  }
}
