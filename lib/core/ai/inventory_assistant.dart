import '../../models/asset_model.dart';
import '../../models/deployment_model.dart';
import '../services/bazaar_service.dart' show BazaarModel;

/// Everything the assistant is allowed to talk about, captured from the
/// providers the signed-in account already listens to.
///
/// The providers are scoped by role (Super Admin and Admin see all inventory,
/// a User only their Admin's), so this snapshot can never contain a record the
/// account is not permitted to read. Nothing here re-implements stock maths:
/// every figure comes from AssetProvider / AssetModel / the movement records.
class InventorySnapshot {
  const InventorySnapshot({
    required this.assets,
    required this.bazaars,
    required this.deployments,
    required this.totalQuantity,
    required this.headOfficeStock,
    required this.assignedQuantity,
    required this.bazaarQuantity,
    required this.damagedQuantity,
    required this.underRepairQuantity,
    required this.lostQuantity,
    required this.disposedQuantity,
    required this.unavailableAtHeadOffice,
    required this.totalInventoryValue,
    required this.roleLabel,
    required this.scopeNote,
    this.bazaarDataLoaded = true,
    this.inventoryLoading = false,
    this.holders = const <String, String>{},
  });

  final List<AssetModel> assets;
  final List<BazaarModel> bazaars;
  final List<DeploymentModel> deployments;

  final int totalQuantity;
  final int headOfficeStock;
  final int assignedQuantity;
  final int bazaarQuantity;
  final int damagedQuantity;
  final int underRepairQuantity;
  final int lostQuantity;
  final int disposedQuantity;
  final int unavailableAtHeadOffice;
  final double totalInventoryValue;

  final String roleLabel;

  /// Explains what the figures cover for this account, e.g. inventory of the
  /// Admin a plain user belongs to.
  final String scopeNote;

  /// Whether the Bazaar master list and the movement records have actually
  /// been loaded. When false the assistant says so instead of reporting zero
  /// Bazaar stock, which would be a confident wrong answer.
  final bool bazaarDataLoaded;

  /// Whether the account's inventory stream is still delivering its first
  /// snapshot.
  ///
  /// An empty list means "this account owns nothing" only once this is false.
  /// Before that it means "not here yet", and saying "I cannot see any
  /// inventory" would be wrong - which is exactly what used to happen when the
  /// assistant was opened before the asset listener had answered.
  final bool inventoryLoading;

  /// Account id -> the person's display name, for the accounts this user is
  /// already allowed to see under Users.
  ///
  /// Held so "who has IT-LAP-001" and "what does Ali have" can be answered.
  /// Only the display name ever leaves the app: [toFacts] never emits an
  /// account id or an email address.
  final Map<String, String> holders;

  /// The display name of whoever holds [asset], or an empty string.
  String holderOf(AssetModel asset) {
    final uid = (asset.assignedTo ?? '').trim();
    if (uid.isEmpty) return '';
    return holders[uid]?.trim() ?? '';
  }

  int get totalAssets => assets.length;

  bool get isEmpty => assets.isEmpty;

  /// Units currently at each Bazaar, taken from the Active movement records
  /// (the same source the Bazaar screens use).
  Map<String, int> get quantityPerBazaar {
    final result = <String, int>{};

    for (final movement in deployments) {
      if (movement.status.trim().toLowerCase() != 'active') continue;

      final name = (movement.toBazaarName ?? movement.toLocation).trim();
      if (name.isEmpty) continue;

      result[name] = (result[name] ?? 0) + movement.quantity;
    }

    return result;
  }

  List<DeploymentModel> movementsForAsset(AssetModel asset) {
    return deployments
        .where((m) => m.assetDocumentId == asset.id || m.assetId == asset.assetId)
        .toList();
  }

