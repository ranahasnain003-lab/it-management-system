/// Types of the Local AI server's `/api/v1` contract.
///
/// These mirror the server's own contract (docs/API.md and shared/api.ts on
/// the server) exactly and are not invented here: the field names, the error
/// codes and the stream event names all come from that document. Anything the
/// server may add later is ignored rather than rejected, because the contract
/// says clients must tolerate unknown event types.
library;

import 'package:flutter/foundation.dart';

// =============================================================================
// ERRORS
// =============================================================================

/// A refusal from the Local AI server, carrying the machine-readable code.
///
/// The code is what the app switches on; the message is the server's own
/// wording and is shown as it is. The two are kept apart because the message
/// may change without the meaning changing.
@immutable
class LocalAiException implements Exception {
  const LocalAiException({
    required this.code,
    required this.message,
    this.status,
    this.retryAfter,
  });

  /// One of the server's `ApiV1ErrorCode` values, or one of the client-side
  /// codes below when the request never reached the server.
  final String code;

  final String message;

  /// HTTP status, absent when the failure happened before a response.
  final int? status;

  /// From the `Retry-After` header, for [rateLimited] and [serverBusy].
  final Duration? retryAfter;

  // --- codes the server sends ------------------------------------------------

  /// Bad JSON, a bad field, or a malformed `X-Conversation-Scope`. Always a
  /// bug in this app rather than something the person can fix.
  static const String invalidRequest = 'INVALID_REQUEST';

  /// No API key was presented.
  static const String unauthorized = 'UNAUTHORIZED';

  /// A key was presented and rejected. Distinct from [unauthorized] because
  /// "you have not configured a key" and "your key is wrong" need different
  /// answers from the person reading the screen.
  static const String invalidApiKey = 'INVALID_API_KEY';

  /// The key is valid but lacks the scope for what was asked, e.g. documents.
  static const String forbiddenScope = 'FORBIDDEN_SCOPE';

  /// The request came from an address the server does not serve.
  static const String forbiddenNetwork = 'FORBIDDEN_NETWORK';

  /// A browser page whose origin is not in the server's `API_CORS_ORIGINS`.
  /// Only Flutter Web can meet this one.
  static const String forbiddenOrigin = 'FORBIDDEN_ORIGIN';

  /// No such route: usually an address that points at the wrong server.
  static const String notFound = 'NOT_FOUND';

  static const String rateLimited = 'RATE_LIMITED';
  static const String serverBusy = 'SERVER_BUSY';

  /// The whole request body is over the server's `API_MAX_BODY_KB`.
  static const String payloadTooLarge = 'PAYLOAD_TOO_LARGE';

  static const String messageTooLong = 'MESSAGE_TOO_LONG';

  /// The `appContext` did not fit next to the question. The app sends less
  /// and tries again.
  static const String contextTooLarge = 'CONTEXT_TOO_LARGE';

  static const String conversationNotFound = 'CONVERSATION_NOT_FOUND';
  static const String conflict = 'CONFLICT';
  static const String ollamaUnreachable = 'OLLAMA_UNREACHABLE';
  static const String modelNotFound = 'MODEL_NOT_FOUND';

  /// Ollama failed part-way through an answer.
  static const String ollamaError = 'OLLAMA_ERROR';

  /// The server's conversation history file could not be read or written.
  static const String storageError = 'STORAGE_ERROR';

  static const String internalError = 'INTERNAL_ERROR';

  // --- codes this client raises itself ---------------------------------------

  /// The server could not be reached at all: laptop asleep, Wi-Fi changed,
  /// wrong address. Deliberately distinct from every server code, because
  /// nothing on the server went wrong.
  static const String unreachable = 'SERVER_UNREACHABLE';

  /// The server accepted the request but stopped answering.
  static const String timedOut = 'TIMED_OUT';

  /// A reply arrived that does not match the contract.
  static const String malformed = 'MALFORMED_RESPONSE';

  /// No server address (or no API key) has been configured yet.
  static const String notConfigured = 'NOT_CONFIGURED';

  /// Nobody is signed in to the app. Every question is asked on behalf of a
  /// signed-in account, so without one nothing is sent at all.
  static const String notSignedIn = 'NOT_SIGNED_IN';

  /// True when asking again later might work.
  ///
  /// [conflict] is here because it only means another answer in the same
  /// conversation is still running, and [ollamaError] because Ollama failing
  /// once part-way is usually a load or memory hiccup rather than a setup
  /// problem.
  bool get isTransient =>
      code == unreachable ||
      code == timedOut ||
      code == serverBusy ||
      code == rateLimited ||
      code == conflict ||
      code == ollamaUnreachable ||
      code == ollamaError;

