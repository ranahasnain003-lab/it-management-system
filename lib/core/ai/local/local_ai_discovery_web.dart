/// Discovery on the web: not possible. A browser cannot send or receive UDP,
/// so Flutter Web uses the address typed into Settings (docs/API.md, 6).
library;

import 'local_ai_discovery.dart';

const bool discoverySupported = false;

Future<List<LocalAiDiscoveredServer>> discover({
  required String apiKey,
  required String keyId,
  required int port,
  required Duration timeout,
}) async => const [];
