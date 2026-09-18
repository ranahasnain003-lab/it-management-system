import '../../models/asset_model.dart';
import '../../models/user_model.dart';
import '../assets/screens/add_asset_screen.dart' show AddAssetScreen;
import 'assistant_actions.dart';
import 'inventory_assistant.dart';

/// Where a quantity is coming from or going to.
class _Place {
  const _Place({
    required this.index,
    required this.id,
    required this.name,
    required this.isHeadOffice,
    this.isActive = true,
  });

  /// Position in the message, used to tell "A to B" from "B from A".
  final int index;
  final String id;
  final String name;
  final bool isHeadOffice;
  final bool isActive;
}

enum _Verb {
  sendOut,
  returnHome,
  assign,
  unassign,
  addStock,
  createAsset,
  setStatus,
  createBazaar,
  disableBazaar,
  openScreen,
}

/// Turns a typed command into a checked, fully resolved [AssistantAction].
///
/// The planner is deliberately deterministic and offline. The language model
/// never decides what happens: it is only ever asked to reword text that this
/// code has already produced. Everything here resolves against the account's
/// own permission-scoped [InventorySnapshot], so the assistant cannot name an
/// asset, a Bazaar, a person or a figure the account cannot already see, and
/// it cannot invent one.
class ActionPlanner {
  ActionPlanner({InventoryAssistant? finder})
    : _finder = finder ?? InventoryAssistant();

  final InventoryAssistant _finder;

  /// Statuses the assistant will set. Assigned and Deployed are results of
  /// stock movements, not things to be typed, so they are not offered.
  static const Map<String, String> _statusWords = {
    'available': 'Available',
    'usable': 'Available',
    'theek': 'Available',
    'sahi': 'Available',
    'damaged': 'Damaged',
    'damage': 'Damaged',
    'kharab': 'Damaged',
    'toota': 'Damaged',
    'broken': 'Damaged',
    'under repair': 'Under Repair',
    'in repair': 'Under Repair',
    'repair': 'Under Repair',
    'maintenance': 'Under Repair',
    'marammat': 'Under Repair',
    'lost': 'Lost',
    'missing': 'Lost',
    'gum': 'Lost',
    'khoya': 'Lost',
    'disposed': 'Disposed',
    'dispose': 'Disposed',
    'scrap': 'Disposed',
    'retired': 'Disposed',
    'zaya': 'Disposed',
  };

  /// Screens the assistant may open, by the words people use for them.
  static const Map<String, String> _screens = {
    'dashboard': '/dashboard',
    'assets': '/assets',
    'inventory': '/assets',
    'bazaar': '/currently-at-bazaars',
    'bazaars': '/currently-at-bazaars',
    'at bazaars': '/currently-at-bazaars',
    'transfers': '/deployments',
    'deployments': '/deployments',
    'history': '/deployment-history',
    'transfer history': '/deployment-history',
    'requests': '/requests',
    'notifications': '/notifications',
    'users': '/users',
    'settings': '/settings',
    'profile': '/profile',
  };

  static bool _has(String q, List<String> words) => words.any(q.contains);

  /// Words that make a message a question about the inventory rather than an
  /// instruction to change it. Read-only questions must stay read-only.
  static const List<String> _questionWords = [
    'kitna',
    'kitne',
    'kitni',
    'how many',
    'how much',
    'kahan',
    'kaha ',
    'where',
    'history',
    'report',
    'list ',
    'show me all',
    'total',
    'batao',
    'bata do',
    'kya hai',
    'what is',
    'konsa',
    'kaunsa',
  ];

  /// Reads the first standalone whole number in the message, or null.
  ///
  /// The digits must not be glued to letters or hyphens, so the "001" in
  /// "IT-LAP-001" is an asset identifier and never a quantity. Reading it as a
  /// quantity is how "send IT-LAP-001 to Township Bazaar" used to silently
  /// become a transfer of one unit instead of a request for the number.
  static int? readQuantity(String q) {
    final match = RegExp(r'(?<![\w-])(\d[\d,]*)(?![\w-])').firstMatch(q);
    if (match == null) return null;

    final digits = match.group(1)!.replaceAll(',', '');
    return int.tryParse(digits);
  }

  // =========================================================================
  // LABELLED FIELDS, for "add asset" with the full record
  // =========================================================================