  /// True when the person needs to fix the configuration before anything works.
  ///
  /// [forbiddenScope] counts because only a new key (created with
  /// `--documents`) changes it, and [forbiddenOrigin] because only the
  /// server's `API_CORS_ORIGINS` does.
  bool get isConfiguration =>
      code == notConfigured ||
      code == unauthorized ||
      code == invalidApiKey ||
      code == forbiddenScope ||
      code == forbiddenNetwork ||
      code == forbiddenOrigin ||
      code == modelNotFound;

  /// The message as the person should read it: the server's wording, plus
  /// when to try again if the server said so. "Busy" alone leaves people
  /// hammering the button; "try again in 20 seconds" does not.
  String get userMessage {
    final wait = retryAfter;
    if (wait == null || wait <= Duration.zero) return message;

    final seconds = wait.inSeconds;
    final when = seconds < 90
        ? '$seconds second${seconds == 1 ? '' : 's'}'
        : '${(seconds / 60).ceil()} minutes';
    final base = message.trimRight();
    final separator = base.endsWith('.') || base.isEmpty ? ' ' : '. ';
    return '$base${separator}Try again in $when.'.trim();
  }

  @override
  String toString() => 'LocalAiException($code): $message';
}

// =============================================================================
// HEALTH AND MODEL
// =============================================================================

/// `GET /api/v1/health`.
@immutable
class LocalAiHealth {
  const LocalAiHealth({
    required this.status,
    required this.ollamaReachable,
    required this.ollamaVersion,
    required this.modelName,
    required this.modelAvailable,
    required this.embeddingModel,
    required this.embeddingAvailable,
    required this.indexedDocuments,
    required this.queueRunning,
    required this.queueWaiting,
    required this.problem,
    this.problemCode,
    this.clientId = '',
    this.clientName = '',
    this.clientScopes = const [],
    this.hasClientInfo = false,
  });

  /// `ok` or `degraded`. The server answers 200 either way, so this - not the
  /// status code - is what says whether the model can actually answer.
  final String status;

  final bool ollamaReachable;
  final String ollamaVersion;
  final String modelName;
  final bool modelAvailable;
  final String embeddingModel;
  final bool embeddingAvailable;
  final int indexedDocuments;
  final int queueRunning;
  final int queueWaiting;

  /// Set when something is wrong even though the request succeeded.
  final String? problem;

  /// `OLLAMA_UNREACHABLE` or `MODEL_NOT_FOUND` alongside [problem].
  final String? problemCode;

  /// The public id of the API key this app uses (the `<id>` in
  /// `lai_<id>_<secret>`), as the server knows it.
  final String clientId;

  /// The name the key was created with on the laptop.
  final String clientName;

  /// What the key may do: `chat`, and `documents` when it was created with
  /// `--documents`.
  final List<String> clientScopes;

  /// False for a server that predates `client` in the health reply. Its
  /// scopes are then unknown, and the app assumes the narrowest (chat only).
  final bool hasClientInfo;

  bool get isHealthy => status == 'ok' && ollamaReachable && modelAvailable;

  /// Whether the key may ask for the laptop's document library. Asking
  /// without this scope is refused with 403 `FORBIDDEN_SCOPE`, so the app only
  /// offers documents when this is true.
  bool get allowsDocuments => clientScopes.contains('documents');

  factory LocalAiHealth.fromJson(Map<String, dynamic> json) {
    final ollama = _mapAt(json, 'ollama');
    final model = _mapAt(json, 'model');
    final documents = _mapAt(json, 'documents');
    final queue = _mapAt(json, 'queue');
    final problem = json['problem'];
    final client = json['client'];
    final clientMap = client is Map ? Map<String, dynamic>.from(client) : null;
    final scopes = clientMap?['scopes'];

    return LocalAiHealth(
      status: _string(json['status'], fallback: 'degraded'),
      ollamaReachable: ollama['reachable'] == true,
      ollamaVersion: _string(ollama['version']),
      modelName: _string(model['name']),
      modelAvailable: model['available'] == true,
      embeddingModel: _string(documents['embeddingModel']),
      embeddingAvailable: documents['available'] == true,
      indexedDocuments: _int(documents['indexedDocuments']),
      queueRunning: _int(queue['running']),
      queueWaiting: _int(queue['waiting']),
      problem: problem is Map
          ? _string(problem['message'], fallback: _string(problem['code']))
          : null,
      problemCode: problem is Map ? _string(problem['code']) : null,
      clientId: _string(clientMap?['id']),
      clientName: _string(clientMap?['name']),
      clientScopes: scopes is List
          ? List.unmodifiable(scopes.whereType<String>())
          : const [],
      hasClientInfo: clientMap != null,
    );
  }
}

