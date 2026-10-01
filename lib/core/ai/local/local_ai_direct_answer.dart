part of 'local_ai_inventory_context.dart';

// =============================================================================
// DIRECT ANSWERS
// =============================================================================

/// Answers a plain lookup straight from the records, so the model is not
/// asked at all.
///
/// On the laptop's CPU the model takes half a minute to read a question and
/// write its answer, and for "how many laptops are at Head Office?" all it
/// does in that time is read a figure back out of the data it was given - a
/// figure the app already had, exactly. So when a question is one of those,
/// the app answers it itself, at once, from the same permission-scoped
/// records, the same reading of the question and the same lists the model
/// would have been sent. Everything else still goes to the model.
///
/// Precision comes first, because a wrong instant answer is worse than a
/// right slow one. A question is answered here only when ALL of these hold:
///
///   * every word in it is understood: a word of the question vocabulary, a
///     filler word, or part of a record the question named (an asset, a
///     category, a Bazaar, a person, a department). One unknown word, and the
///     question may mean something these rules cannot see;
///   * it asks for nothing but a lookup: no "why", "compare", "suggest",
///     "explain", nothing to be written, no "not"/"except", and no number
///     other than a time window ("last 7 days");
///   * it is not an instruction ("transfer 5 laptops to Township", "Ali ko
///     assign kar do"), which the app never carries out from here;
///   * it has exactly one of the shapes below; and
///   * every source it needs was read completely: no note about data that
///     was loading, failed or withheld. A gap is the model's to explain.
///
/// Answers are in English, in the app's own words, with figures exactly as
/// the app's screens compute them.
class _DirectAnswer {
  _DirectAnswer(
    this.b, {
    required this.question,
    required this.entities,
    required this.topics,
    required this.filters,
  });

  final _Build b;

  /// The question as asked. Only its own words are checked: a follow-up's
  /// borrowed topics and records come from a question that was checked when
  /// it was asked.
  final _Reading question;

  /// What the question names, after any follow-up borrowing.
  final _Entities entities;

  /// What the question is about, after any follow-up borrowing.
  final Set<LocalAiTopic> topics;

  /// Where the filters (status, window, "my") come from: the question, or the
  /// one before it for a follow-up that borrowed its topics.
  final _Reading filters;

  _Entities get e => entities;
  InventorySnapshot get d => b._data;

  /// The most lines any list in an answer shows. The count is always given
  /// in full, and what did not fit is said in so many words.
  static const int _maxLines = 10;

  // ---------------------------------------------------------------- answer

  String? text() {
    // A note means some of the data could not be read in full.
    if (b._notes.isNotEmpty) return null;
    if (!_understood()) return null;

    final own = topics.where((t) => t != LocalAiTopic.overview).toSet();
    final focus = b._inventoryOk ? e.focus : null;

    if (focus != null) return _asset(focus, own);

    if (e.persons.isNotEmpty ||
        e.department != null ||
        own.contains(LocalAiTopic.people) ||
        own.contains(LocalAiTopic.departments)) {
      return _people(own);
    }

    if (own.contains(LocalAiTopic.requests)) return _requests(own);
    if (own.contains(LocalAiTopic.bazaarDirectory)) return _directory(own);
    if (own.contains(LocalAiTopic.movements)) return _movements(own);
    if (e.bazaar != null) return _bazaar(own);
    if (own.contains(LocalAiTopic.perBazaar)) return _perBazaar(own);
    if (own.contains(LocalAiTopic.value)) return _value(own);
    if (own.contains(LocalAiTopic.warranty)) return _warranty(own);
    if (own.isNotEmpty) return _stock(own);

    if (e.matches.isNotEmpty || e.categories.isNotEmpty) return _group();

    if (topics.contains(LocalAiTopic.overview) ||
        question.namesWholeInventory ||
        filters.namesWholeInventory) {
      return _overview();
    }

    return null;
  }

  // ------------------------------------------------------------- readiness

  bool get _inventoryReady {
    final state = b.inputs.inventoryState;
    return b._inventoryOk &&
        !state.loading &&
        !state.failed &&
        !d.inventoryLoading;
  }

  bool get _movementsReady {
    final state = b.inputs.movementState;
    return b._movementsOk && !state.loading && !state.failed;
  }

  bool get _bazaarsReady {
    final state = b.inputs.bazaarState;
    return !state.loading && !state.failed;
  }

  bool get _peopleReady {
    final state = b.inputs.peopleState;
    return b.manager && !state.loading && !state.failed;
  }

  bool get _requestsReady {
    final state = b.inputs.requestState;
    return !state.loading && !state.failed;
  }

  // ------------------------------------------------------ understanding

  /// Words that ask for more than a lookup - a reason, a judgement, a
  /// comparison, a calculation, something written, a date - even when every
  /// other word is known. Those are what the model is for.
  static const Set<String> _modelWords = {
    'why',
    'kyun',
    'kyon',
    'kiun',
    'kion',
    'kyu',
    'should',
    'shall',
    'explain',
    'explanation',
    'suggest',
    'suggestion',
    'recommend',
    'recommendation',
    'advice',
    'advise',
    'compare',
    'comparison',
    'versus',
    'vs',
    'difference',
    'differ',
    'better',
    'best',
    'worst',
    'improve',
    'reduce',
    'increase',
    'decrease',
    'plan',
    'predict',
    'forecast',
    'trend',
    'trends',
    'analyse',
    'analyze',
    'analysis',
    'insight',
    'insights',
    'write',
    'draft',
    'email',
    'mail',
    'letter',
    'message',
    'summarise',
    'summarize',
    'describe',
    'mean',
    'means',
    'meaning',
    'define',
    'opinion',
    'think',
    'buy',
    'purchase',
    'procure',
    'replace',
    'upgrade',
    'budget',
    'policy',
    'procedure',
    'process',
    'steps',
    'help',
    'when',
    'kab',
    'since',
    'before',
    'after',
    'between',
    'ago',
    'yesterday',
    'date',
    'than',
    'average',
    'percentage',
    'percent',
    'ratio',
    'rate',
    'growth',
    'calculate',
    'estimate',
    'kaise',
    'kaisay',
    'kese',
    'if',
    'agar',
  };