  /// Sums one breakdown of the whole inventory, not of the sampled slice.
  ///
  /// [key] returns the bucket an asset belongs in, or an empty string to leave
  /// it out. Buckets are capped so a database full of one-off values cannot
  /// grow the payload without bound; the cap is reported so the model knows
  /// the breakdown is partial.
  Map<String, dynamic> _breakdown(
    String Function(AssetModel) key, {
    int maxBuckets = 30,
  }) {
    final records = <String, int>{};
    final quantity = <String, int>{};
    final value = <String, double>{};

    for (final asset in assets) {
      final bucket = key(asset).trim();
      if (bucket.isEmpty) continue;

      records[bucket] = (records[bucket] ?? 0) + 1;
      quantity[bucket] = (quantity[bucket] ?? 0) + asset.quantity;
      value[bucket] =
          (value[bucket] ?? 0) + asset.purchasePrice * asset.quantity;
    }

    final ordered = quantity.keys.toList()
      ..sort((a, b) => (quantity[b] ?? 0).compareTo(quantity[a] ?? 0));

    final result = <String, dynamic>{};

    for (final bucket in ordered.take(maxBuckets)) {
      result[bucket] = {
        'records': records[bucket],
        'quantity': quantity[bucket],
        'value': value[bucket],
      };
    }

    // Whatever did not fit is rolled into one bucket rather than dropped, so
    // the breakdown still adds up to the whole inventory. Silently returning
    // the top 30 would have the model confidently report a total that is short
    // by however many kinds of thing this account happens to own.
    if (ordered.length > maxBuckets) {
      var otherRecords = 0;
      var otherQuantity = 0;
      var otherValue = 0.0;

      for (final bucket in ordered.skip(maxBuckets)) {
        otherRecords += records[bucket] ?? 0;
        otherQuantity += quantity[bucket] ?? 0;
        otherValue += value[bucket] ?? 0;
      }

      result['(everything else)'] = {
        'records': otherRecords,
        'quantity': otherQuantity,
        'value': otherValue,
        'distinctValues': ordered.length - maxBuckets,
      };
    }

    return result;
  }