/// `GET /api/v1/model`.
@immutable
class LocalAiModelInfo {
  const LocalAiModelInfo({
    required this.model,
    required this.available,
    required this.parameterSize,
    required this.quantization,
    required this.contextWindow,
    required this.maxMessageTokens,
    this.replyReserveTokens = 0,
    this.thinking = false,
    this.embeddingModel = '',
    this.embeddingAvailable = false,
    this.maxAppContextTokens,
  });

  final String model;
  final bool available;
  final String parameterSize;
  final String quantization;
  final int contextWindow;

  /// The longest single question the server will accept, in tokens. Used to
  /// refuse an over-long message in the app rather than spend a request
  /// discovering the server refuses it.
  final int maxMessageTokens;

  final int replyReserveTokens;
  final bool thinking;
  final String embeddingModel;
  final bool embeddingAvailable;

  /// The largest `appContext` the server accepts next to a short question,
  /// in its own token estimate. Null for a server that does not report it,
  /// in which case the app assumes a safe default.
  final int? maxAppContextTokens;

  factory LocalAiModelInfo.fromJson(Map<String, dynamic> json) {
    final maxContext = json['maxAppContextTokens'];

    return LocalAiModelInfo(
      model: _string(json['model']),
      available: json['available'] == true,
      parameterSize: _string(json['parameterSize']),
      quantization: _string(json['quantization']),
      contextWindow: _int(json['contextWindow']),
      maxMessageTokens: _int(json['maxMessageTokens']),
      replyReserveTokens: _int(json['replyReserveTokens']),
      thinking: json['thinking'] == true,
      embeddingModel: _string(json['embeddingModel']),
      embeddingAvailable: json['embeddingAvailable'] == true,
      maxAppContextTokens: maxContext is num && maxContext > 0
          ? maxContext.toInt()
          : null,
    );
  }
}

// =============================================================================
// DOCUMENTS (RAG)
// =============================================================================

/// How the server's own document library should be used for one question.
///
/// Retrieval happens entirely on the server. The app never searches, never
/// embeds and never holds an index: it only says which mode to use.
enum LocalAiDocumentsMode {
  off('off'),
  auto('auto'),
  only('only');

  const LocalAiDocumentsMode(this.wire);

  /// The string the API expects.
  final String wire;
}

/// One passage the server's retrieval used, for rendering a citation.
@immutable
class LocalAiSource {
  const LocalAiSource({
    required this.n,
    required this.name,
    required this.location,
    required this.snippet,
    required this.score,
  });

  /// The citation number the answer refers to, as [1], [2]…
  final int n;

  final String name;

  /// Where in the document, e.g. "page 2" or "rows 2-40".
  final String location;

  final String snippet;
  final double score;

  factory LocalAiSource.fromJson(Map<String, dynamic> json) {
    return LocalAiSource(
      n: _int(json['n']),
      name: _string(json['name']),
      location: _string(json['location']),
      snippet: _string(json['snippet']),
      score: _double(json['score']),
    );
  }
}

/// What the document search contributed to one answer: the server's
/// `ApiV1Documents`, carried by both the `sources` event and the `done` event.
@immutable
class LocalAiDocumentsUsage {
  const LocalAiDocumentsUsage({
    required this.mode,
    required this.used,
    required this.sources,
    required this.note,
    this.searchedAs = '',
  });

  final String mode;

  /// True when the answer actually drew on the sources.
  final bool used;

  final List<LocalAiSource> sources;

  /// The server's own wording, e.g. that nothing relevant was found.
  final String note;

  /// For a Roman Urdu question: the English query the documents were also
  /// searched with. Empty otherwise.
  final String searchedAs;

  factory LocalAiDocumentsUsage.fromJson(Map<String, dynamic> json) {
    final raw = json['sources'];

    return LocalAiDocumentsUsage(
      mode: _string(json['mode']),
      used: json['used'] == true,
      sources: raw is List
          ? raw
                .whereType<Map>()
                .map((e) => LocalAiSource.fromJson(Map<String, dynamic>.from(e)))
                .toList()
          : const [],
      note: _string(json['note']),
      searchedAs: _string(json['searchedAs']),
    );
  }
}