  /// Words that turn a lookup inside out ("laptops NOT at Head Office").
  /// The lists here only ever say what IS, so any of these goes to the model.
  static const Set<String> _negations = {
    'not',
    'no',
    'nahi',
    'nahin',
    'nhi',
    'na',
    'without',
    'except',
    'excluding',
    'exclude',
    'never',
    'none',
    'neither',
    'nor',
    'besides',
  };

  /// Question phrases that contain a negation word but are not negated: they
  /// name a topic ("not working" is damaged, "na manzoor" is rejected).
  static const List<String> _negatedTopics = [
    'not working',
    'not yet approved',
    'na manzoor',
  ];

  /// An English instruction opens with its verb.
  static const Set<String> _commandVerbs = {
    'transfer',
    'move',
    'shift',
    'send',
    'assign',
    'unassign',
    'allot',
    'allocate',
    'issue',
    'return',
    'add',
    'create',
    'register',
    'delete',
    'remove',
    'update',
    'edit',
    'change',
    'set',
    'mark',
    'approve',
    'reject',
    'dispose',
    'retire',
    'scrap',
    'deploy',
    'cancel',
    'rename',
  };

  /// A Roman Urdu instruction ends with an imperative.
  static const Set<String> _imperatives = {
    'bhejo',
    'bhejdo',
    'bhejden',
    'bhejein',
    'bhejain',
    'kardo',
    'kardein',
    'karden',
    'kardain',
    'karein',
    'karen',
    'karain',
    'kijiye',
    'kijye',
    'kijiyega',
    'dedo',
    'dijiye',
    'hatao',
    'hatado',
    'mitao',
    'badlo',
    'lagao',
    'dalo',
    'daalo',
    'likho',
  };

  static const List<String> _imperativePhrases = [
    'kar do',
    'kr do',
    'kar dein',
    'kar den',
    'kar dain',
    'bhej do',
    'bhej dein',
    'de do',
    'de dein',
  ];

  /// Politeness before an instruction's verb: "please transfer ...".
  static const Set<String> _polite = {'please', 'plz', 'pls', 'kindly', 'zara'};

  /// How a question opens, when it has no question mark.
  static const Set<String> _questionOpeners = {
    'what',
    'which',
    'how',
    'where',
    'who',
    'whose',
    'is',
    'are',
    'was',
    'were',
    'do',
    'does',
    'did',
    'can',
    'could',
    'kya',
    'kia',
    'kitne',
    'kitna',
    'kitni',
    'kahan',
    'kaun',
    'kis',
    'konsa',
    'konsi',
    'kaunsa',
    'kaunsi',
    'show',
    'list',
    'tell',
    'give',
  };

  /// Words that carry no meaning of their own in a lookup and are missing
  /// from the question vocabulary: fillers, spellings and forms of address.
  static const Set<String> _fillers = {
    'i',
    'hi',
    'hey',
    'dear',
    'sir',
    'madam',
    'bhai',
    'yaar',
    'yar',
    'ok',
    'okay',
    'so',
    'got',
    'hein',
    'hen',
    'hn',
    'mai',
    'mei',
    'mien',
    'men',
    'k',
    'ky',
    'kay',
    'kitnay',
    'kitney',
    'kia',
    'he',
    'hy',
    'ha',
    'h',
    'tha',
    'thi',
    'hua',
    'hui',
    'hue',
    'waly',
    'batain',
    'batayen',
    'bataiye',
    'btao',
    'btaen',
    'dikhayen',
    'dikhaiye',
    'dikhaen',
    'chahiye',
    'chaiye',
    'ab',
    'jo',
    'humare',
    'humara',
    'humari',
    'hamein',
    'apne',
    'apna',
    'apni',
    'am',
    'plz',
    'pls',
    'valuable',
    'qeemti',
    'keemti',
    'top',
    'highest',
    'expired',
  };

  /// Whether every word of the question is understood and it asks for a
  /// lookup and nothing else. See the class comment.
  bool _understood() {
    final raw = question.raw;
    final tokens = LocalAiInventoryContext._words(raw).toList();
    if (tokens.isEmpty) return false;

    if (tokens.any(_modelWords.contains)) return false;

    // "no. of laptops" is how "number of" is often written here.
    var unnegated = ' ${raw.replaceAll(RegExp(r'\s+'), ' ')} '.replaceAll(
      RegExp(r'\bno\.?\s*of\b'),
      ' ',
    );
    for (final phrase in _negatedTopics) {
      unnegated = unnegated.replaceAll(phrase, ' ');
    }
    if (LocalAiInventoryContext._words(unnegated).any(_negations.contains)) {
      return false;
    }

    if (_isInstruction(raw, tokens)) return false;

    final named = _namedWords();
    return tokens.every((token) => _known(token, named));
  }

  bool _isInstruction(String raw, List<String> tokens) {
    if (tokens.any(_imperatives.contains)) return true;

    final padded = ' ${LocalAiInventoryContext._words(raw).join(' ')} ';
    if (_imperativePhrases.any((p) => padded.contains(' $p '))) return true;

    final start = tokens.indexWhere((t) => !_polite.contains(t));
    if (start < 0) return false;
    final first = tokens[start];
    final next = start + 1 < tokens.length ? tokens[start + 1] : '';

    // "transfer history of ABC-123" and "transfer requests" use the verb as a
    // noun: they ask about records rather than for a change.
    return _commandVerbs.contains(first) &&
        !_asNoun.contains(next) &&
        !_readsAsQuestion(raw, first);
  }

  /// Words that, right after a verb such as "transfer", make it a noun.
  static const Set<String> _asNoun = {
    'history',
    'histories',
    'request',
    'requests',
    'record',
    'records',
    'list',
    'report',
    'details',
    'status',
    'log',
    'logs',
  };

