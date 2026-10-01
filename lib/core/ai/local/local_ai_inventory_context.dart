/// Turns one question into the smallest `appContext` that can answer it, from
/// records the app has already read through its own providers.
///
/// Everything here is synchronous and works on plain values, so every rule
/// that decides what leaves the app - who may see what, which fields are never
/// sent, how much fits - is covered by unit tests without Firebase.
/// [ProviderInventoryContextService] only gathers the inputs.
///
/// Three passes, in this order:
///
///   1. Permission. The account is re-checked before anything is added, and
///      each kind of record is cut down to what that role can already read in
///      the app. A User never gets the user directory, and never a request
///      that is not their own.
///   2. Relevance. The words of the question (English, Roman Urdu, or common
///      Urdu-script words) decide which sections are built. A follow-up with
///      nothing of its own ("and at Head Office?") borrows the asset, Bazaar
///      or category of the question before it.
///   3. Size and scrubbing. Lists are shortened, then low-priority sections
///      are left out, until the result fits the budget; the real totals stay
///      in the titles. A final scrubber removes anything shaped like an e-mail
///      address, an account id or a token, whichever field it turned up in.
///
/// Then, from the same reading and the same records: whether the question is
/// a plain lookup the app can answer exactly by itself, without the model
/// (see local_ai_direct_answer.dart and LocalAiAppContext.directAnswer).
library;

import 'dart:convert';

import 'package:flutter/foundation.dart';

import '../../../models/asset_model.dart';
import '../../../models/deployment_model.dart';
import '../../../models/request_model.dart';
import '../../../models/user_model.dart';
import '../../services/bazaar_service.dart' show BazaarModel;
import '../../services/permission_service.dart';
import '../inventory_assistant.dart';
import '../small_talk.dart';
import 'local_ai_context_service.dart';

part 'local_ai_direct_answer.dart';

/// What a question is about. One question can be about several things at once
/// ("damaged laptops at Head Office").
///
/// A named asset, Bazaar, category, person or department is not a topic but an
/// entity; see [LocalAiInventoryContext.build].
enum LocalAiTopic {
  overview,
  headOffice,
  perBazaar,
  bazaarDirectory,
  damaged,
  underRepair,
  lost,
  disposed,
  available,
  assigned,
  movements,
  requests,
  people,
  departments,
  value,
  warranty,
}

/// Whether one source of records could be read for this question.
@immutable
class LocalAiSourceState {
  const LocalAiSourceState({this.loading = false, this.error});

  static const LocalAiSourceState ready = LocalAiSourceState();

  /// The listener has started but has not delivered its first snapshot.
  final bool loading;

  /// Why the listener failed, as the provider reported it; null when it did
  /// not. Shortened and scrubbed before it is ever put in a note.
  final String? error;

  bool get failed => (error ?? '').trim().isNotEmpty;
}

/// Everything one context is built from. Plain values only, so tests can
/// build any situation - any role, any failure - straight from the models.
@immutable
class LocalAiContextInputs {
  const LocalAiContextInputs({
    required this.question,
    required this.askedForUid,
    required this.signedInUid,
    required this.role,
    required this.profile,
    required this.snapshot,
    required this.retrievedAt,
    required this.budgetTokens,
    this.previousQuestion,
    this.requests = const [],
    this.people = const [],
    this.inventoryState = LocalAiSourceState.ready,
    this.movementState = LocalAiSourceState.ready,
    this.bazaarState = LocalAiSourceState.ready,
    this.requestState = LocalAiSourceState.ready,
    this.peopleState = LocalAiSourceState.ready,
    this.inventoryInScope = true,
    this.rememberedAssetId,
    this.rememberedBazaar,
  });

  final String question;
  final String? previousQuestion;

  /// The account the question was asked for, and the account the app is
  /// signed in with right now. Both are compared and never emitted.
  final String? askedForUid;
  final String? signedInUid;

  /// The normalised main role the app's providers scope by
  /// (UserProvider.currentUserRole).
  final String role;

  /// The signed-in account's live profile.
  final UserModel? profile;

  /// The inventory, Bazaars and movements, as the providers hold them.
  final InventorySnapshot snapshot;

  /// The request provider's list, already scoped by RequestService for this
  /// account. Filtered again here for a User.
  final List<RequestModel> requests;

  /// The user directory. Ignored for any role that may not manage users.
  final List<UserModel> people;

  final LocalAiSourceState inventoryState;
  final LocalAiSourceState movementState;
  final LocalAiSourceState bazaarState;
  final LocalAiSourceState requestState;
  final LocalAiSourceState peopleState;

  /// False when the inventory listener is streaming a different scope from the
  /// one this account's role calls for, e.g. for a moment after a role change.
  /// Nothing from the inventory is sent then.
  final bool inventoryInScope;

  /// The asset (document id) and Bazaar an earlier question in this
  /// conversation was about, for "and its warranty?" two questions later.
  /// Resolved again against [snapshot], so a record the account can no longer
  /// see is never brought back.
  final String? rememberedAssetId;
  final String? rememberedBazaar;

  final DateTime retrievedAt;

  /// The size the result must fit, by both
  /// [LocalAiInventoryContext.appDataTokens] (the server's measure) and
  /// [LocalAiAppContext.estimatedTokens].
  final int budgetTokens;
}

/// The context for one question, plus what it turned out to be about, so the
/// service can remember it for the next follow-up.
@immutable
class LocalAiContextResult {
  const LocalAiContextResult({
    required this.context,
    this.focusAsset,
    this.focusBazaar,
    this.topics = const {},
  });

  final LocalAiAppContext context;
  final AssetModel? focusAsset;
  final String? focusBazaar;
  final Set<LocalAiTopic> topics;
}

/// Builds the `appContext` for one question. See the library comment.
class LocalAiInventoryContext {
  const LocalAiInventoryContext._();

  static const Set<String> _mainRoles = {'super_admin', 'admin', 'user'};

  // ===========================================================================
  // PERMISSION
  // ===========================================================================

  /// Why this account may not be sent any data, or null when it may.
  ///
  /// Checked by the service before a single listener is started, and again by
  /// [build] after the wait, because an account can be switched, disabled or
  /// demoted while a question is in flight.
  static String? accessProblem({
    required String? askedForUid,
    required String? signedInUid,
    required UserModel? profile,
    required String role,
  }) {
    final asked = askedForUid?.trim() ?? '';
    final signedIn = signedInUid?.trim() ?? '';

    if (asked.isEmpty || signedIn.isEmpty) {
      return 'Nobody is signed in, so no records were read.';
    }

    if (asked != signedIn) {
      return 'The signed-in account changed while this question was being '
          'asked, so no records were read. Ask again.';
    }

    if (profile == null) {
      return 'This account\'s profile has not loaded yet, so no records were '
          'read. Ask again in a moment.';
    }

    if (profile.uid.trim() != signedIn) {
      return 'This account\'s profile does not match the signed-in account, so '
          'no records were read.';
    }

    if (!profile.isActive) {
      return 'This account is not active, so no records were read.';
    }

    if (!_mainRoles.contains(role)) {
      return 'This account has no recognised role (Super Admin, Admin or '
          'User), so no records were read.';
    }

    return null;
  }

  /// What the asking role may see, in words. Never a name or an id.
  static String scopeFor(String role) {
    switch (role) {
      case 'super_admin':
        return 'Asked by a Super Admin: all inventory, Bazaars and movements; '
            'all requests; the user directory.';
      case 'admin':
        return 'Asked by an Admin: all inventory, Bazaars and movements; '
            'requests the Admin received, owns or made; the user directory.';
      case 'user':
        return 'Asked by a User: all inventory, Bazaars and movements, '
            'read-only; only requests this User made or received. No user '
            'directory.';
      default:
        return 'The asking account could not be verified, so nothing from the '
            'inventory is included.';
    }
  }

  /// A context that carries no data, only [notes] saying why, so the model
  /// answers "I could not retrieve that" instead of guessing.
  static LocalAiAppContext withoutData({
    required String role,
    required DateTime retrievedAt,
    required List<String> notes,
  }) {
    return LocalAiAppContext(
      source: LocalAiAppContext.defaultSource,
      retrievedAt: retrievedAt,
      scope: _redact(scopeFor(role)),
      sections: const [],
      notes: _cleanNotes(notes),
    );
  }

  // ===========================================================================
  // SIZE, AS THE SERVER MEASURES IT
  // ===========================================================================

  /// The size of [context] as the server counts it against
  /// `maxAppContextTokens`: the estimate of `shared/tokens.ts` over the lines
  /// `appContextBlock` (server/api/appContext.ts) puts inside `<app_data>`.
  ///
  /// [LocalAiAppContext.estimatedTokens] counts about three characters per
  /// token. The server counts every digit and punctuation mark as one, and
  /// these contexts are mostly numbers, dates and JSON punctuation, so it
  /// measures them 1.5 to 2 times larger. Fitting to the seam's figure alone
  /// could therefore be refused with 413 CONTEXT_TOO_LARGE.
  static int appDataTokens(LocalAiAppContext context) {
    final lines = <String>[];
    final scope = _plainText(context.scope);
    if (scope.isNotEmpty) lines.add('Scope: $scope');
    for (final section in context.sections) {
      lines
        ..add('## ${_plainText(section.title)}')
        ..add(jsonEncode(section.data).replaceAll('<', r'<'));
    }
    final notes = [
      for (final note in context.notes)
        if (_plainText(note).isNotEmpty) _plainText(note),
    ];
    if (notes.isNotEmpty) {
      lines
        ..add('Notes:')
        ..addAll([for (final note in notes) '- $note']);
    }
    return serverTokens(lines.join('\n'));
  }