  /// The facts the language model is allowed to see: this snapshot, already
  /// filtered by the signed-in account's permissions, flattened and capped so
  /// one question never ships the whole database.
  ///
  /// [focus] is the asset the question is about, if one was recognised; it is
  /// always included even when the list is truncated.
  ///
  /// The breakdowns below are computed over EVERY asset this account can see,
  /// not over the sampled `assets` list. That is the point of them: the model
  /// is forbidden to count from the sample, so anything it might be asked to
  /// total has to arrive already totalled. [now] is injected so the date
  /// arithmetic is testable.
  Map<String, dynamic> toFacts({
    int maxAssets = 40,
    AssetModel? focus,
    DateTime? now,
  }) {
    final today = now ?? DateTime.now();

    final chosen = <AssetModel>[
      ?focus,
      ...assets.where((a) => a.id != focus?.id).take(maxAssets),
    ];

    Map<String, dynamic> assetFacts(AssetModel a) => {
      'assetId': a.assetId,
      'name': a.name,
      'category': a.category,
      'status': a.status,
      'condition': a.condition,
      'quantity': a.quantity,
      'headOffice': a.calculatedHeadOfficeQuantity,
      'atBazaars': a.calculatedDeployedQuantity,
      'assigned': a.calculatedAssignedQuantity,
      'unitPrice': a.purchasePrice,
      'totalValue': a.purchasePrice * a.quantity,
      if (a.brand.trim().isNotEmpty) 'brand': a.brand,
      if (a.model.trim().isNotEmpty) 'model': a.model,
      if (a.serialNumber.trim().isNotEmpty) 'serialNumber': a.serialNumber,
      if (a.location.trim().isNotEmpty) 'location': a.location,
      'isAssigned': (a.assignedTo ?? '').trim().isNotEmpty,
      if (a.warrantyMonths > 0) 'warrantyMonths': a.warrantyMonths,
      if (a.purchaseDate != null)
        'purchaseDate': a.purchaseDate!.toIso8601String().split('T').first,
    };
    // Note: the holder's account id is deliberately NOT sent outside the app,
    // and neither is anyone's email address. "Who has it" is answered from the
    // display name in `assignments` below, which is the least that can be sent
    // and still answer the question.

    final focusMovements = focus == null
        ? const <Map<String, dynamic>>[]
        : movementsForAsset(focus).take(10).map((m) => {
            'date': m.deploymentDate.toIso8601String().split('T').first,
            'quantity': m.quantity,
            'from': m.fromBazaarName ?? m.fromLocation,
            'to': m.toBazaarName ?? m.toLocation,
            'status': m.status,
          }).toList();

    // What is out at each Bazaar, asset by asset, from the same Active
    // movement records the Bazaar screens read. Without this the model knows
    // a Bazaar's total but cannot say what makes it up.
    final perBazaarAssets = <String, Map<String, int>>{};
    for (final movement in deployments) {
      if (movement.status.trim().toLowerCase() != 'active') continue;

      final bazaar = (movement.toBazaarName ?? movement.toLocation).trim();
      if (bazaar.isEmpty) continue;

      final tag = movement.assetId.trim().isEmpty
          ? movement.assetName.trim()
          : movement.assetId.trim();
      if (tag.isEmpty) continue;

      final bucket = perBazaarAssets.putIfAbsent(bazaar, () => <String, int>{});
      bucket[tag] = (bucket[tag] ?? 0) + movement.quantity;
    }

    final bazaarContents = <String, dynamic>{};
    for (final entry in perBazaarAssets.entries.take(15)) {
      bazaarContents[entry.key] = entry.value.entries
          .take(12)
          .map((e) => {'assetId': e.key, 'quantity': e.value})
          .toList();
    }

    // Who is holding what. Display names only: no account id and no email
    // address ever leaves the app.
    final assignments = <Map<String, dynamic>>[];
    var assignedRecords = 0;

    for (final asset in assets) {
      if (asset.calculatedAssignedQuantity <= 0) continue;

      assignedRecords++;
      if (assignments.length >= 25) continue;

      final holder = holderOf(asset);
      assignments.add({
        'assetId': asset.assetId,
        'name': asset.name,
        'quantity': asset.calculatedAssignedQuantity,
        if (holder.isNotEmpty) 'heldBy': holder,
      });
    }

    // Ranking needs the whole set, so it is done here rather than left to the
    // model, which only ever sees a sample.
    final byValue = assets.toList()
      ..sort((a, b) => (b.purchasePrice * b.quantity)
          .compareTo(a.purchasePrice * a.quantity));

    final mostValuable = byValue.take(10).map((a) => {
      'assetId': a.assetId,
      'name': a.name,
      'totalValue': a.purchasePrice * a.quantity,
      'quantity': a.quantity,
    }).toList();

    final noneAtHeadOffice =
        assets.where((a) => a.calculatedHeadOfficeQuantity <= 0).toList();
    final noneAtHeadOfficeTotal = noneAtHeadOffice.length;

    final outOfStockAtHeadOffice = noneAtHeadOffice
        .take(15)
        .map((a) => {'assetId': a.assetId, 'name': a.name})
        .toList();

    // Warranty, worked out against the same clock the rest of the answer uses.
    final warranties = <Map<String, dynamic>>[];
    var expired = 0;
    var expiringSoon = 0;

    for (final asset in assets) {
      final bought = asset.purchaseDate;
      if (bought == null || asset.warrantyMonths <= 0) continue;

      final months = bought.month + asset.warrantyMonths;
      final year = bought.year + (months - 1) ~/ 12;
      final month = (months - 1) % 12 + 1;

      // Day 0 of the next month is the last day of this one. Without this, a
      // warranty bought on the 31st would expire on the 1st of the month
      // after the one it actually runs to.
      final lastDay = DateTime(year, month + 1, 0).day;
      final ends = DateTime(year, month, bought.day < lastDay ? bought.day : lastDay);

      final days = ends.difference(today).inDays;
      if (days < 0) {
        expired++;
      } else if (days <= 90) {
        expiringSoon++;
      }

      warranties.add({
        'assetId': asset.assetId,
        'name': asset.name,
        'expires': ends.toIso8601String().split('T').first,
        'daysLeft': days,
      });
    }

    // Soonest first, because "which warranties are running out" is the
    // question people ask. Listing the first 15 in storage order would name
    // the wrong assets entirely.
    warranties.sort(
      (a, b) => (a['daysLeft'] as int).compareTo(b['daysLeft'] as int),
    );
    final warrantySoonest = warranties.take(15).toList();

    // Movement activity, so "how many transfers this week" has something to
    // stand on rather than a list of the most recent few.
    final movementsByStatus = <String, int>{};
    var last7Days = 0;
    var last30Days = 0;

    for (final movement in deployments) {
      final status = movement.status.trim();
      if (status.isNotEmpty) {
        movementsByStatus[status] = (movementsByStatus[status] ?? 0) + 1;
      }

      final age = today.difference(movement.deploymentDate).inDays;
      if (age < 0) continue;
      if (age <= 7) last7Days++;
      if (age <= 30) last30Days++;
    }

    final recent = deployments.toList()
      ..sort((a, b) => b.deploymentDate.compareTo(a.deploymentDate));

    final recentMovements = recent.take(15).map((m) => {
      'date': m.deploymentDate.toIso8601String().split('T').first,
      'assetId': m.assetId,
      'quantity': m.quantity,
      'from': m.fromBazaarName ?? m.fromLocation,
      'to': m.toBazaarName ?? m.toLocation,
      'status': m.status,
    }).toList();

    return {
      'today': today.toIso8601String().split('T').first,
      'scope': {
        'role': roleLabel,
        'note': scopeNote,
        'assetsVisible': totalAssets,
        'assetsIncludedHere': chosen.length,
      },
      'totals': {
        'assetRecords': totalAssets,
        'totalQuantity': totalQuantity,
        'headOfficeAvailable': headOfficeStock,
        'atBazaars': bazaarQuantity,
        'assigned': assignedQuantity,
        'damaged': damagedQuantity,
        'underRepair': underRepairQuantity,
        'lost': lostQuantity,
        'disposed': disposedQuantity,
        'unavailableAtHeadOffice': unavailableAtHeadOffice,
        'totalInventoryValue': totalInventoryValue,
        'currency': 'Rs.',
      },
      // Every breakdown below covers ALL assetsVisible, not the sample.
      'byCategory': _breakdown((a) => a.category),
      'byStatus': _breakdown((a) => a.status),
      'byCondition': _breakdown((a) => a.condition),
      'byBrand': _breakdown((a) => a.brand),
      'byLocation': _breakdown((a) => a.location),
      'bazaarStock': quantityPerBazaar,
      if (bazaarDataLoaded)
        'bazaarDirectory': bazaars.take(60).map((b) => {
          'name': b.name,
          if (b.location.trim().isNotEmpty) 'location': b.location,
          'isActive': b.isActive,
        }).toList(),
      if (bazaarContents.isNotEmpty) 'bazaarContents': bazaarContents,
      if (assignments.isNotEmpty)
        'assignments': {
          'assetRecordsAssigned': assignedRecords,
          'listed': assignments.length,
          'items': assignments,
        },
      if (mostValuable.isNotEmpty) 'mostValuable': mostValuable,
      if (outOfStockAtHeadOffice.isNotEmpty)
        'noneAtHeadOffice': {
          'assetRecords': noneAtHeadOfficeTotal,
          'listed': outOfStockAtHeadOffice.length,
          'items': outOfStockAtHeadOffice,
        },
      if (warranties.isNotEmpty)
        'warranty': {
          'assetRecordsWithWarranty': warranties.length,
          'expired': expired,
          'expiringWithin90Days': expiringSoon,
          'soonestToExpire': warrantySoonest,
        },
      if (movementsByStatus.isNotEmpty)
        'movements': {
          'total': deployments.length,
          'byStatus': movementsByStatus,
          'inLast7Days': last7Days,
          'inLast30Days': last30Days,
          'recent': recentMovements,
        },
      // The model is told these two describe different things, because they
      // do and it would otherwise be asked to reconcile them.
      'fieldNotes': {
        'totals':
            'Unit counts for the whole inventory. damaged, underRepair, lost '
            'and disposed count only units sitting at Head Office.',
        'byStatus':
            'Asset records and their FULL quantity wherever it is, grouped by '
            'the status field. Deliberately not the same measure as '
            'totals.damaged and its neighbours, so do not compare the two.',
        'lists':
            'Every "items" list is capped. Where a list has a count beside it, '
            'that count is the real number; the list is only a sample of it.',
      },
      'assets': chosen.map(assetFacts).toList(),
      if (focus != null) 'focusAsset': focus.assetId,
      if (focusMovements.isNotEmpty) 'focusAssetMovements': focusMovements,
    };
  }
}