  /// Words people use for each asset field, mapped to the field they mean.
  ///
  /// Longer labels are matched first, so "purchase price" wins over "price"
  /// and "serial number" over "serial".
  static const Map<String, String> _assetLabels = {
    'asset id': 'assetId',
    'assetid': 'assetId',
    'asset tag': 'assetId',
    'tag': 'assetId',
    'id': 'assetId',
    'name': 'name',
    'category': 'category',
    'type': 'category',
    'quantity': 'quantity',
    'qty': 'quantity',
    'brand': 'brand',
    'make': 'brand',
    'model': 'model',
    'serial number': 'serialNumber',
    'serial no': 'serialNumber',
    'serial': 'serialNumber',
    'purchase price': 'purchasePrice',
    'unit price': 'purchasePrice',
    'unit purchase price': 'purchasePrice',
    'price': 'purchasePrice',
    'cost': 'purchasePrice',
    'qeemat': 'purchasePrice',
    'purchase date': 'purchaseDate',
    'purchased on': 'purchaseDate',
    'purchased': 'purchaseDate',
    'bought on': 'purchaseDate',
    'warranty months': 'warrantyMonths',
    'warranty': 'warrantyMonths',
    'location': 'location',
    'jagah': 'location',
    'condition': 'condition',
    'halat': 'condition',
    'status': 'status',
    'notes': 'notes',
    'note': 'notes',
    'remarks': 'notes',
  };

  /// Reads `label value` pairs out of [message], keeping the value exactly as
  /// the user typed it.
  ///
  /// A value runs from the end of its label to the start of the next label, so
  /// `brand Dell model Latitude 5420` yields brand "Dell" and model
  /// "Latitude 5420" without either swallowing the other.
  static Map<String, String> readAssetFields(String message) {
    final lower = message.toLowerCase();

    // Where each label sits in the message, longest label first so a short
    // label inside a longer one never wins.
    final labels = _assetLabels.keys.toList()
      ..sort((a, b) => b.length.compareTo(a.length));

    final hits = <({int start, int end, String field})>[];

    for (final label in labels) {
      // Hyphens and underscores count as part of a word here, so the "BRAND"
      // inside a serial like SN-BRAND-NEW is not mistaken for the brand label.
      final pattern = RegExp(
        '(?<![a-z0-9_-])${RegExp.escape(label)}(?![a-z0-9_-])\\s*[:=]?\\s*',
      );

      for (final match in pattern.allMatches(lower)) {
        final overlaps = hits.any(
          (h) => match.start < h.end && h.start < match.end,
        );
        if (overlaps) continue;

        hits.add((start: match.start, end: match.end, field: _assetLabels[label]!));
      }
    }

    hits.sort((a, b) => a.start.compareTo(b.start));

    final fields = <String, String>{};

    // A bare "5 units" written between two labels belongs to neither of them:
    // in "category Laptop 5 units price 85000" it is the quantity. It is kept
    // aside and only used if no explicit quantity label was given.
    String? loneQuantity;

    for (var i = 0; i < hits.length; i++) {
      final valueStart = hits[i].end;
      final valueEnd = i + 1 < hits.length ? hits[i + 1].start : message.length;

      if (valueEnd <= valueStart) {
        fields[hits[i].field] = '';
        continue;
      }

      var value = message.substring(valueStart, valueEnd).trim();

      // Trim the punctuation and joining words that separate one field from
      // the next: `brand Dell, model X` and `brand Dell and model X`.
      value = value.replaceAll(RegExp(r'[,;]+$'), '').trim();
      value = value.replaceAll(RegExp(r'\s+and$', caseSensitive: false), '').trim();

      if (value.length >= 2 &&
          ((value.startsWith('"') && value.endsWith('"')) ||
              (value.startsWith("'") && value.endsWith("'")))) {
        value = value.substring(1, value.length - 1).trim();
      }

      if (hits[i].field != 'quantity' && hits[i].field != 'notes') {
        final trailing = RegExp(
          r'^(.*?)[\s,]+(\d[\d,]*)\s*(units?|pcs|pieces?|nos)$',
          caseSensitive: false,
        ).firstMatch(value);

        if (trailing != null) {
          value = trailing.group(1)!.trim();
          loneQuantity ??= trailing.group(2);
        }
      }

      // A repeated label keeps the first value rather than the last.
      fields.putIfAbsent(hits[i].field, () => value);
    }

    if (loneQuantity != null) {
      fields.putIfAbsent('quantity', () => loneQuantity!);
    }

    return fields;
  }

  /// The screen a navigation phrase refers to, or null.
  static String? screenRoute(String q) {
    String? route;
    var bestLength = 0;

    _screens.forEach((word, path) {
      if (q.contains(word) && word.length > bestLength) {
        route = path;
        bestLength = word.length;
      }
    });

    return route;
  }

