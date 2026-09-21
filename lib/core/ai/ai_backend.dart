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
  Future<BackendReply?> ask({
    required String question,
    required Map<String, dynamic> facts,
    String groundedAnswer = '',
    List<Map<String, dynamic>> history = const [],
    List<String> capabilities = const [],
    void Function(String notice)? onLimited,
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

  @override
  Future<BackendReply?> ask({
    required String question,
    required Map<String, dynamic> facts,
    String groundedAnswer = '',
    List<Map<String, dynamic>> history = const [],
    List<String> capabilities = const [],
    void Function(String notice)? onLimited,
  }) async {
    if (!enabled) return null;

    try {
      // Who is asking. The Worker verifies this against Google's public keys,
      // so it cannot be forged, and it is the only thing that identifies the
      // account: the app never tells the backend who it is in the body.
      final user = FirebaseAuth.instance.currentUser;
      if (user == null) return null;

      final idToken = await user.getIdToken();
      if (idToken == null || idToken.isEmpty) return null;

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
      if (text == null || text.isEmpty) return null;

      return BackendReply(
        text: text,
        intent: AssistantIntent.fromMap(data['intent']),
        needsClarification: data['needsClarification'] == true,
        model: (data['model'] as String?) ?? '',
        provider: (data['provider'] as String?) ?? '',
      );
    } catch (error) {
      // Never surface backend problems as a failed answer: the grounded answer
      // is already correct, so the assistant keeps working without the model.
      final notice = quotaNotice(error);
      if (notice != null) onLimited?.call(notice);

      debugPrint('AI backend unavailable, using the computed answer: $error');
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