  static bool _readsAsQuestion(String raw, String first) {
    final trimmed = raw.trim();
    if (trimmed.endsWith('?') || trimmed.endsWith('؟')) return true;
    return _questionOpeners.contains(first);
  }

  bool _known(String token, Set<String> named) {
    if (_fillers.contains(token)) return true;

    // A number is known only as the time window it names: "last 7 days" is a
    // filter, while "transfer 5" or "in 2024" asks something else entirely.
    if (RegExp(r'^\d+$').hasMatch(token)) {
      return question.windowDays?.toString() == token;
    }

    // Urdu script: only the words the question vocabulary translates.
    if (RegExp('[؀-ۿ]').hasMatch(token)) {
      return LocalAiInventoryContext._urduWords.keys.any(
        (key) => LocalAiInventoryContext._words(key).contains(token),
      );
    }

    if (LocalAiInventoryContext._forms(token).any(named.contains)) return true;
    return LocalAiInventoryContext._isVocabulary(token);
  }

  /// The words of every record the question named, in every form.
  Set<String> _namedWords() {
    final words = <String>{};
    void add(String text) {
      for (final word in LocalAiInventoryContext._words(text)) {
        words.addAll(LocalAiInventoryContext._forms(word));
        words.addAll({'${word}s', '${word}es'});
        if (word.endsWith('y')) {
          words.add('${word.substring(0, word.length - 1)}ies');
        }
      }
    }

    final focus = e.focus;
    if (focus != null) {
      add(focus.assetId);
      add(focus.name);
      add(focus.brand);
      add(focus.model);
      add(focus.serialNumber);
      add(focus.category);
    }
    for (final asset in e.matches) {
      add(asset.name);
      add(asset.brand);
      add(asset.model);
    }
    e.categories.forEach(add);
    if (e.bazaar != null) add(e.bazaar!);
    for (final person in e.persons) {
      add(person.name);
    }
    if (e.department != null) add(e.department!);
    if (topics.contains(LocalAiTopic.bazaarDirectory)) {
      for (final bazaar in d.bazaars) {
        add(bazaar.location);
      }
    }
    return words;
  }

  bool _asks(Set<String> words) =>
      LocalAiInventoryContext._words(question.raw).any(words.contains);

  // -------------------------------------------------------------- wording

  static String _n(num value) {
    final digits = value.round().abs().toString();
    final buffer = StringBuffer();
    for (var i = 0; i < digits.length; i++) {
      if (i > 0 && (digits.length - i) % 3 == 0) buffer.write(',');
      buffer.write(digits[i]);
    }
    return (value.round() < 0 ? '-' : '') + buffer.toString();
  }

  static String _units(int value) =>
      value == 1 ? '1 unit' : '${_n(value)} units';

  static String _records(int value) =>
      value == 1 ? '1 asset record' : '${_n(value)} asset records';

  static String _money(num value) => 'Rs. ${_n(value)}';

  static String _label(AssetModel a) {
    final tag = a.assetId.trim();
    final name = a.name.trim();
    if (tag.isEmpty) return name;
    return name.isEmpty ? tag : '$tag ($name)';
  }

  static String _day(DateTime date) => LocalAiInventoryContext._day(date);

  /// Bulleted [lines], at most [_maxLines] of them, with how many more there
  /// are when [total] is larger.
  static String _list(List<String> lines, {int? total}) {
    final all = total ?? lines.length;
    final shown = lines.take(_maxLines).toList();
    final more = all - shown.length;
    return [
      for (final line in shown) '• $line',
      if (more > 0) '…and ${_n(more)} more.',
    ].join('\n');
  }

  static String _join(List<String?> parts) =>
      parts.whereType<String>().where((p) => p.isNotEmpty).join('\n');

  /// What the question narrowed to, as a phrase that reads right whatever
  /// the category is called: "in the Laptop category", 'among assets
  /// matching "dell"'. Category names are used exactly as recorded, never
  /// made plural: "Networking" and "Power" have no plural.
  String get _within {
    if (e.matches.isNotEmpty) return 'among assets matching "${e.nameHint}"';
    final many = e.categories.length > 1;
    return 'in the ${e.categories.join(' and ')} '
        '${many ? 'categories' : 'category'}';
  }

  /// The same as a heading: "Laptop category", 'Assets matching "dell"'.
  String get _heading {
    if (e.matches.isNotEmpty) return 'Assets matching "${e.nameHint}"';
    final many = e.categories.length > 1;
    return '${e.categories.join(' and ')} '
        '${many ? 'categories' : 'category'}';
  }

  List<AssetModel> get _all => b._base(e) ?? d.assets;

  static int _sum(Iterable<AssetModel> assets, int Function(AssetModel) of) =>
      assets.fold<int>(0, (s, a) => s + of(a));

  static int _headOffice(AssetModel a) => a.calculatedHeadOfficeQuantity;

  static int _quantity(AssetModel a) => a.quantity < 0 ? 0 : a.quantity;

  static double _worth(AssetModel a) =>
      (a.purchasePrice < 0 ? 0.0 : a.purchasePrice) * _quantity(a);

  // ------------------------------------------------------------ overview

  String? _overview() {
    if (!_inventoryReady || !e.isEmpty) return null;

    return _join([
      'Inventory overview:',
      _list([
        'Asset records: ${_n(d.totalAssets)}',
        'Total quantity: ${_units(d.totalQuantity)}',
        'Available at Head Office: ${_units(d.headOfficeStock)}',
        'At Bazaars: ${_units(d.bazaarQuantity)}',
        'Assigned to people: ${_units(d.assignedQuantity)}',
        'Not usable at Head Office: ${_units(d.unavailableAtHeadOffice)} '
            '(damaged ${_n(d.damagedQuantity)}, under repair '
            '${_n(d.underRepairQuantity)}, lost ${_n(d.lostQuantity)}, '
            'disposed ${_n(d.disposedQuantity)})',
      ]),
      if (d.scopeNote.isNotEmpty) '\n${d.scopeNote}',
    ]);
  }

