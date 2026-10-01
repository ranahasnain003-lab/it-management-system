/// State for the Local AI Assistant screen.
///
/// Holds one signed-in account's conversation, the connection status, and the
/// configuration. It owns the rule that matters most here: a conversation
/// belongs to exactly one signed-in account, and changing account - or signing
/// out - throws the previous one away completely.
///
/// It also owns everything that makes a question succeed without anyone
/// having to understand why it might not: the inventory data that grounds the
/// answer (`appContext`), the document mode the key is actually allowed, a
/// server that forgot the conversation, and a laptop that moved to another
/// address.
library;

import 'dart:async';
import 'dart:convert';
import 'dart:math' as math;

import 'package:crypto/crypto.dart';
import 'package:flutter/foundation.dart';

import 'local_ai_client.dart';
import 'local_ai_config.dart';
import 'local_ai_context_service.dart';
import 'local_ai_discovery.dart';
import 'local_ai_models.dart';

/// The opaque per-user value sent as `X-Conversation-Scope`.
///
/// The Local AI server makes (API key, scope) the owner of a conversation, and
/// every account on this device shares one API key - so without a scope, two
/// people signing into the same phone would see each other's chats. The scope
/// is what separates them.
///
/// It is HMAC-SHA256 of the Firebase uid, keyed with the API key. The server
/// only needs a value that is stable per person and different between people;
/// it has no business knowing who they are. A plain hash of the uid would not
/// be enough for that: uids appear in documents other accounts can read, so
/// anyone could hash one and recognise the scope. Keyed with the API key -
/// which the server itself does not hold, only its SHA-256 - nobody without
/// the key can link a scope to a person. It is stable across reinstalls, so a
/// conversation survives one, and it changes with the key, so a new key
/// starts clean.
class LocalAiScope {
  const LocalAiScope._();

  /// Domain separation, so this value can never collide with an HMAC of the
  /// same uid computed somewhere else for another purpose.
  static const String _prefix = 'psba-it-inventory:local-ai:v2:';

  /// The scope for [uid] under [apiKey], or empty when nobody is signed in or
  /// no key is configured (and nothing may then be sent).
  ///
  /// The result is 64 lower-case hex characters, comfortably inside the
  /// server's 1-128 character limit and its permitted character set.
  static String forUser(String? uid, {required String apiKey}) {
    final clean = (uid ?? '').trim();
    if (clean.isEmpty || apiKey.trim().isEmpty) return '';

    return Hmac(sha256, utf8.encode(apiKey))
        .convert(utf8.encode('$_prefix$clean'))
        .toString();
  }
}

/// How the app is currently getting on with the Local AI server.
enum LocalAiStatus {
  /// No address configured yet.
  notConfigured,

  /// Nothing tried yet this session.
  unknown,

  checking,

  /// Reachable and the model is loaded.
  ready,

  /// Reachable, but something is wrong - Ollama down, model missing, key
  /// refused.
  degraded,

  /// Could not be reached at all.
  unreachable,
}

class LocalAiProvider extends ChangeNotifier {
  LocalAiProvider({
    LocalAiClient? client,
    LocalAiSettingsStore? settings,
    this._contextService,
    LocalAiDiscovery? discovery,
    this._stopGrace = LocalAiStream.defaultStopGrace,
    this._contextTimeout = const Duration(seconds: 15),
    this._monitorInterval = const Duration(seconds: 30),
  }) : _client = client ?? LocalAiClient(),
       _settings = settings ?? LocalAiSettingsStore(),
       _discovery = discovery ?? const LocalAiDiscovery();

  final LocalAiClient _client;
  final LocalAiSettingsStore _settings;
  final LocalAiContextService? _contextService;
  final LocalAiDiscovery _discovery;
  final Duration _stopGrace;
  final Duration _contextTimeout;
  final Duration _monitorInterval;

  /// The most inventory data sent with one question, in the server's token
  /// estimate, even when the server would take more (it reports up to
  /// `maxAppContextTokens`, about 2 900 for Qwen3 8B).
  ///
  /// This is a speed trade-off. On a CPU-only laptop Qwen3 reads its prompt
  /// at a few hundred tokens a second, so every 1 000 tokens of data is
  /// several more seconds before the first word appears. 1 600 tokens holds
  /// the totals and the relevant list for nearly every question while keeping
  /// that wait tolerable; the context service trims to it.
  static const int preferredContextTokens = 1600;

  /// Assumed when the server does not report `maxAppContextTokens` (or the
  /// model has not been read yet): below what any supported server accepts.
  static const int fallbackMaxAppContextTokens = 1800;

  /// Sent in place of data the app could not read, so the model says it could
  /// not retrieve the answer instead of guessing one.
  static const String unreadableContextNote =
      'The app could not read the inventory data for this question.';

  static const String _readingProgress = 'Reading your inventory data…';
  static const String _searchingProgress =
      'Looking for the AI server on this network…';

  /// How often an idle screen may run discovery on its own when the laptop
  /// stays unreachable. A switched-off laptop should not mean a broadcast
  /// every 30 seconds for as long as the screen is open.
  static const Duration _automaticDiscoveryInterval = Duration(minutes: 2);

  LocalAiConfig _config = LocalAiConfig.empty;
  LocalAiStatus _status = LocalAiStatus.unknown;
  LocalAiHealth? _health;
  LocalAiModelInfo? _model;

