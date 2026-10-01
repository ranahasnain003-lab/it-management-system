/// The in-app assistant's language model: Qwen3 on the organisation's own
/// laptop, asked through the same [LocalAiProvider] as the AI Assistant
/// screen.
///
/// Nothing is re-implemented here. The provider already does everything a
/// question needs: the permission-scoped IT Inventory context read under the
/// signed-in account, the pinned HTTPS connection, the per-user conversation
/// scope, the retries, and finding the laptop again after its address
/// changed. So the floating panel and the screen share one conversation per
/// signed-in account, and a question asked in either is answered - and
/// grounded - the same way.
///
/// Words only: Qwen3 answers questions, while commands ("transfer 2 laptops
/// to Township") stay with the app's own planner and its confirmations. See
/// [WordsOnlyBackend].
///
/// Streaming: the provider already writes the answer into its conversation
/// as it arrives, for the screen. The panel is shown the same text, as it
/// grows, through [StreamingBackend.askStreaming].
library;

import '../ai_backend.dart';
import 'local_ai_models.dart';
import 'local_ai_provider.dart';

class LocalAiAssistantBackend implements WordsOnlyBackend, StreamingBackend {
  LocalAiAssistantBackend(this._localAi);

  final LocalAiProvider _localAi;

  /// Shown under the app's own answer when the laptop was asked and did not
  /// answer, so a fixed reply is never passed off as the model's.
  static const String _fallbackNote =
      'This reply was worked out by the app itself.';

  /// [BackendReply.provider] for an answer the app worked out by itself from
  /// the records, without the model (LocalAiMessage.answeredByApp).
  static const String answeredByApp = 'app-records';

  @override
  bool get enabled => _localAi.isConfigured;

  /// Asks Qwen3 and returns its whole answer, or null to show the answer the
  /// app computed. The same as [askStreaming], with nobody watching the
  /// answer arrive.
  @override
  Future<BackendReply?> ask({
    required String question,
    required Map<String, dynamic> facts,
    String groundedAnswer = '',
    List<Map<String, dynamic>> history = const [],
    List<String> capabilities = const [],
    void Function(String notice)? onLimited,
    void Function(String reason)? onFailed,
  }) {
    return askStreaming(
      question: question,
      facts: facts,
      groundedAnswer: groundedAnswer,
      history: history,
      capabilities: capabilities,
      onLimited: onLimited,
      onFailed: onFailed,
      onPartial: _unwatched,
    );
  }

  static void _unwatched(String partialText) {}

  /// Asks Qwen3, passes [onPartial] its answer as it is written, and returns
  /// the whole answer, or null to show the answer the app computed.
  ///
  /// [facts], [groundedAnswer], [history] and [capabilities] are not sent:
  /// the provider builds its own minimal, permission-scoped context for the
  /// question, and the server keeps the conversation's history itself.
  ///
  /// [onPartial] is given the answer trimmed, as the returned reply's text
  /// is, so the last preview and the finished answer read the same and
  /// nothing on screen jumps when one replaces the other.
  @override
  Future<BackendReply?> askStreaming({
    required String question,
    required Map<String, dynamic> facts,
    String groundedAnswer = '',
    List<Map<String, dynamic>> history = const [],
    List<String> capabilities = const [],
    void Function(String notice)? onLimited,
    void Function(String reason)? onFailed,
    required void Function(String partialText) onPartial,
  }) async {
    // The screen loads the configuration when it opens; the panel may be
    // used first.
    if (!_localAi.isConfigured) await _localAi.loadConfig();

    // No server set up on this device: the app answers on its own, quietly,
    // exactly like a build with no model.
    if (!_localAi.isConfigured) return null;

    if (_localAi.isSending) {
      onFailed?.call(
        'The AI on the laptop is still answering another question. $_fallbackNote',
      );
      return null;
    }

    final before = _localAi.messages.length;

    // The provider notifies on everything - health checks, the screen's own
    // questions, a conversation thrown away - so only the answer to THIS
    // question may reach [onPartial]. That answer sits right after this
    // question, which [send] adds at [before]. The question is recognised
    // once, when the conversation first grows past [before], and from then
    // on by identity: the provider replaces the answer as it grows but never
    // the question, and a conversation discarded meanwhile (another account
    // signing in, Clear on the screen) starts again with new messages. So
    // text from any other question can never be shown as this one's answer.
    final asked = question.trim();
    LocalAiMessage? mine;
    var recognised = false;
    var shown = '';

    void relay() {
      final messages = _localAi.messages;
      if (messages.length < before + 2) return;

      if (!recognised) {
        recognised = true;
        final first = messages[before];
        if (first.isUser && first.content == asked) mine = first;
      }
      if (mine == null || !identical(messages[before], mine)) return;

      final answer = messages[before + 1];
      final text = answer.content.trim();

      // Only words the model has actually written. The progress notes before
      // the first word ("Reading your inventory data…") carry no content, and
      // a finished, stopped or failed answer is the returned reply's business.
      // A notification that changed nothing else is not passed on either.
      if (answer.isUser || !answer.isStreaming || text.isEmpty) return;
      if (text == shown) return;

      shown = text;
      onPartial(text);
    }

    _localAi.addListener(relay);
    try {
      await _localAi.send(question);
    } finally {
      // Before anything else, and whatever happened: a listener left behind
      // would keep the closed panel alive for as long as the provider lives,
      // which is the life of the app.
      _localAi.removeListener(relay);
    }

    final messages = _localAi.messages;

    // Refused before anything was sent: nobody signed in, or the question is
    // longer than the model accepts.
    if (messages.length == before) {
      final reason = _localAi.lastError?.userMessage;
      onFailed?.call(
        '${reason ?? 'The AI on the laptop could not take this question.'} '
        '$_fallbackNote',
      );
      return null;
    }

    // The finished answer is found exactly as the previews were: right after
    // THIS question, still the same message it was when it was asked. Not
    // simply the last message: if the conversation was thrown away while the
    // answer was being written, the last message is another question's
    // answer - which the panel would then show in place of this one's preview
    // - or there is no message at all. Either way this question went
    // unanswered, and the app's own answer is shown, labelled as such.
    final ours = mine;
    final answer =
        ours != null &&
            messages.length >= before + 2 &&
            identical(messages[before], ours)
        ? messages[before + 1]
        : null;
    final text = answer?.content.trim() ?? '';
    if (answer != null &&
        !answer.isUser &&
        answer.status == 'done' &&
        text.isNotEmpty) {
      // A plain lookup the app answered by itself, from the records, without
      // asking the model: said so, so the panel can say so too.
      if (answer.answeredByApp) {
        return BackendReply(text: text, provider: answeredByApp);
      }
      return BackendReply(
        text: text,
        model: _localAi.model?.model ?? _localAi.health?.modelName ?? '',
        provider: 'local-ai',
      );
    }

    final reason = (answer?.error ?? '').trim();
    onFailed?.call(
      reason.isEmpty
          ? 'The AI on the laptop did not answer. $_fallbackNote'
          : 'The AI on the laptop did not answer: $reason $_fallbackNote',
    );
    return null;
  }
}