/// What the assistant replied, plus what it was talking about so a follow-up
/// question such as "aur head office mein kitne hain?" can be understood.
class AssistantReply {
  const AssistantReply(this.text, {this.asset, this.bazaar, this.understood = true});

  final String text;
  final AssetModel? asset;
  final String? bazaar;

  /// False when the deterministic engine did not recognise the question and
  /// [text] is its "ask me another way" message rather than an answer.
  ///
  /// The language model is given the computed answer as authoritative, so a
  /// message that answers nothing must not be handed over wearing that badge.
  final bool understood;
}

/// Turns a question in English or Roman Urdu into an answer built only from
/// [InventorySnapshot]. It never invents a figure: anything it cannot ground in
/// the snapshot is answered with a plain "I don't have that".
class InventoryAssistant {
  InventoryAssistant();

  AssetModel? _lastAsset;
  String? _lastBazaar;

  /// The asset the conversation is currently about, so a follow-up command
  /// such as "aur 5 wapas bhejo" stays on the same asset.
  AssetModel? get lastAsset => _lastAsset;

  /// The Bazaar the conversation is currently about.
  String? get lastBazaar => _lastBazaar;

  void reset() {
    _lastAsset = null;
    _lastBazaar = null;
  }

  static const _money = 'Rs.';

  // ---------------------------------------------------------------- helpers

  String _n(num value) {
    final digits = value.round().abs().toString();
    final buffer = StringBuffer();

    for (var i = 0; i < digits.length; i++) {
      if (i > 0 && (digits.length - i) % 3 == 0) buffer.write(',');
      buffer.write(digits[i]);
    }

    return (value < 0 ? '-' : '') + buffer.toString();
  }