  final List<LocalAiMessage> _messages = [];
  String? _conversationId;
  String _scope = '';
  String? _uid;

  /// Bumped whenever the conversation is thrown away (account change, new
  /// key, clear). Work still in flight for the old one compares its own
  /// number with this and quietly drops its result.
  int _generation = 0;

  LocalAiStream? _active;
  bool _sending = false;
  bool _stopRequested = false;

  /// Completed by [stop] for the question being sent. Waits that have no
  /// stream to stop - reading the inventory data, looking for a laptop that
  /// moved - race against it, so Stop ends the answer at once instead of
  /// after the wait.
  Completer<void>? _stopSignal;
  LocalAiException? _lastError;
  LocalAiDocumentsMode _documentsMode = LocalAiDocumentsMode.off;

  /// Set when the server refused documents although health said the key may
  /// use them; cleared by the next health check.
  bool _documentsRefused = false;

  String? _notice;
  StreamSubscription<String?>? _authSubscription;

  Timer? _monitor;
  bool _polling = false;
  DateTime? _pollPausedUntil;
  DateTime? _lastAutomaticDiscovery;
  Future<bool>? _rediscovery;
  bool _disposed = false;

  // --- reading ---------------------------------------------------------------

  LocalAiConfig get config => _config;
  LocalAiStatus get status => _status;
  LocalAiHealth? get health => _health;
  LocalAiModelInfo? get model => _model;

  /// The current account's conversation. Never another account's: [bindUser]
  /// clears it the moment the signed-in account changes.
  List<LocalAiMessage> get messages => List.unmodifiable(_messages);

  String? get conversationId => _conversationId;
  bool get isSending => _sending;
  bool get isConfigured => _config.isConfigured;
  bool get isSignedIn => _uid != null;
  LocalAiException? get lastError => _lastError;
  LocalAiDocumentsMode get documentsMode => _documentsMode;
  bool get hasConversation => _messages.isNotEmpty;

  /// Whether the configured key may use the laptop's document library, as
  /// the server said in its last health reply. False until it has said so:
  /// asking for documents without the scope is refused outright.
  bool get documentsAllowed =>
      (_health?.allowsDocuments ?? false) && !_documentsRefused;

  /// True while a question is on its way, which is when Stop is offered -
  /// also while the inventory data is being read, before anything is sent.
  bool get canStop => _sending && !_stopRequested;

  /// True between pressing Stop and the answer actually ending.
  bool get isStopping => _sending && _stopRequested;

  /// False on the web, where a browser cannot send the UDP probe.
  bool get discoverySupported => _discovery.isSupported;

  bool get isMonitoring => _monitor != null;

  /// A short message worth a SnackBar, e.g. that the laptop was found at a
  /// new address. See [takeNotice].
  String? get notice => _notice;

  /// Returns [notice] and clears it, so it is shown once. Does not notify:
  /// the screen calls it from its own listener.
  String? takeNotice() {
    final notice = _notice;
    _notice = null;
    return notice;
  }

  // --- lifecycle -------------------------------------------------------------

  /// Loads the stored configuration. Safe to call more than once.
  ///
  /// A different API key means a different conversation scope, which throws
  /// the current conversation away: the server would no longer let this
  /// device continue it, and it must not be continued under another key.
  Future<void> loadConfig() async {
    final loaded = await _settings.load();
    if (_disposed) return;

    if (loaded.apiKey != _config.apiKey) {
      // What the old key was allowed says nothing about the new one.
      _health = null;
      _model = null;
      _documentsMode = LocalAiDocumentsMode.off;
    }
    _config = loaded;

    if (!_config.isConfigured) {
      _status = LocalAiStatus.notConfigured;
    } else if (_status == LocalAiStatus.notConfigured) {
      _status = LocalAiStatus.unknown;
    }

    _refreshScope();
    notifyListeners();
  }

  /// Follows the signed-in account for the life of the app.
  ///
  /// Wired to Firebase's own auth state rather than to each sign-out call
  /// site, because there are several of those - the Settings button, an
  /// expired session, a disabled account, an incomplete login - and any one of
  /// them being missed would leave one person's conversation on screen for the
  /// next. Listening to the state itself cannot be forgotten.
  void attachUserStream(Stream<String?> userIds) {
    _authSubscription?.cancel();
    _authSubscription = userIds.listen(bindUser);
  }

  /// Ties this provider to the signed-in account.
  ///
  /// A different uid - including null on sign-out - discards the previous
  /// account's conversation before anything can be displayed, which is what
  /// stops User B opening the screen and finding User A's chat still on it.
  void bindUser(String? uid) {
    final next = (uid ?? '').trim().isEmpty ? null : uid!.trim();
    if (next == _uid) return;

    _uid = next;
    _refreshScope(accountChanged: true);
    notifyListeners();
  }

  /// Clears everything held in memory for the signed-out account.
  ///
  /// Deliberately does NOT clear the configured address or API key: those
  /// belong to the device and were set by an administrator, not by whoever
  /// happens to be signed in.
  void clearForLogout() {
    _uid = null;
    _scope = '';
    _discardConversation();
    _contextService?.reset();
    _health = null;
    _model = null;
    _documentsMode = LocalAiDocumentsMode.off;
    _status = _config.isConfigured
        ? LocalAiStatus.unknown
        : LocalAiStatus.notConfigured;
    notifyListeners();
  }

