import 'dart:async';
import 'dart:convert';

import 'package:firebase_app_check/firebase_app_check.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

import 'assistant_actions.dart';

/// What the assistant backend replied.
@immutable
class BackendReply {
  const BackendReply({
    required this.text,
    this.intent,
    this.needsClarification = false,
    this.model = '',
    this.provider = '',
  });

  /// The answer to show, already in the language the user wrote in.
  final String text;

  /// Set when the message read as an instruction rather than a question.
  final AssistantIntent? intent;

  /// True when [text] is a question back to the user rather than an answer.
  final bool needsClarification;

  final String model;
  final String provider;
}

/// A refusal from the assistant backend, carrying the reason it gave.
///
/// Only `resource-exhausted` is ever shown to the user, as a note that their
/// allowance is spent. Every other refusal stays invisible: the locally
/// computed answer is already correct, so there is nothing to apologise for.
@immutable
class AssistantBackendException implements Exception {
  const AssistantBackendException({required this.code, required this.message});

  final String code;
  final String message;

  @override
  String toString() => 'AssistantBackendException($code): $message';
}

/// The seam the assistant panel talks to.
///
/// Exists so tests can drive the whole natural-language flow - questions in
/// English, Urdu and Roman Urdu, follow-ups, proposed actions - without a
/// network, a key or a deployed backend.
abstract class AssistantBackend {
  /// Whether this build may call the model at all.
  bool get enabled;

  /// Answers [question] from [facts], or returns null to use the answer the
  /// app computed locally.
  ///
  /// [onFailed] is called with a readable reason whenever a call that was
  /// supposed to happen did not produce an answer. It fires only for a build
  /// that has the model switched on, so a deliberately offline build stays
  /// silent, and it exists so a broken deployment is visible to the user
  /// instead of looking identical to a working one.
  Future<BackendReply?> ask({
    required String question,
    required Map<String, dynamic> facts,
    String groundedAnswer = '',
    List<Map<String, dynamic>> history = const [],
    List<String> capabilities = const [],
    void Function(String notice)? onLimited,
    void Function(String reason)? onFailed,
  });
}

/// A backend that answers in words only: it never reads a message as an
/// instruction, so its replies carry no [BackendReply.intent].
///
/// With one of these the assistant keeps planning actions itself, exactly as
/// it does with no model at all, and keeps its own exact wording for
/// proposals, refusals and outcomes. Only questions are answered by the
/// model. Handing a half-understood command to a model that cannot hand it
/// back as an intent would quietly turn "transfer this" into a chat reply.
abstract interface class WordsOnlyBackend implements AssistantBackend {}

/// A backend that can show its answer while it is still being written.
///
/// Qwen3 on a CPU-only laptop writes about nine tokens (word pieces) a second,
/// so a typical answer takes 10-30 seconds to finish. Shown only once it is complete, that
/// is 10-30 seconds of typing dots; shown as it arrives, the first words
/// appear as soon as the model has read the question. Nothing about the
/// answer itself changes - only when the user starts seeing it.
///
/// A separate interface rather than a new parameter on [AssistantBackend.ask],
/// so backends that answer in one piece - and every test fake written against
/// [AssistantBackend] - are untouched and simply keep showing the dots.
abstract interface class StreamingBackend implements AssistantBackend {
  /// Exactly [AssistantBackend.ask], and additionally calls [onPartial] with
  /// the answer written so far, each time more of it arrives.
  ///
  /// [onPartial] is given the whole answer so far, not the latest piece, so
  /// the caller only ever has to show what it was last given. It is a preview
  /// and nothing more: the returned [BackendReply] is the answer. That may
  /// differ from the last preview, and when the model fails part-way through
  /// it is null, so the caller shows its own answer instead - as it would
  /// have without the preview. [onPartial] is never called after the returned
  /// future completes.
  Future<BackendReply?> askStreaming({
    required String question,
    required Map<String, dynamic> facts,
    String groundedAnswer = '',
    List<Map<String, dynamic>> history = const [],
    List<String> capabilities = const [],
    void Function(String notice)? onLimited,
    void Function(String reason)? onFailed,
    required void Function(String partialText) onPartial,
  });
}

/// The natural-language layer over the assistant, served by the
/// `psba-inventory-assistant` Cloudflare Worker.
///
/// **Disabled by default.** With [isEnabled] false the app has no external
/// dependency at all: every answer, figure and action comes from the on-device
/// grounded engine, which reads the account's permission-filtered inventory
/// directly. Turning it on adds natural-language understanding on top; it
/// never replaces the grounding.
///
/// The backend is a Cloudflare Worker rather than a Cloud Function because
/// Cloud Functions are not offered on Firebase's free Spark plan, while the
/// Workers free plan and the Gemini API free tier both need no billing
/// account at all.
///
/// Moving hosts changed nothing about the security model. The Gemini API key
/// lives only in Cloudflare's secret store; no key, token or endpoint secret
/// exists in this app. The Worker answers nobody without a valid Firebase ID
/// token AND a valid App Check token, each verified against Google's own
/// public keys, so the endpoint being publicly reachable buys an attacker
/// nothing. Only facts the account has already read from Firestore are sent.
/// If the backend is unreachable, times out, refuses, or is simply not
/// configured for this build, [ask] returns null and the locally computed
/// answer is used unchanged.
class AiBackend implements AssistantBackend {
  const AiBackend();