  /// A port of `estimateTokens` in the server's `shared/tokens.ts`, calibrated
  /// there against qwen3:8b. Kept step for step the same, so a context this
  /// app sends is never measured larger on the server than it was here.
  static int serverTokens(String text) {
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
      tokens += run.length / 1.25;
      rest = match.end;
    }
    tokens += _countPieces(text.substring(rest));
    return (tokens * 1.1).ceil();
  }

  /// Base64, JWTs and similar encoded runs: about 1.25 characters a token.
  static final RegExp _encodedRun = RegExp(r'[A-Za-z0-9+/_-]{20,}={0,2}');
  static final RegExp _digit = RegExp('[0-9]');
  static final RegExp _lower = RegExp('[a-z]');
  static final RegExp _upper = RegExp('[A-Z]');

  static final RegExp _pieces = RegExp(
    r'[A-Za-z]+|\p{L}[\p{L}\p{M}]*|\d|\n+[ \t]*|[ \t]{2,}|\s|\S',
    unicode: true,
  );
  static final RegExp _asciiLetter = RegExp('^[A-Za-z]');
  static final RegExp _letter = RegExp(r'^\p{L}', unicode: true);

  static double _countPieces(String text) {
    var tokens = 0.0;
    for (final match in _pieces.allMatches(text)) {
      final piece = match[0]!;
      final first = piece.runes.first;
      if (first < 128 && _asciiLetter.hasMatch(piece)) {
        tokens += (piece.length / 4.5).ceil();
      } else if (first > 127 && _letter.hasMatch(piece)) {
        // Devanagari, Bengali, Tamil and the other Brahmic scripts split into
        // more tokens than Arabic-script Urdu does.
        final brahmic = first >= 0x0900 && first <= 0x0dff;
        tokens += piece.length * (brahmic ? 1.25 : 0.85);
      } else if (piece == ' ' || piece == '\t') {
        // A single space or tab is merged into the next token.
      } else if (first > 0xffff) {
        tokens += first >= 0x1fa70 && first <= 0x1faff ? 3 : 2;
      } else {
        // Digits, punctuation, symbols, line breaks and indentation runs.
        tokens += 1;
      }
    }
    return tokens;
  }

  /// Text as the server shows it outside the JSON: on one line, with "<"
  /// swapped for its look-alike.
  static String _plainText(String text) =>
      text.replaceAll(RegExp(r'\s+'), ' ').trim().replaceAll('<', '‹');

  // ===========================================================================
  // READING A QUESTION
  // ===========================================================================

  /// Whether answering [question] needs the request records, taking a
  /// follow-up of a question about requests into account.
  ///
  /// Read from the words alone, so the service can decide before any record
  /// is read whether to start the request listener at all.
  static bool needsRequests(String question, {String? previousQuestion}) {
    final current = _Reading(question);
    if (current.topics.contains(LocalAiTopic.requests)) return true;

    final previous = previousQuestion?.trim() ?? '';
    if (previous.isEmpty) return false;

    return current.ownTopics.isEmpty &&
        current.canBorrowTopics &&
        _Reading(previous).topics.contains(LocalAiTopic.requests);
  }

  // ===========================================================================
  // BUILD
  // ===========================================================================

  /// The context for [inputs], fitted to [LocalAiContextInputs.budgetTokens]
  /// and scrubbed.
  static LocalAiContextResult build(LocalAiContextInputs inputs) {
    final problem = accessProblem(
      askedForUid: inputs.askedForUid,
      signedInUid: inputs.signedInUid,
      profile: inputs.profile,
      role: inputs.role,
    );

    if (problem != null) {
      return LocalAiContextResult(
        context: withoutData(
          role: inputs.role,
          retrievedAt: inputs.retrievedAt,
          notes: [problem],
        ),
      );
    }

    // A greeting names nothing, so it would otherwise be read as a bare
    // follow-up and carry the previous question's records - or the whole
    // overview - to the model, which then talks figures instead of saying
    // hello. Nothing is read for it; the note tells the model why, and the
    // follow-up memory is left as it was.
    if (isSmallTalk(inputs.question)) {
      return LocalAiContextResult(
        context: withoutData(
          role: inputs.role,
          retrievedAt: inputs.retrievedAt,
          notes: const [smallTalkNote],
        ),
      );
    }

    return _Build(inputs).run();
  }

  /// Whether [question] is only a greeting, a "how are you", thanks or a
  /// farewell (see SmallTalk), and so needs no inventory data at all.
  static bool isSmallTalk(String question) => SmallTalk.read(question) != null;

  /// Sent instead of data with small talk. Worded so the model greets back
  /// briefly rather than reporting that something "could not be retrieved";
  /// checked against the real qwen3:8b.
  static const String smallTalkNote =
      'No inventory data was read for this message: it is a greeting or small '
      'talk, not a question about the inventory. Reply briefly and naturally, '
      'and offer to help with the inventory.';

  // ===========================================================================
  // SCRUBBING
  // ===========================================================================

  /// Keys that are never sent, whatever structure they turn up in. Compared
  /// lower-case with anything but letters and digits removed, so `assigned_to`
  /// and `assignedTo` are the same key.
  ///
  /// `assetId` is deliberately absent: it is the asset tag people read off the
  /// label (e.g. IT-LAP-001), not a database id.
  static const Set<String> sensitiveKeys = {
    'id',
    'uid',
    'userid',
    'docid',
    'documentid',
    'assetdocumentid',
    'email',
    'emailaddress',
    'createdbyemail',
    'phone',
    'phonenumber',
    'mobile',
    'contact',
    'contactnumber',
    'contactperson',
    'receivercontact',
    'address',
    'adminid',
    'assetadminid',
    'assignedto',
    'assigneeid',
    'requestedby',
    'receiverid',
    'approvedbyuid',
    'sentby',
    'createdby',
    'attachment',
    'attachmenturl',
    'organizationid',
    'employeeid',
    'bazaarid',
    'frombazaarid',
    'tobazaarid',
    'sourcebazaarid',
    'destinationbazaarid',
    'currentbazaarid',
    'token',
    'idtoken',
    'accesstoken',
    'refreshtoken',
    'apikey',
    'password',
    'secret',
  };

  static final RegExp _email = RegExp(
    r'[A-Za-z0-9._%+-]+@[A-Za-z0-9-]+(?:\.[A-Za-z0-9-]+)+',
  );

  /// A Firebase Auth uid: 28 letters and digits standing on their own.
  static final RegExp _firebaseUid = RegExp(
    r'(?<![A-Za-z0-9])[A-Za-z0-9]{28}(?![A-Za-z0-9])',
  );

  /// A JSON Web Token, such as a Firebase ID token.
  static final RegExp _jwt = RegExp(
    r'eyJ[A-Za-z0-9_-]{4,}\.[A-Za-z0-9_-]{4,}\.[A-Za-z0-9_-]*',
  );

  /// A Local AI API key, or a Google API key.
  static final RegExp _apiKey = RegExp(
    r'lai_[A-Za-z0-9]+_[A-Za-z0-9_-]{8,}|AIza[0-9A-Za-z_-]{30,}',
  );

  /// A Pakistani mobile number, or any international number.
  static final RegExp _phone = RegExp(
    r'(?<!\d)(?:(?:\+|00)92|0)[\s-]?3\d{2}[\s-]?\d{7}(?!\d)|\+\d[\d\s-]{9,15}\d',
  );

  static final List<RegExp> _sensitivePatterns = [
    _email,
    _jwt,
    _apiKey,
    _firebaseUid,
    _phone,
  ];

  /// Whether [value] contains anything shaped like an identifier or a
  /// credential.
  static bool looksSensitive(String value) =>
      _sensitivePatterns.any((pattern) => pattern.hasMatch(value));

  static String _keyForm(String key) =>
      key.toLowerCase().replaceAll(RegExp(r'[^a-z0-9]'), '');

  static bool _isSensitiveKey(String key) =>
      sensitiveKeys.contains(_keyForm(key));

  /// The deepest nesting kept inside one section's data. The server accepts
  /// eight levels; this leaves room for the section wrapper.
  static const int _maxDepth = 6;

  /// The final, defensive pass over a section's data.
  ///
  /// The sections are built from chosen fields only, so this should find
  /// nothing. It is here for the day a field is added upstream, or a person
  /// types an e-mail address into an asset name: any string that contains an
  /// e-mail address, a uid-like token, a JWT, an API key or a phone number is
  /// removed (dropped from a map, null in a list, so the columns of a table
  /// stay aligned), and any known sensitive key is dropped at any depth,
  /// including a sensitive column of a `{columns, rows}` table.
  static Object? scrubData(Object? data) => _orNull(_scrub(data, 0));

  /// Marks a value the scrubber took out, as distinct from a JSON null.
  static final Object _removed = Object();

  static Object? _orNull(Object? value) =>
      identical(value, _removed) ? null : value;

  static Object? _scrub(Object? value, int depth) {
    if (value == null || value is num || value is bool) return value;

    if (value is String) {
      return looksSensitive(value) ? _removed : value;
    }

    if (value is DateTime) return _day(value);

    if (depth >= _maxDepth) return null;

    if (value is Map) {
      final columns = value['columns'];
      final rows = value['rows'];
      if (columns is List && rows is List) {
        return _scrubTable(value, columns, rows, depth);
      }

      final result = <String, Object?>{};
      for (final entry in value.entries) {
        final key = entry.key.toString();
        if (_isSensitiveKey(key) || looksSensitive(key)) continue;

        final cleaned = _scrub(entry.value, depth + 1);
        if (identical(cleaned, _removed)) continue;
        result[key] = cleaned;
      }
      return result;
    }

    if (value is Iterable) {
      return [for (final item in value) _orNull(_scrub(item, depth + 1))];
    }

    // Anything else is not JSON; it is left out rather than stringified,
    // because its toString() could say anything.
    return null;
  }

  static Map<String, Object?> _scrubTable(
    Map<dynamic, dynamic> table,
    List<dynamic> columns,
    List<dynamic> rows,
    int depth,
  ) {
    final keep = <int>[
      for (var i = 0; i < columns.length; i++)
        if (!_isSensitiveKey(columns[i].toString()) &&
            !looksSensitive(columns[i].toString()))
          i,
    ];

    final result = <String, Object?>{};

    for (final entry in table.entries) {
      final key = entry.key.toString();
      if (key == 'columns' || key == 'rows') continue;
      if (_isSensitiveKey(key) || looksSensitive(key)) continue;

      final cleaned = _scrub(entry.value, depth + 1);
      if (identical(cleaned, _removed)) continue;
      result[key] = cleaned;
    }

    result['columns'] = [for (final i in keep) columns[i].toString()];
    result['rows'] = [
      for (final row in rows)
        if (row is List)
          [
            for (final i in keep)
              if (i < row.length) _orNull(_scrub(row[i], depth + 2)),
          ],
    ];

    return result;
  }

  /// Masks identifiers inside free text that must stay (a title, a note), where
  /// removing the whole value would leave nothing to read.
  static String _redact(String text) {
    var result = text;
    for (final pattern in _sensitivePatterns) {
      result = result.replaceAll(pattern, '[hidden]');
    }
    return result;
  }

  /// A provider's error, cut down to something a note can carry.
  ///
  /// Firebase messages are long and name internal codes; the model only needs
  /// to know roughly why ("permission denied", "network error").
  static String shortReason(String? error) {
    var text = (error ?? '').trim();
    if (text.isEmpty) return 'unknown error';

    final code = RegExp(r'\[[\w_]+/([\w-]+)\]').firstMatch(text);
    if (code != null) {
      final name = code.group(1)!;
      if (name == 'permission-denied') return 'permission denied';
      if (name == 'unavailable') return 'the database is unreachable';
      text = text.replaceFirst(code.group(0)!, '').trim();
      if (text.isEmpty) return name.replaceAll('-', ' ');
    }

    if (text.toLowerCase().contains('permission')) return 'permission denied';

    text = text.split('\n').first.trim();
    if (text.startsWith('Exception: ')) text = text.substring(11).trim();
    if (text.length > 120) text = '${text.substring(0, 117).trimRight()}...';

    return _redact(text);
  }

  static List<String> _cleanNotes(List<String> notes) {
    final result = <String>[];
    for (final note in notes) {
      var text = _redact(note.trim());
      if (text.isEmpty || result.contains(text)) continue;
      if (text.length > 300) text = '${text.substring(0, 297).trimRight()}...';
      result.add(text);
    }
    return result.length > 12 ? result.sublist(0, 12) : result;
  }

  // ===========================================================================
  // WORDS
  // ===========================================================================

  /// Common Urdu-script words, mapped onto the English vocabulary below.
  /// Deliberately short: only words cheap to recognise without a tokenizer.
  static const Map<String, String> _urduWords = {
    'لیپ ٹاپ': 'laptop',
    'لیپٹاپ': 'laptop',
    'کمپیوٹر': 'computer',
    'پرنٹر': 'printer',
    'مانیٹر': 'monitor',
    'ہیڈ آفس': 'head office',
    'ہیڈآفس': 'head office',
    'بازار': 'bazaar',
    'بازاروں': 'bazaar',
    'خراب': 'damaged',
    'ٹوٹا': 'damaged',
    'مرمت': 'repair',
    'کل': 'total',
    'کتنے': 'how many',
    'کتنی': 'how many',
    'کتنا': 'how much',
    'درخواست': 'request',
    'درخواستیں': 'request',
    'زیر التوا': 'pending',
    'منظور': 'approved',
    'مسترد': 'rejected',
    'صارف': 'users',
    'صارفین': 'users',
    'یوزر': 'users',
    'ملازم': 'staff',
    'ملازمین': 'staff',
    'شعبہ': 'department',
    'منتقل': 'transfer',
    'ٹرانسفر': 'transfer',
    'واپس': 'return',
    'وارنٹی': 'warranty',
    'قیمت': 'value',
    'مالیت': 'value',
    'گم': 'lost',
    'غائب': 'missing',
    'دستیاب': 'available',
    'تفویض': 'assigned',
    'اسٹاک': 'stock',
    'سٹاک': 'stock',
    'اثاثے': 'assets',
    'اثاثہ': 'asset',
    'کہاں': 'where',
    'تفصیل': 'details',
    'اس کا': 'this asset',
    'اس کی': 'this asset',
    'اسکا': 'this asset',
    'اور': 'and',
    'ہر': 'each',
  };

  static const List<String> _overviewWords = [
    'total',
    'overall',
    'overview',
    'summary',
    'kul ',
    'saara',
    'sara ',
    'poora',
    'poori',
    'pura ',
    'puri ',
    'whole',
    'entire',
    'sab kuch',
    'everything',
    'dashboard',
  ];

  /// The inventory as a whole, named without a topic ("how many assets do we
  /// have?"). Such a question stands on its own and never borrows the asset
  /// of the question before it. "asset" alone is left out: "status of the
  /// asset?" is a follow-up.
  static const List<String> _wholeInventoryWords = [
    'assets',
    'inventory',
    'all items',
    'saman',
    'samaan',
    'saaman',
  ];

  static const List<String> _headOfficeWords = [
    'head office',
    'headoffice',
    'head-office',
    'h.o.',
    'ho stock',
    'hq',
    'office mein',
    'office main',
    'office me ',
    'office par',
    'main office',
    'central store',
  ];

  static const List<String> _bazaarWords = ['bazaar', 'bazar', 'sahulat'];

  /// Words that make a Bazaar question about the Bazaars themselves rather
  /// than about what is in them.
  static const List<String> _directoryWords = [
    'active',
    'inactive',
    'disabled',
    'disable',
    'enabled',
    'closed',
    'city',
    'cities',
    'shehar',
    'shahar',
    'directory',
    'names of',
    'list of bazaar',
    'how many bazaar',
    'kitne bazaar',
    'number of bazaar',
    'located',
  ];

  static const List<String> _stockWords = [
    'asset',
    'stock',
    'unit',
    'item',
    'saman',
    'samaan',
    'maal',
    'quantity',
    'deployed',
    'equipment',
    'inventory',
    'kitna',
    'hold',
    'most',
    'least',
  ];

  static const List<String> _damagedWords = [
    'damage',
    'kharab',
    'kharaab',
    'toot',
    'broken',
    'faulty',
    'defective',
    'not working',
    'out of order',
  ];

  static const List<String> _repairWords = [
    'repair',
    'maintenance',
    'marammat',
    'mrammat',
    'servicing',
    'under service',
    'being fixed',
  ];

  static const List<String> _lostWords = [
    'lost',
    'missing',
    'gum ',
    'gumshuda',
    'khoya',
    'khoye',
    'kho gay',
    'chori',
    'stolen',
  ];

  static const List<String> _disposedWords = [
    'dispose',
    'retire',
    'scrap',
    'zaya',
    'written off',
    'write off',
    'write-off',
    'condemn',
    'auction',
  ];

  static const List<String> _availableWords = [
    'available',
    'maujood',
    'mojood',
    'usable',
    'free stock',
    'in stock',
    'spare',
    'unused',
    'idle',
  ];

  static const List<String> _assignedWords = [
    'assign',
    'issued',
    'allocated',
    'kis ke paas',
    'kis ke pas',
    'kis k pas',
    'kis kay pas',
    'diye',
    'held by',
    'holder',
    'who has',
    'who is using',
    'handed',
  ];

  static const List<String> _movementWords = [
    'transfer',
    'moved',
    'move',
    'movement',
    'deployment',
    'shift',
    'bheja',
    'bheje',
    'bhej',
    'return',
    'wapas',
    'wapis',
    'history',
    'recent',
    'latest',
    'sent',
  ];

  /// Movement words that still mean movement records in a question that is
  /// also about requests. "transfer" does not: "pending transfer requests"
  /// names a kind of request.
  static const List<String> _plainMovementWords = [
    'moved',
    'movement',
    'deployment',
    'shift',
    'bheja',
    'bheje',
  ];

  static const List<String> _requestWords = [
    'request',
    'darkhwast',
    'darkhast',
    'darkhaast',
    'approval',
    'approve',
    'pending',
    'reject',
    'manzoor',
    'mustarad',
  ];

  static const List<String> _peopleWords = [
    'user',
    'people',
    'person',
    'staff',
    'employee',
    'member',
    'account',
    'admin',
    'afraad',
    'mulazim',
    'mulazmeen',
    'team',
    'colleague',
    'personnel',
  ];

  static const List<String> _departmentWords = [
    'department',
    'dept',
    'shoba',
    'shuba',
    'division',
    'section',
    'wing',
  ];

  static const List<String> _valueWords = [
    'value',
    'worth',
    'cost',
    'price',
    'qeemat',
    'keemat',
    'kimat',
    'maliyat',
    'rupee',
    'rs ',
    'rs.',
    'pkr',
    'expensive',
    'mehnga',
    'mehenga',
    'costly',
    'amount',
  ];

  static const List<String> _warrantyWords = [
    'warrant',
    'guarantee',
    'zamanat',
    'expir',
  ];

  /// Words that point back at what was just discussed.
  static const List<String> _backReferences = [
    'this asset',
    'that asset',
    'this one',
    'that one',
    'this item',
    'that item',
    'same asset',
    'same one',
    'iska',
    'iski',
    'iske',
    'isko',
    'is ka ',
    'is ki ',
    'is ke ',
    'uska',
    'uski',
    'uske',
    'usko',
    'us ka ',
    'us ki ',
    'us ke ',
    'its ',
    'wahan',
    'wahaan',
    'this bazaar',
    'that bazaar',
    'ye wala',
    'yeh wala',
    'wo wala',
    'woh wala',
  ];

  /// Openings that continue the previous question ("and at Head Office?").
  static const List<String> _continuations = [
    'and ',
    'aur ',
    'also ',
    'what about',
    'how about',
    'or ',
    'phir ',
  ];

  /// Topics that are never about one asset, so a follow-up about them does
  /// not borrow the previous question's asset.
  static const Set<LocalAiTopic> _unrelatedToAssets = {
    LocalAiTopic.people,
    LocalAiTopic.departments,
    LocalAiTopic.bazaarDirectory,
  };

  static const List<String> _requestStatusPending = [
    'pending',
    'awaiting',
    'baqi',
    'waiting',
    'zer e ghaur',
    'not yet approved',
  ];
  static const List<String> _requestStatusApproved = [
    'approved',
    'manzoor',
    'accepted',
  ];
  static const List<String> _requestStatusRejected = [
    'reject',
    'declined',
    'mustarad',
    'na manzoor',
    'refused',
  ];

  static const List<String> _mineWords = [
    'my ',
    'mine',
    'meri ',
    'mere ',
    'mera ',
    'i made',
    'i sent',
    'i submitted',
    'i asked',
    'i raised',
    'maine',
    'mainay',
    'by me',
  ];

  /// Words that carry no entity: a token in this set never matches an asset,
  /// a person or a category by name.
  static const Set<String> _stopWords = {
    'the',
    'a',
    'an',
    'of',
    'in',
    'at',
    'on',
    'for',
    'to',
    'and',
    'or',
    'is',
    'are',
    'was',
    'were',
    'be',
    'been',
    'we',
    'our',
    'us',
    'me',
    'my',
    'you',
    'your',
    'it',
    'its',
    'this',
    'that',
    'these',
    'those',
    'what',
    'which',
    'who',
    'whom',
    'whose',
    'where',
    'when',
    'why',
    'how',
    'many',
    'much',
    'do',
    'does',
    'did',
    'have',
    'has',
    'had',
    'there',
    'here',
    'all',
    'any',
    'some',
    'each',
    'every',
    'per',
    'with',
    'by',
    'from',
    'give',
    'show',
    'list',
    'tell',
    'get',
    'find',
    'current',
    'currently',
    'now',
    'right',
    'please',
    'details',
    'detail',
    'info',
    'information',
    'about',
    'asset',
    'assets',
    'item',
    'items',
    'thing',
    'things',
    'stock',
    'inventory',
    'units',
    'unit',
    'quantity',
    'number',
    'count',
    'status',
    'condition',
    'location',
    'located',
    'kitne',
    'kitna',
    'kitni',
    'hain',
    'hai',
    'hy',
    'mein',
    'main',
    'ka',
    'ki',
    'ke',
    'ko',
    'se',
    'aur',
    'kya',
    'kaun',
    'konsa',
    'konsi',
    'kaunsa',
    'kaunsi',
    'kahan',
    'kaha',
    'sab',
    'sabhi',
    'kul',
    'hamare',
    'hamara',
    'hamari',
    'mera',
    'meri',
    'mere',
    'ye',
    'yeh',
    'woh',
    'wo',
    'iska',
    'uska',
    'iski',
    'uski',
    'batao',
    'bataen',
    'bata',
    'dikhao',
    'dikha',
    'wala',
    'wali',
    'wale',
    'sirf',
    'bhi',
    'abhi',
    'tak',
    'liye',
    'par',
    'pe',
    'pr',
    'saath',
    'sath',
    'hon',
    'ho',
    'raha',
    'rahe',
    'rahi',
    'gaya',
    'gaye',
    'gayi',
    'kar',
    'karo',
    'kr',
    'other',
    'others',
    'more',
    'most',
    'least',
    'than',
    'less',
    'then',
    'also',
    'still',
    'yet',
    'just',
    'only',
    'same',
    'new',
    'old',
    'one',
    'ones',
    'them',
    'they',
    'their',
    'will',
    'would',
    'can',
    'could',
    'should',
    'may',
    'might',
    'total',
    'overall',
    'want',
    'need',
    'know',
    'see',
    'look',
    'check',
    'kindly',
    'thanks',
    'hello',
    'salam',
    'office',
    'head',
    'bazaar',
    'bazaars',
    'bazar',
    'bazars',
    'sahulat',
    'org',
    'organisation',
    'organization',
    'company',
    'psba',
    'system',
    'app',
    'record',
    'records',
    'entry',
    'entries',
    'data',
    'report',
    'week',
    'month',
    'day',
    'days',
    'today',
    'yesterday',
    'last',
    'past',
    'since',
    'between',
    'before',
    'after',
    'recently',
    'ago',
    'time',
    'date',
    'kab',
    'kyun',
    'kion',
    'not',
    'no',
    'yes',
    'nahi',
    'nahin',
    'haan',
    'ji',
    'jee',
    'ya',
    'kis',
    'kisi',
    'koi',
    'hum',
    'humein',
    'mujhe',
    'aap',
    'ap',
    'tum',
  };

  static final Set<String> _vocabulary = {
    for (final list in <List<String>>[
      _overviewWords,
      _headOfficeWords,
      _bazaarWords,
      _directoryWords,
      _stockWords,
      _damagedWords,
      _repairWords,
      _lostWords,
      _disposedWords,
      _availableWords,
      _assignedWords,
      _movementWords,
      _requestWords,
      _peopleWords,
      _departmentWords,
      _valueWords,
      _warrantyWords,
      _backReferences,
      _continuations,
      _requestStatusPending,
      _requestStatusApproved,
      _requestStatusRejected,
      _mineWords,
    ])
      for (final phrase in list)
        for (final word in _words(phrase)) ...{word, ..._forms(word)},
  };

  /// Whether [word] is one of the words the topics are read from, in any
  /// form: "transferred" is 'transfer', "requests" is 'request'. Such a word
  /// says what is asked, never which record, so it never matches a name.
  static bool _isVocabulary(String word) {
    if (_stopWords.contains(word)) return true;
    if (_forms(word).any(_vocabulary.contains)) return true;
    return _vocabulary.any((v) => v.length >= 5 && word.startsWith(v));
  }

  // ---------------------------------------------------------------- matching

  static bool _isWordChar(int c) =>
      (c >= 0x30 && c <= 0x39) ||
      (c >= 0x61 && c <= 0x7a) ||
      (c >= 0x41 && c <= 0x5a);

  /// Whether [word] starts a word somewhere in [text], so 'damage' finds
  /// "damaged" but 'gum' does not find "argument".
  static bool _hasWord(String text, String word) {
    var from = 0;
    while (true) {
      final i = text.indexOf(word, from);
      if (i < 0) return false;
      if (i == 0 || !_isWordChar(text.codeUnitAt(i - 1))) return true;
      from = i + 1;
    }
  }

  static bool _hasAny(String text, List<String> words) =>
      words.any((word) => _hasWord(text, word));

  /// Whether [phrase] appears in [text] as whole words.
  static bool _hasPhrase(String text, String phrase) {
    if (phrase.isEmpty) return false;
    var from = 0;
    while (true) {
      final i = text.indexOf(phrase, from);
      if (i < 0) return false;
      final end = i + phrase.length;
      final startOk = i == 0 || !_isWordChar(text.codeUnitAt(i - 1));
      final endOk = end >= text.length || !_isWordChar(text.codeUnitAt(end));
      if (startOk && endOk) return true;
      from = i + 1;
    }
  }

  static Iterable<String> _words(String text) => text
      .toLowerCase()
      .split(RegExp(r'[^a-z0-9\-؀-ۿ]+'))
      .where((w) => w.isNotEmpty);

  /// A word and its likely singular forms, so "laptops" meets "Laptop" and
  /// "batteries" meets "Battery".
  static Set<String> _forms(String word) {
    final forms = {word};
    if (word.length > 4 && word.endsWith('ies')) {
      forms.add('${word.substring(0, word.length - 3)}y');
    }
    if (word.length > 4 && word.endsWith('es')) {
      forms.add(word.substring(0, word.length - 2));
    }
    if (word.length > 3 && word.endsWith('s')) {
      forms.add(word.substring(0, word.length - 1));
    }
    return forms;
  }

  /// Lower-case, Urdu-script words translated, padded with spaces so a phrase
  /// can be tested at either end.
  static String _normalize(String question) {
    final lower = question.toLowerCase();
    final tokens = lower
        .split(RegExp(r'[\s؟?،,.!:;]+'))
        .where((t) => t.isNotEmpty)
        .toSet();

    final extra = <String>[
      for (final entry in _urduWords.entries)
        if (entry.key.contains(' ')
            ? lower.contains(entry.key)
            : tokens.contains(entry.key))
          entry.value,
    ];

    final joined = extra.isEmpty ? lower : '$lower ${extra.join(' ')}';
    return ' ${joined.replaceAll(RegExp(r'\s+'), ' ').trim()} ';
  }

  /// How many days back a question looks ("last 7 days", "this month").
  static int? _windowDays(String text) {
    final explicit = RegExp(
      r'(?:last|past|pichle|pichhle|previous)\s+(\d{1,3})\s+(?:day|din)',
    ).firstMatch(text);
    if (explicit != null) return int.tryParse(explicit.group(1)!);

    if (_hasAny(text, ['today', 'aaj '])) return 1;
    if (_hasAny(text, ['week', 'hafta', 'hafte', '7 days', 'seven days'])) {
      return 7;
    }
    if (_hasAny(text, [
      'month',
      'mahina',
      'mahine',
      '30 days',
      'thirty days',
    ])) {
      return 30;
    }
    return null;
  }

  static String _day(DateTime date) => date.toIso8601String().split('T').first;

  static String _status(AssetModel a) => a.status.trim().toLowerCase();

  // The same status sets AssetProvider counts the totals with, so a list and
  // the figure above it always agree. The model's own helpers are used where
  // they exist.
  static bool isDamaged(AssetModel a) => a.isDamaged || _status(a) == 'damage';

  static bool isUnderRepair(AssetModel a) =>
      a.isUnderRepair || _status(a) == 'maintenance';

  static bool isLost(AssetModel a) =>
      _status(a) == 'lost' || _status(a) == 'missing';

  static bool isDisposed(AssetModel a) =>
      a.isRetired || _status(a) == 'disposed' || _status(a) == 'deleted';

  static bool isUnusable(AssetModel a) =>
      isDamaged(a) || isUnderRepair(a) || isLost(a) || isDisposed(a);
}