  /// Recomputes the scope from the signed-in account and the key, and throws
  /// the conversation away when it changed (or the account did).
  void _refreshScope({bool accountChanged = false}) {
    final next = LocalAiScope.forUser(_uid, apiKey: _config.apiKey);
    final changed = next != _scope;
    _scope = next;

    if (accountChanged || changed) {
      _discardConversation();
      _contextService?.reset();
    }
  }

  void _discardConversation() {
    _generation++;
    final active = _active;
    _active = null;
    // Dropping the connection stops the answer on the server too. Nothing of
    // it can reach the screen any more: every update checks the generation.
    active?.abort();
    _messages.clear();
    _conversationId = null;
    _sending = false;
    _stopRequested = false;
    _lastError = null;
  }

  @override
  void notifyListeners() {
    // Answers, health checks and discovery can all finish after the provider
    // is gone; none of them may throw because of it.
    if (!_disposed) super.notifyListeners();
  }

  @override
  void dispose() {
    _disposed = true;
    stopMonitoring();
    unawaited(_authSubscription?.cancel());
    _generation++;
    _active?.abort();
    _active = null;
    super.dispose();
  }

  // --- configuration ---------------------------------------------------------

  /// Saves an administrator's settings and re-tests the connection.
  ///
  /// A null or empty [apiKey] keeps the key already stored (or the build's),
  /// so the address can be changed without re-typing the secret.
  ///
  /// Throws [LocalAiException] ([LocalAiException.notConfigured]) with a
  /// readable reason when the address or fingerprint is not usable.
  Future<void> saveConfig({
    required String baseUrl,
    String? apiKey,
    String certificateFingerprint = '',
  }) async {
    final problem =
        LocalAiSettingsStore.addressProblem(baseUrl) ??
        LocalAiSettingsStore.fingerprintProblem(certificateFingerprint);
    if (problem != null) {
      throw LocalAiException(code: LocalAiException.notConfigured, message: problem);
    }

    final key = (apiKey ?? '').trim();
    if (key.isEmpty) {
      await _settings.saveAddress(
        baseUrl: baseUrl,
        certificateFingerprint: certificateFingerprint,
      );
    } else {
      await _settings.save(
        baseUrl: baseUrl,
        apiKey: key,
        certificateFingerprint: certificateFingerprint,
      );
    }
    await loadConfig();
    await testConnection();
  }

  /// Forgets the address, key and fingerprint saved on this device, falling
  /// back to whatever the build supplies (often nothing).
  ///
  /// The conversation goes too, even when the build supplies the same key
  /// (so the scope, and with it [loadConfig]'s own clearing, does not
  /// change): a reset is a fresh start, and its id may belong to a server
  /// this device no longer points at.
  Future<void> resetConfig() async {
    await _settings.clearDeviceConfig();
    if (_disposed) return;
    _discardConversation();
    _contextService?.reset();
    _health = null;
    _model = null;
    _lastError = null;
    await loadConfig();
    if (_config.isConfigured) await testConnection();
  }

  /// Chooses whether the laptop's documents are searched. `auto` and `only`
  /// are only accepted when the key has the `documents` scope; otherwise the
  /// server would refuse every question with 403 FORBIDDEN_SCOPE.
  void setDocumentsMode(LocalAiDocumentsMode mode) {
    if (mode == _documentsMode) return;
    if (mode != LocalAiDocumentsMode.off && !documentsAllowed) return;
    _documentsMode = mode;
    notifyListeners();
  }

  /// Asks the server how it is. Backs the Settings "Test connection" button
  /// and the banner on the assistant screen.
  ///
  /// When the laptop cannot be reached, it is looked for on the local network
  /// first (native builds with a key), and the check is repeated at its new
  /// address.
  Future<bool> testConnection() =>
      _checkHealth(showChecking: true, allowRediscovery: true);

  Future<bool> _checkHealth({
    required bool showChecking,
    required bool allowRediscovery,
    bool automatic = false,
  }) async {
    if (!_config.isConfigured) {
      _status = LocalAiStatus.notConfigured;
      notifyListeners();
      return false;
    }

    if (showChecking) {
      _status = LocalAiStatus.checking;
      _lastError = null;
      notifyListeners();
    }

    final config = _config;
    try {
      final health = await _client.health(config);
      // Settings were saved meanwhile; that save runs its own check.
      if (!config.sameConnectionAs(_config)) return health.isHealthy;

      _lastError = null;
      _applyHealth(health);

      // Only worth asking once the server is answering at all.
      try {
        _model = await _client.model(config);
      } on LocalAiException {
        _model = null;
      }

      notifyListeners();
      return health.isHealthy;
    } on LocalAiException catch (error) {
      if (!config.sameConnectionAs(_config)) return false;

      if (allowRediscovery &&
          error.code == LocalAiException.unreachable &&
          (!automatic || _automaticDiscoveryDue()) &&
          await _rediscover()) {
        return _checkHealth(showChecking: false, allowRediscovery: false);
      }

      _lastError = error;
      _health = null;
      _model = null;
      _status = _statusAfter(error) ?? LocalAiStatus.degraded;
      _pauseMonitoringFor(error);
      notifyListeners();
      return false;
    }
  }

  void _applyHealth(LocalAiHealth health) {
    _health = health;
    _documentsRefused = false;
    _status = health.isHealthy ? LocalAiStatus.ready : LocalAiStatus.degraded;
    if (!health.allowsDocuments && _documentsMode != LocalAiDocumentsMode.off) {
      _documentsMode = LocalAiDocumentsMode.off;
    }
  }