  _Verb? _verb(String q) {
    // Most specific first: "create bazaar" must not read as "create asset",
    // and "return" must not read as a generic transfer.
    if (_has(q, ['disable bazaar', 'close bazaar', 'deactivate bazaar', 'bazaar band', 'bazaar disable', 'bazaar ko band'])) {
      return _Verb.disableBazaar;
    }
    if (_has(q, ['new bazaar', 'create bazaar', 'add bazaar', 'naya bazaar', 'bazaar banao', 'bazaar add'])) {
      return _Verb.createBazaar;
    }
    if (_has(q, ['new asset', 'create asset', 'add asset', 'naya asset', 'asset banao', 'register asset', 'asset add kar'])) {
      return _Verb.createAsset;
    }
    // "open the transfers screen" contains "transfer", so navigation is
    // settled before the movement verbs. It only fires when a navigation word
    // and a screen the app actually has are both present.
    if (_has(q, ['open ', 'go to ', 'take me to', 'kholo', 'dikhao', 'screen']) &&
        screenRoute(q) != null) {
      return _Verb.openScreen;
    }
    if (_has(q, ['add stock', 'stock add', 'increase stock', 'stock barha', 'barhao', 'add units', 'units add', 'stock bharo']) ||
        // "add 20 units to IT-LAP-001", "20 aur add karo"
        RegExp(r'\badd\s+\d[\d,]*\s').hasMatch(q) ||
        RegExp(r'\d[\d,]*\s+aur\s+add').hasMatch(q)) {
      return _Verb.addStock;
    }
    if (_has(q, ['return', 'wapas', 'wapis', 'bring back', 'send back'])) {
      return _Verb.returnHome;
    }
    if (_has(q, ['unassign', 'take back', 'recall', 'release from', 'wapas lo'])) {
      return _Verb.unassign;
    }
    if (_has(q, ['assign', 'issue to', 'de do', 'dedo', 'hawale'])) {
      return _Verb.assign;
    }
    if (_has(q, ['mark as', 'mark ', 'set status', 'status change', 'status ko', 'change status'])) {
      return _Verb.setStatus;
    }
    if (_has(q, ['send', 'transfer', 'move', 'deploy', 'shift', 'bhej', 'bheij'])) {
      return _Verb.sendOut;
    }

    return null;
  }

  /// Every location named in the message, in the order they appear.
  List<_Place> _places(String q, InventorySnapshot data) {
    final found = <_Place>[];

    final headOffice = _firstIndexOf(q, ['head office', 'head-office', 'headoffice', 'ho stock']);
    if (headOffice != null) {
      found.add(_Place(index: headOffice, id: '', name: 'Head Office', isHeadOffice: true));
    }

    for (final bazaar in data.bazaars) {
      final name = bazaar.name.trim();
      if (name.length <= 2) continue;

      final lower = name.toLowerCase();
      var at = q.indexOf(lower);

      if (at < 0) {
        // "Township" for "Township Bazaar".
        final short = lower.replaceAll(' bazaar', '').trim();
        if (short.length > 3) at = q.indexOf(short);
      }

      if (at < 0) continue;

      found.add(_Place(
        index: at,
        id: bazaar.id,
        name: name,
        isHeadOffice: false,
        isActive: bazaar.isActive,
      ));
    }

    found.sort((a, b) => a.index.compareTo(b.index));

    // Two different mentions of the same place are one place.
    final unique = <_Place>[];
    for (final place in found) {
      final already = unique.any((p) =>
          p.isHeadOffice == place.isHeadOffice &&
          p.name.toLowerCase() == place.name.toLowerCase());
      if (!already) unique.add(place);
    }

    return unique;
  }

  static int? _firstIndexOf(String q, List<String> words) {
    int? best;
    for (final word in words) {
      final at = q.indexOf(word);
      if (at >= 0 && (best == null || at < best)) best = at;
    }
    return best;
  }

  /// True when the words just before [place] mark it as where stock comes from.
  static bool _markedAsSource(String q, _Place place) {
    final start = place.index - 14 < 0 ? 0 : place.index - 14;
    final before = q.substring(start, place.index);
    return _has(before, ['from ', ' se ', 'se ']);
  }

  /// Units of [asset] currently at [place], from the movement records the app
  /// already uses. Nothing is recalculated here.
  static int _availableAt(AssetModel asset, InventorySnapshot data, _Place place) {
    if (place.isHeadOffice) return asset.calculatedHeadOfficeQuantity;

    var total = 0;

    for (final movement in data.movementsForAsset(asset)) {
      if (movement.status.trim().toLowerCase() != 'active') continue;

      final id = (movement.toBazaarId ?? '').trim();
      final name = (movement.toBazaarName ?? movement.toLocation).trim();

      final matches = (place.id.isNotEmpty && id == place.id) ||
          (name.isNotEmpty && name.toLowerCase() == place.name.toLowerCase());

      if (matches) total += movement.quantity;
    }

    return total;
  }

  /// Plans an action, or returns null when the message was not a command and
  /// the ordinary read-only answer should be used instead.
  ActionPlan? plan(
    String message,
    InventorySnapshot data,
    AssistantPermissions permissions, {
    List<UserModel> people = const <UserModel>[],
    AssetModel? lastAsset,
  }) {
    final q = message.toLowerCase().trim();
    if (q.isEmpty) return null;

    final verb = _verb(q);
    if (verb == null) return null;

    // Opening a screen is the one thing that reads as both a question and a
    // command, and it changes nothing, so it is allowed through.
    if (verb != _Verb.openScreen && _has(q, _questionWords)) return null;

    switch (verb) {
      case _Verb.openScreen:
        return _planOpenScreen(q);
      case _Verb.createBazaar:
        return _planCreateBazaar(message, q, data, permissions);
      case _Verb.disableBazaar:
        return _planDisableBazaar(q, data, permissions);
      case _Verb.createAsset:
        return _planCreateAsset(message, q, data, permissions);
      case _Verb.addStock:
        return _planAddStock(q, data, permissions, lastAsset);
      case _Verb.setStatus:
        return _planSetStatus(q, data, permissions, lastAsset);
      case _Verb.assign:
        return _planAssign(q, data, permissions, people, lastAsset);
      case _Verb.unassign:
        return _planUnassign(q, data, permissions, lastAsset);
      case _Verb.sendOut:
      case _Verb.returnHome:
        return _planMovement(q, data, permissions, verb, lastAsset);
    }
  }