  // ------------------------------------------------- stock by condition

  /// Damaged, under repair, lost, disposed, available, assigned or at Head
  /// Office: one of them, for everything or a category.
  String? _stock(Set<LocalAiTopic> own) {
    if (!_inventoryReady || e.bazaar != null || e.department != null) {
      return null;
    }

    // Damaged, repair, lost, disposed and available are Head Office figures
    // already, so "at Head Office" adds nothing to them.
    final kinds = own.where((t) => t != LocalAiTopic.headOffice).toSet();
    if (kinds.length > 1) return null;

    if (kinds.isEmpty) {
      return own.contains(LocalAiTopic.headOffice) ? _atHeadOffice() : null;
    }

    return switch (kinds.single) {
      LocalAiTopic.damaged => _condition(
        'Damaged',
        'damaged',
        LocalAiInventoryContext.isDamaged,
        d.damagedQuantity,
      ),
      LocalAiTopic.underRepair => _condition(
        'Under repair',
        'under repair',
        LocalAiInventoryContext.isUnderRepair,
        d.underRepairQuantity,
      ),
      LocalAiTopic.lost => _condition(
        'Lost or missing',
        'lost or missing',
        LocalAiInventoryContext.isLost,
        d.lostQuantity,
      ),
      LocalAiTopic.disposed => _condition(
        'Disposed or retired',
        'disposed or retired',
        LocalAiInventoryContext.isDisposed,
        d.disposedQuantity,
      ),
      LocalAiTopic.available => _available(),
      LocalAiTopic.assigned =>
        own.contains(LocalAiTopic.headOffice) ? null : _assigned(),
      _ => null,
    };
  }

  /// A condition's units are counted at Head Office, as the Dashboard counts
  /// them: units of a damaged asset that are out at a Bazaar or with a person
  /// are counted there instead, so no unit is counted twice.
  String? _condition(
    String title,
    String marked,
    bool Function(AssetModel) test,
    int dashboard,
  ) {
    final base = b._base(e);
    final records = _all.where(test).toList()
      ..sort((x, y) => _quantity(y).compareTo(_quantity(x)));
    final units = base == null ? dashboard : _sum(records, _headOffice);

    final headline = base == null
        ? '$title: ${_units(units)} at Head Office, as the Dashboard counts '
              'them.'
        : '$title, $_within: ${_units(units)} at Head Office.';

    if (records.isEmpty) {
      return _join([
        headline,
        base == null
            ? 'No asset record is marked $marked.'
            : 'No asset record $_within is marked $marked.',
      ]);
    }

    return _join([
      headline,
      '${_records(records.length)} marked $marked:',
      _list([
        for (final a in records)
          '${_label(a)}: ${_units(_quantity(a))}, '
              '${_n(_headOffice(a))} at Head Office',
      ]),
    ]);
  }

  String? _available() {
    final base = b._base(e);
    final records =
        _all
            .where(
              (a) =>
                  !LocalAiInventoryContext.isUnusable(a) && _headOffice(a) > 0,
            )
            .toList()
          ..sort((x, y) => _headOffice(y).compareTo(_headOffice(x)));
    final units = base == null ? d.headOfficeStock : _sum(records, _headOffice);

    if (records.isEmpty) {
      return base == null
          ? 'No stock is available at Head Office right now.'
          : 'Nothing $_within is available at Head Office right now.';
    }

    return _join([
      'Available at Head Office${base == null ? '' : ', $_within'}: '
          '${_units(units)}, in ${_records(records.length)}.',
      _list([
        for (final a in records) '${_label(a)}: ${_units(_headOffice(a))}',
      ]),
    ]);
  }

  String? _atHeadOffice() {
    final base = b._base(e);

    if (base == null) {
      return 'Head Office has ${_units(d.headOfficeStock)} available for use, '
          'plus ${_units(d.unavailableAtHeadOffice)} that cannot be used '
          '(damaged, under repair, lost or disposed).';
    }

    final records = base.where((a) => _headOffice(a) > 0).toList()
      ..sort((x, y) => _headOffice(y).compareTo(_headOffice(x)));
    if (records.isEmpty) return 'Nothing $_within is at Head Office.';

    final usable = _sum(
      records.where((a) => !LocalAiInventoryContext.isUnusable(a)),
      _headOffice,
    );

    return _join([
      'At Head Office, $_within: ${_units(_sum(records, _headOffice))}, of '
          'which ${_n(usable)} can be used.',
      _list([
        for (final a in records)
          '${_label(a)}: ${_units(_headOffice(a))} (${a.status.trim()})',
      ]),
    ]);
  }

  String? _assigned() {
    final base = b._base(e);
    final records = _all.where((a) => a.calculatedAssignedQuantity > 0).toList()
      ..sort(
        (x, y) => y.calculatedAssignedQuantity.compareTo(
          x.calculatedAssignedQuantity,
        ),
      );
    final units = base == null
        ? d.assignedQuantity
        : _sum(records, (a) => a.calculatedAssignedQuantity);

    if (records.isEmpty) {
      return base == null
          ? 'No stock is assigned to anyone.'
          : 'Nothing $_within is assigned to anyone.';
    }

    return _join([
      'Assigned${base == null ? '' : ', $_within'}: ${_units(units)}, in '
          '${_records(records.length)}.',
      _list([
        for (final a in records)
          '${_label(a)}: ${_units(a.calculatedAssignedQuantity)}'
              '${_heldBy(a)}',
      ]),
    ]);
  }

  /// ", held by Ali Khan", for the accounts that may see who holds what.
  String _heldBy(AssetModel a) {
    final holder = d.holderOf(a);
    return holder.isEmpty ? '' : ', held by $holder';
  }

  static String _capitalised(String text) =>
      text.isEmpty ? text : '${text[0].toUpperCase()}${text.substring(1)}';