  /// Where the Worker is deployed.
  ///
  /// Not a secret - it is a public endpoint that refuses anyone without a
  /// verified Firebase identity - but it is not in the repository either, so
  /// a build has to name it:
  ///   --dart-define=AI_PROXY_URL=https://NAME.SUBDOMAIN.workers.dev
  static const String proxyUrl =
      String.fromEnvironment('AI_PROXY_URL', defaultValue: '');

  /// Whether this build may call the language model at all.
  ///
  /// Off by default, so the app has no external dependency: the assistant
  /// answers entirely from the on-device grounded engine and never opens a
  /// network call. What is lost is natural-language understanding of
  /// free-form questions - every figure, answer and action already comes from
  /// the local engine either way.
  ///
  /// Turn it on only once the Worker is deployed, with both defines:
  ///   --dart-define=AI_LLM_ENABLED=true
  ///   --dart-define=AI_PROXY_URL=https://NAME.SUBDOMAIN.workers.dev
  static const bool isEnabled =
      bool.fromEnvironment('AI_LLM_ENABLED', defaultValue: false);

  /// True only when this build is both allowed to call out and told where to.
  @override
  bool get enabled => isEnabled && proxyUrl.isNotEmpty;

  /// The deadline for the whole round trip.
  ///
  /// Longer than the Worker's own 15s Gemini deadline, so a slow but
  /// successful answer is still delivered rather than thrown away after the
  /// account has already been charged a request for it.
  static const Duration _timeout = Duration(seconds: 25);

  /// Fallback wording when the backend refuses a call but sends no message.
  static const String _defaultQuotaNotice =
      'You have reached your assistant limit for now. Please try again later.';

  /// A short note to show the user when the backend refused the call because
  /// the account has used its allowance.
  ///
  /// Returns null for every other failure, so an unreachable backend stays
  /// invisible and the computed answer is simply shown as is.
  static String? quotaNotice(Object error) {
    if (error is! AssistantBackendException) return null;
    if (error.code != 'resource-exhausted') return null;

    final message = error.message.trim();

    return message.isEmpty ? _defaultQuotaNotice : message;
  }

  /// Why a call that should have produced an answer did not, in words worth
  /// showing the user.
  ///
  /// The point is that a broken deployment must not look like a working one.
  /// The Worker already sends a specific message with every refusal, so that
  /// message is preferred over anything invented here; only the transport
  /// failures, which never reach the Worker, are described locally.
  static String failureNotice(Object error) {
    if (error is AssistantBackendException) {
      final message = error.message.trim();
      if (message.isNotEmpty) return message;

      switch (error.code) {
        case 'resource-exhausted':
          return _defaultQuotaNotice;
        case 'unauthenticated':
          return 'The AI assistant could not confirm your sign-in. '
              'Please sign out and back in.';
        case 'permission-denied':
          return 'The AI assistant needs a verified email address.';
        case 'failed-precondition':
          return 'The AI assistant did not recognise this app installation.';
        case 'invalid-argument':
          return 'The AI assistant could not read that question.';
        default:
          return 'The AI assistant is unavailable right now.';
      }
    }

    if (error is TimeoutException) {
      return 'The AI assistant took too long to reply. Please try again.';
    }

    if (error is http.ClientException || error is FormatException) {
      return 'The AI assistant could not be reached. Check your connection.';
    }

    return 'The AI assistant is unavailable right now.';
  }

  /// A one-line description of how this build is configured.
  ///
  /// Logged once per question so a build that answers from the on-device
  /// engine can be told apart from one that tried the model and failed -
  /// which, before this existed, looked exactly the same from the outside.
  static String get configurationSummary {
    if (!isEnabled) {
      return 'AI_LLM_ENABLED is false, so the on-device engine answers. '
          'Build with --dart-define=AI_LLM_ENABLED=true to use the model.';
    }

    if (proxyUrl.isEmpty) {
      return 'AI_LLM_ENABLED is true but AI_PROXY_URL is empty, so the '
          'on-device engine answers. Build with '
          '--dart-define=AI_PROXY_URL=<worker address> as well.';
    }

    return 'The model is enabled, calling $proxyUrl';
  }