  // ---------------------------------------------------------------- helpers

  AssetModel? _asset(String q, InventorySnapshot data, AssetModel? lastAsset) {
    return _finder.findAsset(q, data) ?? lastAsset;
  }

  static String _units(int value) => value == 1 ? '1 unit' : '$value units';

  ActionPlan _needAsset() => const ActionPlan.ask(
    'Which asset do you mean? Give me its Asset ID, serial number or exact name.',
  );

  ActionPlan? _checkQuantity(int? quantity) {
    if (quantity == null) {
      return const ActionPlan.ask('How many units? Tell me a whole number.');
    }
    if (quantity <= 0) {
      return const ActionPlan.refuse(
        'The quantity has to be at least 1, so there is nothing for me to do here.',
      );
    }
    return null;
  }

  // ------------------------------------------------------------- navigation

  ActionPlan? _planOpenScreen(String q) {
    final route = screenRoute(q);
    if (route == null) return null;

    return ActionPlan.propose(AssistantAction(
      kind: AssistantActionKind.openScreen,
      title: 'Open $route',
      details: const [],
      route: route,
    ));
  }

  // ------------------------------------------------------------ stock moves

  ActionPlan _planMovement(
    String q,
    InventorySnapshot data,
    AssistantPermissions permissions,
    _Verb verb,
    AssetModel? lastAsset,
  ) {
    if (!permissions.canTransfer && !permissions.worksThroughRequests) {
      return const ActionPlan.refuse(
        'Your account is not allowed to move stock, so I cannot do that.',
      );
    }

    if (!data.bazaarDataLoaded) {
      return const ActionPlan.ask(
        'I do not have the Bazaar records loaded yet, so I will not guess where '
        'the stock is. Open the Bazaars or Transfers screen once and ask me again.',
      );
    }

    final asset = _asset(q, data, lastAsset);
    if (asset == null) return _needAsset();

    final quantity = readQuantity(q);
    final quantityProblem = _checkQuantity(quantity);
    if (quantityProblem != null) return quantityProblem;

    final places = _places(q, data);

    _Place? source;
    _Place? destination;

    if (verb == _Verb.returnHome) {
      destination = const _Place(index: -1, id: '', name: 'Head Office', isHeadOffice: true);
      source = places.where((p) => !p.isHeadOffice).firstOrNull;

      if (source == null) {
        return const ActionPlan.ask(
          'Which Bazaar should the stock come back from?',
        );
      }
    } else {
      final marked = places.where(_markedAsSourceIn(q)).toList();
      final unmarked = places.where((p) => !_markedAsSource(q, p)).toList();

      if (marked.isNotEmpty) {
        source = marked.first;
        destination = unmarked.firstOrNull;
      } else if (places.length >= 2) {
        source = places.first;
        destination = places[1];
      } else if (places.length == 1) {
        // "send 10 LaptopA to Township" - from Head Office by default, which
        // is where unassigned stock sits.
        destination = places.first;
        source = const _Place(index: -1, id: '', name: 'Head Office', isHeadOffice: true);
      }

      // "from Township to Township": only one place resolves, because a name
      // is looked up once, so the repeat is caught here instead.
      if (destination == null && source != null && !source.isHeadOffice) {
        final mentions = source.name.toLowerCase().allMatches(q).length;
        if (mentions >= 2) {
          return const ActionPlan.refuse(
            'The source and the destination are the same Bazaar, so there is '
            'nothing to move.',
          );
        }
      }

      if (destination == null) {
        return const ActionPlan.ask(
          'Which Bazaar should I send them to? Name the Bazaar exactly as it '
          'appears in the app.',
        );
      }

      source ??= const _Place(index: -1, id: '', name: 'Head Office', isHeadOffice: true);
    }

    if (source.isHeadOffice && destination.isHeadOffice) {
      return const ActionPlan.refuse(
        'That would move stock from Head Office to Head Office, which changes nothing.',
      );
    }

    if (!source.isHeadOffice &&
        !destination.isHeadOffice &&
        source.name.toLowerCase() == destination.name.toLowerCase()) {
      return const ActionPlan.refuse(
        'The source and the destination are the same Bazaar, so there is nothing to move.',
      );
    }

    if (!destination.isHeadOffice && !destination.isActive) {
      return ActionPlan.refuse(
        '${destination.name} is disabled, so I will not send stock there.',
      );
    }

    final available = _availableAt(asset, data, source);

    if (available <= 0) {
      return ActionPlan.refuse(
        'There is no stock of ${_label(asset)} at ${source.name} right now, so '
        'I cannot move any.',
      );
    }

    if (quantity! > available) {
      return ActionPlan.refuse(
        '${source.name} only has ${_units(available)} of ${_label(asset)}, so I '
        'cannot move ${_units(quantity)}.',
      );
    }

    final kind = destination.isHeadOffice
        ? AssistantActionKind.returnToHeadOffice
        : (source.isHeadOffice
            ? AssistantActionKind.sendToBazaar
            : AssistantActionKind.moveBetweenBazaars);

    final viaRequest = permissions.worksThroughRequests;

    return ActionPlan.propose(AssistantAction(
      kind: kind,
      title: viaRequest
          ? 'Request a transfer of ${_units(quantity)}'
          : 'Move ${_units(quantity)}',
      details: [
        'Asset: ${_label(asset)}',
        'From: ${source.name}',
        'To: ${destination.name}',
        'Quantity: ${_units(quantity)}',
        'Available at ${source.name}: ${_units(available)}',
        if (viaRequest) 'This will be sent to your Admin for approval.',
      ],
      asset: asset,
      quantity: quantity,
      sourceId: source.id,
      sourceName: source.name,
      destinationId: destination.id,
      destinationName: destination.name,
      viaRequest: viaRequest,
    ));
  }

