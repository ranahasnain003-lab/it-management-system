/// The seam through which IT Management System data reaches the Local AI
/// server: the `appContext` of `POST /api/v1/ai/chat` (see the server's
/// docs/API.md, section 4).
///
/// Three rules are built into the shape of it:
///
///   1. Firestore is read through the app's existing providers and services,
///      which already run under the signed-in account's own permissions and
///      security rules, and the implementation re-checks the account's role
///      before anything is added. Nothing here can see more than the screens
///      of the app can.
///   2. A context is assembled for ONE question and is never cached, so a
///      change in permission cannot be outrun by stale data.
///   3. Whatever is assembled is scrubbed of identifiers before it is sent:
///      no uid, no e-mail address, no phone number, no API key, no Firebase
///      token. People appear by display name only.
library;

import 'dart:convert';

import 'package:flutter/foundation.dart';

/// One titled piece of data, e.g. "Inventory totals" or "Damaged assets".
@immutable
class LocalAiContextSection {
  const LocalAiContextSection({required this.title, required this.data});

  /// 1-120 characters.
  final String title;

  /// Any JSON value (maps, lists, strings, numbers, booleans, null), at most
  /// 8 levels deep.
  final Object? data;

  Map<String, dynamic> toJson() => {'title': title, 'data': data};
}

/// The `appContext` for one question.
@immutable
class LocalAiAppContext {
  const LocalAiAppContext({
    required this.source,
    required this.retrievedAt,
    required this.scope,
    required this.sections,
    this.notes = const [],
    this.directAnswer,
  });

  /// The name the server shows the model, e.g. "PSBA IT Inventory (Firebase)".
  static const String defaultSource = 'PSBA IT Inventory (Firebase)';

  final String source;

  /// When the data was read from the providers.
  final DateTime retrievedAt;

  /// Who is asking and what they may see, in words, never an identifier.
  final String scope;

  final List<LocalAiContextSection> sections;

  /// What could not be retrieved, or was left out on purpose.
  final List<String> notes;

  /// The whole answer, when the app could work it out exactly by itself from
  /// these same records: a plain lookup such as "how many laptops are at Head
  /// Office?" or "IT-LAP-001 ki warranty". The provider then shows it at once
  /// and the model is not asked, so a question the database can answer is
  /// never slower, or less exact, than the database.
  ///
  /// Null for everything else - conversation, reasons, advice, comparisons, a
  /// question with a word the app does not know - and whenever any of the
  /// data behind it could not be read in full. Those go to the model, with
  /// the notes that say why.
  ///
  /// Never sent to the server: it is not part of [toJson].
  final String? directAnswer;

  /// True when there is at least one section of data.
  bool get hasData => sections.isNotEmpty;

  /// This context with [answer] as its [directAnswer].
  LocalAiAppContext withDirectAnswer(String? answer) => LocalAiAppContext(
    source: source,
    retrievedAt: retrievedAt,
    scope: scope,
    sections: sections,
    notes: notes,
    directAnswer: answer,
  );

  /// The wire form: exactly the server's `ApiV1AppContext`.
  Map<String, dynamic> toJson() => {
    'source': source,
    'retrievedAt': retrievedAt.toUtc().toIso8601String(),
    if (scope.isNotEmpty) 'scope': scope,
    'sections': [for (final s in sections) s.toJson()],
    if (notes.isNotEmpty) 'notes': notes,
  };

  /// A conservative token estimate of the serialised context (about three
  /// characters per token for compact JSON), used to stay inside the server's
  /// `maxAppContextTokens` before sending rather than being refused with
  /// `CONTEXT_TOO_LARGE`.
  int get estimatedTokens => (jsonEncode(toJson()).length / 3).ceil() + 120;
}

/// Supplies the `appContext` for one question.
///
/// Implementations must only ever return data the signed-in account may
/// already read in the app itself, and must never include credentials or
/// personal identifiers.
abstract class LocalAiContextService {
  /// The data for [question], for the account identified by [uid].
  ///
  /// [uid] is only used to confirm that the account the app is currently
  /// signed in with is the one asking; it must NOT be included in the result.
  /// [previousQuestion] is the question before this one in the conversation,
  /// so a follow-up ("and at Head Office?") can be understood.
  /// [budgetTokens] is how large the result may be (see
  /// [LocalAiAppContext.estimatedTokens]).
  ///
  /// Returns null only when there is nobody signed in. When data cannot be
  /// read, the result carries no sections and a note saying why, so the model
  /// answers "I could not retrieve that" instead of guessing.
  Future<LocalAiAppContext?> contextFor({
    required String question,
    required String? uid,
    String? previousQuestion,
    required int budgetTokens,
  });

  /// Forgets any conversation state (e.g. the asset a follow-up refers to),
  /// on a new conversation or a change of account.
  void reset();
}
