import 'package:flutter_test/flutter_test.dart';

import 'package:it_management_system/core/ai/inventory_assistant.dart';
import 'package:it_management_system/core/services/bazaar_service.dart';
import 'package:it_management_system/models/asset_model.dart';
import 'package:it_management_system/models/deployment_model.dart';

/// The assistant answers only from the snapshot it is given. These tests build
/// a snapshot the way the app does - real models, real figures - and check that
/// every answer is grounded in it.
void main() {
  AssetModel asset({
    required String id,
    required String tag,
    required String name,
    required int quantity,
    double price = 0,
    int headOffice = 0,
    int assigned = 0,
    int deployed = 0,
    String status = 'Available',
    String condition = 'Good',
    String category = 'Laptop',
    String brand = '',
    String model = '',
    String serial = '',
    String? assignedTo,
    int warrantyMonths = 0,
    DateTime? purchaseDate,
  }) {
    return AssetModel(
      id: id,
      assetId: tag,
      name: name,
      category: category,
      status: status,
      condition: condition,
      quantity: quantity,
      purchasePrice: price,
      headOfficeQuantity: headOffice,
      assignedQuantity: assigned,
      deployedQuantity: deployed,
      brand: brand,
      model: model,
      serialNumber: serial,
      assignedTo: assignedTo,
      warrantyMonths: warrantyMonths,
      purchaseDate: purchaseDate,
    );
  }

  DeploymentModel movement({
    required String assetDocId,
    required String tag,
    required String assetName,
    required String toBazaar,
    required int quantity,
    String status = 'Active',
    DateTime? date,
  }) {
    return DeploymentModel(
      id: '$tag-$toBazaar-$quantity-$status',
      assetDocumentId: assetDocId,
      assetId: tag,
      assetName: assetName,
      action: 'Transfer',
      fromLocation: 'Head Office',
      toLocation: toBazaar,
      toBazaarId: toBazaar.toLowerCase().replaceAll(' ', '-'),
      toBazaarName: toBazaar,
      quantity: quantity,
      sentBy: 'admin-1',
      deploymentDate: date ?? DateTime(2026, 3, 2),
      status: status,
      createdAt: date ?? DateTime(2026, 3, 2),
    );
  }

  // Laptop: 100 units, 40 at Head Office, 30 + 20 at two Bazaars, 10 assigned.
  final laptop = asset(
    id: 'a1',
    tag: 'IT-LAP-001',
    name: 'Dell Latitude 5440',
    quantity: 100,
    price: 10000,
    headOffice: 40,
    assigned: 10,
    deployed: 50,
    brand: 'Dell',
    model: 'Latitude 5440',
    serial: 'SN-LAP-001',
    assignedTo: 'Usman Rafiq',
    warrantyMonths: 24,
    purchaseDate: DateTime(2026, 1, 15),
  );

  final monitor = asset(
    id: 'a2',
    tag: 'IT-MON-002',
    name: 'HP Monitor E24',
    quantity: 20,
    price: 20000,
    headOffice: 20,
  );

  final damaged = asset(
    id: 'a3',
    tag: 'IT-PRN-003',
    name: 'Canon Printer',
    quantity: 5,
    price: 5000,
    headOffice: 5,
    status: 'Damaged',
    condition: 'Poor',
  );

  final movements = [
    movement(assetDocId: 'a1', tag: 'IT-LAP-001', assetName: 'Dell Latitude 5440', toBazaar: 'Township Bazaar', quantity: 30),
    movement(assetDocId: 'a1', tag: 'IT-LAP-001', assetName: 'Dell Latitude 5440', toBazaar: 'Sahiwal Bazaar', quantity: 20),
    movement(assetDocId: 'a1', tag: 'IT-LAP-001', assetName: 'Dell Latitude 5440', toBazaar: 'Township Bazaar', quantity: 15, status: 'Returned', date: DateTime(2026, 2, 1)),
  ];

  // Figures match what AssetProvider would report for these three assets.
  InventorySnapshot snapshot({List<AssetModel>? assets, List<DeploymentModel>? deployments}) {
    final list = assets ?? [laptop, monitor, damaged];
    final moves = deployments ?? movements;

    final totalQuantity = list.fold<int>(0, (s, a) => s + a.quantity);
    final value = list.fold<double>(0, (s, a) => s + a.quantity * a.purchasePrice);

    return InventorySnapshot(
      assets: list,
      bazaars: const [
        BazaarModel(id: 'b1', name: 'Township Bazaar', location: 'Lahore'),
        BazaarModel(id: 'b2', name: 'Sahiwal Bazaar', location: 'Sahiwal'),
      ],
      deployments: moves,
      totalQuantity: totalQuantity,
      headOfficeStock: 60,
      assignedQuantity: 10,
      bazaarQuantity: 50,
      damagedQuantity: 5,
      underRepairQuantity: 0,
      lostQuantity: 0,
      disposedQuantity: 0,
      unavailableAtHeadOffice: 5,
      totalInventoryValue: value,
      roleLabel: 'Super Admin',
      scopeNote: '',
    );
  }

  group('totals, in English and Roman Urdu', () {
    test('total stock reports records, quantity and value', () {
      final reply = InventoryAssistant().answer('total stock', snapshot());

      expect(reply.text, contains('125 units'));
      expect(reply.text, contains('3'));
      expect(reply.text, contains('1,425,000')); // 100x10,000 + 20x20,000 + 5x5,000
    });

    test('kul kitna stock hai is understood', () {
      final reply = InventoryAssistant().answer('kul kitna stock hai', snapshot());
      expect(reply.text, contains('125 units'));
    });

    test('head office mein kitne hain', () {
      final reply = InventoryAssistant().answer('head office mein kitne hain', snapshot());
      expect(reply.text, contains('60 units'));
    });

    test('inventory value multiplies quantity by unit price', () {
      final reply = InventoryAssistant().answer('total inventory value', snapshot());
      expect(reply.text, contains('Rs.1,425,000'));
    });

    test('damaged, repair, lost and assigned each report their own figure', () {
      final a = InventoryAssistant();
      expect(a.answer('damaged', snapshot()).text, contains('5 units'));
      expect(a.answer('kitne repair mein hain', snapshot()).text, contains('0 units'));
      expect(a.answer('lost', snapshot()).text, contains('0 units'));
      expect(a.answer('assigned', snapshot()).text, contains('10 units'));
    });
  });

  group('bazaars', () {
    test('bazaar stock lists every Bazaar holding stock', () {
      final reply = InventoryAssistant().answer('bazaar stock', snapshot());

      expect(reply.text, contains('Township Bazaar: 30 units'));
      expect(reply.text, contains('Sahiwal Bazaar: 20 units'));
      expect(reply.text, isNot(contains('15 units')), reason: 'returned movements are not current stock');
    });

    test('a single Bazaar is answered with its assets', () {
      final reply = InventoryAssistant().answer(
        'Township Bazaar mein kitna stock hai',
        snapshot(),
      );

      expect(reply.bazaar, 'Township Bazaar');
      expect(reply.text, contains('30 units'));
      expect(reply.text, contains('IT-LAP-001'));
    });

    test('a Bazaar with no stock says so instead of guessing', () {
      final reply = InventoryAssistant().answer(
        'Sahiwal Bazaar mein kitna hai',
        snapshot(deployments: const []),
      );

      expect(reply.text, contains('no stock recorded'));
    });
  });

  group('a single asset', () {
    test('an Asset ID returns its real details', () {
      final reply = InventoryAssistant().answer('IT-LAP-001', snapshot());

      expect(reply.asset?.id, 'a1');
      expect(reply.text, contains('Dell'));
      expect(reply.text, contains('SN-LAP-001'));
      expect(reply.text, contains('100 units'));
      expect(reply.text, contains('Head Office 40'));
      expect(reply.text, contains('Rs.10,000'));
    });

    test('price question multiplies by quantity', () {
      final reply = InventoryAssistant().answer('IT-LAP-001 ki qeemat', snapshot());
      expect(reply.text, contains('Rs.1,000,000'));
    });

    test('warranty is calculated from purchase date and months', () {
      final reply = InventoryAssistant().answer('IT-LAP-001 ki warranty', snapshot());
      expect(reply.text, contains('15/1/2028'));
    });

    test('where-is lists Head Office, each Bazaar and the assignment', () {
      final reply = InventoryAssistant().answer('IT-LAP-001 kahan hai', snapshot());

      expect(reply.text, contains('Head Office: 40 units'));
      expect(reply.text, contains('Township Bazaar: 30 units'));
      expect(reply.text, contains('Sahiwal Bazaar: 20 units'));
      expect(reply.text, contains('Usman Rafiq'));
    });

    test('history shows movements including returned ones', () {
      final reply = InventoryAssistant().answer('IT-LAP-001 transfer history', snapshot());

      expect(reply.text, contains('Township Bazaar'));
      expect(reply.text, contains('Returned'));
    });

    test('status and condition are reported as stored', () {
      final reply = InventoryAssistant().answer('IT-PRN-003 condition', snapshot());

      expect(reply.text, contains('Damaged'));
      expect(reply.text, contains('Poor'));
    });

    test('a follow-up keeps talking about the same asset', () {
      final assistant = InventoryAssistant();
      assistant.answer('IT-LAP-001', snapshot());

      final followUp = assistant.answer('aur head office mein kitne hain?', snapshot());

      expect(followUp.asset?.id, 'a1');
      expect(followUp.text, contains('40 units'));
      expect(followUp.text, contains('100 units'));
    });
  });

  group('never invents data', () {
    test('an asset outside the snapshot is not answered', () {
      final reply = InventoryAssistant().answer('IT-SRV-999 details', snapshot());

      expect(reply.asset, isNull);
      expect(reply.text, isNot(contains('IT-SRV-999')));
    });

    test('an empty snapshot reports nothing visible rather than zero facts', () {
      final reply = InventoryAssistant().answer(
        'total stock',
        snapshot(assets: const [], deployments: const []),
      );

      expect(reply.text, contains('cannot see any inventory'));
    });

    test('refuses to report Bazaar stock before the records are loaded', () {
      final notLoaded = InventorySnapshot(
        assets: [laptop],
        bazaars: const [],
        deployments: const [],
        totalQuantity: 100,
        headOfficeStock: 40,
        assignedQuantity: 10,
        bazaarQuantity: 50,
        damagedQuantity: 0,
        underRepairQuantity: 0,
        lostQuantity: 0,
        disposedQuantity: 0,
        unavailableAtHeadOffice: 0,
        totalInventoryValue: 1000000,
        roleLabel: 'Admin',
        scopeNote: '',
        bazaarDataLoaded: false,
      );

      final reply = InventoryAssistant().answer('bazaar stock', notLoaded);

      expect(reply.text, contains('do not have the Bazaar records loaded'));
      expect(reply.text, isNot(contains('No stock is at any Bazaar')));
    });

    test('an unclear question asks for a rephrase instead of answering', () {
      final reply = InventoryAssistant().answer('blah blah zzz', snapshot());
      expect(reply.text, contains('did not catch'));
    });

    test('one assistant answers a run of questions without repeating itself', () {
      // Guards the "every question gives me the same answer" report: one
      // instance, asked in sequence, so any carried-over state - the last
      // asset, the last Bazaar, a cached snapshot - would show up as two
      // identical answers.
      final assistant = InventoryAssistant();
      // Each asks something genuinely different: synonyms such as "total
      // stock" and "kul kitna stock hai" are meant to land on one answer.
      const questions = [
        'bazaar stock',
        'total stock',
        'total inventory value',
        'head office mein kitne hain',
        'IT-LAP-001 ki qeemat',
        'damaged',
        'IT-LAP-001 ki warranty',
      ];

      final answers = [
        for (final question in questions)
          assistant.answer(question, snapshot()).text,
      ];

      expect(answers.toSet(), hasLength(questions.length));
      expect(answers.first, contains('are at Bazaars'));
      expect(
        answers.skip(1).where((a) => a.contains('are at Bazaars')),
        isEmpty,
        reason: 'only the Bazaar question may produce the Bazaar breakdown',
      );
    });
  });

  group('facts sent to the language model', () {
    test('carry the real totals, bazaar stock and currency', () {
      final facts = snapshot().toFacts();

      expect(facts['totals']['totalQuantity'], 125);
      expect(facts['totals']['headOfficeAvailable'], 60);
      expect(facts['totals']['totalInventoryValue'], 1425000);
      expect(facts['totals']['currency'], 'Rs.');
      expect(facts['bazaarStock']['Township Bazaar'], 30);
      expect(facts['bazaarStock']['Sahiwal Bazaar'], 20);
    });

    test('contain only assets from the permission-filtered snapshot', () {
      final facts = snapshot(assets: [monitor]).toFacts();
      final tags = (facts['assets'] as List).map((a) => a['assetId']).toList();

      expect(tags, ['IT-MON-002']);
      expect(tags, isNot(contains('IT-LAP-001')));
    });

    test('are capped so one question never ships the whole database', () {
      final many = List.generate(
        200,
        (i) => asset(id: 'x$i', tag: 'BULK-$i', name: 'Bulk $i', quantity: 1),
      );

      final facts = snapshot(assets: many, deployments: const []).toFacts(maxAssets: 40);

      expect((facts['assets'] as List).length, 40);
      expect(facts['scope']['assetsVisible'], 200);
      expect(facts['scope']['assetsIncludedHere'], 40);
    });

    test('always include the asset a question is about, plus its movements', () {
      final many = List.generate(
        200,
        (i) => asset(id: 'x$i', tag: 'BULK-$i', name: 'Bulk $i', quantity: 1),
      );

      final facts = snapshot(assets: [...many, laptop]).toFacts(maxAssets: 40, focus: laptop);
      final tags = (facts['assets'] as List).map((a) => a['assetId']).toList();

      expect(tags.first, 'IT-LAP-001');
      expect(facts['focusAsset'], 'IT-LAP-001');
      expect((facts['focusAssetMovements'] as List).length, 3);
    });

    test('never include a password, token, key or internal document id', () {
      final encoded = factsAsText(snapshot().toFacts(focus: laptop));

      for (final banned in ['password', 'token', 'apiKey', 'api_key', 'secret', 'uid']) {
        expect(encoded.toLowerCase(), isNot(contains(banned.toLowerCase())), reason: banned);
      }
      // Account ids and Firestore document ids stay on the device.
      expect(encoded, isNot(contains('Usman Rafiq')));
      expect(encoded, isNot(contains('"a1"')));
    });
  });
}

String factsAsText(Map<String, dynamic> facts) => facts.toString();