// =============================================================================
// ONE QUESTION, READ
// =============================================================================

/// Shorthand for the vocabulary and helpers of [LocalAiInventoryContext].
typedef _C = LocalAiInventoryContext;

/// The words of one question: its topics, filters and follow-up signals.
/// Entities (which asset, which Bazaar) need the records, so they are
/// resolved later, in [_Build].
class _Reading {
  _Reading(String question)
    : raw = question.toLowerCase().trim(),
      text = LocalAiInventoryContext._normalize(question) {
    final t = text;
    final trimmed = t.trim();

    wordCount = trimmed.isEmpty ? 0 : trimmed.split(' ').length;
    backReference = LocalAiInventoryContext._hasAny(t, _C._backReferences);
    continuation =
        _C._continuations.any(trimmed.startsWith) ||
        LocalAiInventoryContext._hasAny(t, const ['what about', 'how about']);
    weakReference =
        LocalAiInventoryContext._hasPhrase(t, 'it') ||
        LocalAiInventoryContext._hasPhrase(t, 'them');

    final has = LocalAiInventoryContext._hasAny;
    final requests = has(t, _C._requestWords);

    if (requests) topics.add(LocalAiTopic.requests);
    if (has(t, _C._peopleWords)) topics.add(LocalAiTopic.people);
    if (has(t, _C._departmentWords)) topics.add(LocalAiTopic.departments);
    if (has(t, _C._headOfficeWords)) topics.add(LocalAiTopic.headOffice);
    if (has(t, _C._damagedWords)) topics.add(LocalAiTopic.damaged);
    if (has(t, _C._repairWords)) topics.add(LocalAiTopic.underRepair);
    if (has(t, _C._lostWords)) topics.add(LocalAiTopic.lost);
    if (has(t, _C._disposedWords)) topics.add(LocalAiTopic.disposed);
    if (has(t, _C._availableWords)) topics.add(LocalAiTopic.available);

    // "assignment requests" are a kind of request, not assigned stock.
    if (has(t, _C._assignedWords) &&
        !(requests && has(t, const ['assignment']))) {
      topics.add(LocalAiTopic.assigned);
    }

    windowDays = LocalAiInventoryContext._windowDays(t);

    // Likewise "transfer requests": with requests in the question, only a
    // word that plainly means movement records adds them.
    if (requests) {
      if (has(t, _C._plainMovementWords)) topics.add(LocalAiTopic.movements);
    } else if (has(t, _C._movementWords) || windowDays != null) {
      topics.add(LocalAiTopic.movements);
    }

    if (has(t, _C._valueWords)) topics.add(LocalAiTopic.value);
    if (has(t, _C._warrantyWords)) topics.add(LocalAiTopic.warranty);

    if (has(t, _C._bazaarWords)) {
      final directory = has(t, _C._directoryWords);
      if (directory) topics.add(LocalAiTopic.bazaarDirectory);
      if (!directory || has(t, _C._stockWords)) {
        topics.add(LocalAiTopic.perBazaar);
      }
    }

    if (has(t, _C._overviewWords)) topics.add(LocalAiTopic.overview);
    namesWholeInventory = has(t, _C._wholeInventoryWords);

    // Filters.
    if (has(t, _C._requestStatusPending)) {
      requestStatus = 'pending';
    } else if (has(t, _C._requestStatusRejected)) {
      requestStatus = 'rejected';
    } else if (has(t, _C._requestStatusApproved)) {
      requestStatus = 'approved';
    }

    if (has(t, const ['transfer'])) {
      requestType = 'transfer';
    } else if (has(t, const ['assignment', 'assign'])) {
      requestType = 'assignment';
    } else if (has(t, const ['edit', 'change request', 'update request'])) {
      requestType = 'edit';
    } else if (has(t, const ['delete', 'deletion', 'removal'])) {
      requestType = 'delete';
    }

    mine = has(t, _C._mineWords);
    returnsOnly =
        has(t, const ['return', 'wapas', 'wapis']) &&
        !has(t, const ['transfer', 'moved', 'movement']);
    priority = has(t, const ['priority', 'urgent', 'high priority']);

    if (has(t, const ['super admin', 'superadmin', 'super-admin'])) {
      roleFilter = 'super_admin';
    } else if (has(t, const ['admin'])) {
      roleFilter = 'admin';
    } else if (has(t, const ['normal user', 'regular user', 'staff user'])) {
      roleFilter = 'user';
    }

    if (has(t, const ['inactive', 'disabled', 'blocked', 'band '])) {
      activeFilter = false;
    } else if (has(t, const ['active', 'enabled'])) {
      activeFilter = true;
    }
  }