// =============================================================================
// APP DATA (appContext)
// =============================================================================

/// What the question's `appContext` contributed to an answer, as the `done`
/// event reports it. Only a summary: the data itself is never stored on the
/// server and never comes back.
@immutable
class LocalAiAppContextUsage {
  const LocalAiAppContextUsage({
    required this.used,
    required this.source,
    required this.retrievedAt,
    required this.sections,
    required this.tokens,
  });

  /// The data was given to the model.
  final bool used;

  final String source;

  /// When the app read the data, as the app itself stated it. Null when the
  /// value was missing or unreadable.
  final DateTime? retrievedAt;

  /// Sections the model was given.
  final int sections;

  /// Tokens the data took in the prompt, by the server's estimate.
  final int tokens;

  factory LocalAiAppContextUsage.fromJson(Map<String, dynamic> json) {
    final at = json['retrievedAt'];

    return LocalAiAppContextUsage(
      used: json['used'] == true,
      source: _string(json['source']),
      retrievedAt: at is String ? DateTime.tryParse(at) : null,
      sections: _int(json['sections']),
      tokens: _int(json['tokens']),
    );
  }
}

// =============================================================================
// CHAT
// =============================================================================

/// One turn in a conversation, as the app holds it.
@immutable
class LocalAiMessage {
  const LocalAiMessage({
    required this.id,
    required this.role,
    required this.content,
    this.status = 'done',
    this.sources = const [],
    this.documentsNote = '',
    this.error,
    this.progress,
    this.appContext,
    this.answeredByApp = false,
  });

  final String id;

  /// `user` or `assistant`.
  final String role;

  final String content;

  /// `done`, `stopped`, `error`, or `streaming` while it is still arriving.
  final String status;

  final List<LocalAiSource> sources;
  final String documentsNote;
  final String? error;

  /// What is happening before the first word, e.g. "Reading your inventory
  /// data…". Null shows the default "Thinking…".
  final String? progress;

  /// What the inventory data contributed, from the `done` event.
  final LocalAiAppContextUsage? appContext;

  /// True when the app worked this answer out by itself, from the records,
  /// and the model was not asked (see LocalAiAppContext.directAnswer). The
  /// bubble says so, so an instant answer is never passed off as the
  /// model's, nor the model's as the database's.
  final bool answeredByApp;

  bool get isUser => role == 'user';
  bool get isStreaming => status == 'streaming';
  bool get wasStopped => status == 'stopped';

  /// True when the answer was grounded in this app's own data, which the
  /// bubble says in so many words.
  ///
  /// It takes at least one section of data: a greeting, or a question the
  /// account may not see data for, still sends an `appContext` - a note with
  /// no records - and the server reports that as "used", but nothing in the
  /// answer came from the inventory.
  bool get usedAppData {
    final usage = appContext;
    return usage != null && usage.used && usage.sections > 0;
  }

  LocalAiMessage copyWith({
    String? content,
    String? status,
    List<LocalAiSource>? sources,
    String? documentsNote,
    String? error,
    LocalAiAppContextUsage? appContext,
  }) {
    return LocalAiMessage(
      id: id,
      role: role,
      content: content ?? this.content,
      status: status ?? this.status,
      sources: sources ?? this.sources,
      documentsNote: documentsNote ?? this.documentsNote,
      error: error ?? this.error,
      progress: progress,
      appContext: appContext ?? this.appContext,
      answeredByApp: answeredByApp,
    );
  }
}

/// The finished result of one answer, from the `done` event or the
/// non-streaming body.
@immutable
class LocalAiAnswer {
  const LocalAiAnswer({
    required this.conversationId,
    required this.messageId,
    required this.content,
    required this.status,
    required this.model,
    required this.documents,
    this.appContext,
  });

  final String conversationId;
  final String messageId;
  final String content;

  /// `done` or `stopped`. A stopped answer still arrives as a `done` event.
  final String status;

  final String model;
  final LocalAiDocumentsUsage? documents;

  /// Null when the question carried no `appContext`.
  final LocalAiAppContextUsage? appContext;

  factory LocalAiAnswer.fromJson(Map<String, dynamic> json) {
    final message = _mapAt(json, 'message');
    final documents = json['documents'];
    final appContext = json['appContext'];

    return LocalAiAnswer(
      conversationId: _string(json['conversationId']),
      messageId: _string(message['id'], fallback: _string(json['messageId'])),
      content: _string(message['content']),
      status: _string(message['status'], fallback: 'done'),
      model: _string(json['model']),
      documents: documents is Map
          ? LocalAiDocumentsUsage.fromJson(Map<String, dynamic>.from(documents))
          : null,
      appContext: appContext is Map
          ? LocalAiAppContextUsage.fromJson(Map<String, dynamic>.from(appContext))
          : null,
    );
  }
}