  // ------------------------------------------------ a category or a name

  /// "How many laptops do we have?", "dell ke kitne hain".
  String? _group() {
    if (!_inventoryReady || e.bazaar != null) return null;

    final records = [...b._base(e)!]
      ..sort((x, y) => _quantity(y).compareTo(_quantity(x)));
    if (records.isEmpty) return null;

    return _join([
      '$_heading: ${_units(_sum(records, _quantity))} in '
          '${_records(records.length)} - '
          '${_n(_sum(records, _headOffice))} at Head Office, '
          '${_n(_sum(records, (a) => a.calculatedDeployedQuantity))} at '
          'Bazaars, '
          '${_n(_sum(records, (a) => a.calculatedAssignedQuantity))} assigned.',
      _list([
        for (final a in records)
          '${_label(a)}: ${_units(_quantity(a))} (Head Office '
              '${_n(_headOffice(a))}, Bazaars '
              '${_n(a.calculatedDeployedQuantity)}, assigned '
              '${_n(a.calculatedAssignedQuantity)})',
      ]),
    ]);
  }

  // ------------------------------------------------------------ one asset

  static const Set<String> _whereWords = {
    'where',
    'kahan',
    'kaha',
    'kahaan',
    'location',
    'located',
  };

  static const Set<String> _statusWords = {'status', 'condition'};

  static const Set<String> _countWords = {
    'many',
    'kitne',
    'kitna',
    'kitni',
    'quantity',
    'units',
    'unit',
    'stock',
    'count',
  };

  String? _asset(AssetModel a, Set<LocalAiTopic> own) {
    if (!_inventoryReady) return null;

    const answerable = {
      LocalAiTopic.warranty,
      LocalAiTopic.value,
      LocalAiTopic.movements,
      LocalAiTopic.headOffice,
      LocalAiTopic.perBazaar,
      LocalAiTopic.assigned,
      LocalAiTopic.damaged,
      LocalAiTopic.underRepair,
      LocalAiTopic.lost,
      LocalAiTopic.disposed,
      LocalAiTopic.available,
    };
    if (!own.every(answerable.contains)) return null;

    // Where its units are needs the movement records whenever some are out.
    final where = a.calculatedDeployedQuantity > 0 && !_movementsReady
        ? null
        : _whereIs(a);

    if (own.contains(LocalAiTopic.movements)) {
      return own.length == 1 ? _history(a) : null;
    }

    if (own.length > 1) return where == null ? null : _card(a, where);

    if (own.isEmpty) {
      if (_asks(_whereWords)) return where;
      if (_asks(_statusWords)) return _statusOf(a);
      if (_asks(_countWords)) return _spread(a);
      return where == null ? null : _card(a, where);
    }

    return switch (own.single) {
      LocalAiTopic.warranty => '${_label(a)}\n${_warrantyOf(a)}',
      LocalAiTopic.value =>
        '${_label(a)}\n'
            'Unit price: ${_money(a.purchasePrice)} · Quantity: '
            '${_units(_quantity(a))} · Total value: ${_money(_worth(a))}',
      LocalAiTopic.headOffice =>
        '${_label(a)} has ${_units(_headOffice(a))} at Head Office, out of '
            '${_units(_quantity(a))} in total.',
      LocalAiTopic.perBazaar => where,
      LocalAiTopic.assigned => _holderOf(a),
      LocalAiTopic.available =>
        '${_label(a)} has ${_units(_headOffice(a))} at Head Office '
            '(status: ${a.status.trim()}).',
      _ => _statusOf(a),
    };
  }

  String _statusOf(AssetModel a) =>
      '${_label(a)}: status ${a.status.trim()}, condition '
      '${a.condition.trim()}.';

  String _spread(AssetModel a) =>
      '${_label(a)}: ${_units(_quantity(a))} in total - '
      '${_n(_headOffice(a))} at Head Office, '
      '${_n(a.calculatedDeployedQuantity)} at Bazaars, '
      '${_n(a.calculatedAssignedQuantity)} assigned.';

  String _holderOf(AssetModel a) {
    final assigned = a.calculatedAssignedQuantity;
    if (assigned <= 0) return '${_label(a)} is not assigned to anyone.';

    final holder = d.holderOf(a);
    return holder.isEmpty
        ? '${_label(a)}: ${_units(assigned)} assigned.'
        : '${_label(a)}: ${_units(assigned)} assigned to $holder.';
  }

  /// Head Office, each Bazaar (from the Active movement records, as the
  /// Bazaar screens read them) and assigned.
  String _whereIs(AssetModel a) {
    final lines = <String>[];
    if (_headOffice(a) > 0) lines.add('Head Office: ${_units(_headOffice(a))}');

    final atBazaars = <String, int>{};
    for (final m in d.movementsForAsset(a)) {
      if (!m.isActive) continue;
      final name = (m.toBazaarName ?? m.toLocation).trim();
      if (name.isEmpty) continue;
      atBazaars[name] = (atBazaars[name] ?? 0) + m.quantity;
    }
    for (final entry in atBazaars.entries) {
      lines.add('${entry.key}: ${_units(entry.value)}');
    }

    final assigned = a.calculatedAssignedQuantity;
    if (assigned > 0) {
      final holder = d.holderOf(a);
      lines.add(
        'Assigned${holder.isEmpty ? '' : ' to $holder'}: ${_units(assigned)}',
      );
    }

    if (lines.isEmpty) {
      return '${_label(a)} has no units recorded at Head Office, at a Bazaar '
          'or with anyone.';
    }
    return _join(['${_label(a)} is at:', _list(lines)]);
  }

  String _warrantyOf(AssetModel a) {
    final ends = InventorySnapshot.warrantyEnds(a);
    if (ends == null) {
      return a.warrantyMonths > 0
          ? 'Warranty: ${a.warrantyMonths} months, but the purchase date is '
                'not recorded, so the end date cannot be worked out.'
          : 'Warranty: not recorded.';
    }

    final days = ends.difference(b.inputs.retrievedAt).inDays;
    if (days < 0) {
      return 'Warranty: ended on ${_day(ends)}, ${_n(-days)} days ago.';
    }
    return 'Warranty: ends on ${_day(ends)}, in ${_n(days)} days.';
  }