  /// Lower-case, as InventoryAssistant.findAsset expects it.
  final String raw;

  /// [LocalAiInventoryContext._normalize]d.
  final String text;

  final Set<LocalAiTopic> topics = {};

  late final int wordCount;
  late final bool backReference;
  late final bool continuation;
  late final bool weakReference;

  int? windowDays;
  String? requestStatus;
  String? requestType;
  bool mine = false;
  bool returnsOnly = false;
  bool priority = false;
  String? roleFilter;
  bool? activeFilter;

  /// Whether the question speaks of the inventory as a whole ("how many
  /// assets do we have?") without naming any topic.
  bool namesWholeInventory = false;

  /// The topics the question names itself, beyond a general "total".
  Set<LocalAiTopic> get ownTopics =>
      topics.where((t) => t != LocalAiTopic.overview).toSet();

  bool get isShort => wordCount <= 6;

  /// A short question that names nothing at all, such as "details?" or
  /// "kahan hai?", so it can only mean the thing asked about before.
  ///
  /// A plain "total" or "how many assets" does not count: "What is our total
  /// inventory?" asked after a question about one asset is about the whole
  /// inventory, and only "and the total?" (a continuation) or "its total"
  /// (a back-reference) ties it to the earlier question.
  bool get isBareFollowUp => isShort && topics.isEmpty && !namesWholeInventory;

  /// Whether this question may take its topics from the one before it.
  bool get canBorrowTopics => backReference || continuation || isBareFollowUp;
}

/// The records one question names.
class _Entities {
  AssetModel? focus;
  List<AssetModel> matches = const [];
  List<String> categories = const [];
  String? bazaar;
  List<UserModel> persons = const [];
  String? department;

  /// The words that matched asset names, for a list's title.
  String nameHint = '';

  bool get isEmpty =>
      focus == null &&
      matches.isEmpty &&
      categories.isEmpty &&
      bazaar == null &&
      persons.isEmpty &&
      department == null;

  void borrow(_Entities other) {
    focus = other.focus;
    matches = other.matches;
    categories = other.categories;
    bazaar = other.bazaar;
    persons = other.persons;
    department = other.department;
    nameHint = other.nameHint;
  }
}

// =============================================================================
// SECTIONS AND FITTING
// =============================================================================

/// A `{columns, rows}` list whose visible length the fitter can shorten.
class _Table {
  _Table(this.columns, this.rows, {Map<String, Object?>? extra})
    : extra = extra ?? const {},
      shown = rows.length < _maxRows ? rows.length : _maxRows;

  /// The most rows a list starts with, before the budget is even considered.
  ///
  /// A chat answer never reads out more than this, and every list carries
  /// its full count in the title and its sums in `sumOfAll`, so the rest would
  /// only lengthen the prompt: on a laptop CPU, every extra hundred tokens is
  /// time the person waits before the first word of the answer.
  static const int _maxRows = 40;

  final List<String> columns;
  final List<List<Object?>> rows;
  final Map<String, Object?> extra;
  int shown;

  int get total => rows.length;

  Map<String, Object?> toData() => {
    ...extra,
    'columns': columns,
    'rows': rows.take(shown).toList(),
  };

  /// Removes the columns that are empty in every row, e.g. `designation` when
  /// nobody has one.
  _Table withoutEmptyColumns(Set<String> optional) {
    final keep = <int>[
      for (var i = 0; i < columns.length; i++)
        if (!optional.contains(columns[i]) ||
            rows.any((r) => r[i] != null && r[i].toString().trim().isNotEmpty))
          i,
    ];
    if (keep.length == columns.length) return this;

    return _Table(
      [for (final i in keep) columns[i]],
      [
        for (final row in rows) [for (final i in keep) row[i]],
      ],
      extra: extra,
    );
  }
}

/// One section before it is fitted: a plain value or a shortenable list.
class _Draft {
  _Draft.data(this.baseTitle, this.priority, this.data) : table = null;

  _Draft.table(this.baseTitle, this.priority, _Table this.table) : data = null;

  final String baseTitle;
  final int priority;
  final Object? data;
  final _Table? table;

  String get title {
    final t = table;
    if (t == null) return _fitTitle(baseTitle, '');
    if (t.total == 0) return _fitTitle(baseTitle, ' (none)');
    return _fitTitle(baseTitle, ' (showing ${t.shown} of ${t.total})');
  }

  static String _fitTitle(String base, String suffix) {
    final clean = LocalAiInventoryContext._redact(base.trim());
    final room = 120 - suffix.length;
    final head = clean.length > room
        ? '${clean.substring(0, room - 3).trimRight()}...'
        : clean;
    return '$head$suffix';
  }

  LocalAiContextSection toSection() =>
      LocalAiContextSection(title: title, data: table?.toData() ?? data);
}

// =============================================================================
// THE BUILD
// =============================================================================

/// One run of [LocalAiInventoryContext.build], for inputs that already passed
/// [LocalAiInventoryContext.accessProblem]. Holds the notes and draft sections
/// as they are collected, so each section builder stays small.
class _Build {
  _Build(this.inputs)
    : role = inputs.role,
      uid = inputs.signedInUid!.trim(),
      manager = inputs.role == 'super_admin' || inputs.role == 'admin';

  final LocalAiContextInputs inputs;
  final String role;
  final String uid;
  final bool manager;

  final List<String> _notes = [];
  final List<_Draft> _drafts = [];

  late InventorySnapshot _data;
  late Map<String, dynamic> _facts;

  bool _inventoryOk = false;
  bool _movementsOk = false;

  /// True when a User's movements were left out because their inventory,
  /// which decides which movements are theirs, could not be used.
  bool _movementsWithheld = false;

  static const int _never = 1000;
  static const int _focusPriority = 900;
  static const int _primary = 800;
  static const int _supporting = 700;
  static const int _background = 600;

  static final InventoryAssistant _finder = InventoryAssistant();

  LocalAiContextResult run() {
    _data = _scopedSnapshot();
    _facts = _data.toFacts(maxAssets: 0, now: inputs.retrievedAt);

    // ------------------------------------------------------------ reading
    final current = _Reading(inputs.question);
    final entities = _resolve(current);
    final ownEntity = !entities.isEmpty;
    final topics = {...current.topics};
    var filters = current;

    final previousText = inputs.previousQuestion?.trim() ?? '';
    final previous = previousText.isEmpty ? null : _Reading(previousText);

    final unrelated = current.ownTopics.any(
      LocalAiInventoryContext._unrelatedToAssets.contains,
    );

    // "and at Head Office?", "aur iska status?", "which bazaars have this
    // asset?": nothing named, so the previous question says what is meant.
    final mayBorrowEntity =
        current.backReference ||
        ((current.continuation || current.weakReference) && !unrelated) ||
        current.isBareFollowUp;

    if (!ownEntity && previous != null && mayBorrowEntity) {
      entities.borrow(_resolve(previous));
    }

    // "and the monitors?" after "show damaged laptops": the question names a
    // new thing and keeps the old topic.
    if (current.ownTopics.isEmpty &&
        previous != null &&
        (current.backReference ||
            current.continuation ||
            (current.isBareFollowUp && !ownEntity))) {
      topics.addAll(previous.topics);
      filters = previous;
    }

    if (entities.isEmpty && mayBorrowEntity) {
      _remembered(entities);
    }

    // Named only in part ("the canon"), but only one asset fits: that asset.
    if (entities.focus == null && entities.matches.length == 1) {
      entities.focus = entities.matches.single;
      entities.matches = const [];
    }

    // --------------------------------------------------------- sections
    _addTotals(topics);

    final focus = _inventoryOk ? entities.focus : null;

    if (focus != null) {
      _addAssetDetails(focus, topics);
    } else {
      if (entities.bazaar != null) _addBazaarContents(entities);
      _addAssetLists(entities, topics);
      if (topics.contains(LocalAiTopic.perBazaar) && entities.bazaar == null) {
        _addPerBazaar(entities);
      }
      if (topics.contains(LocalAiTopic.warranty)) _addWarranty(entities);
      if (topics.contains(LocalAiTopic.value)) _addValue(entities);
    }

    if (topics.contains(LocalAiTopic.bazaarDirectory)) {
      _addDirectory(current, filters);
    }

    if (topics.contains(LocalAiTopic.movements) && focus == null) {
      _addMovements(entities, filters);
    }

    if (topics.contains(LocalAiTopic.requests)) {
      _addRequests(entities, filters, focus);
    }

    if (topics.contains(LocalAiTopic.people) ||
        topics.contains(LocalAiTopic.departments) ||
        entities.persons.isNotEmpty ||
        entities.department != null) {
      _addPeople(entities, topics, filters);
    }

    final nothingAsked = topics.isEmpty && entities.isEmpty;
    if (focus == null &&
        (topics.contains(LocalAiTopic.overview) || nothingAsked)) {
      _addOverview(topics);
    }

    // Worked out from the full records, not from the fitted context, and only
    // now: every note about data that could not be read in full has been
    // added by the sections above, and any such note rules it out.
    final answer = _DirectAnswer(
      this,
      question: current,
      entities: entities,
      topics: topics,
      filters: filters,
    ).text();

    final context = _fit().withDirectAnswer(answer);

    return LocalAiContextResult(
      context: context,
      focusAsset: focus,
      focusBazaar: focus == null ? entities.bazaar : null,
      topics: topics,
    );
  }