  static bool Function(_Place) _markedAsSourceIn(String q) {
    return (place) => _markedAsSource(q, place);
  }

  static String _label(AssetModel asset) {
    final tag = asset.assetId.trim();
    return tag.isEmpty ? asset.name : '$tag (${asset.name})';
  }

  // ---------------------------------------------------------------- assign

  ActionPlan _planAssign(
    String q,
    InventorySnapshot data,
    AssistantPermissions permissions,
    List<UserModel> people,
    AssetModel? lastAsset,
  ) {
    if (!permissions.canAssign && !permissions.worksThroughRequests) {
      return const ActionPlan.refuse(
        'Your account is not allowed to assign assets, so I cannot do that.',
      );
    }

    final asset = _asset(q, data, lastAsset);
    if (asset == null) return _needAsset();

    if (asset.calculatedHeadOfficeQuantity <= 0) {
      return ActionPlan.refuse(
        '${_label(asset)} has no unassigned stock at Head Office, so there is '
        'nothing to hand over.',
      );
    }

    UserModel? person;
    var bestLength = 0;

    for (final candidate in people) {
      for (final handle in [candidate.name.trim(), candidate.email.trim()]) {
        final lower = handle.toLowerCase();
        if (lower.length <= 2 || !q.contains(lower)) continue;
        if (lower.length > bestLength) {
          person = candidate;
          bestLength = lower.length;
        }
      }
    }

    if (person == null) {
      return const ActionPlan.ask(
        'Who should I assign it to? Give me the exact name or the email address '
        'of the person, as it appears under Users.',
      );
    }

    final viaRequest = permissions.worksThroughRequests;

    return ActionPlan.propose(AssistantAction(
      kind: AssistantActionKind.assign,
      title: viaRequest ? 'Request an assignment' : 'Assign ${_label(asset)}',
      details: [
        'Asset: ${_label(asset)}',
        'To: ${person.name} (${person.email})',
        'Unassigned at Head Office: ${_units(asset.calculatedHeadOfficeQuantity)}',
        if (viaRequest) 'This will be sent to your Admin for approval.',
      ],
      asset: asset,
      assigneeUid: person.uid,
      assigneeName: person.name,
      viaRequest: viaRequest,
    ));
  }

  ActionPlan _planUnassign(
    String q,
    InventorySnapshot data,
    AssistantPermissions permissions,
    AssetModel? lastAsset,
  ) {
    if (!permissions.canReturn && !permissions.worksThroughRequests) {
      return const ActionPlan.refuse(
        'Your account is not allowed to take assets back, so I cannot do that.',
      );
    }

    final asset = _asset(q, data, lastAsset);
    if (asset == null) return _needAsset();

    final holder = (asset.assignedTo ?? '').trim();

    if (holder.isEmpty && asset.calculatedAssignedQuantity <= 0) {
      return ActionPlan.refuse(
        '${_label(asset)} is not assigned to anyone, so there is nothing to take back.',
      );
    }

    final viaRequest = permissions.worksThroughRequests;

    return ActionPlan.propose(AssistantAction(
      kind: AssistantActionKind.unassign,
      title: viaRequest ? 'Request an unassignment' : 'Take ${_label(asset)} back',
      details: [
        'Asset: ${_label(asset)}',
        'Currently assigned: ${_units(asset.calculatedAssignedQuantity)}',
        'The stock returns to Head Office.',
        if (viaRequest) 'This will be sent to your Admin for approval.',
      ],
      asset: asset,
      viaRequest: viaRequest,
    ));
  }

  // ---------------------------------------------------------------- status