  String _card(AssetModel a, String where) {
    final brand = [
      a.brand,
      a.model,
    ].map((v) => v.trim()).where((v) => v.isNotEmpty).join(' ');
    final holder = d.holderOf(a);

    return _join([
      _label(a),
      _list([
        if (a.category.trim().isNotEmpty) 'Category: ${a.category.trim()}',
        'Status: ${a.status.trim()} · Condition: ${a.condition.trim()}',
        if (brand.isNotEmpty) 'Brand / model: $brand',
        if (a.serialNumber.trim().isNotEmpty)
          'Serial number: ${a.serialNumber.trim()}',
        'Quantity: ${_units(_quantity(a))} - ${_n(_headOffice(a))} at Head '
            'Office, ${_n(a.calculatedDeployedQuantity)} at Bazaars, '
            '${_n(a.calculatedAssignedQuantity)} assigned',
        if (holder.isNotEmpty && a.calculatedAssignedQuantity > 0)
          'Assigned to: $holder',
        'Unit price: ${_money(a.purchasePrice)} · Total value: '
            '${_money(_worth(a))}',
        _warrantyOf(a),
        if (a.purchaseDate != null) 'Purchased: ${_day(a.purchaseDate!)}',
      ]),
      if (a.calculatedDeployedQuantity > 0) '\n$where',
    ]);
  }

  String? _history(AssetModel a) {
    if (!_movementsReady) return null;

    final movements = d.movementsForAsset(a)
      ..sort((x, y) => y.deploymentDate.compareTo(x.deploymentDate));
    if (movements.isEmpty) return '${_label(a)} has no movement records.';

    return _join([
      '${_label(a)}: ${movements.length == 1 ? '1 movement' : '${_n(movements.length)} movements'}. The latest:',
      _list([for (final m in movements) _movementLine(m, withAsset: false)]),
    ]);
  }

  static String _movementLine(DeploymentModel m, {bool withAsset = true}) {
    final tag = m.assetId.trim();
    final name = m.assetName.trim();
    final asset = tag.isEmpty
        ? name
        : name.isEmpty
        ? tag
        : '$tag ($name)';
    final from = (m.fromBazaarName ?? m.fromLocation).trim();
    final to = (m.toBazaarName ?? m.toLocation).trim();
    final status = m.status.trim();

    return [
      _day(m.deploymentDate),
      if (withAsset && asset.isNotEmpty) asset,
      _units(m.quantity),
      '${from.isEmpty ? '?' : from} → ${to.isEmpty ? '?' : to}'
          '${status.isEmpty ? '' : ' ($status)'}',
    ].join(' · ');
  }

  // -------------------------------------------------------------- Bazaars

  /// "Township Bazaar mein kitna stock hai", "laptops at Township".
  String? _bazaar(Set<LocalAiTopic> own) {
    if (!own.every((t) => t == LocalAiTopic.perBazaar)) return null;
    if (!_movementsReady || !_bazaarsReady || e.persons.isNotEmpty) {
      return null;
    }
    if (e.matches.isNotEmpty || e.categories.isNotEmpty) {
      if (!_inventoryReady) return null;
    }

    final bazaar = e.bazaar!;
    final (:tags, :units, :names) = b._stockAtBazaar(e);
    final total = units.values.fold<int>(0, (s, u) => s + u);

    BazaarModel? record;
    for (final item in d.bazaars) {
      if (item.name.trim().toLowerCase() == bazaar.toLowerCase()) record = item;
    }
    final inactive = record != null && !record.isActive
        ? '$bazaar is marked inactive.'
        : null;

    final whole = b._base(e) == null;
    if (tags.isEmpty) {
      return _join([
        whole
            ? 'There is no stock at $bazaar right now.'
            : 'There is nothing $_within at $bazaar right now.',
        inactive,
      ]);
    }

    return _join([
      '$bazaar has ${_units(total)}${whole ? '' : ' $_within'}, from '
          '${tags.length == 1 ? '1 asset' : '${_n(tags.length)} assets'}:',
      _list([
        for (final tag in tags)
          '${(names[tag] ?? '').isEmpty || names[tag] == tag ? tag : '$tag (${names[tag]})'}: '
              '${_units(units[tag]!)}',
      ]),
      inactive,
    ]);
  }

  /// "Bazaar stock", "which Bazaar has the most laptops".
  String? _perBazaar(Set<LocalAiTopic> own) {
    if (own.length != 1 || !_movementsReady || !_bazaarsReady) return null;
    if (e.persons.isNotEmpty || e.department != null) return null;
    final base = b._base(e);
    if (base != null && !_inventoryReady) return null;

    final (:names, :units, records: _, active: _) = b._stockAtEachBazaar(e);
    final withStock = names.where((n) => units[n]! > 0).toList();
    final empty = names.where((n) => units[n]! <= 0).toList();
    final total = units.values.fold<int>(0, (s, u) => s + u);

    if (withStock.isEmpty) {
      return base == null
          ? 'No stock is at any Bazaar right now.'
          : 'Nothing $_within is at a Bazaar right now.';
    }

    // The Dashboard's figure is worked out from the asset records, this one
    // from the transfer records the Bazaar screens read. They should agree;
    // when they do not, both are shown rather than one silently.
    final dashboard = base == null && d.bazaarQuantity != total
        ? '\nThe Dashboard shows ${_units(d.bazaarQuantity)} at Bazaars; it '
              'counts from the asset records, and this list from the transfer '
              'records.'
        : null;

    return _join([
      '${base == null ? 'Stock at Bazaars' : 'At Bazaars, $_within'}: '
          '${_units(total)}, at '
          '${withStock.length == 1 ? '1 Bazaar' : '${_n(withStock.length)} Bazaars'}:',
      _list([for (final n in withStock) '$n: ${_units(units[n]!)}']),
      if (empty.isNotEmpty)
        '${base == null ? 'With no stock' : 'With none of it'}: '
            '${empty.take(_maxLines).join(', ')}'
            '${empty.length > _maxLines ? ' and ${_n(empty.length - _maxLines)} more' : ''}.',
      dashboard,
    ]);
  }