  String _units(int value) => value == 1 ? '1 unit' : '${_n(value)} units';

  bool _has(String q, List<String> words) => words.any(q.contains);

  // ---------------------------------------------------------------- answer

  AssistantReply answer(String question, InventorySnapshot data) {
    final q = question.toLowerCase().trim();

    if (q.isEmpty) {
      return const AssistantReply('Ask me anything about the inventory.');
    }

    if (_has(q, ['help', 'what can you', 'kya kar sakt', 'madad'])) {
      return AssistantReply(_help(data));
    }

    if (data.isEmpty) {
      // "Still arriving" and "there is none" are different answers, and only
      // the second one is about permissions.
      if (data.inventoryLoading) {
        return const AssistantReply(
          'Your inventory is still loading. Give it a moment and ask me again.',
        );
      }

      return const AssistantReply(
        'I cannot see any inventory for your account yet, so I have nothing to '
        'report. If you expect to see assets here, ask an administrator to check '
        'which inventory your account is linked to.',
      );
    }

    // A named asset wins over everything else: "IT-LAP-001 ki warranty?"
    final asset = _findAsset(q, data) ?? _followUpAsset(q);
    final bazaar = _findBazaar(q, data) ?? _followUpBazaar(q);

    if (asset != null) {
      final reply = _answerAboutAsset(q, asset, data);
      _lastAsset = asset;
      return reply;
    }

    if (bazaar != null) {
      final reply = _answerAboutBazaar(q, bazaar, data);
      _lastBazaar = bazaar;
      return reply;
    }

    return _answerAboutTotals(q, data);
  }

  // ------------------------------------------------------------- resolution

  /// Resolves the asset a phrase refers to, by Asset ID, serial or name.
  /// Public so the action planner resolves targets exactly the same way the
  /// read-only answers do, rather than matching names a second time.
  AssetModel? findAsset(String q, InventorySnapshot data) => _findAsset(q, data);

  /// Resolves the Bazaar a phrase refers to, from the loaded Bazaar list.
  String? findBazaar(String q, InventorySnapshot data) => _findBazaar(q, data);

  AssetModel? _findAsset(String q, InventorySnapshot data) {
    AssetModel? best;
    var bestScore = 0;

    for (final asset in data.assets) {
      final tag = asset.assetId.trim().toLowerCase();
      final name = asset.name.trim().toLowerCase();
      final serial = asset.serialNumber.trim().toLowerCase();

      var score = 0;
      if (tag.isNotEmpty && q.contains(tag)) {
        score = tag.length + 20;
      } else if (serial.isNotEmpty && q.contains(serial)) {
        score = serial.length + 15;
      } else if (name.isNotEmpty && name.length > 3 && q.contains(name)) {
        score = name.length;
      }

      if (score > bestScore) {
        bestScore = score;
        best = asset;
      }
    }

    return best;
  }

  String? _findBazaar(String q, InventorySnapshot data) {
    String? best;
    var bestLength = 0;

    for (final bazaar in data.bazaars) {
      final name = bazaar.name.trim().toLowerCase();
      if (name.isEmpty || name.length <= 2) continue;

      final short = name.replaceAll(' bazaar', '').trim();

      if (q.contains(name) && name.length > bestLength) {
        best = bazaar.name.trim();
        bestLength = name.length;
      } else if (short.length > 3 && q.contains(short) && short.length > bestLength) {
        best = bazaar.name.trim();
        bestLength = short.length;
      }
    }

    return best;
  }

  /// "aur is ka head office stock?" - keep talking about the last asset.
  AssetModel? _followUpAsset(String q) {
    if (_lastAsset == null) return null;
    if (!_has(q, ['aur ', 'and ', 'is ka', 'iska', 'uska', 'us ka', 'its ', 'it '])) {
      return null;
    }
    return _lastAsset;
  }

  String? _followUpBazaar(String q) {
    if (_lastBazaar == null) return null;
    if (!_has(q, ['aur ', 'and ', 'wahan', 'there', 'is mein', 'ismein'])) return null;
    return _lastBazaar;
  }

  // ------------------------------------------------------------ asset facts