// =============================================================================
// STREAM EVENTS
// =============================================================================

/// One line of the `application/x-ndjson` stream.
///
/// The contract's event names are `start`, `sources`, `delta`, `done`,
/// `error` and `ping`. Anything else is represented as [unknown] and ignored
/// by the caller, which the contract requires: the server may add events and
/// old clients must not break.
sealed class LocalAiEvent {
  const LocalAiEvent();

  /// Parses one decoded line, never throwing: a line this client does not
  /// understand becomes [LocalAiUnknownEvent] rather than an error, because
  /// one unrecognised line must not abandon an answer in progress.
  factory LocalAiEvent.fromJson(Map<String, dynamic> json) {
    switch (json['type']) {
      case 'start':
        return LocalAiStartEvent(
          conversationId: _string(json['conversationId']),
          messageId: _string(json['messageId']),
          model: _string(json['model']),
          title: _string(json['title']),
        );
      case 'delta':
        return LocalAiDeltaEvent(_string(json['text']));
      case 'sources':
        // {"type":"sources","documents":{mode,used,sources,note,searchedAs?}}
        // - the search summary is nested, exactly as in the `done` event.
        return LocalAiSourcesEvent(
          LocalAiDocumentsUsage.fromJson(_mapAt(json, 'documents')),
        );
      case 'done':
        return LocalAiDoneEvent(LocalAiAnswer.fromJson(json));
      case 'error':
        final error = _mapAt(json, 'error');
        return LocalAiErrorEvent(
          LocalAiException(
            code: _string(error['code'], fallback: LocalAiException.malformed),
            message: _string(
              error['message'],
              fallback: 'The Local AI server reported an error.',
            ),
          ),
        );
      case 'ping':
        return const LocalAiPingEvent();
      default:
        return LocalAiUnknownEvent(_string(json['type'], fallback: '?'));
    }
  }
}

class LocalAiStartEvent extends LocalAiEvent {
  const LocalAiStartEvent({
    required this.conversationId,
    required this.messageId,
    required this.model,
    this.title = '',
  });

  final String conversationId;
  final String messageId;
  final String model;
  final String title;
}

class LocalAiDeltaEvent extends LocalAiEvent {
  const LocalAiDeltaEvent(this.text);

  final String text;
}

/// The document search for this answer, sent before the first delta and only
/// when documents were searched.
class LocalAiSourcesEvent extends LocalAiEvent {
  const LocalAiSourcesEvent(this.documents);

  final LocalAiDocumentsUsage documents;

  List<LocalAiSource> get sources => documents.sources;
}

class LocalAiDoneEvent extends LocalAiEvent {
  const LocalAiDoneEvent(this.answer);

  final LocalAiAnswer answer;
}

class LocalAiErrorEvent extends LocalAiEvent {
  const LocalAiErrorEvent(this.error);

  final LocalAiException error;
}

/// Sent after 15s of silence so the connection is not dropped by a NAT while
/// the model is still thinking. Carries nothing and is only a sign of life.
class LocalAiPingEvent extends LocalAiEvent {
  const LocalAiPingEvent();
}

/// An event this version of the app does not know. Ignored on purpose.
class LocalAiUnknownEvent extends LocalAiEvent {
  const LocalAiUnknownEvent(this.type);

  final String type;
}

// =============================================================================
// SMALL READERS
// =============================================================================
//
// Every field is read defensively. A local server that is mid-upgrade, or an
// answer truncated by a dropped Wi-Fi connection, must not crash the screen.

Map<String, dynamic> _mapAt(Map<String, dynamic> json, String key) {
  final value = json[key];
  return value is Map ? Map<String, dynamic>.from(value) : const {};
}

String _string(Object? value, {String fallback = ''}) {
  if (value is String) return value;
  if (value == null) return fallback;
  return value.toString();
}

int _int(Object? value) {
  if (value is int) return value;
  if (value is num) return value.toInt();
  if (value is String) return int.tryParse(value) ?? 0;
  return 0;
}

double _double(Object? value) {
  if (value is double) return value;
  if (value is num) return value.toDouble();
  if (value is String) return double.tryParse(value) ?? 0;
  return 0;
}