  /// "How many Bazaars are there", "active Bazaars in Lahore".
  String? _directory(Set<LocalAiTopic> own) {
    if (own.length != 1 || !_bazaarsReady || e.bazaar != null) return null;
    if (!e.isEmpty) return null;

    final (:list, :title) = b._bazaarsFor(question, filters);
    final all = d.bazaars;

    final summary =
        '${all.length == 1 ? '1 Bazaar' : '${_n(all.length)} Bazaars'} in all: '
        '${_n(all.where((x) => x.isActive).length)} active, '
        '${_n(all.where((x) => !x.isActive).length)} disabled.';

    if (title == 'Bazaars') {
      return _join([
        summary,
        _list([for (final x in list) _bazaarLine(x)]),
      ]);
    }

    if (list.isEmpty) return '$title: none.\n$summary';
    return _join([
      '$title: ${_n(list.length)}.',
      _list([for (final x in list) _bazaarLine(x)]),
    ]);
  }

  static String _bazaarLine(BazaarModel x) {
    final city = x.location.trim();
    return [
      x.name.trim(),
      if (city.isNotEmpty) '($city)',
      if (!x.isActive) '- disabled',
    ].join(' ');
  }

  // ------------------------------------------------------------ movements

  /// "Transfers this week", "returns from Township in the last 30 days".
  String? _movements(Set<LocalAiTopic> own) {
    if (own.length != 1 || !_movementsReady) return null;
    if (e.persons.isNotEmpty || e.department != null) return null;
    if ((e.matches.isNotEmpty || e.categories.isNotEmpty) && !_inventoryReady) {
      return null;
    }

    final (list, qualifiers) = b._movementsFor(e, filters);
    final described = qualifiers.isEmpty ? '' : ' ${qualifiers.join(' ')}';

    if (list.isEmpty) return 'No movements$described.';

    final units = list.fold<int>(0, (s, m) => s + m.quantity);
    return _join([
      'Movements$described: ${_n(list.length)}, ${_units(units)} in all'
          '${list.length > _maxLines ? '. The latest:' : ':'}',
      _list([for (final m in list) _movementLine(m)]),
    ]);
  }

  // ------------------------------------------------------------- requests

  /// "Pending requests", "my transfer requests this week".
  String? _requests(Set<LocalAiTopic> own) {
    if (own.length != 1 || !_requestsReady) return null;
    if (e.persons.isNotEmpty || e.department != null) return null;
    if ((e.matches.isNotEmpty || e.categories.isNotEmpty) && !_inventoryReady) {
      return null;
    }

    final visible = b._visibleRequests();
    final list = b._requestsFor(visible, e, filters, null);
    final title = b._requestsTitle(filters, null);

    if (list.isEmpty) return '$title: none.';

    final byStatus = <String, int>{};
    if (filters.requestStatus == null) {
      for (final r in list) {
        final s = r.status.trim().isEmpty ? 'Unknown' : r.status.trim();
        byStatus[s] = (byStatus[s] ?? 0) + 1;
      }
    }

    return _join([
      '$title: ${_n(list.length)}'
          '${byStatus.length > 1 ? ' (${byStatus.entries.map((s) => '${_n(s.value)} ${s.key}').join(', ')})' : ''}.',
      _list([for (final r in list) _requestLine(r)]),
    ]);
  }

  static String _requestLine(RequestModel r) {
    final by = r.requestedUserName.trim();
    return [
      if (r.requestDate != null) _day(r.requestDate!),
      if (r.requestType.trim().isNotEmpty) _capitalised(r.requestType.trim()),
      if (r.assetName.trim().isNotEmpty) r.assetName.trim(),
      ?_Build._requestDetail(r),
      if (by.isNotEmpty) 'by $by',
      if (r.status.trim().isNotEmpty) r.status.trim(),
    ].join(' · ');
  }

  // --------------------------------------------------------------- people

  String? _people(Set<LocalAiTopic> own) {
    if (!_peopleReady) return null;

    final people = b._people();

    if (e.persons.isNotEmpty) {
      const about = {LocalAiTopic.people, LocalAiTopic.assigned};
      if (!own.every(about.contains) || e.department != null) return null;
      if (e.persons.length > 3 || !_inventoryReady) return null;
      if (e.matches.isNotEmpty || e.categories.isNotEmpty) return null;
      return [for (final p in e.persons) _person(p)].join('\n\n');
    }

    if (e.focus != null || e.bazaar != null) return null;
    if (e.matches.isNotEmpty || e.categories.isNotEmpty) return null;

    final department = e.department;
    if (department != null) {
      const about = {LocalAiTopic.people, LocalAiTopic.departments};
      if (!own.every(about.contains)) return null;
      if (filters.roleFilter != null || filters.activeFilter != null) {
        return null;
      }

      final key = department.toLowerCase();
      final members =
          people.where((p) => p.department.trim().toLowerCase() == key).toList()
            ..sort((x, y) => x.name.compareTo(y.name));

      return _join([
        'The $department department has '
            '${members.length == 1 ? '1 user account' : '${_n(members.length)} user accounts'}:',
        _list([for (final p in members) _personLine(p)]),
      ]);
    }

    if (own.length != 1) return null;

    if (own.single == LocalAiTopic.departments) {
      final counts = <String, int>{};
      for (final p in people) {
        final name = p.department.trim().isEmpty
            ? '(no department)'
            : p.department.trim();
        counts[name] = (counts[name] ?? 0) + 1;
      }
      final names = counts.keys.toList()
        ..sort((x, y) => counts[y]!.compareTo(counts[x]!));

      return _join([
        'User accounts by department:',
        _list([for (final n in names) '$n: ${_n(counts[n]!)}']),
      ]);
    }

    var list = people;
    final words = <String>[];

    final role = filters.roleFilter;
    if (role != null) {
      list = list.where((p) => p.effectiveRole == role).toList();
      words.add(PermissionService.roleLabel(role));
    }

    final active = filters.activeFilter;
    if (active != null) {
      list = list.where((p) => p.isActive == active).toList();
      words.insert(0, active ? 'Active' : 'Inactive');
    }

    if (words.isEmpty) {
      final byRole = <String, int>{};
      for (final p in people) {
        final label = PermissionService.roleLabel(p.effectiveRole);
        byRole[label] = (byRole[label] ?? 0) + 1;
      }
      final activeCount = people.where((p) => p.isActive).length;

      return _join([
        'User accounts: ${_n(people.length)} in all - '
            '${byRole.entries.map((r) => '${_n(r.value)} ${r.key}').join(', ')}. '
            '${_n(activeCount)} active.',
        _list([
          for (final p in [...people]..sort((x, y) => x.name.compareTo(y.name)))
            _personLine(p),
        ]),
      ]);
    }

    list.sort((x, y) => x.name.compareTo(y.name));
    final what = '${words.join(' ')} accounts';
    if (list.isEmpty) return '$what: none.';

    return _join([
      '$what: ${_n(list.length)}.',
      _list([for (final p in list) _personLine(p)]),
    ]);
  }