  AssistantReply _answerAboutAsset(String q, AssetModel a, InventorySnapshot data) {
    final label = '${a.assetId.isEmpty ? a.name : a.assetId} (${a.name})';

    if (_has(q, ['warranty', 'guarantee', 'zamanat'])) {
      return AssistantReply(_warranty(a, label), asset: a);
    }

    if (_has(q, ['history', 'transfer', 'movement', 'deployment', 'kahan kahan', 'bheja'])) {
      return AssistantReply(_movements(a, label, data), asset: a);
    }

    if (_has(q, ['price', 'value', 'cost', 'qeemat', 'keemat', 'rate'])) {
      final total = a.purchasePrice * a.quantity;
      return AssistantReply(
        '$label\n'
        'Unit purchase price: $_money${_n(a.purchasePrice)}\n'
        'Quantity: ${_units(a.quantity)}\n'
        'Total value: $_money${_n(total)} (${_n(a.quantity)} x $_money${_n(a.purchasePrice)})',
        asset: a,
      );
    }

    if (_has(q, ['head office', 'ho ', 'headoffice', 'office mein', 'office main'])) {
      return AssistantReply(
        '$label has ${_units(a.calculatedHeadOfficeQuantity)} at Head Office, '
        'out of ${_units(a.quantity)} in total.',
        asset: a,
      );
    }

    if (_has(q, ['kis ke paas', 'who has', 'assigned to', 'kis ko', 'holder'])) {
      final holder = (a.assignedTo ?? '').trim();
      return AssistantReply(
        holder.isEmpty
            ? '$label is not assigned to anyone right now. '
              '${_units(a.calculatedAssignedQuantity)} are recorded as assigned.'
            : '$label is assigned to $holder (${_units(a.calculatedAssignedQuantity)}).',
        asset: a,
      );
    }

    if (_has(q, ['kahan', 'kaha ', 'where', 'location', 'bazaar mein', 'which bazaar'])) {
      return AssistantReply(_whereIs(a, label, data), asset: a);
    }

    if (_has(q, ['condition', 'halat', 'status'])) {
      return AssistantReply(
        '$label\nStatus: ${a.status}\nCondition: ${a.condition}\n'
        'Location: ${a.location.isEmpty ? 'Head Office' : a.location}',
        asset: a,
      );
    }

    if (_has(q, ['kitne', 'kitna', 'quantity', 'how many', 'stock'])) {
      return AssistantReply(_distribution(a, label, data), asset: a);
    }

    return AssistantReply(_assetDetails(a, label, data), asset: a);
  }

  String _assetDetails(AssetModel a, String label, InventorySnapshot data) {
    final parts = <String>[
      label,
      'Category: ${a.category}',
      'Status: ${a.status}   Condition: ${a.condition}',
      if (a.brand.trim().isNotEmpty || a.model.trim().isNotEmpty)
        'Brand / model: ${[a.brand, a.model].where((v) => v.trim().isNotEmpty).join(' ')}',
      if (a.serialNumber.trim().isNotEmpty) 'Serial number: ${a.serialNumber}',
      'Quantity: ${_units(a.quantity)}',
      _distributionLine(a),
      'Unit price: $_money${_n(a.purchasePrice)}   Total value: $_money${_n(a.purchasePrice * a.quantity)}',
      if (a.warrantyMonths > 0) _warrantyLine(a),
      'Location: ${a.location.isEmpty ? 'Head Office' : a.location}',
      if ((a.assignedTo ?? '').trim().isNotEmpty) 'Assigned to: ${a.assignedTo}',
    ];

    return parts.join('\n');
  }

  String _distributionLine(AssetModel a) =>
      'Head Office ${_n(a.calculatedHeadOfficeQuantity)} · '
      'At Bazaars ${_n(a.calculatedDeployedQuantity)} · '
      'Assigned ${_n(a.calculatedAssignedQuantity)}';

  String _distribution(AssetModel a, String label, InventorySnapshot data) {
    final buffer = StringBuffer('$label has ${_units(a.quantity)} in total.\n')
      ..writeln(_distributionLine(a));

    final atBazaars = <String, int>{};
    for (final m in data.movementsForAsset(a)) {
      if (m.status.trim().toLowerCase() != 'active') continue;
      final name = (m.toBazaarName ?? m.toLocation).trim();
      if (name.isEmpty) continue;
      atBazaars[name] = (atBazaars[name] ?? 0) + m.quantity;
    }

    if (atBazaars.isNotEmpty) {
      buffer.writeln('\nAt Bazaars:');
      for (final entry in atBazaars.entries) {
        buffer.writeln('  ${entry.key}: ${_units(entry.value)}');
      }
    }

    return buffer.toString().trimRight();
  }