  @override
  Future<BackendReply?> ask({
    required String question,
    required Map<String, dynamic> facts,
    String groundedAnswer = '',
    List<Map<String, dynamic>> history = const [],
    List<String> capabilities = const [],
    void Function(String notice)? onLimited,
    void Function(String reason)? onFailed,
  }) async {
    if (!enabled) {
      debugPrint('AI assistant: ${AiBackend.configurationSummary}');
      return null;
    }

    try {
      // Who is asking. The Worker verifies this against Google's public keys,
      // so it cannot be forged, and it is the only thing that identifies the
      // account: the app never tells the backend who it is in the body.
      final user = FirebaseAuth.instance.currentUser;
      if (user == null) {
        onFailed?.call('The AI assistant needs you to be signed in.');
        debugPrint('AI assistant: no signed-in user, cannot call the model.');
        return null;
      }

      final idToken = await user.getIdToken();
      if (idToken == null || idToken.isEmpty) {
        onFailed?.call(
          'The AI assistant could not confirm your sign-in. '
          'Please sign out and back in.',
        );
        debugPrint('AI assistant: could not obtain a Firebase ID token.');
        return null;
      }

      // That this is a genuine installation of this app, verified the same
      // way. A build that cannot produce one sends no header and is refused,
      // unless the deployment has enforcement switched off for side-loading.
      String appCheckToken = '';
      try {
        appCheckToken = await FirebaseAppCheck.instance.getToken() ?? '';
      } catch (error) {
        debugPrint('App Check token unavailable: $error');
      }

      final response = await http
          .post(
            Uri.parse(proxyUrl),
            headers: {
              'content-type': 'application/json',
              'authorization': 'Bearer $idToken',
              if (appCheckToken.isNotEmpty) 'x-firebase-appcheck': appCheckToken,
            },
            // The facts are serialised here rather than by the Worker. They
            // are much the largest thing in the request and the Worker has no
            // reason to look inside them, so leaving them as one string keeps
            // it well inside the free plan's CPU budget - which excludes time
            // spent waiting on the network, but not time spent parsing JSON.
            body: jsonEncode({
              'question': question,
              'facts': jsonEncode(facts),
              'groundedAnswer': groundedAnswer,
              'history': history,
              'capabilities': capabilities,
            }),
          )
          .timeout(_timeout);

      final decoded = jsonDecode(response.body);
      final data =
          decoded is Map<String, dynamic> ? decoded : const <String, dynamic>{};

      if (response.statusCode != 200) {
        final error = data['error'];

        // The exact reason, named: HTTP status plus the Worker's own code and
        // message. Without this line a misconfigured key, a rejected App
        // Check token and an unreachable Worker all looked the same.
        debugPrint(
          'AI assistant: the backend refused the call. '
          'HTTP ${response.statusCode} from $proxyUrl, '
          'code=${error is Map ? error['code'] : 'none'}, '
          'message=${error is Map ? error['message'] : response.body}',
        );

        throw AssistantBackendException(
          code: error is Map && error['code'] is String
              ? error['code'] as String
              : 'unavailable',
          message: error is Map && error['message'] is String
              ? error['message'] as String
              : '',
        );
      }

      final text = (data['text'] as String?)?.trim();
      if (text == null || text.isEmpty) {
        onFailed?.call('The AI assistant returned an empty answer.');
        debugPrint('AI assistant: the backend replied 200 with no text.');
        return null;
      }

      return BackendReply(
        text: text,
        intent: AssistantIntent.fromMap(data['intent']),
        needsClarification: data['needsClarification'] == true,
        model: (data['model'] as String?) ?? '',
        provider: (data['provider'] as String?) ?? '',
      );
    } catch (error) {
      // The grounded answer is still correct and is still shown, so nothing is
      // lost - but the user is told the model did not answer, because a build
      // that silently falls back is indistinguishable from a working one, and
      // that is precisely how a broken deployment goes unnoticed.
      final notice = quotaNotice(error);
      if (notice != null) {
        onLimited?.call(notice);
      } else {
        onFailed?.call(failureNotice(error));
      }

      debugPrint(
        'AI assistant: falling back to the on-device answer. '
        'Reason: $error. Endpoint: $proxyUrl',
      );
      return null;
    }
  }

  /// Returns natural wording for [groundedAnswer], or null to use it as is.
  ///
  /// Used for text the app has already decided on - a planner's question or
  /// refusal - where only the phrasing, and the language it is phrased in, is
  /// wanted. Any action the model suggests in reply is deliberately ignored:
  /// the app has already made its decision about this message.
  Future<String?> rephrase({
    required String question,
    required Map<String, dynamic> facts,
    required String groundedAnswer,
    List<Map<String, dynamic>> history = const [],
    void Function(String notice)? onLimited,
  }) async {
    final reply = await ask(
      question: question,
      facts: facts,
      groundedAnswer: groundedAnswer,
      history: history,
      onLimited: onLimited,
    );

    return reply?.text;
  }
}
