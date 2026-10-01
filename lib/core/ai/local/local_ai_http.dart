/// The HTTP transport to the Local AI server, with certificate pinning where
/// the platform allows it.
///
/// The LAN listener normally uses a self-signed certificate made on the laptop
/// (`create-certificate.ps1`). No public authority vouches for it, so the app
/// trusts it by its SHA-256 fingerprint instead - the one the administrator
/// typed, or the one discovery delivered with proof (see docs/API.md, 7).
///
///   * Android, Windows, iOS, macOS, Linux (dart:io): with a fingerprint, the
///     connection is made with NO trusted roots at all, so every certificate
///     is refused unless its SHA-256 equals the pin. Not "the pin or any
///     public CA": exactly the pin. Without a fingerprint, the platform's
///     normal trust store applies.
///   * Web: the browser owns TLS and a page cannot pin. The certificate must
///     be trusted by the operating system, or the page must use plain HTTP.
library;

import 'dart:typed_data';

import 'package:crypto/crypto.dart';
import 'package:http/http.dart' as http;

import 'local_ai_http_web.dart'
    if (dart.library.io) 'local_ai_http_io.dart'
    as platform;

/// A client for one request to the Local AI server.
///
/// [pinnedSha256] is the configured fingerprint (lower-case hex, as the
/// settings store keeps it); empty means no pinning.
http.Client createLocalAiHttpClient({String pinnedSha256 = ''}) =>
    platform.createPlatformClient(pinnedSha256.trim());

/// False on the web, where the browser decides which certificates to trust.
bool get localAiSupportsCertificatePinning => platform.supportsPinning;

/// True only when [der] (a certificate in DER form) hashes to [pinHex].
///
/// [pinHex] may carry colons or upper-case letters, as
/// `create-certificate.ps1` prints it. An empty or malformed pin never
/// matches: "no pin" must mean "use the trust store", never "accept anything".
bool certificateMatchesPin(Uint8List der, String pinHex) {
  final pin = pinHex.replaceAll(RegExp(r'[^0-9a-fA-F]'), '').toLowerCase();
  if (pin.length != 64 || der.isEmpty) return false;

  final actual = sha256.convert(der).toString();

  // Compared in full rather than stopping at the first difference. The pin is
  // not a secret, but there is no reason to hand out timing information.
  var difference = 0;
  for (var i = 0; i < 64; i++) {
    difference |= actual.codeUnitAt(i) ^ pin.codeUnitAt(i);
  }
  return difference == 0;
}