  String _whereIs(AssetModel a, String label, InventorySnapshot data) {
    final lines = <String>['$label is recorded as:'];

    if (a.calculatedHeadOfficeQuantity > 0) {
      lines.add('  Head Office: ${_units(a.calculatedHeadOfficeQuantity)}');
    }

    for (final m in data.movementsForAsset(a)) {
      if (m.status.trim().toLowerCase() != 'active') continue;
      final name = (m.toBazaarName ?? m.toLocation).trim();
      if (name.isEmpty) continue;
      lines.add('  $name: ${_units(m.quantity)}');
    }

    if (a.calculatedAssignedQuantity > 0) {
      final holder = (a.assignedTo ?? '').trim();
      lines.add(
        '  Assigned${holder.isEmpty ? '' : ' to $holder'}: '
        '${_units(a.calculatedAssignedQuantity)}',
      );
    }

    if (lines.length == 1) lines.add('  Head Office: ${_units(a.quantity)}');

    return lines.join('\n');
  }

  String _warrantyLine(AssetModel a) {
    if (a.warrantyMonths <= 0) return 'Warranty: not recorded';
    if (a.purchaseDate == null) {
      return 'Warranty: ${a.warrantyMonths} months from purchase '
          '(purchase date not recorded)';
    }

    final purchase = a.purchaseDate!;
    final expiry = DateTime(
      purchase.year,
      purchase.month + a.warrantyMonths,
      purchase.day,
    );
    final left = expiry.difference(DateTime.now()).inDays;

    if (left < 0) {
      return 'Warranty: expired ${-left} day(s) ago '
          '(${expiry.day}/${expiry.month}/${expiry.year})';
    }

    return 'Warranty: $left day(s) left '
        '(expires ${expiry.day}/${expiry.month}/${expiry.year})';
  }

  String _warranty(AssetModel a, String label) => '$label\n${_warrantyLine(a)}';

  String _movements(AssetModel a, String label, InventorySnapshot data) {
    final movements = data.movementsForAsset(a)
      ..sort((x, y) => y.deploymentDate.compareTo(x.deploymentDate));

    if (movements.isEmpty) {
      return '$label has no transfer records. All ${_units(a.quantity)} are '
          'accounted for at Head Office or assigned.';
    }

    final buffer = StringBuffer('$label - last ${movements.length > 8 ? 8 : movements.length} movement(s):\n');

    for (final m in movements.take(8)) {
      final date = '${m.deploymentDate.day}/${m.deploymentDate.month}/${m.deploymentDate.year}';
      final from = m.fromBazaarName ?? m.fromLocation;
      final to = m.toBazaarName ?? m.toLocation;
      buffer.writeln('  $date  ${_units(m.quantity)}  $from -> $to  (${m.status})');
    }

    return buffer.toString().trimRight();
  }

  // ----------------------------------------------------------- bazaar facts

  AssistantReply _answerAboutBazaar(String q, String bazaar, InventorySnapshot data) {
    final key = bazaar.toLowerCase();

    final movements = data.deployments.where((m) {
      if (m.status.trim().toLowerCase() != 'active') return false;
      final name = (m.toBazaarName ?? m.toLocation).trim().toLowerCase();
      return name == key;
    }).toList();

    final total = movements.fold<int>(0, (sum, m) => sum + m.quantity);

    if (movements.isEmpty) {
      return AssistantReply(
        'There is no stock recorded at $bazaar right now.',
        bazaar: bazaar,
      );
    }

    final perAsset = <String, int>{};
    for (final m in movements) {
      final label = m.assetId.trim().isEmpty ? m.assetName : '${m.assetId} (${m.assetName})';
      perAsset[label] = (perAsset[label] ?? 0) + m.quantity;
    }

    final buffer = StringBuffer('$bazaar holds ${_units(total)} across ${perAsset.length} asset(s):\n');
    for (final entry in perAsset.entries) {
      buffer.writeln('  ${entry.key}: ${_units(entry.value)}');
    }

    return AssistantReply(buffer.toString().trimRight(), bazaar: bazaar);
  }

  // ------------------------------------------------------------ totals

