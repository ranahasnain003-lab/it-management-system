/// Browser transport for the Local AI server (Flutter Web).
///
/// `http.Client()` is the fetch-based BrowserClient here, which streams the
/// NDJSON answer as it arrives. The browser owns TLS: a page cannot pin a
/// certificate or accept a self-signed one, so [pinnedSha256] is ignored and
/// the server's certificate must be trusted by the operating system (or the
/// page must be plain HTTP talking to plain HTTP). See docs/API.md, 7.
library;

import 'package:http/http.dart' as http;

const bool supportsPinning = false;

http.Client createPlatformClient(String pinnedSha256) => http.Client();