  ActionPlan _planSetStatus(
    String q,
    InventorySnapshot data,
    AssistantPermissions permissions,
    AssetModel? lastAsset,
  ) {
    if (!permissions.canChangeStatus && !permissions.worksThroughRequests) {
      return const ActionPlan.refuse(
        'Your account is not allowed to change an asset status, so I cannot do that.',
      );
    }

    final asset = _asset(q, data, lastAsset);
    if (asset == null) return _needAsset();

    String? status;
    var bestLength = 0;

    _statusWords.forEach((word, canonical) {
      if (q.contains(word) && word.length > bestLength) {
        status = canonical;
        bestLength = word.length;
      }
    });

    if (status == null) {
      return const ActionPlan.ask(
        'Which status? I can set Available, Damaged, Under Repair, Lost or Disposed.',
      );
    }

    if (asset.status.trim().toLowerCase() == status!.toLowerCase()) {
      return ActionPlan.refuse(
        '${_label(asset)} is already marked $status, so nothing would change.',
      );
    }

    final viaRequest = permissions.worksThroughRequests;

    return ActionPlan.propose(AssistantAction(
      kind: AssistantActionKind.updateStatus,
      title: viaRequest ? 'Request a status change' : 'Mark ${_label(asset)} $status',
      details: [
        'Asset: ${_label(asset)}',
        'Current status: ${asset.status}',
        'New status: $status',
        if (viaRequest) 'This will be sent to your Admin for approval.',
      ],
      asset: asset,
      status: status!,
      viaRequest: viaRequest,
    ));
  }

  // ----------------------------------------------------------------- stock

  ActionPlan _planAddStock(
    String q,
    InventorySnapshot data,
    AssistantPermissions permissions,
    AssetModel? lastAsset,
  ) {
    if (!permissions.canEditAsset && !permissions.worksThroughRequests) {
      return const ActionPlan.refuse(
        'Your account is not allowed to change stock levels, so I cannot do that.',
      );
    }

    final asset = _asset(q, data, lastAsset);
    if (asset == null) return _needAsset();

    final quantity = readQuantity(q);
    final quantityProblem = _checkQuantity(quantity);
    if (quantityProblem != null) return quantityProblem;

    final viaRequest = permissions.worksThroughRequests;

    return ActionPlan.propose(AssistantAction(
      kind: AssistantActionKind.addStock,
      title: viaRequest
          ? 'Request ${_units(quantity!)} more'
          : 'Add ${_units(quantity!)} to ${_label(asset)}',
      details: [
        'Asset: ${_label(asset)}',
        'Current total: ${_units(asset.quantity)}',
        'Adding: ${_units(quantity)}',
        'New total: ${_units(asset.quantity + quantity)}',
        'The new units go to Head Office.',
        if (viaRequest) 'This will be sent to your Admin for approval.',
      ],
      asset: asset,
      quantity: quantity,
      viaRequest: viaRequest,
    ));
  }