  AssistantReply _answerAboutTotals(String q, InventorySnapshot data) {
    if (_has(q, ['value', 'worth', 'qeemat', 'keemat', 'price', 'total cost'])) {
      return AssistantReply(
        'Total inventory value: $_money${_n(data.totalInventoryValue)}\n'
        'That is every asset\'s quantity multiplied by its unit purchase price, '
        'across ${_n(data.totalAssets)} asset record(s) and ${_units(data.totalQuantity)}.',
      );
    }

    if (_has(q, ['head office', 'headoffice', 'ho stock', 'office mein', 'office main'])) {
      return AssistantReply(
        'Head Office has ${_units(data.headOfficeStock)} available.\n'
        'Unusable units still at Head Office (damaged, repair, lost, disposed): '
        '${_units(data.unavailableAtHeadOffice)}.',
      );
    }

    if (_has(q, ['bazaar', 'bazar', 'bazaron', 'bazaars'])) {
      if (!data.bazaarDataLoaded) {
        return const AssistantReply(
          'I do not have the Bazaar records loaded yet, so I will not guess. '
          'Open the Bazaars or Transfers screen once and ask me again.',
        );
      }

      final perBazaar = data.quantityPerBazaar;

      if (perBazaar.isEmpty) {
        return AssistantReply(
          'No stock is at any Bazaar right now. All ${_units(data.totalQuantity)} '
          'are at Head Office or assigned.',
        );
      }

      final buffer = StringBuffer('${_units(data.bazaarQuantity)} are at Bazaars:\n');
      final sorted = perBazaar.entries.toList()
        ..sort((a, b) => b.value.compareTo(a.value));
      for (final entry in sorted) {
        buffer.writeln('  ${entry.key}: ${_units(entry.value)}');
      }

      return AssistantReply(buffer.toString().trimRight());
    }

    if (_has(q, ['assign', 'issued', 'kis ke paas', 'diye'])) {
      return AssistantReply('${_units(data.assignedQuantity)} are assigned to people.');
    }

    if (_has(q, ['damage', 'kharab', 'toota', 'broken'])) {
      return AssistantReply(
        '${_units(data.damagedQuantity)} are damaged (counted at Head Office).',
      );
    }

    if (_has(q, ['repair', 'maintenance', 'marammat', 'theek'])) {
      return AssistantReply(
        '${_units(data.underRepairQuantity)} are under repair or maintenance '
        '(counted at Head Office).',
      );
    }

    if (_has(q, ['lost', 'missing', 'gum', 'khoya'])) {
      return AssistantReply('${_units(data.lostQuantity)} are recorded as lost or missing.');
    }

    if (_has(q, ['disposed', 'retired', 'scrap', 'zaya'])) {
      return AssistantReply('${_units(data.disposedQuantity)} are disposed or retired.');
    }

    if (_has(q, ['available', 'maujood', 'usable', 'free stock'])) {
      return AssistantReply(
        '${_units(data.headOfficeStock)} are available at Head Office.',
      );
    }

    if (_has(q, ['how many asset', 'kitne asset', 'records', 'asset count'])) {
      return AssistantReply(
        'There are ${_n(data.totalAssets)} asset record(s), holding '
        '${_units(data.totalQuantity)} in total.',
      );
    }

    if (_has(q, ['total', 'kul', 'sab', 'overall', 'inventory', 'stock', 'kitna', 'kitne'])) {
      return AssistantReply(_overview(data));
    }

    return AssistantReply(
      understood: false,
      'I did not catch which figure you need. Try for example:\n'
      '  "total stock"  ·  "head office mein kitne hain"\n'
      '  "Township Bazaar mein kitna stock hai"\n'
      '  "IT-LAP-001 ki warranty"  ·  "inventory value"\n\n'
      'I only answer from the inventory you are allowed to see, and I never '
      'guess a number.',
    );
  }

  String _overview(InventorySnapshot d) {
    return 'Inventory overview (${d.roleLabel})\n'
        '  Asset records: ${_n(d.totalAssets)}\n'
        '  Total quantity: ${_units(d.totalQuantity)}\n'
        '  Head Office (available): ${_units(d.headOfficeStock)}\n'
        '  At Bazaars: ${_units(d.bazaarQuantity)}\n'
        '  Assigned: ${_units(d.assignedQuantity)}\n'
        '  Damaged: ${_units(d.damagedQuantity)}   Under repair: ${_units(d.underRepairQuantity)}\n'
        '  Total value: $_money${_n(d.totalInventoryValue)}'
        '${d.scopeNote.isEmpty ? '' : '\n\n${d.scopeNote}'}';
  }

  String _help(InventorySnapshot d) {
    return 'I answer from this app\'s live inventory - English or Roman Urdu.\n\n'
        'Try:\n'
        '  total stock  ·  kul kitna stock hai\n'
        '  head office mein kitne hain\n'
        '  bazaar stock  ·  Township Bazaar mein kitna hai\n'
        '  damaged  ·  under repair  ·  lost  ·  assigned\n'
        '  inventory value  ·  total value\n'
        '  IT-LAP-001  (any Asset ID, name or serial) for full details\n'
        '  IT-LAP-001 ki warranty  ·  iski history  ·  ye kahan hai\n\n'
        'I only see the inventory your account is allowed to see, and I never '
        'invent a figure.';
  }
}
