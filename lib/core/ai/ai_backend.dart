import 'package:cloud_functions/cloud_functions.dart';
import 'package:flutter/foundation.dart';

/// Optional wording layer over the assistant's own answers.
///
/// **Disabled by default.** The app ships with no paid dependency: every
/// answer, figure and action comes from the on-device grounded engine, which
/// reads the account's permission-filtered inventory directly. This class only
/// exists to make those answers read more naturally once the
/// `askInventoryAssistant` Cloud Function is deployed, and it is skipped
/// entirely while [isEnabled] is false.
///
/// When it is enabled: the OpenAI key lives only in Google Secret Manager; no
/// key, token or endpoint secret exists in the app. Only facts the account has
/// already read from Firestore are sent, and the model is asked for wording,
/// never for data. If the backend is not deployed, is unreachable, times out or
/// errors, [rephrase] returns null and the locally computed answer is used
/// unchanged.
class AiBackend {
  const AiBackend();

  /// Region the function is deployed to. Not a secret; overridable at build
  /// time with --dart-define=AI_REGION=...
  static const String region =
      String.fromEnvironment('AI_REGION', defaultValue: 'us-central1');

  /// Whether this build may call the language model at all.
  ///
  /// Off by default, so the app has no paid dependency: the assistant answers
  /// entirely from the on-device grounded engine and never opens a network
  /// call for wording. Nothing is lost but phrasing - every figure, every
  /// answer and every action already comes from the local engine.
  ///
  /// Turn it on only once the Cloud Function is deployed:
  ///   flutter build apk --release --dart-define=AI_LLM_ENABLED=true
  static const bool isEnabled =
      bool.fromEnvironment('AI_LLM_ENABLED', defaultValue: false);

  static const String _callable = 'askInventoryAssistant';

  /// Fallback wording when the backend refuses a call but sends no message.
  static const String _defaultQuotaNotice =
      'You have reached your assistant limit for now. Please try again later.';

  /// A short note to show the user when the backend refused the call because
  /// the account has used its allowance.
  ///
  /// Returns null for every other failure, so an undeployed or unreachable
  /// backend stays invisible and the computed answer is simply shown as is.
  static String? quotaNotice(Object error) {
    if (error is! FirebaseFunctionsException) return null;
    if (error.code != 'resource-exhausted') return null;

    final message = error.message?.trim();

    return (message == null || message.isEmpty) ? _defaultQuotaNotice : message;
  }

  /// Returns natural wording for [groundedAnswer], or null to use it as is.
  ///
  /// [onLimited] is called instead when the account has hit its request limit,
  /// so the panel can tell the user rather than silently dropping the model.
  Future<String?> rephrase({
    required String question,
    required Map<String, dynamic> facts,
    required String groundedAnswer,
    List<Map<String, dynamic>> history = const [],
    void Function(String notice)? onLimited,
  }) async {
    if (!isEnabled) return null;

    try {
      final callable = FirebaseFunctions.instanceFor(region: region)
          .httpsCallable(
            _callable,
            options: HttpsCallableOptions(timeout: const Duration(seconds: 20)),
          );

      final result = await callable.call<Map<String, dynamic>>({
        'question': question,
        'facts': facts,
        'groundedAnswer': groundedAnswer,
        'history': history,
      });

      final text = (result.data['text'] as String?)?.trim();

      return (text == null || text.isEmpty) ? null : text;
    } catch (error) {
      // Never surface backend problems as a failed answer: the grounded answer
      // is already correct, so the assistant keeps working without the model.
      final notice = quotaNotice(error);
      if (notice != null) onLimited?.call(notice);

      debugPrint('AI backend unavailable, using the computed answer: $error');
      return null;
    }
  }
}