  ActionPlan _planCreateAsset(
    String original,
    String q,
    InventorySnapshot data,
    AssistantPermissions permissions,
  ) {
    if (!permissions.canAddAsset) {
      return const ActionPlan.refuse(
        'Only an Admin or Super Admin can create an asset, so I cannot do that '
        'for your account. You can raise a request from the Requests screen.',
      );
    }

    final fields = readAssetFields(original);

    // The name may be given as a label or simply quoted, the way people write
    // it: add asset "Dell Latitude 5420" id IT-LAP-010 ...
    final name = (fields['name'] ?? _quoted(original) ?? '').trim();

    // The four the Add Asset form marks required, plus the category, which the
    // form pre-selects but the assistant must not pick on the user's behalf.
    final missing = <String>[
      if (fields['assetId'] == null || fields['assetId']!.trim().isEmpty) 'Asset ID',
      if (name.length < 2) 'name',
      if (fields['category'] == null || fields['category']!.trim().isEmpty) 'category',
      if (fields['quantity'] == null && _quantityWords(original) == null) 'quantity',
      if (fields['purchasePrice'] == null ||
          fields['purchasePrice']!.trim().isEmpty)
        'unit purchase price',
    ];

    if (missing.isNotEmpty) {
      return ActionPlan.ask(
        'I still need the ${_list(missing)}. Give it to me like this:\n'
        '  add asset "Dell Latitude 5420" id IT-LAP-010 category Laptop '
        'qty 10 price 85000\n'
        'You can also add brand, model, serial, purchase date, warranty, '
        'location, condition, status and notes.',
      );
    }

    final assetId = fields['assetId']!.trim();

    // --- the required values must parse -----------------------------------
    // "qty 5", "qty 5 units" and a bare "5 units" all mean the same thing.
    final quantityDigits = fields['quantity'] == null
        ? null
        : RegExp(r'\d[\d,]*').firstMatch(fields['quantity']!);

    final quantity = quantityDigits != null
        ? int.tryParse(quantityDigits.group(0)!.replaceAll(',', ''))
        : _quantityWords(original);

    if (quantity == null) {
      return const ActionPlan.ask('How many units? Tell me a whole number.');
    }
    if (quantity <= 0) {
      return const ActionPlan.refuse('The quantity has to be at least 1.');
    }

    final price = double.tryParse(
      fields['purchasePrice']!.trim().replaceAll(',', '').replaceAll(RegExp(r'^rs\.?\s*', caseSensitive: false), ''),
    );

    if (price == null || price < 0) {
      return const ActionPlan.ask(
        'What is the unit purchase price? Give me a number, for example 85000.',
      );
    }

    // --- the fixed vocabularies, taken from the Add Asset form itself ------
    final category = _oneOf(fields['category']!, AddAssetScreen.categories);

    if (category == null) {
      return ActionPlan.ask(
        'I do not recognise that category. Pick one of: '
        '${AddAssetScreen.categories.join(', ')}.',
      );
    }

    String? status = 'Available';
    if (fields['status'] != null && fields['status']!.trim().isNotEmpty) {
      status = _oneOf(fields['status']!, AddAssetScreen.statuses);
      if (status == null) {
        return ActionPlan.ask(
          'I do not recognise that status. Pick one of: '
          '${AddAssetScreen.statuses.join(', ')}.',
        );
      }
    }

    String? condition = 'Good';
    if (fields['condition'] != null && fields['condition']!.trim().isNotEmpty) {
      condition = _oneOf(fields['condition']!, AddAssetScreen.conditions);
      if (condition == null) {
        return ActionPlan.ask(
          'I do not recognise that condition. Pick one of: '
          '${AddAssetScreen.conditions.join(', ')}.',
        );
      }
    }

    // --- optional values, each checked rather than guessed ----------------
    DateTime? purchaseDate;
    if (fields['purchaseDate'] != null && fields['purchaseDate']!.trim().isNotEmpty) {
      purchaseDate = readDate(fields['purchaseDate']!);
      if (purchaseDate == null) {
        return const ActionPlan.ask(
          'I could not read that purchase date. Write it as 2026-01-15, '
          '15/01/2026 or 15-01-2026.',
        );
      }
    }

    var warrantyMonths = 0;
    if (fields['warrantyMonths'] != null &&
        fields['warrantyMonths']!.trim().isNotEmpty) {
      final digits = RegExp(r'\d+').firstMatch(fields['warrantyMonths']!);
      final months = digits == null ? null : int.tryParse(digits.group(0)!);

      if (months == null || months < 0) {
        return const ActionPlan.ask(
          'How many months of warranty? Give me a whole number, for example 24.',
        );
      }

      warrantyMonths = months;
    }

    // --- nothing may collide with what already exists ----------------------
    final idClash = data.assets.where(
      (a) => a.assetId.trim().toLowerCase() == assetId.toLowerCase(),
    ).firstOrNull;

    if (idClash != null) {
      return ActionPlan.refuse(
        'Asset ID "$assetId" already belongs to ${idClash.name}. Pick a different one.',
      );
    }

    final nameClash = data.assets.where(
      (a) => a.name.trim().toLowerCase() == name.toLowerCase(),
    ).firstOrNull;

    if (nameClash != null) {
      return ActionPlan.refuse(
        'There is already an asset called "${nameClash.name}" (${nameClash.assetId}). '
        'If you meant to add stock to it, say: add $quantity units to ${nameClash.assetId}.',
      );
    }

    final serial = (fields['serialNumber'] ?? '').trim();

    if (serial.isNotEmpty) {
      final serialClash = data.assets.where(
        (a) => a.serialNumber.trim().toLowerCase() == serial.toLowerCase(),
      ).firstOrNull;

      if (serialClash != null) {
        return ActionPlan.refuse(
          'Serial number "$serial" already belongs to ${serialClash.assetId} '
          '(${serialClash.name}).',
        );
      }
    }

    final location = (fields['location'] ?? '').trim();

    final draft = NewAssetDraft(
      assetId: assetId,
      name: name,
      category: category,
      quantity: quantity,
      purchasePrice: price,
      status: status,
      condition: condition,
      location: location.isEmpty ? 'Head Office' : location,
      brand: (fields['brand'] ?? '').trim(),
      model: (fields['model'] ?? '').trim(),
      serialNumber: serial,
      purchaseDate: purchaseDate,
      warrantyMonths: warrantyMonths,
      notes: (fields['notes'] ?? '').trim(),
    );

    return ActionPlan.propose(AssistantAction(
      kind: AssistantActionKind.createAsset,
      title: 'Create "$name"',
      details: draft.previewLines(),
      quantity: quantity,
      subjectName: name,
      draft: draft,
    ));
  }

  /// "10 units" / "10 pcs" - a quantity written before the word, not after a
  /// label. Kept separate so a price or a warranty figure is never mistaken
  /// for a quantity.
  static int? _quantityWords(String message) {
    final match = RegExp(
      r'(?<![\w-])(\d[\d,]*)\s*(units?|pcs|pieces?|nos)(?![a-z])',
      caseSensitive: false,
    ).firstMatch(message);

    if (match == null) return null;

    return int.tryParse(match.group(1)!.replaceAll(',', ''));
  }