  /// The status an error says the server is in, or null when it says nothing
  /// about the server (a question that was too long, a conflict).
  LocalAiStatus? _statusAfter(LocalAiException error) {
    if (error.code == LocalAiException.unreachable ||
        error.code == LocalAiException.malformed) {
      return LocalAiStatus.unreachable;
    }
    if (error.isConfiguration ||
        error.code == LocalAiException.ollamaUnreachable ||
        error.code == LocalAiException.modelNotFound) {
      return LocalAiStatus.degraded;
    }
    return null;
  }

  // --- monitoring ------------------------------------------------------------

  /// Re-checks the server every 30 seconds while the assistant screen is
  /// visible, so the banner says "unavailable" when the laptop goes to sleep
  /// and "connected" when it is back - before anyone types a question into a
  /// dead connection. Skipped while an answer is running, and paused for as
  /// long as the server asked with `Retry-After`.
  void startMonitoring() {
    if (_monitor != null || _disposed) return;
    _monitor = Timer.periodic(_monitorInterval, (_) => unawaited(_poll()));
  }

  void stopMonitoring() {
    _monitor?.cancel();
    _monitor = null;
  }

  Future<void> _poll() async {
    if (_disposed ||
        _polling ||
        _sending ||
        !_config.isConfigured ||
        _status == LocalAiStatus.checking) {
      return;
    }
    final pausedUntil = _pollPausedUntil;
    if (pausedUntil != null && DateTime.now().isBefore(pausedUntil)) return;

    _polling = true;
    try {
      await _checkHealth(
        showChecking: false,
        allowRediscovery: true,
        automatic: true,
      );
    } catch (error) {
      debugPrint('Local AI: background health check failed ($error)');
    } finally {
      _polling = false;
    }
  }

  void _pauseMonitoringFor(LocalAiException error) {
    final wait = error.retryAfter;
    if (wait != null && wait > Duration.zero) {
      _pollPausedUntil = DateTime.now().add(wait);
    }
  }

  bool _automaticDiscoveryDue() {
    final last = _lastAutomaticDiscovery;
    final now = DateTime.now();
    if (last != null && now.difference(last) < _automaticDiscoveryInterval) {
      return false;
    }
    _lastAutomaticDiscovery = now;
    return true;
  }

  // --- discovery -------------------------------------------------------------

  /// Searches the local network for the server that holds [apiKey] (the key
  /// typed in Settings, or the stored one), probing the port of [address]
  /// (the address typed, or the stored one). See [LocalAiDiscovery.find].
  Future<List<LocalAiDiscoveredServer>> findServers({
    String? apiKey,
    String? address,
  }) {
    final typed = (apiKey ?? '').trim();
    return _discovery.find(
      apiKey: typed.isNotEmpty ? typed : _config.apiKey,
      port: LocalAiDiscovery.portFor(
        (address ?? '').trim().isNotEmpty ? address! : _config.baseUrl,
      ),
    );
  }

  /// Saves a server an administrator picked from [findServers]: the first of
  /// its addresses that answers, with the fingerprint it announced (with
  /// proof) as the pin. A typed [apiKey] is saved along with it; otherwise
  /// the stored key stays where it is. Returns the address saved.
  ///
  /// Throws [LocalAiException] when none of its addresses answers.
  Future<String> useDiscoveredServer(
    LocalAiDiscoveredServer server, {
    String? apiKey,
  }) async {
    final typed = (apiKey ?? '').trim();
    final key = typed.isNotEmpty ? typed : _config.apiKey;
    final pin = server.isSecure ? (server.certSha256 ?? '') : '';

    for (final url in server.baseUrls) {
      if (!await _answers(url, key, pin)) continue;

      if (typed.isNotEmpty) {
        await _settings.save(baseUrl: url, apiKey: typed, certificateFingerprint: pin);
      } else {
        await _settings.saveAddress(baseUrl: url, certificateFingerprint: pin);
      }
      await loadConfig();
      await testConnection();
      return url;
    }

    throw LocalAiException(
      code: LocalAiException.unreachable,
      message:
          '${server.name.isEmpty ? 'The server' : server.name} answered the '
          'search, but none of its addresses (${server.addresses.join(', ')}) '
          'accepted a connection from this device. The firewall on the laptop '
          'may be blocking TCP port ${server.port}.',
    );
  }

  /// Looks for the laptop at a new address after the saved one stopped
  /// answering. Shared between callers, so a health check and a question that
  /// fail together start one search, not two.
  Future<bool> _rediscover() {
    final running = _rediscovery;
    if (running != null) return running;

    // Never throws: a failed search is simply "not found", and the caller
    // reports the original unreachable error.
    final search = _findMovedServer().catchError((Object error) {
      debugPrint('Local AI: looking for the server failed ($error)');
      return false;
    });
    _rediscovery = search;
    search.whenComplete(() => _rediscovery = null).ignore();
    return search;
  }