  // ------------------------------------------------------------ permission

  /// The snapshot cut down to what this role may see, with every source's
  /// state turned into a note where it matters.
  InventorySnapshot _scopedSnapshot() {
    final source = inputs.snapshot;

    final inventory = inputs.inventoryState;
    final loading = inventory.loading || source.inventoryLoading;
    final present = source.assets.isNotEmpty;

    if (!inputs.inventoryInScope) {
      _notes.add(
        'The inventory loaded in the app did not match this account\'s '
        'permissions yet, so none of it was included. Ask again in a moment.',
      );
    } else if (inventory.failed && !present) {
      _notes.add(
        'The inventory could not be loaded: '
        '${LocalAiInventoryContext.shortReason(inventory.error)}.',
      );
    } else if (loading && !present) {
      _notes.add(
        'The inventory was still loading, so no inventory figures are '
        'included. Ask again in a moment.',
      );
    } else {
      _inventoryOk = true;
      if (inventory.failed) {
        _notes.add(
          'The inventory listener reported an error, so these figures may be '
          'out of date: ${LocalAiInventoryContext.shortReason(inventory.error)}.',
        );
      } else if (loading) {
        _notes.add(
          'The inventory was still loading when this was read, so the figures '
          'may be incomplete.',
        );
      }
    }

    final assets = _inventoryOk ? source.assets : const <AssetModel>[];

    // A User reads all inventory and all movement history, read-only, so the
    // movement records need no owner filter any more. What a User still may
    // not see is kept out elsewhere: the user directory, activity logs, and
    // anyone else's requests.
    var movements = source.deployments;
    if (!_inventoryOk && role == 'user') {
      movements = const [];
    }

    // The Bazaar figures are worked out from the movement records together
    // with the inventory. When the inventory could not be used, an empty list
    // means "unknown" and must not reach the model as zero stock everywhere.
    _movementsWithheld = !_inventoryOk && role == 'user';

    final movementState = inputs.movementState;
    _movementsOk =
        !_movementsWithheld &&
        !((movementState.failed || movementState.loading) && movements.isEmpty);

    return InventorySnapshot(
      assets: assets,
      bazaars: source.bazaars,
      deployments: movements,
      totalQuantity: source.totalQuantity,
      headOfficeStock: source.headOfficeStock,
      assignedQuantity: source.assignedQuantity,
      bazaarQuantity: source.bazaarQuantity,
      damagedQuantity: source.damagedQuantity,
      underRepairQuantity: source.underRepairQuantity,
      lostQuantity: source.lostQuantity,
      disposedQuantity: source.disposedQuantity,
      unavailableAtHeadOffice: source.unavailableAtHeadOffice,
      totalInventoryValue: source.totalInventoryValue,
      roleLabel: source.roleLabel,
      scopeNote: source.scopeNote,
      bazaarDataLoaded: source.bazaarDataLoaded,
      inventoryLoading: source.inventoryLoading,
      // Holder names are the user directory by another route, so only an
      // account that may read the directory gets them.
      holders: manager ? source.holders : const <String, String>{},
    );
  }

  /// A note for a source the question needed but could not have, once.
  void _needMovements() {
    if (_movementsOk) {
      final state = inputs.movementState;
      if (state.failed) {
        _addNote(
          'The transfer records reported an error, so Bazaar figures may be '
          'out of date: ${LocalAiInventoryContext.shortReason(state.error)}.',
        );
      } else if (state.loading) {
        _addNote(
          'The transfer records were still loading, so Bazaar figures may be '
          'incomplete.',
        );
      }
      return;
    }

    if (_movementsWithheld) {
      _addNote(
        'Bazaar stock and transfers are worked out from this account\'s '
        'inventory, which could not be used for this question, so none are '
        'included.',
      );
      return;
    }

    final state = inputs.movementState;
    _addNote(
      state.failed
          ? 'Transfers and Bazaar stock could not be loaded: '
                '${LocalAiInventoryContext.shortReason(state.error)}.'
          : 'Transfers and Bazaar stock were still loading, so none are '
                'included. Ask again in a moment.',
    );
  }

  void _addNote(String note) {
    if (!_notes.contains(note)) _notes.add(note);
  }

  // ----------------------------------------------------------- resolution

  _Entities _resolve(_Reading reading) {
    final e = _Entities();
    final text = reading.text;
    final assets = _inventoryOk ? _data.assets : const <AssetModel>[];

    e.bazaar = _finder.findBazaar(reading.raw, _data);

    // Categories: "laptops", "Laptop stock", "monitors aur printers".
    final categories = <String>{};
    for (final asset in assets) {
      final category = asset.category.trim();
      if (category.isEmpty) continue;
      categories.add(category);
    }

    final matchedCategories = <String>[];
    for (final category in categories) {
      final lower = category.toLowerCase();
      if (LocalAiInventoryContext._stopWords.contains(lower)) continue;

      final variants = {
        ...LocalAiInventoryContext._forms(lower),
        '${lower}s',
        '${lower}es',
        if (lower.endsWith('y')) '${lower.substring(0, lower.length - 1)}ies',
      };

      if (variants.any((v) => LocalAiInventoryContext._hasPhrase(text, v))) {
        matchedCategories.add(category);
      }
    }
    e.categories = matchedCategories;

    // One asset by its tag, serial or full name.
    final found = assets.isEmpty ? null : _finder.findAsset(reading.raw, _data);
    if (found != null) {
      final tag = found.assetId.trim().toLowerCase();
      final serial = found.serialNumber.trim().toLowerCase();
      final byTag = tag.isNotEmpty && reading.raw.contains(tag);
      final bySerial = serial.isNotEmpty && reading.raw.contains(serial);

      if (byTag || bySerial) {
        e.focus = found;
      } else {
        // A name several records share is not one asset, and a name that is
        // also a category ("Laptop") means the category.
        final name = found.name.trim().toLowerCase();
        final sameName = assets
            .where((a) => a.name.trim().toLowerCase() == name)
            .toList();

        final isCategory = matchedCategories.any(
          (c) => LocalAiInventoryContext._forms(
            c.toLowerCase(),
          ).any(LocalAiInventoryContext._forms(name).contains),
        );

        if (sameName.length > 1) {
          e.matches = sameName;
          e.nameHint = found.name.trim();
        } else if (!isCategory) {
          e.focus = found;
        }
      }
    }

    // People and departments, for the accounts that may see the directory.
    final taken = <String>{
      for (final c in matchedCategories)
        ...LocalAiInventoryContext._words(
          c,
        ).expand(LocalAiInventoryContext._forms),
      if (e.bazaar != null) ...LocalAiInventoryContext._words(e.bazaar!),
    };

    if (manager) _resolvePeople(reading, e, taken);

    // Assets named in part: "dell", "latitude", "canon".
    if (e.focus == null && e.matches.isEmpty && assets.isNotEmpty) {
      final tokens = <String>{
        for (final word in LocalAiInventoryContext._words(text))
          if (word.length >= 3 &&
              RegExp('[a-z]').hasMatch(word) &&
              !LocalAiInventoryContext._isVocabulary(word) &&
              !LocalAiInventoryContext._forms(word).any(taken.contains))
            word,
      };

      if (tokens.isNotEmpty) {
        final used = <String>{};
        final matched = <AssetModel>[];

        for (final asset in assets) {
          final words = LocalAiInventoryContext._words(
            '${asset.name} ${asset.brand} ${asset.model}',
          ).toSet();

          for (final token in tokens) {
            if (LocalAiInventoryContext._forms(token).any(words.contains)) {
              matched.add(asset);
              used.add(token);
              break;
            }
          }
        }

        if (matched.isNotEmpty) {
          // "dell laptops": the Dell ones among the laptops.
          if (matchedCategories.isNotEmpty) {
            final wanted = matchedCategories
                .map((c) => c.toLowerCase())
                .toSet();
            final narrowed = matched
                .where((a) => wanted.contains(a.category.trim().toLowerCase()))
                .toList();
            if (narrowed.isNotEmpty) {
              e.matches = narrowed;
              e.nameHint = used.join(' ');
            }
          } else {
            e.matches = matched;
            e.nameHint = used.join(' ');
          }
        }
      }
    }

    return e;
  }

  void _resolvePeople(_Reading reading, _Entities e, Set<String> taken) {
    final people = _people();
    if (people.isEmpty) return;

    final text = reading.text;

    // Departments: "the IT department", "Accounts shoba", "Procurement".
    final departments = {
      for (final p in people)
        if (p.department.trim().isNotEmpty) p.department.trim(),
    };

    for (final department in departments) {
      final lower = department.toLowerCase();
      if (!LocalAiInventoryContext._hasPhrase(text, lower)) continue;

      final named =
          lower.length >= 4 ||
          LocalAiInventoryContext._hasAny(text, [
            '$lower department',
            '$lower dept',
            '$lower shoba',
            '$lower section',
            '$lower wing',
            'department of $lower',
          ]);

      if (named &&
          (e.department == null || lower.length > e.department!.length)) {
        e.department = department;
      }
    }

    if (e.department != null) {
      taken.addAll(LocalAiInventoryContext._words(e.department!));
    }

    // Names: a full name always counts; a single first or last name only when
    // the question is about people or what somebody holds, and only when the
    // word is not also an asset word.
    final aboutPeople =
        reading.topics.contains(LocalAiTopic.people) ||
        reading.topics.contains(LocalAiTopic.assigned) ||
        LocalAiInventoryContext._hasAny(text, const [
          'have',
          'has',
          'held',
          'paas',
          'pas ',
          'with',
          'using',
        ]);

    final assetWords = <String>{
      for (final a in _data.assets)
        ...LocalAiInventoryContext._words('${a.name} ${a.brand} ${a.category}'),
    };

    final matched = <UserModel>[];
    for (final person in people) {
      final name = person.name.trim().toLowerCase();
      if (name.length < 3) continue;

      if (LocalAiInventoryContext._hasPhrase(text, name)) {
        matched.add(person);
        continue;
      }

      if (!aboutPeople) continue;

      final parts = LocalAiInventoryContext._words(name).where(
        (w) =>
            w.length >= 3 &&
            !LocalAiInventoryContext._isVocabulary(w) &&
            !assetWords.contains(w) &&
            !taken.contains(w),
      );

      if (parts.any((w) => LocalAiInventoryContext._hasPhrase(text, w))) {
        matched.add(person);
      }
    }

    e.persons = matched.length > 10 ? matched.sublist(0, 10) : matched;
    for (final person in e.persons) {
      taken.addAll(LocalAiInventoryContext._words(person.name));
    }
  }

  void _remembered(_Entities e) {
    final id = inputs.rememberedAssetId?.trim() ?? '';
    if (id.isNotEmpty && _inventoryOk) {
      for (final asset in _data.assets) {
        if (asset.id == id) {
          e.focus = asset;
          return;
        }
      }
    }

    final bazaar = inputs.rememberedBazaar?.trim() ?? '';
    if (bazaar.isNotEmpty) {
      for (final b in _data.bazaars) {
        if (b.name.trim().toLowerCase() == bazaar.toLowerCase()) {
          e.bazaar = b.name.trim();
          return;
        }
      }
    }
  }

  /// The user directory, for the roles that may read it.
  List<UserModel> _people() {
    if (!manager) return const [];
    return inputs.people
        .where((p) => p.status.trim().toLowerCase() != 'deleted')
        .toList();
  }

  // --------------------------------------------------------------- rows

  static const List<String> _numericColumns = [
    'quantity',
    'headOffice',
    'atBazaars',
    'assigned',
    'totalValue',
  ];