  static String _personLine(UserModel p) {
    final department = p.department.trim();
    return '${p.name.trim()} (${PermissionService.roleLabel(p.effectiveRole)}'
        '${department.isEmpty ? '' : ', $department'}'
        '${p.isActive ? '' : ', inactive'})';
  }

  /// One person and what they hold.
  String _person(UserModel p) {
    final held =
        d.assets
            .where(
              (a) =>
                  (a.assignedTo ?? '').trim() == p.uid &&
                  a.calculatedAssignedQuantity > 0,
            )
            .toList()
          ..sort(
            (x, y) => y.calculatedAssignedQuantity.compareTo(
              x.calculatedAssignedQuantity,
            ),
          );

    final who = _personLine(p);
    if (held.isEmpty) return '$who holds no assets.';

    return _join([
      '$who holds ${_units(_sum(held, (a) => a.calculatedAssignedQuantity))}, '
          'in ${_records(held.length)}:',
      _list([
        for (final a in held)
          '${_label(a)}: ${_units(a.calculatedAssignedQuantity)}',
      ]),
    ]);
  }

  // ------------------------------------------------------ value, warranty

  static const Set<String> _rankingWords = {
    'most',
    'top',
    'highest',
    'expensive',
    'costly',
    'mehnga',
    'mehenga',
    'mehngi',
    'valuable',
    'qeemti',
    'keemti',
  };

  /// "Total inventory value", "value of laptops", "most expensive assets".
  String? _value(Set<LocalAiTopic> own) {
    if (own.length != 1 || !_inventoryReady) return null;
    if (e.persons.isNotEmpty || e.department != null) return null;

    final base = b._base(e);
    final records = _all;

    final total = base == null
        ? d.totalInventoryValue
        : records.fold<double>(0, (s, a) => s + _worth(a));
    final quantity = base == null ? d.totalQuantity : _sum(records, _quantity);

    final headline = base == null
        ? 'Total inventory value: ${_money(total)}, for ${_units(quantity)} '
              'in ${_records(d.totalAssets)}.'
        : 'Value $_within: ${_money(total)}, for ${_units(quantity)} in '
              '${_records(records.length)}.';

    if (!_asks(_rankingWords)) return headline;

    final ranked = [...records]..sort((x, y) => _worth(y).compareTo(_worth(x)));
    return _join([
      headline,
      'Most valuable:',
      _list([
        for (final a in ranked.take(5))
          '${_label(a)}: ${_money(_worth(a))} (${_units(_quantity(a))})',
      ], total: ranked.length < 5 ? ranked.length : 5),
    ]);
  }

  /// "Which warranties expire soon", "expired warranties of laptops".
  String? _warranty(Set<LocalAiTopic> own) {
    if (own.length != 1 || !_inventoryReady) return null;
    if (e.persons.isNotEmpty || e.department != null) return null;

    final today = b.inputs.retrievedAt;
    final dated = <(AssetModel, DateTime, int)>[
      for (final a in _all)
        if (InventorySnapshot.warrantyEnds(a) case final ends?)
          (a, ends, ends.difference(today).inDays),
    ];

    final within = b._base(e) == null ? '' : ' $_within';
    if (dated.isEmpty) {
      return 'No asset record$within has both a purchase date and a warranty '
          'period, so no warranty end dates can be worked out.';
    }

    final expired = dated.where((w) => w.$3 < 0).toList()
      ..sort((x, y) => y.$3.compareTo(x.$3));
    final running = dated.where((w) => w.$3 >= 0).toList()
      ..sort((x, y) => x.$3.compareTo(y.$3));
    final soon = running.where((w) => w.$3 <= 90).length;

    final headline =
        'Warranty end dates are known for ${_records(dated.length)}$within: '
        '${_n(expired.length)} expired, ${_n(soon)} end within 90 days.';

    if (_asks(const {'expired'})) {
      if (expired.isEmpty) return '$headline\nNone has expired.';
      return _join([
        headline,
        'Expired most recently:',
        _list([
          for (final (a, ends, days) in expired)
            '${_label(a)}: ended ${_day(ends)}, ${_n(-days)} days ago',
        ]),
      ]);
    }

    if (running.isEmpty) return '$headline\nEvery one of them has expired.';
    return _join([
      headline,
      'Ending soonest:',
      _list([
        for (final (a, ends, days) in running)
          '${_label(a)}: ends ${_day(ends)}, in ${_n(days)} days',
      ]),
    ]);
  }
}