  /// The rules (docs/API.md, 6): only a server that proved it holds the key,
  /// only with the SAME certificate as the one pinned (never a different
  /// one, whatever it proves), and only at an address that answers. With no
  /// pin yet, an HTTPS server's proven fingerprint becomes the pin.
  ///
  /// Never from HTTPS to plain HTTP. The proof only shows the sender knows
  /// SHA-256 of the key - which is what the laptop's key file stores - so an
  /// HTTP announce "with the pinned fingerprint" proves nothing about the
  /// certificate, and following it would send the key itself unencrypted.
  /// Moving to HTTP is an administrator's decision, made in Settings.
  Future<bool> _findMovedServer() async {
    final config = _config;
    if (!_discovery.isSupported ||
        !config.isConfigured ||
        config.keyId == null) {
      return false;
    }

    final List<LocalAiDiscoveredServer> servers;
    try {
      servers = await _discovery.find(
        apiKey: config.apiKey,
        port: LocalAiDiscovery.portFor(config.baseUrl),
      );
    } catch (error) {
      debugPrint('Local AI: discovery failed ($error)');
      return false;
    }

    final secureOnly = config.isPinned || config.isHttps;
    for (final server in servers) {
      if (secureOnly && !server.isSecure) continue;
      final announced = server.certSha256 ?? '';
      if (config.isPinned && announced != config.certificateFingerprint) {
        continue;
      }
      final pin = config.isPinned
          ? config.certificateFingerprint
          : (server.isSecure ? announced : '');

      for (final url in server.baseUrls) {
        if (url == config.baseUrl) continue;
        if (!await _answers(url, config.apiKey, pin)) continue;

        // An administrator saved something else meanwhile: theirs wins.
        if (_disposed || !config.sameConnectionAs(_config)) return false;

        try {
          await _settings.saveAddress(baseUrl: url, certificateFingerprint: pin);
        } catch (error) {
          debugPrint('Local AI: could not save the new server address ($error)');
          return false;
        }
        await loadConfig();
        _notice =
            'The AI server moved to ${Uri.tryParse(url)?.host ?? url}; '
            'reconnected.';
        notifyListeners();
        return true;
      }
    }
    return false;
  }

  Future<bool> _answers(String baseUrl, String apiKey, String pin) async {
    try {
      await _client.health(
        LocalAiConfig(
          baseUrl: baseUrl,
          apiKey: apiKey,
          certificateFingerprint: pin,
          source: LocalAiConfigSource.device,
        ),
      );
      return true;
    } on LocalAiException {
      return false;
    }
  }

  // --- asking ----------------------------------------------------------------

  /// A conservative token count for [text], to refuse an over-long question
  /// in the app instead of sending it to be refused.
  ///
  /// The server's own estimate (shared/tokens.ts) splits text the same way
  /// and is mirrored here piece for piece, so digits and punctuation (one
  /// token each - a pasted list of serial numbers is mostly these), Brahmic
  /// scripts and encoded runs are counted as the server counts them. Every
  /// rate is the server's or higher: about three characters per token for
  /// English words (the server uses 4.5) and one token per other letter (the
  /// server uses 0.85), with the same 1.1 safety factor. The result is never
  /// below the server's, so a question this passes is never refused as too
  /// long; erring high only refuses long English questions somewhat early.
  static int estimateTokens(String text) {
    var tokens = 0.0;
    var rest = 0;
    for (final match in _encodedRun.allMatches(text)) {
      final run = match[0]!;
      if (!run.contains(_digit) ||
          !run.contains(_lower) ||
          !run.contains(_upper)) {
        continue;
      }
      tokens += _countPieces(text.substring(rest, match.start));
      tokens += run.length / _encodedCharsPerToken;
      rest = match.end;
    }
    tokens += _countPieces(text.substring(rest));
    return (tokens * _tokenSafetyFactor).ceil();
  }

  static const double _asciiCharsPerWordToken = 3;
  static const double _tokensPerNonAsciiLetter = 1;
  static const double _tokensPerBrahmicChar = 1.25;
  static const double _encodedCharsPerToken = 1.25;
  static const double _tokenSafetyFactor = 1.1;

  static final RegExp _pieces = RegExp(
    r'[A-Za-z]+|\p{L}[\p{L}\p{M}]*|\d|\n+[ \t]*|[ \t]{2,}|\s|\S',
    unicode: true,
  );

  /// Long runs mixing upper case, lower case and digits: base64, a JWT.
  static final RegExp _encodedRun = RegExp(r'[A-Za-z0-9+/_-]{20,}={0,2}');
  static final RegExp _digit = RegExp('[0-9]');
  static final RegExp _lower = RegExp('[a-z]');
  static final RegExp _upper = RegExp('[A-Z]');
  static final RegExp _asciiLetter = RegExp('^[A-Za-z]');
  static final RegExp _letter = RegExp(r'^\p{L}', unicode: true);

  static double _countPieces(String text) {
    var tokens = 0.0;
    for (final match in _pieces.allMatches(text)) {
      final piece = match[0]!;
      final first = piece.runes.first;
      if (first < 128 && _asciiLetter.hasMatch(piece)) {
        tokens += (piece.length / _asciiCharsPerWordToken).ceil();
      } else if (first > 127 && _letter.hasMatch(piece)) {
        final brahmic = first >= 0x0900 && first <= 0x0dff;
        tokens += piece.length *
            (brahmic ? _tokensPerBrahmicChar : _tokensPerNonAsciiLetter);
      } else if (piece == ' ' || piece == '\t') {
        // Merged into the next token, as on the server.
      } else if (first > 0xffff) {
        // Emoji outside the Basic Multilingual Plane; the newest block costs
        // more.
        tokens += first >= 0x1fa70 && first <= 0x1faff ? 3 : 2;
      } else {
        // Digits, punctuation, symbols, joiners, line breaks, indentation.
        tokens += 1;
      }
    }
    return tokens;
  }