  List<Object?> _assetRow(AssetModel a, List<String> columns) {
    final facts = InventorySnapshot.assetFacts(a);
    return [
      for (final column in columns)
        switch (column) {
          'heldBy' => _data.holderOf(a).isEmpty ? null : _data.holderOf(a),
          _ => facts[column],
        },
    ];
  }

  _Table _assetTable(
    List<AssetModel> assets,
    List<String> columns, {
    required String sortBy,
  }) {
    final facts = {
      for (final a in assets) a.id: InventorySnapshot.assetFacts(a),
    };
    num valueOf(AssetModel a, String key) => (facts[a.id]?[key] as num?) ?? 0;

    final sorted = [...assets]
      ..sort((a, b) {
        final byValue = valueOf(b, sortBy).compareTo(valueOf(a, sortBy));
        return byValue != 0 ? byValue : a.assetId.compareTo(b.assetId);
      });

    final sums = <String, Object?>{'records': assets.length};
    for (final column in _numericColumns) {
      if (!columns.contains(column)) continue;
      final sum = assets.fold<num>(0, (s, a) => s + valueOf(a, column));
      sums[column] = sum is double && sum == sum.roundToDouble()
          ? sum.round()
          : sum;
    }

    return _Table(
      columns,
      [for (final a in sorted) _assetRow(a, columns)],
      extra: {'sumOfAll': sums},
    ).withoutEmptyColumns(const {'heldBy'});
  }

  List<Object?> _movementRow(DeploymentModel m, {bool withAsset = true}) => [
    _dayOf(m.deploymentDate),
    if (withAsset) m.assetId.trim().isEmpty ? null : m.assetId.trim(),
    if (withAsset) m.assetName.trim().isEmpty ? null : m.assetName.trim(),
    m.quantity,
    (m.fromBazaarName ?? m.fromLocation).trim(),
    (m.toBazaarName ?? m.toLocation).trim(),
    m.action.trim().toLowerCase(),
    m.status.trim(),
  ];

  static String _dayOf(DateTime date) => LocalAiInventoryContext._day(date);

  static String _capitalised(String text) =>
      text.isEmpty ? text : '${text[0].toUpperCase()}${text.substring(1)}';

  // ------------------------------------------------------------- totals

  void _addTotals(Set<LocalAiTopic> topics) {
    if (!_inventoryOk) return;

    final totals = Map<String, dynamic>.from(_facts['totals'] as Map);
    if (!topics.contains(LocalAiTopic.value)) {
      totals
        ..remove('totalInventoryValue')
        ..remove('currency');
    }

    totals['meaning'] =
        'Units. totalQuantity = headOfficeAvailable + unavailableAtHeadOffice '
        '+ atBazaars + assigned. damaged, underRepair, lost and disposed are '
        'units at Head Office only.';

    _drafts.add(_Draft.data('Inventory totals', _never, totals));
  }

  // ------------------------------------------------------- one asset

  void _addAssetDetails(AssetModel asset, Set<LocalAiTopic> topics) {
    final details = <String, Object?>{...InventorySnapshot.assetFacts(asset)};

    final holder = _data.holderOf(asset);
    if (holder.isNotEmpty) details['heldBy'] = holder;

    final ends = InventorySnapshot.warrantyEnds(asset);
    if (ends != null) {
      details['warrantyEnds'] = _dayOf(ends);
      details['warrantyDaysLeft'] = ends.difference(inputs.retrievedAt).inDays;
    }

    // Where its units are: Head Office, each Bazaar (from the Active movement
    // records, as the Bazaar screens read them), and assigned.
    final where = <List<Object?>>[];
    if (asset.calculatedHeadOfficeQuantity > 0) {
      where.add(['Head Office', asset.calculatedHeadOfficeQuantity]);
    }

    final movements = _movementsOk
        ? (_data.movementsForAsset(asset)
            ..sort((a, b) => b.deploymentDate.compareTo(a.deploymentDate)))
        : <DeploymentModel>[];

    final atBazaars = <String, int>{};
    for (final m in movements) {
      if (!m.isActive) continue;
      final name = (m.toBazaarName ?? m.toLocation).trim();
      if (name.isEmpty) continue;
      atBazaars[name] = (atBazaars[name] ?? 0) + m.quantity;
    }
    for (final entry in atBazaars.entries) {
      where.add([entry.key, entry.value]);
    }

    if (asset.calculatedAssignedQuantity > 0) {
      where.add(['Assigned', asset.calculatedAssignedQuantity]);
    }

    details['where'] = {
      'columns': const ['place', 'units'],
      'rows': where,
    };

    if (!_movementsOk && asset.calculatedDeployedQuantity > 0) _needMovements();

    final wantsHistory =
        topics.contains(LocalAiTopic.movements) ||
        topics.contains(LocalAiTopic.perBazaar);
    if (wantsHistory && movements.isNotEmpty) {
      details['movements'] = {
        'total': movements.length,
        'columns': const ['date', 'quantity', 'from', 'to', 'action', 'status'],
        'rows': [
          for (final m in movements.take(10)) _movementRow(m, withAsset: false),
        ],
      };
    }

    final label = asset.assetId.trim().isEmpty
        ? asset.name.trim()
        : '${asset.assetId.trim()} (${asset.name.trim()})';

    _drafts.add(
      _Draft.data(
        'Asset $label',
        _focusPriority,
        LocalAiInventoryContext.scrubData(details),
      ),
    );
  }

  // ----------------------------------------------------- lists of assets

  /// The assets a question narrows to by category or name, or null for all.
  List<AssetModel>? _base(_Entities e) {
    if (e.matches.isNotEmpty) return e.matches;
    if (e.categories.isNotEmpty) {
      final wanted = e.categories.map((c) => c.toLowerCase()).toSet();
      return _data.assets
          .where((a) => wanted.contains(a.category.trim().toLowerCase()))
          .toList();
    }
    return null;
  }

  String _baseLabel(_Entities e) {
    if (e.matches.isNotEmpty) return 'matching "${e.nameHint}"';
    if (e.categories.isNotEmpty) return e.categories.join(' and ');
    return '';
  }

  void _addAssetLists(_Entities e, Set<LocalAiTopic> topics) {
    if (!_inventoryOk) return;

    final base = _base(e);
    final label = _baseLabel(e);
    final all = base ?? _data.assets;
    final withCategory = e.categories.length != 1;
    final value = topics.contains(LocalAiTopic.value);

    List<String> columns(List<String> middle) => [
      'assetId',
      'name',
      if (withCategory) 'category',
      ...middle,
      if (value) ...['unitPrice', 'totalValue'],
    ];

    String titled(String what) => label.isEmpty ? what : '$what - $label';

    final filters = <(LocalAiTopic, String, bool Function(AssetModel))>[
      (
        LocalAiTopic.damaged,
        'Damaged assets',
        LocalAiInventoryContext.isDamaged,
      ),
      (
        LocalAiTopic.underRepair,
        'Assets under repair',
        LocalAiInventoryContext.isUnderRepair,
      ),
      (
        LocalAiTopic.lost,
        'Lost or missing assets',
        LocalAiInventoryContext.isLost,
      ),
      (
        LocalAiTopic.disposed,
        'Disposed or retired assets',
        LocalAiInventoryContext.isDisposed,
      ),
    ];

    var listed = false;

    for (final (topic, title, test) in filters) {
      if (!topics.contains(topic)) continue;
      listed = true;
      _drafts.add(
        _Draft.table(
          titled(title),
          _primary,
          _assetTable(
            all.where(test).toList(),
            columns(['status', 'quantity', 'headOffice']),
            sortBy: 'quantity',
          ),
        ),
      );
    }

    if (topics.contains(LocalAiTopic.available)) {
      listed = true;
      _drafts.add(
        _Draft.table(
          titled('Assets available at Head Office'),
          _primary,
          _assetTable(
            all
                .where(
                  (a) =>
                      !LocalAiInventoryContext.isUnusable(a) &&
                      a.calculatedHeadOfficeQuantity > 0,
                )
                .toList(),
            columns(['headOffice']),
            sortBy: 'headOffice',
          ),
        ),
      );
    }

    if (topics.contains(LocalAiTopic.assigned)) {
      listed = true;
      _drafts.add(
        _Draft.table(
          titled('Assigned assets'),
          _primary,
          _assetTable(
            all.where((a) => a.calculatedAssignedQuantity > 0).toList(),
            columns(['assigned', 'heldBy']),
            sortBy: 'assigned',
          ),
        ),
      );
    }

    if (topics.contains(LocalAiTopic.headOffice) && !listed) {
      listed = true;
      _drafts.add(
        _Draft.table(
          titled('Assets at Head Office'),
          _primary,
          _assetTable(
            all.where((a) => a.calculatedHeadOfficeQuantity > 0).toList(),
            columns(['status', 'headOffice']),
            sortBy: 'headOffice',
          ),
        ),
      );
    }

    // "Show the current stock of laptops", "dell ke kitne hain".
    if (base != null && !listed) {
      final what = e.matches.isNotEmpty
          ? 'Assets matching "${e.nameHint}"'
          : '${e.categories.join(' and ')} stock';
      _drafts.add(
        _Draft.table(
          what,
          _primary,
          _assetTable(
            base,
            columns([
              'status',
              'quantity',
              'headOffice',
              'atBazaars',
              'assigned',
            ]),
            sortBy: 'quantity',
          ),
        ),
      );
    }
  }

  // ------------------------------------------------------------- Bazaars

  void _addBazaarContents(_Entities e) {
    final bazaar = e.bazaar!;
    final key = bazaar.toLowerCase();

    BazaarModel? record;
    for (final b in _data.bazaars) {
      if (b.name.trim().toLowerCase() == key) record = b;
    }

    final about = <String, Object?>{
      'city': ?(record == null || record.location.trim().isEmpty
          ? null
          : record.location.trim()),
      'active': ?record?.isActive,
    };

    _needMovements();

    // Without the movement records the Bazaar's contents are unknown, not
    // empty; what is known about the Bazaar itself is still sent.
    if (!_movementsOk) {
      if (about.isNotEmpty) {
        _drafts.add(_Draft.data('Bazaar $bazaar', _supporting, about));
      }
      return;
    }

    final (:tags, :units, :names) = _stockAtBazaar(e);

    final label = _baseLabel(e);
    final title = label.isEmpty ? 'Stock at $bazaar' : '$label at $bazaar';

    _drafts.add(
      _Draft.table(
        title,
        _focusPriority - 20,
        _Table(
          const ['assetId', 'name', 'units'],
          [
            for (final tag in tags) [tag, names[tag], units[tag]],
          ],
          extra: {
            ...about,
            'sumOfAll': {
              'assetRecords': tags.length,
              'units': units.values.fold<int>(0, (s, u) => s + u),
            },
          },
        ),
      ),
    );
  }

  /// What is at the Bazaar [e] names, asset by asset (tag, or name when a
  /// movement has no tag), most units first. Shared by [_addBazaarContents]
  /// and the direct answer.
  ({List<String> tags, Map<String, int> units, Map<String, String> names})
  _stockAtBazaar(_Entities e) {
    final key = e.bazaar!.toLowerCase();

    final base = _base(e);
    final allowed = base == null
        ? null
        : {
            for (final a in base) ...[a.id, a.assetId.trim()],
          };

    final units = <String, int>{};
    final names = <String, String>{};

    for (final m in _data.deployments) {
      if (!m.isActive) continue;
      final to = (m.toBazaarName ?? m.toLocation).trim().toLowerCase();
      if (to != key) continue;
      if (allowed != null &&
          !allowed.contains(m.assetDocumentId.trim()) &&
          !allowed.contains(m.assetId.trim())) {
        continue;
      }

      final tag = m.assetId.trim().isEmpty
          ? m.assetName.trim()
          : m.assetId.trim();
      if (tag.isEmpty) continue;

      units[tag] = (units[tag] ?? 0) + m.quantity;
      names[tag] = m.assetName.trim();
    }

    final tags = units.keys.toList()
      ..sort((a, b) => units[b]!.compareTo(units[a]!));

    return (tags: tags, units: units, names: names);
  }

  void _addPerBazaar(_Entities e) {
    _needMovements();
    if (!_movementsOk) return;

    final (:names, :units, :records, :active) = _stockAtEachBazaar(e);
    final label = _baseLabel(e);

    _drafts.add(
      _Draft.table(
        label.isEmpty ? 'Stock at each Bazaar' : '$label stock at each Bazaar',
        _primary,
        _Table(
          const ['bazaar', 'units', 'assetRecords', 'active'],
          [
            for (final name in names)
              [name, units[name], records[name]?.length ?? 0, active[name]],
          ],
          extra: {
            'sumOfAll': {
              'units': units.values.fold<int>(0, (s, u) => s + u),
              'bazaarsWithStock': units.values.where((u) => u > 0).length,
            },
          },
        ).withoutEmptyColumns(const {'active'}),
      ),
    );
  }

