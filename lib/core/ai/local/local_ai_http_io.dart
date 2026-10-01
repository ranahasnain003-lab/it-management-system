/// dart:io transport for the Local AI server: Android, Windows, iOS, macOS
/// and Linux. See local_ai_http.dart for what the pinning guarantees.
library;

import 'dart:io';

import 'package:http/http.dart' as http;
import 'package:http/io_client.dart';

import 'local_ai_http.dart';

const bool supportsPinning = true;

/// How long to wait for the TCP connection itself.
///
/// Short on purpose, and separate from the waits for an answer: a laptop that
/// changed its Wi-Fi address leaves nothing listening at the old one, and the
/// sooner that is known, the sooner discovery can look for the new address.
/// The operating system's own connect timeout is 20 seconds or more.
const Duration _connectTimeout = Duration(seconds: 8);

http.Client createPlatformClient(String pinnedSha256) {
  if (pinnedSha256.isEmpty) {
    return IOClient(HttpClient()..connectionTimeout = _connectTimeout);
  }

  // No trusted roots: nothing is valid by default, so EVERY certificate -
  // self-signed or signed by a public authority - reaches the callback, and
  // the callback accepts exactly one. That is strict pinning; a certificate
  // from a public CA for some other machine at the same address is refused
  // just like a self-signed impostor.
  final inner = HttpClient(context: SecurityContext(withTrustedRoots: false))
    ..connectionTimeout = _connectTimeout
    ..badCertificateCallback = (certificate, host, port) =>
        certificateMatchesPin(certificate.der, pinnedSha256);

  return IOClient(inner);
}