  /// Why [question] cannot be sent right now, in words for the person, or
  /// null when it can. The composer asks before clearing the text box, so a
  /// refused question is not lost.
  String? validateQuestion(String question) =>
      _refusalFor(question.trim())?.userMessage;

  LocalAiException? _refusalFor(String text) {
    if (!_config.isConfigured) {
      return const LocalAiException(
        code: LocalAiException.notConfigured,
        message:
            'No Local AI server is configured yet. An administrator can set it '
            'up in Settings > AI Assistant server.',
      );
    }
    // Every question is asked for a signed-in account, and only its own
    // conversation scope keeps it apart from everyone else's. Without one,
    // nothing is sent.
    if (_uid == null) {
      return const LocalAiException(
        code: LocalAiException.notSignedIn,
        message: 'Sign in to ask the AI Assistant.',
      );
    }
    if (_scope.isEmpty) {
      return const LocalAiException(
        code: LocalAiException.notConfigured,
        message:
            'No API key is set for the AI server. An administrator can add one '
            'in Settings > AI Assistant server.',
      );
    }

    final limit = _model?.maxMessageTokens ?? 0;
    if (limit > 0) {
      final estimate = estimateTokens(text);
      if (estimate > limit) {
        return LocalAiException(
          code: LocalAiException.messageTooLong,
          message:
              'This question is too long for the AI model (about $estimate '
              'tokens; the limit is $limit). Please shorten it or split it '
              'into parts.',
        );
      }
    }
    return null;
  }

  /// Sends [question] and streams the answer into [messages].
  ///
  /// Before anything is sent, the inventory data for the question is read
  /// through the context service, under the signed-in account's own
  /// permissions. Then one question is asked, and at most one retry is made
  /// for each thing the app can fix by itself: documents the key may not use,
  /// data too large for the model, a conversation the server no longer has,
  /// and a laptop that moved to another address.
  Future<void> send(String question) async {
    final text = question.trim();
    if (text.isEmpty || _sending) return;

    final refusal = _refusalFor(text);
    if (refusal != null) {
      _lastError = refusal;
      _notice = refusal.userMessage;
      if (!_config.isConfigured) _status = LocalAiStatus.notConfigured;
      notifyListeners();
      return;
    }

    // Everything below belongs to this generation of the conversation. If
    // the account changes (or the conversation is cleared) while the answer
    // is on its way, the rest is dropped rather than shown to whoever is
    // signed in next.
    final generation = _generation;
    bool current() => generation == _generation && !_disposed;

    final scope = _scope;
    final previousQuestion = _lastUserQuestion();

    _lastError = null;
    _sending = true;
    _stopRequested = false;
    _stopSignal = Completer<void>();
    _messages.add(
      LocalAiMessage(
        id: 'u${DateTime.now().microsecondsSinceEpoch}',
        role: 'user',
        content: text,
      ),
    );
    final answerIndex = _messages.length;
    _messages.add(
      _pending(progress: _contextService != null ? _readingProgress : null),
    );
    notifyListeners();

    try {
      final budget = math.min(
        _model?.maxAppContextTokens ?? fallbackMaxAppContextTokens,
        preferredContextTokens,
      );
      var appContext = await _unlessStopped<LocalAiAppContext?>(
        _contextFor(text, previousQuestion, budget),
        null,
      );
      if (!current()) return;

      // A plain lookup the app could answer exactly by itself, from these
      // same records: shown at once, and the model is not asked. On the
      // laptop's CPU that is the difference between half a minute and no
      // wait at all, for an answer that is the same figure either way. A
      // Stop pressed while the records were read is still a stop, below.
      final direct = appContext?.directAnswer?.trim() ?? '';
      if (direct.isNotEmpty && !_stopRequested) {
        _setAnswer(
          answerIndex,
          LocalAiMessage(
            id: 'a${DateTime.now().microsecondsSinceEpoch}',
            role: 'assistant',
            content: direct,
            answeredByApp: true,
            appContext: LocalAiAppContextUsage(
              used: true,
              source: appContext!.source,
              retrievedAt: appContext.retrievedAt,
              sections: appContext.sections.length,
              tokens: 0,
            ),
          ),
        );
        return;
      }

      var documents = documentsAllowed
          ? _documentsMode
          : LocalAiDocumentsMode.off;
      var retriedScope = false;
      var retriedContext = false;
      var retriedConversation = false;
      var retriedDiscovery = false;

      while (true) {
        if (_stopRequested) {
          _setAnswer(answerIndex, _stopped(''));
          break;
        }

        _setAnswer(answerIndex, _pending());
        notifyListeners();

        final sentConversation = _conversationId;
        final attempt = await _attempt(
          text: text,
          scope: scope,
          documents: documents,
          appContext: appContext,
          generation: generation,
          answerIndex: answerIndex,
        );
        if (!current() || attempt.abandoned) return;

        final error = attempt.error;
        if (error == null) break;

        // Pressing Stop and then losing the connection is still a stop.
        if (_stopRequested) {
          _setAnswer(answerIndex, _stopped(attempt.content));
          break;
        }

        // Retries only before any of the answer has been shown: a second
        // answer after half of a first would read as the model changing its
        // mind.
        if (!attempt.sawDelta) {
          if (error.code == LocalAiException.forbiddenScope &&
              documents != LocalAiDocumentsMode.off &&
              !retriedScope) {
            retriedScope = true;
            documents = LocalAiDocumentsMode.off;
            _documentsMode = LocalAiDocumentsMode.off;
            _documentsRefused = true;
            continue;
          }

          if (error.code == LocalAiException.contextTooLarge &&
              appContext != null &&
              !retriedContext) {
            retriedContext = true;
            _setAnswer(answerIndex, _pending(progress: _readingProgress));
            notifyListeners();
            appContext = await _unlessStopped<LocalAiAppContext?>(
              _contextFor(text, previousQuestion, math.max(1, budget ~/ 2)),
              null,
            );
            if (!current()) return;
            continue;
          }

          // The server lost the conversation (its history was cleared, or
          // this scope changed on the server side). Ask again as a new one
          // rather than leave the person stuck on a dead id.
          if (error.code == LocalAiException.conversationNotFound &&
              sentConversation != null &&
              !retriedConversation) {
            retriedConversation = true;
            _conversationId = null;
            continue;
          }

          if (error.code == LocalAiException.unreachable && !retriedDiscovery) {
            retriedDiscovery = true;
            _setAnswer(answerIndex, _pending(progress: _searchingProgress));
            notifyListeners();
            // The search itself carries on if Stop cuts this wait short: a
            // laptop found at a new address is worth saving either way.
            final moved = await _unlessStopped(_rediscover(), false);
            if (!current()) return;
            if (_stopRequested) {
              _setAnswer(answerIndex, _stopped(attempt.content));
              break;
            }
            if (moved) continue;
          }
        }

        _fail(answerIndex, error, attempt.content);
        break;
      }
    } catch (error) {
      // Nothing above is expected to throw. If something does, the bubble
      // must still end rather than spin for ever.
      debugPrint('Local AI: the question failed unexpectedly ($error)');
      if (current()) {
        _fail(
          answerIndex,
          const LocalAiException(
            code: LocalAiException.internalError,
            message: 'Something went wrong in the app while asking. Please try again.',
          ),
          '',
        );
      }
    } finally {
      if (current()) {
        _active = null;
        _sending = false;
        _stopRequested = false;
        _stopSignal = null;
        notifyListeners();
      }
    }
  }