  /// Units at each Bazaar, most first, including the Bazaars with none.
  /// Shared by [_addPerBazaar] and the direct answer.
  ({
    List<String> names,
    Map<String, int> units,
    Map<String, Set<String>> records,
    Map<String, bool> active,
  })
  _stockAtEachBazaar(_Entities e) {
    final base = _base(e);
    final allowed = base == null
        ? null
        : {
            for (final a in base) ...[a.id, a.assetId.trim()],
          };

    // Units come from the same figure toFacts gives the model elsewhere
    // (bazaarStock); only a category or name filter needs its own count.
    final units = <String, int>{};
    final records = <String, Set<String>>{};

    for (final m in _data.deployments) {
      if (!m.isActive) continue;
      final name = (m.toBazaarName ?? m.toLocation).trim();
      if (name.isEmpty) continue;
      if (allowed != null &&
          !allowed.contains(m.assetDocumentId.trim()) &&
          !allowed.contains(m.assetId.trim())) {
        continue;
      }

      units[name] = (units[name] ?? 0) + m.quantity;
      records
          .putIfAbsent(name, () => <String>{})
          .add(
            m.assetId.trim().isEmpty ? m.assetName.trim() : m.assetId.trim(),
          );
    }

    if (allowed == null) {
      final stock = Map<String, dynamic>.from(_facts['bazaarStock'] as Map);
      units
        ..clear()
        ..addAll({
          for (final entry in stock.entries)
            entry.key: (entry.value as num).toInt(),
        });
    }

    // Bazaars with nothing at them are listed too, so "which Bazaar has no
    // stock" is answerable rather than invisible.
    final active = <String, bool>{};
    for (final b in _data.bazaars) {
      final name = b.name.trim();
      if (name.isEmpty) continue;
      active[name] = b.isActive;
      units.putIfAbsent(name, () => 0);
    }

    final names = units.keys.toList()
      ..sort((a, b) {
        final byUnits = units[b]!.compareTo(units[a]!);
        return byUnits != 0 ? byUnits : a.compareTo(b);
      });

    return (names: names, units: units, records: records, active: active);
  }

  void _addDirectory(_Reading reading, _Reading filters) {
    final state = inputs.bazaarState;
    final bazaars = _data.bazaars;

    if (bazaars.isEmpty && (state.failed || state.loading)) {
      _addNote(
        state.failed
            ? 'The Bazaar list could not be loaded: '
                  '${LocalAiInventoryContext.shortReason(state.error)}.'
            : 'The Bazaar list was still loading, so it is not included.',
      );
      return;
    }

    final (:list, :title) = _bazaarsFor(reading, filters);

    _drafts.add(
      _Draft.table(
        title,
        _primary,
        _Table(
          const ['bazaar', 'city', 'active'],
          [
            for (final b in list)
              [
                b.name.trim(),
                b.location.trim().isEmpty ? null : b.location.trim(),
                b.isActive,
              ],
          ],
          extra: {
            'allBazaars': {
              'total': bazaars.length,
              'active': bazaars.where((b) => b.isActive).length,
              'disabled': bazaars.where((b) => !b.isActive).length,
            },
          },
        ).withoutEmptyColumns(const {'city'}),
      ),
    );
  }

  /// The Bazaars a question about the Bazaar list asks for (active, disabled,
  /// in a named city), by name, and the words that describe them. Shared by
  /// [_addDirectory] and the direct answer.
  ({List<BazaarModel> list, String title}) _bazaarsFor(
    _Reading reading,
    _Reading filters,
  ) {
    final bazaars = _data.bazaars;
    var list = bazaars.toList();

    final active = filters.activeFilter;
    if (active != null) list = list.where((b) => b.isActive == active).toList();

    final cities = {
      for (final b in bazaars)
        if (b.location.trim().length >= 3) b.location.trim(),
    };
    final city = cities
        .where(
          (c) =>
              LocalAiInventoryContext._hasPhrase(reading.text, c.toLowerCase()),
        )
        .toSet();
    if (city.isNotEmpty) {
      list = list.where((b) => city.contains(b.location.trim())).toList();
    }

    list.sort((a, b) => a.name.compareTo(b.name));

    final what = switch (active) {
      true => 'Active Bazaars',
      false => 'Disabled Bazaars',
      null => 'Bazaars',
    };

    return (
      list: list,
      title: city.isEmpty ? what : '$what in ${city.join(' and ')}',
    );
  }

  // ----------------------------------------------------------- movements

  void _addMovements(_Entities e, _Reading filters) {
    _needMovements();
    if (!_movementsOk) return;

    final (list, qualifiers) = _movementsFor(e, filters);

    final tags = {
      for (final m in list)
        m.assetId.trim().isEmpty ? m.assetName.trim() : m.assetId.trim(),
    };

    _drafts.add(
      _Draft.table(
        ['Movements', ...qualifiers].join(' '),
        _primary,
        _Table(
          const [
            'date',
            'assetId',
            'name',
            'quantity',
            'from',
            'to',
            'action',
            'status',
          ],
          [for (final m in list) _movementRow(m)],
          extra: {
            'sumOfAll': {
              'movements': list.length,
              'distinctAssets': tags.length,
              'units': list.fold<int>(0, (s, m) => s + m.quantity),
            },
          },
        ),
      ),
    );

    // The whole picture, from toFacts: how many movements there are in all,
    // by status and by age.
    final summary = _facts['movements'];
    if (summary is Map) {
      final byAction = <String, int>{};
      for (final m in _data.deployments) {
        final action = m.action.trim().toLowerCase();
        if (action.isEmpty) continue;
        byAction[action] = (byAction[action] ?? 0) + 1;
      }

      _drafts.add(
        _Draft.data('All movements, summary', _supporting, {
          for (final entry in summary.entries)
            if (entry.key != 'recent') entry.key.toString(): entry.value,
          'byAction': byAction,
        }),
      );
    }
  }

  /// The movements a question asks about, newest first, and the words that
  /// describe the filter ("in the last 7 days"). Shared by [_addMovements]
  /// and the direct answer, so both count the same records.
  (List<DeploymentModel>, List<String>) _movementsFor(
    _Entities e,
    _Reading filters,
  ) {
    var list = _data.deployments.toList();
    final qualifiers = <String>[];

    final base = _base(e);
    if (base != null) {
      final allowed = {
        for (final a in base) ...[a.id, a.assetId.trim()],
      };
      list = list
          .where(
            (m) =>
                allowed.contains(m.assetDocumentId.trim()) ||
                allowed.contains(m.assetId.trim()),
          )
          .toList();
      qualifiers.add('of ${_baseLabel(e)}');
    }

    final bazaar = e.bazaar?.toLowerCase();
    if (bazaar != null) {
      list = list.where((m) {
        final to = (m.toBazaarName ?? m.toLocation).trim().toLowerCase();
        final from = (m.fromBazaarName ?? m.fromLocation).trim().toLowerCase();
        return to == bazaar || from == bazaar;
      }).toList();
      qualifiers.add('to or from ${e.bazaar}');
    }

    if (filters.returnsOnly) {
      list = list.where((m) => m.isReturn).toList();
      qualifiers.add('(returns)');
    }

    final days = filters.windowDays;
    if (days != null) {
      final since = inputs.retrievedAt.subtract(Duration(days: days));
      list = list.where((m) => !m.deploymentDate.isBefore(since)).toList();
      qualifiers.add(days == 1 ? 'today' : 'in the last $days days');
    }

    list.sort((a, b) => b.deploymentDate.compareTo(a.deploymentDate));

    return (list, qualifiers);
  }

  // ------------------------------------------------------------ requests

  /// The requests this account may see.
  ///
  /// Defence in depth: RequestService already scopes the stream by role. A
  /// User is cut down again to their own requests, as firestore.rules allow;
  /// an Admin's list is the service's own filtered one.
  List<RequestModel> _visibleRequests() => role == 'user'
      ? inputs.requests
            .where(
              (r) => r.requestedBy.trim() == uid || r.receiverId.trim() == uid,
            )
            .toList()
      : inputs.requests.toList();

  void _addRequests(_Entities e, _Reading filters, AssetModel? focus) {
    final state = inputs.requestState;
    final visible = _visibleRequests();

    if (state.failed) {
      _addNote(
        'Requests could not be loaded: '
        '${LocalAiInventoryContext.shortReason(state.error)}.',
      );
      if (visible.isEmpty) return;
    } else if (state.loading) {
      if (visible.isEmpty) {
        _addNote('Requests were still loading, so none are included.');
        return;
      }
      _addNote('Requests were still loading, so the list may be incomplete.');
    }

    final list = _requestsFor(visible, e, filters, focus);

    final columns = [
      'date',
      'type',
      'asset',
      'status',
      'requester',
      'receiver',
      'detail',
      'decidedBy',
      if (filters.priority) 'priority',
    ];

    final rows = [
      for (final r in list)
        [
          r.requestDate == null ? null : _dayOf(r.requestDate!),
          r.requestType.trim(),
          r.assetName.trim().isEmpty ? null : r.assetName.trim(),
          r.status.trim(),
          r.requestedUserName.trim().isEmpty
              ? null
              : r.requestedUserName.trim(),
          r.receiverName.trim().isEmpty ? null : r.receiverName.trim(),
          _requestDetail(r),
          r.approvedBy.trim().isEmpty ? null : r.approvedBy.trim(),
          if (filters.priority) r.priority.trim(),
        ],
    ];

    _drafts.add(
      _Draft.table(
        _requestsTitle(filters, focus),
        _primary,
        _Table(columns, rows).withoutEmptyColumns(const {
          'asset',
          'requester',
          'receiver',
          'detail',
          'decidedBy',
        }),
      ),
    );

    final byStatus = <String, int>{};
    final byType = <String, int>{};
    for (final r in visible) {
      final s = r.status.trim().isEmpty ? 'Unknown' : r.status.trim();
      final t = r.requestType.trim().isEmpty ? 'Unknown' : r.requestType.trim();
      byStatus[s] = (byStatus[s] ?? 0) + 1;
      byType[t] = (byType[t] ?? 0) + 1;
    }

    _drafts.add(
      _Draft.data(
        role == 'user' ? 'Your requests, summary' : 'Requests summary',
        _supporting,
        {'total': visible.length, 'byStatus': byStatus, 'byType': byType},
      ),
    );
  }

  /// The requests of [visible] that a question asks about, newest first.
  /// Shared by [_addRequests] and the direct answer.
  List<RequestModel> _requestsFor(
    List<RequestModel> visible,
    _Entities e,
    _Reading filters,
    AssetModel? focus,
  ) {
    var list = visible;

    final status = filters.requestStatus;
    if (status != null) {
      list = list
          .where((r) => r.status.trim().toLowerCase() == status)
          .toList();
    }

    final type = filters.requestType;
    if (type != null) {
      list = list
          .where((r) => r.requestType.trim().toLowerCase() == type)
          .toList();
    }

    if (filters.mine) {
      list = list.where((r) => r.requestedBy.trim() == uid).toList();
    }

    if (focus != null) {
      list = list.where((r) => r.assetId.trim() == focus.id).toList();
    } else {
      final base = _base(e);
      if (base != null) {
        final ids = {for (final a in base) a.id};
        final categories = e.categories.map((c) => c.toLowerCase()).toSet();
        list = list
            .where(
              (r) =>
                  ids.contains(r.assetId.trim()) ||
                  categories.contains(r.category.trim().toLowerCase()),
            )
            .toList();
      }

      final bazaar = e.bazaar?.toLowerCase();
      if (bazaar != null) {
        list = list
            .where(
              (r) =>
                  r.destinationBazaarName.trim().toLowerCase() == bazaar ||
                  r.sourceBazaarName.trim().toLowerCase() == bazaar,
            )
            .toList();
      }
    }

    final days = filters.windowDays;
    if (days != null) {
      final since = inputs.retrievedAt.subtract(Duration(days: days));
      list = list
          .where(
            (r) => r.requestDate != null && !r.requestDate!.isBefore(since),
          )
          .toList();
    }

    final epoch = DateTime.fromMillisecondsSinceEpoch(0);
    list.sort(
      (a, b) => (b.requestDate ?? epoch).compareTo(a.requestDate ?? epoch),
    );

    return list;
  }

  /// "Pending transfer requests", "Your requests for IT-LAP-001".
  String _requestsTitle(_Reading filters, AssetModel? focus) {
    final kind = [?filters.requestStatus, ?filters.requestType].join(' ');
    var title = role == 'user' || filters.mine
        ? (kind.isEmpty ? 'Your requests' : 'Your $kind requests')
        : (kind.isEmpty ? 'Requests' : '${_capitalised(kind)} requests');
    if (focus != null) {
      final tag = focus.assetId.trim();
      title = '$title for ${tag.isEmpty ? focus.name.trim() : tag}';
    }
    return title;
  }

  static String? _requestDetail(RequestModel r) {
    if (r.isTransferRequest) {
      final from = r.sourceBazaarName.trim().isNotEmpty
          ? r.sourceBazaarName.trim()
          : r.sourceLocation.trim();
      final to = r.destinationBazaarName.trim();
      final parts = [
        if (r.transferQuantity > 0)
          r.transferQuantity == 1 ? '1 unit' : '${r.transferQuantity} units',
        if (from.isNotEmpty) 'from $from',
        if (to.isNotEmpty) 'to $to',
      ];
      return parts.isEmpty ? null : parts.join(' ');
    }

    if (r.isAssignmentRequest) {
      if (!r.assignsToSomebody) return 'unassign';
      final name = r.assigneeName.trim();
      return name.isEmpty ? 'assign' : 'assign to $name';
    }

    return null;
  }