  /// Matches [value] against one of the app's own dropdown options.
  static String? _oneOf(String value, List<String> options) {
    final clean = value.trim().toLowerCase();

    for (final option in options) {
      if (option.toLowerCase() == clean) return option;
    }

    return null;
  }

  /// Reads 2026-01-15, 15/01/2026 or 15-01-2026.
  static DateTime? readDate(String value) {
    final clean = value.trim();

    final iso = RegExp(r'^(\d{4})-(\d{1,2})-(\d{1,2})$').firstMatch(clean);
    if (iso != null) {
      return _date(iso.group(1)!, iso.group(2)!, iso.group(3)!);
    }

    final dmy = RegExp(r'^(\d{1,2})[/-](\d{1,2})[/-](\d{4})$').firstMatch(clean);
    if (dmy != null) {
      return _date(dmy.group(3)!, dmy.group(2)!, dmy.group(1)!);
    }

    return null;
  }

  static DateTime? _date(String year, String month, String day) {
    final y = int.tryParse(year);
    final m = int.tryParse(month);
    final d = int.tryParse(day);

    if (y == null || m == null || d == null) return null;
    if (m < 1 || m > 12 || d < 1 || d > 31) return null;

    final result = DateTime(y, m, d);

    // DateTime rolls 31 February over into March; that is a typo, not a date.
    if (result.year != y || result.month != m || result.day != d) return null;

    return result;
  }

  static String _list(List<String> items) {
    if (items.length == 1) return items.first;
    return '${items.sublist(0, items.length - 1).join(', ')} and ${items.last}';
  }

  /// The text inside the first pair of quotes, if any.
  static String? _quoted(String message) {
    final match = RegExp('"([^"]{2,80})"').firstMatch(message) ??
        RegExp("'([^']{2,80})'").firstMatch(message);
    return match?.group(1);
  }

  // --------------------------------------------------------------- bazaars

  ActionPlan _planCreateBazaar(
    String original,
    String q,
    InventorySnapshot data,
    AssistantPermissions permissions,
  ) {
    if (!permissions.canManageBazaars) {
      return const ActionPlan.refuse(
        'Only an account that manages locations can add a Bazaar, so I cannot '
        'do that for your account.',
      );
    }

    final name = _quoted(original);

    if (name == null || name.trim().length < 2) {
      return const ActionPlan.ask(
        'What should the Bazaar be called? Put the name in quotes, for example: '
        'create bazaar "Model Town Bazaar".',
      );
    }

    final clash = data.bazaars.where(
      (b) => b.name.trim().toLowerCase() == name.trim().toLowerCase(),
    ).firstOrNull;

    if (clash != null) {
      return ActionPlan.refuse('"${clash.name}" already exists in the Bazaar list.');
    }

    return ActionPlan.propose(AssistantAction(
      kind: AssistantActionKind.createBazaar,
      title: 'Create Bazaar "$name"',
      details: ['Name: $name', 'It will be created as Active.'],
      subjectName: name.trim(),
    ));
  }

  ActionPlan _planDisableBazaar(
    String q,
    InventorySnapshot data,
    AssistantPermissions permissions,
  ) {
    if (!permissions.canManageBazaars) {
      return const ActionPlan.refuse(
        'Only an account that manages locations can disable a Bazaar, so I '
        'cannot do that for your account.',
      );
    }

    final name = _finder.findBazaar(q, data);

    if (name == null) {
      return const ActionPlan.ask(
        'Which Bazaar should I disable? Name it exactly as it appears in the app.',
      );
    }

    final bazaar = data.bazaars.where(
      (b) => b.name.trim().toLowerCase() == name.trim().toLowerCase(),
    ).firstOrNull;

    if (bazaar == null) {
      return const ActionPlan.ask(
        'I could not find that Bazaar in the list, so I will not guess which one you mean.',
      );
    }

    if (!bazaar.isActive) {
      return ActionPlan.refuse('${bazaar.name} is already disabled.');
    }

    final stillThere = data.quantityPerBazaar[bazaar.name] ?? 0;

    if (stillThere > 0) {
      return ActionPlan.refuse(
        '${bazaar.name} still holds ${_units(stillThere)}. Return that stock to '
        'Head Office first, then I can disable it.',
      );
    }

    return ActionPlan.propose(AssistantAction(
      kind: AssistantActionKind.disableBazaar,
      title: 'Disable ${bazaar.name}',
      details: [
        'Bazaar: ${bazaar.name}',
        'Stock currently there: none',
        'The record is kept; it is only marked inactive.',
      ],
      destinationId: bazaar.id,
      subjectName: bazaar.name,
    ));
  }
}

extension _FirstOrNull<T> on Iterable<T> {
  T? get firstOrNull {
    final iterator = this.iterator;
    return iterator.moveNext() ? iterator.current : null;
  }
}