  /// [work], or [onStop] as soon as Stop is pressed, whichever comes first.
  /// [work] is not cancelled; its result (or error) is simply not waited for.
  Future<T> _unlessStopped<T>(Future<T> work, T onStop) {
    final signal = _stopSignal;
    if (signal == null) return work;
    return Future.any([work, signal.future.then((_) => onStop)]);
  }

  /// One request and its stream, into the answer bubble.
  Future<_Attempt> _attempt({
    required String text,
    required String scope,
    required LocalAiDocumentsMode documents,
    required LocalAiAppContext? appContext,
    required int generation,
    required int answerIndex,
  }) async {
    final stream = _client.ask(
      config: _config,
      message: text,
      scope: scope,
      conversationId: _conversationId,
      documents: documents,
      appContext: appContext?.toJson(),
    );
    _active = stream;

    final buffer = StringBuffer();
    LocalAiDocumentsUsage? searched;
    var sawDelta = false;
    var finished = false;

    try {
      await for (final event in stream.events) {
        if (generation != _generation || _disposed) {
          stream.abort();
          return const _Attempt.abandoned();
        }

        switch (event) {
          case LocalAiStartEvent(:final conversationId):
            if (conversationId.isNotEmpty) _conversationId = conversationId;

          case LocalAiSourcesEvent(:final documents):
            searched = documents;

          case LocalAiDeltaEvent(:final text):
            sawDelta = true;
            buffer.write(text);
            _setAnswer(
              answerIndex,
              LocalAiMessage(
                id: 'pending',
                role: 'assistant',
                content: buffer.toString(),
                status: 'streaming',
                sources: searched?.sources ?? const [],
              ),
            );
            notifyListeners();

          case LocalAiDoneEvent(:final answer):
            finished = true;
            if (answer.conversationId.isNotEmpty) {
              _conversationId = answer.conversationId;
            }
            final usage = answer.documents ?? searched;
            _setAnswer(
              answerIndex,
              LocalAiMessage(
                id: answer.messageId.isNotEmpty
                    ? answer.messageId
                    : 'a${DateTime.now().microsecondsSinceEpoch}',
                role: 'assistant',
                // A stopped answer keeps what it managed to say.
                content: answer.content.isNotEmpty
                    ? answer.content
                    : buffer.toString(),
                status: answer.status == 'stopped' ? 'stopped' : 'done',
                sources: usage?.sources ?? const [],
                documentsNote: usage?.note ?? '',
                appContext: answer.appContext,
              ),
            );
            // A finished answer is the best evidence there is that the
            // server works, whatever the banner last said.
            _status = LocalAiStatus.ready;
            _lastError = null;

          case LocalAiErrorEvent(:final error):
            return _Attempt(
              error: error,
              sawDelta: sawDelta,
              content: buffer.toString(),
            );

          case LocalAiPingEvent() || LocalAiUnknownEvent():
            break;
        }
      }
    } on LocalAiException catch (error) {
      if (generation != _generation || _disposed) {
        return const _Attempt.abandoned();
      }
      return _Attempt(error: error, sawDelta: sawDelta, content: buffer.toString());
    } finally {
      if (identical(_active, stream)) _active = null;
    }

    if (generation != _generation || _disposed) return const _Attempt.abandoned();
    if (finished) return const _Attempt();

    // Ended without `done`: the connection was dropped after Stop (the
    // server has saved the partial answer as stopped), or the stream broke
    // off in a way the contract does not allow.
    if (_stopRequested) {
      _setAnswer(
        answerIndex,
        _stopped(buffer.toString(), sources: searched?.sources ?? const []),
      );
      return const _Attempt();
    }
    return _Attempt(
      error: const LocalAiException(
        code: LocalAiException.malformed,
        message:
            'The AI server ended the answer without finishing it. Please ask '
            'again.',
      ),
      sawDelta: sawDelta,
      content: buffer.toString(),
    );
  }