  // -------------------------------------------------------------- people

  void _addPeople(_Entities e, Set<LocalAiTopic> topics, _Reading filters) {
    if (!manager) {
      _addNote(
        'The user directory is only available to Admins and the Super Admin, '
        'so no information about people was included.',
      );
      return;
    }

    final state = inputs.peopleState;
    final people = _people();

    if (people.isEmpty && (state.failed || state.loading)) {
      _addNote(
        state.failed
            ? 'The user directory could not be loaded: '
                  '${LocalAiInventoryContext.shortReason(state.error)}.'
            : 'The user directory was still loading, so it is not included.',
      );
      return;
    }
    if (state.failed) {
      _addNote(
        'The user directory reported an error, so it may be out of date: '
        '${LocalAiInventoryContext.shortReason(state.error)}.',
      );
    }

    String roleOf(UserModel p) => PermissionService.roleLabel(p.effectiveRole);

    List<Object?> row(UserModel p) => [
      p.name.trim().isEmpty ? null : p.name.trim(),
      roleOf(p),
      p.status.trim(),
      p.department.trim().isEmpty ? null : p.department.trim(),
      p.designation.trim().isEmpty ? null : p.designation.trim(),
    ];

    _Table table(List<UserModel> list) => _Table(
      const ['name', 'role', 'status', 'department', 'designation'],
      [
        for (final p in [...list]..sort((a, b) => a.name.compareTo(b.name)))
          row(p),
      ],
    ).withoutEmptyColumns(const {'department', 'designation'});

    // Named people, with what they hold.
    for (final person in e.persons) {
      final held = _inventoryOk
          ? _data.assets
                .where(
                  (a) =>
                      (a.assignedTo ?? '').trim() == person.uid &&
                      a.calculatedAssignedQuantity > 0,
                )
                .toList()
          : const <AssetModel>[];

      _drafts.add(
        _Draft.data('Person: ${person.name.trim()}', _focusPriority - 10, {
          'role': roleOf(person),
          'status': person.status.trim(),
          if (person.department.trim().isNotEmpty)
            'department': person.department.trim(),
          if (person.designation.trim().isNotEmpty)
            'designation': person.designation.trim(),
          'holds': {
            'assetRecords': held.length,
            'units': held.fold<int>(
              0,
              (s, a) => s + a.calculatedAssignedQuantity,
            ),
            'columns': const ['assetId', 'name', 'assigned'],
            'rows': [
              for (final a in held.take(20))
                [a.assetId, a.name, a.calculatedAssignedQuantity],
            ],
          },
        }),
      );
    }

    var list = people;
    final words = <String>[];

    final roleFilter = filters.roleFilter;
    if (roleFilter != null) {
      list = list.where((p) => p.effectiveRole == roleFilter).toList();
      words.add(PermissionService.roleLabel(roleFilter));
    }

    final active = filters.activeFilter;
    if (active != null && topics.contains(LocalAiTopic.people)) {
      list = list.where((p) => p.isActive == active).toList();
      words.insert(0, active ? 'Active' : 'Inactive');
    }

    final department = e.department;
    if (department != null) {
      final key = department.toLowerCase();
      list = list
          .where((p) => p.department.trim().toLowerCase() == key)
          .toList();
    }

    final wantsList =
        department != null ||
        (topics.contains(LocalAiTopic.people) && e.persons.isEmpty);

    if (wantsList) {
      final what = words.isEmpty
          ? 'User accounts'
          : '${words.join(' ')} accounts';
      _drafts.add(
        _Draft.table(
          department == null ? what : '$what in the $department department',
          department == null && roleFilter == null && active == null
              ? _supporting
              : _primary,
          table(list),
        ),
      );
    }

    if (topics.contains(LocalAiTopic.departments) && department == null) {
      final counts = <String, int>{};
      for (final p in people) {
        final d = p.department.trim().isEmpty ? '(none)' : p.department.trim();
        counts[d] = (counts[d] ?? 0) + 1;
      }
      final names = counts.keys.toList()
        ..sort((a, b) => counts[b]!.compareTo(counts[a]!));

      _drafts.add(
        _Draft.table(
          'Departments',
          _primary,
          _Table(
            const ['department', 'users'],
            [
              for (final d in names) [d, counts[d]],
            ],
          ),
        ),
      );
    }

    if (topics.contains(LocalAiTopic.people) ||
        topics.contains(LocalAiTopic.departments)) {
      final byRole = <String, int>{};
      final byStatus = <String, int>{};
      for (final p in people) {
        final r = roleOf(p);
        final s = p.status.trim().isEmpty ? 'unknown' : p.status.trim();
        byRole[r] = (byRole[r] ?? 0) + 1;
        byStatus[s] = (byStatus[s] ?? 0) + 1;
      }

      _drafts.add(
        _Draft.data('User accounts, summary', _primary + 10, {
          'total': people.length,
          'byRole': byRole,
          'byStatus': byStatus,
        }),
      );
    }
  }

  // ---------------------------------------------------- value, warranty

  void _addValue(_Entities e) {
    if (!_inventoryOk) return;

    final base = _base(e);
    if (base != null) return; // The list above already carries the values.

    final most = _facts['mostValuable'];
    if (most is List && most.isNotEmpty) {
      _drafts.add(
        _Draft.table(
          'Most valuable assets',
          _supporting,
          _Table(
            const ['assetId', 'name', 'quantity', 'totalValue'],
            [
              for (final item in most.whereType<Map>())
                [
                  item['assetId'],
                  item['name'],
                  item['quantity'],
                  item['totalValue'],
                ],
            ],
          ),
        ),
      );
    }

    _addBreakdown(
      'Value by category',
      'byCategory',
      'category',
      _primary,
      withValue: true,
    );
  }

  void _addWarranty(_Entities e) {
    if (!_inventoryOk) return;

    final base = _base(e);

    if (base == null) {
      final warranty = _facts['warranty'];
      if (warranty is! Map) {
        _drafts.add(
          _Draft.data('Warranties', _primary, {
            'assetRecordsWithWarranty': 0,
            'note': 'No asset has both a purchase date and a warranty period.',
          }),
        );
        return;
      }

      final soonest = (warranty['soonestToExpire'] as List? ?? const [])
          .whereType<Map>()
          .toList();

      final table = _Table(
        const ['assetId', 'name', 'expires', 'daysLeft'],
        [
          for (final w in soonest)
            [w['assetId'], w['name'], w['expires'], w['daysLeft']],
        ],
        extra: {
          'assetRecordsWithWarranty': warranty['assetRecordsWithWarranty'],
          'expired': warranty['expired'],
          'expiringWithin90Days': warranty['expiringWithin90Days'],
        },
      );

      // toFacts lists only the soonest 15; the title says how many exist.
      _drafts.add(
        _WarrantyDraft(
          'Warranties, soonest to expire first',
          _primary,
          table,
          (warranty['assetRecordsWithWarranty'] as num?)?.toInt() ??
              table.total,
        ),
      );
      return;
    }

    final rows = <List<Object?>>[];
    var expired = 0;
    var soon = 0;
    for (final asset in base) {
      final ends = InventorySnapshot.warrantyEnds(asset);
      if (ends == null) continue;
      final days = ends.difference(inputs.retrievedAt).inDays;
      if (days < 0) {
        expired++;
      } else if (days <= 90) {
        soon++;
      }
      rows.add([asset.assetId, asset.name, _dayOf(ends), days]);
    }
    rows.sort((a, b) => (a[3] as int).compareTo(b[3] as int));

    _drafts.add(
      _Draft.table(
        'Warranties - ${_baseLabel(e)}, soonest to expire first',
        _primary,
        _Table(
          const ['assetId', 'name', 'expires', 'daysLeft'],
          rows,
          extra: {'expired': expired, 'expiringWithin90Days': soon},
        ),
      ),
    );
  }

  // ------------------------------------------------------------ overview

  void _addOverview(Set<LocalAiTopic> topics) {
    if (!_inventoryOk) return;

    final value = topics.contains(LocalAiTopic.value);
    if (!value) {
      _addBreakdown('Stock by category', 'byCategory', 'category', _background);
    }
    _addBreakdown(
      'Stock by status',
      'byStatus',
      'status',
      _background - 10,
      note:
          'Full quantity of each record wherever it is. Not the same measure '
          'as the damaged/underRepair totals.',
    );
  }

  /// One of toFacts' breakdowns (byCategory, byStatus) as a table.
  void _addBreakdown(
    String title,
    String key,
    String column,
    int priority, {
    bool withValue = false,
    String? note,
  }) {
    final breakdown = _facts[key];
    if (breakdown is! Map || breakdown.isEmpty) return;

    final rows = <List<Object?>>[
      for (final entry in breakdown.entries)
        if (entry.value is Map)
          [
            entry.key.toString(),
            (entry.value as Map)['records'],
            (entry.value as Map)['quantity'],
            if (withValue) (entry.value as Map)['value'],
          ],
    ];

    _drafts.add(
      _Draft.table(
        title,
        priority,
        _Table(
          [column, 'records', 'quantity', if (withValue) 'value'],
          rows,
          extra: {'note': ?note},
        ),
      ),
    );
  }

  // ------------------------------------------------------------- fitting

  /// Fits the drafts into the budget: longest lists are halved first, then the
  /// lowest-priority sections are left out, and the totals never are.
  LocalAiAppContext _fit() {
    final scope = LocalAiInventoryContext._redact(
      LocalAiInventoryContext.scopeFor(role),
    );

    // The server takes at most 24 sections; the least important go first.
    final kept = [..._drafts];
    final left = <String>[];
    if (kept.length > 24) {
      final ranked = [...kept]
        ..sort((a, b) => b.priority.compareTo(a.priority));
      for (final draft in ranked.skip(24)) {
        kept.remove(draft);
        left.add(draft.baseTitle);
      }
    }

    LocalAiAppContext compose() {
      final notes = [..._notes];
      if (left.isNotEmpty) {
        notes.add('Left out to stay within size: ${left.join('; ')}.');
      }
      // The left-out note is the one that must survive the cap of twelve.
      final capped = notes.length > 12
          ? [...notes.take(11), notes.last]
          : notes;

      // The final, defensive scrub of everything that leaves. It runs before
      // measuring, so the size fitted is the size sent.
      return LocalAiAppContext(
        source: LocalAiAppContext.defaultSource,
        retrievedAt: inputs.retrievedAt,
        scope: scope,
        sections: [
          for (final d in kept)
            LocalAiContextSection(
              title: d.title,
              data: LocalAiInventoryContext.scrubData(d.toSection().data),
            ),
        ],
        notes: LocalAiInventoryContext._cleanNotes(capped),
      );
    }

    // Both measures must fit: the server's, which decides CONTEXT_TOO_LARGE,
    // and the seam's, which callers may check the result against.
    int size(LocalAiAppContext c) {
      final server = LocalAiInventoryContext.appDataTokens(c);
      final seam = c.estimatedTokens;
      return server > seam ? server : seam;
    }

    final budget = inputs.budgetTokens;
    var context = compose();

    _Table? longest(int floor) {
      _Table? best;
      var bestSize = 0;
      for (final draft in kept) {
        final table = draft.table;
        if (table == null || table.shown <= floor) continue;
        final size = jsonEncode(table.rows.take(table.shown).toList()).length;
        if (size > bestSize) {
          best = table;
          bestSize = size;
        }
      }
      return best;
    }

    _Draft? lowest(int below) {
      _Draft? worst;
      for (final draft in kept) {
        if (draft.priority >= below) continue;
        // On a tie the later one goes: sections are added most central first.
        if (worst == null || draft.priority <= worst.priority) worst = draft;
      }
      return worst;
    }

    while (size(context) > budget) {
      final table =
          longest(8) ?? (lowest(_primary) == null ? longest(1) : null);
      if (table != null) {
        table.shown = table.shown ~/ 2 < 1 ? 1 : table.shown ~/ 2;
        context = compose();
        continue;
      }

      final draft = lowest(_primary) ?? lowest(_never);
      if (draft == null) break;

      kept.remove(draft);
      left.add(draft.baseTitle);
      context = compose();
    }

    return context;
  }
}

/// A list whose true length is larger than the rows it carries: toFacts gives
/// only the soonest warranties, and the title must still state how many exist.
class _WarrantyDraft extends _Draft {
  _WarrantyDraft(super.baseTitle, super.priority, super.table, this.realTotal)
    : super.table();

  final int realTotal;

  @override
  String get title {
    final t = table!;
    if (realTotal == 0) return _Draft._fitTitle(baseTitle, ' (none)');
    return _Draft._fitTitle(baseTitle, ' (showing ${t.shown} of $realTotal)');
  }
}