  /// The inventory data for one question, or null when no context service is
  /// wired in (then no `appContext` is sent at all).
  ///
  /// Never throws and never takes longer than the context timeout: when the
  /// data cannot be read, the question still goes, with a note saying so, so
  /// the model answers "I could not retrieve that" instead of guessing.
  Future<LocalAiAppContext?> _contextFor(
    String question,
    String? previousQuestion,
    int budgetTokens,
  ) async {
    final service = _contextService;
    if (service == null) return null;

    try {
      final context = await service
          .contextFor(
            question: question,
            uid: _uid,
            previousQuestion: previousQuestion,
            budgetTokens: budgetTokens,
          )
          .timeout(_contextTimeout);
      return context ?? _unreadableContext();
    } catch (error) {
      // The type only: a message could quote the data it failed on.
      debugPrint(
        'Local AI: the inventory data could not be read (${error.runtimeType})',
      );
      return _unreadableContext();
    }
  }

  static LocalAiAppContext _unreadableContext() => LocalAiAppContext(
    source: LocalAiAppContext.defaultSource,
    retrievedAt: DateTime.now(),
    scope: '',
    sections: const [],
    notes: const [unreadableContextNote],
  );

  /// The question before the one being asked, in this conversation.
  String? _lastUserQuestion() {
    for (var i = _messages.length - 1; i >= 0; i--) {
      if (_messages[i].isUser) return _messages[i].content;
    }
    return null;
  }

  LocalAiMessage _pending({String? progress}) => LocalAiMessage(
    id: 'pending',
    role: 'assistant',
    content: '',
    status: 'streaming',
    progress: progress,
  );

  LocalAiMessage _stopped(
    String content, {
    List<LocalAiSource> sources = const [],
  }) => LocalAiMessage(
    id: 's${DateTime.now().microsecondsSinceEpoch}',
    role: 'assistant',
    content: content,
    status: 'stopped',
    sources: sources,
  );

  void _setAnswer(int index, LocalAiMessage message) {
    if (index < _messages.length) _messages[index] = message;
  }

  void _fail(int index, LocalAiException error, String content) {
    _lastError = error;
    final status = _statusAfter(error);
    if (status != null) _status = status;
    _pauseMonitoringFor(error);
    _setAnswer(
      index,
      LocalAiMessage(
        id: 'e${DateTime.now().microsecondsSinceEpoch}',
        role: 'assistant',
        content: content,
        status: 'error',
        error: error.userMessage,
      ),
    );
  }

  /// Stops the answer being written, keeping what it has said so far.
  ///
  /// See [LocalAiStream.stop]: the server is told and its own `done` (status
  /// `stopped`) is waited for, with the connection dropped only as a
  /// fallback. While the inventory data is still being read, nothing has been
  /// sent yet and the question is simply not sent. Never throws.
  Future<void> stop() async {
    if (!_sending || _stopRequested) return;

    _stopRequested = true;
    final signal = _stopSignal;
    if (signal != null && !signal.isCompleted) signal.complete();
    notifyListeners();

    final active = _active;
    if (active == null) return;

    try {
      await active.stop(grace: _stopGrace);
    } catch (error) {
      debugPrint('Local AI: stopping the answer failed ($error)');
      active.abort();
    }
  }

  /// Forgets the conversation on this device and, when the server knows it,
  /// deletes it there too. Never throws: the conversation is gone from the
  /// screen either way, and a server that cannot be reached is not the
  /// person's problem here.
  Future<void> clearConversation() async {
    final conversationId = _conversationId;
    final scope = _scope;
    final config = _config;

    _discardConversation();
    _contextService?.reset();
    notifyListeners();

    if (conversationId == null || !config.isConfigured || scope.isEmpty) return;

    try {
      await _client.deleteConversation(
        config: config,
        conversationId: conversationId,
        scope: scope,
      );
    } on LocalAiException catch (error) {
      debugPrint('Local AI: could not delete the conversation (${error.code})');
    } catch (error) {
      debugPrint('Local AI: could not delete the conversation ($error)');
    }
  }
}

/// How one request of [LocalAiProvider.send] ended.
class _Attempt {
  const _Attempt({this.error, this.sawDelta = false, this.content = ''})
    : abandoned = false;

  /// The conversation was thrown away while it ran; nothing may be shown.
  const _Attempt.abandoned()
    : error = null,
      sawDelta = false,
      content = '',
      abandoned = true;

  /// Null when the answer finished (or was stopped).
  final LocalAiException? error;

  /// Some of the answer had already been shown.
  final bool sawDelta;

  /// What had arrived before [error].
  final String content;

  final bool abandoned;
}
