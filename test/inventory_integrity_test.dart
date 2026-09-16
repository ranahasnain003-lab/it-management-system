import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:it_management_system/core/providers/asset_provider.dart';
import 'package:it_management_system/core/services/asset_service.dart';
import 'package:it_management_system/core/services/deployment_service.dart';
import 'package:it_management_system/models/asset_model.dart';

const headOfficeId = '__head_office__';
const headOffice = 'Head Office';

void main() {
  late FakeFirebaseFirestore db;
  late AssetService assets;
  late DeploymentService movements;

  Future<String> createLaptop({int quantity = 100}) async {
    return assets.addAsset(
      AssetModel(
        id: '',
        assetId: 'IT-LAP-${DateTime.now().microsecondsSinceEpoch}',
        name: 'Laptop',
        category: 'Laptop',
        status: 'Available',
        quantity: quantity,
        adminId: 'admin-1',
        createdAt: DateTime(2026, 1, 1),
      ),
    );
  }

  Future<Map<String, dynamic>> assetData(String id) async {
    return (await db.collection('assets').doc(id).get()).data()!;
  }

  /// Stock physically at each Bazaar = sum of Active movement records.
  Future<Map<String, int>> bazaarStock(String assetId) async {
    final snapshot = await db
        .collection('deployments')
        .where('assetDocumentId', isEqualTo: assetId)
        .where('status', isEqualTo: 'Active')
        .get();

    final result = <String, int>{};

    for (final doc in snapshot.docs) {
      final id = doc.data()['toBazaarId'] as String;
      result[id] = (result[id] ?? 0) + (doc.data()['quantity'] as int);
    }

    return result;
  }

  Future<void> expectInvariant(String assetId) async {
    final data = await assetData(assetId);
    final stock = await bazaarStock(assetId);
    final atBazaars = stock.values.fold<int>(0, (a, b) => a + b);

    expect(
      data['headOfficeQuantity'] +
          data['assignedQuantity'] +
          data['deployedQuantity'],
      data['quantity'],
      reason: 'quantity = HO + assigned + deployed',
    );
    expect(
      data['deployedQuantity'],
      atBazaars,
      reason: 'deployedQuantity must equal Active movement records',
    );
  }

  Future<String> move(
    String assetId, {
    required String fromId,
    required String fromName,
    required String toId,
    required String toName,
    required int quantity,
  }) {
    return movements.transferAsset(
      assetDocumentId: assetId,
      sourceId: fromId,
      sourceName: fromName,
      destinationId: toId,
      destinationName: toName,
      quantity: quantity,
      transferredBy: 'admin-1',
    );
  }

  setUp(() async {
    db = FakeFirebaseFirestore();
    assets = AssetService(firestore: db);
    movements = DeploymentService(firestore: db);

    await db.collection('bazaars').doc('A').set({
      'name': 'Bazaar A',
      'location': 'Lahore',
      'isActive': true,
      'status': 'Active',
    });
    await db.collection('bazaars').doc('B').set({
      'name': 'Bazaar B',
      'location': 'Lahore',
      'isActive': true,
      'status': 'Active',
    });
    await db.collection('bazaars').doc('C').set({
      'name': 'Bazaar C',
      'location': 'Multan',
      'isActive': false,
      'status': 'Disabled',
    });
    // Same name as A, different city.
    await db.collection('bazaars').doc('A2').set({
      'name': 'Bazaar A',
      'location': 'Faisalabad',
      'isActive': true,
      'status': 'Active',
    });
  });

  // ===========================================================================
  // SECTION 9: SINGLE SOURCE OF TRUTH
  // ===========================================================================

  test('HO -> A (20), A -> B (5), B -> HO (3) preserves total', () async {
    final id = await createLaptop();

    await move(id, fromId: headOfficeId, fromName: headOffice, toId: 'A', toName: 'Bazaar A', quantity: 20);

    var data = await assetData(id);
    expect(data['headOfficeQuantity'], 80);
    expect(await bazaarStock(id), {'A': 20});
    await expectInvariant(id);

    await move(id, fromId: 'A', fromName: 'Bazaar A', toId: 'B', toName: 'Bazaar B', quantity: 5);

    data = await assetData(id);
    expect(data['headOfficeQuantity'], 80);
    expect(await bazaarStock(id), {'A': 15, 'B': 5});
    await expectInvariant(id);

    await move(id, fromId: 'B', fromName: 'Bazaar B', toId: headOfficeId, toName: headOffice, quantity: 3);

    data = await assetData(id);
    expect(data['headOfficeQuantity'], 83);
    expect(await bazaarStock(id), {'A': 15, 'B': 2});
    expect(data['quantity'], 100);
    await expectInvariant(id);
  });

  // ===========================================================================
  // SECTION 27: CONTROLLED DATA-INTEGRITY SCENARIO
  // ===========================================================================

  test('section 27 scenario reconciles in Firestore and in the dashboard provider', () async {
    final id = await createLaptop();

    await move(id, fromId: headOfficeId, fromName: headOffice, toId: 'A', toName: 'Bazaar A', quantity: 20);
    await move(id, fromId: headOfficeId, fromName: headOffice, toId: 'B', toName: 'Bazaar B', quantity: 10);
    await move(id, fromId: 'A', fromName: 'Bazaar A', toId: 'B', toName: 'Bazaar B', quantity: 5);
    await move(id, fromId: 'B', fromName: 'Bazaar B', toId: headOfficeId, toName: headOffice, quantity: 3);

    final data = await assetData(id);
    expect(data['quantity'], 100);
    expect(data['headOfficeQuantity'], 73);
    expect(data['deployedQuantity'], 27);
    expect(await bazaarStock(id), {'A': 15, 'B': 12});
    await expectInvariant(id);

    // Dashboard numbers come from AssetProvider over the same data.
    final provider = AssetProvider(assetService: AssetService(firestore: db));
    provider.listenToAssets();
    await Future<void>.delayed(const Duration(milliseconds: 50));

    expect(provider.totalQuantity, 100);
    expect(provider.headOfficeStock, 73);
    expect(provider.deployedToBazaarsQuantity, 27);
    expect(provider.assignedQuantity, 0);
    expect(provider.isStockBalanced, isTrue);

    provider.dispose();
  });

  test('dashboard counts every unit exactly once for damaged stock', () async {
    final id = await createLaptop(quantity: 10);
    await move(id, fromId: headOfficeId, fromName: headOffice, toId: 'A', toName: 'Bazaar A', quantity: 4);
    await assets.updateAssetStatus(assetId: id, status: 'Damaged');

    final provider = AssetProvider(assetService: AssetService(firestore: db));
    provider.listenToAssets();
    await Future<void>.delayed(const Duration(milliseconds: 50));

    // 6 damaged units at Head Office + 4 at Bazaar A = 10, never 14.
    expect(provider.headOfficeStock, 0);
    expect(provider.damagedQuantity, 6);
    expect(provider.unavailableAtHeadOfficeQuantity, 6);
    expect(provider.deployedToBazaarsQuantity, 4);
    expect(
      provider.headOfficeStock +
          provider.unavailableAtHeadOfficeQuantity +
          provider.assignedQuantity +
          provider.deployedToBazaarsQuantity,
      provider.totalQuantity,
    );
    expect(provider.isStockBalanced, isTrue);

    provider.dispose();
  });

  // ===========================================================================
  // SECTION 10: TRANSFER VALIDATION
  // ===========================================================================

  group('invalid transfers are rejected without changing stock', () {
    late String id;

    setUp(() async {
      id = await createLaptop(quantity: 10);
    });

    Future<void> expectRejected(Future<void> Function() action, String message) async {
      final before = await assetData(id);

      await expectLater(action(), throwsA(isA<Exception>()), reason: message);

      final after = await assetData(id);
      expect(after['headOfficeQuantity'], before['headOfficeQuantity'], reason: message);
      expect(after['deployedQuantity'], before['deployedQuantity'], reason: message);
    }

    test('zero, negative and excessive quantity', () async {
      await expectRejected(() => move(id, fromId: headOfficeId, fromName: headOffice, toId: 'A', toName: 'Bazaar A', quantity: 0), 'zero');
      await expectRejected(() => move(id, fromId: headOfficeId, fromName: headOffice, toId: 'A', toName: 'Bazaar A', quantity: -3), 'negative');
      await expectRejected(() => move(id, fromId: headOfficeId, fromName: headOffice, toId: 'A', toName: 'Bazaar A', quantity: 11), 'more than available');
    });

    test('same source and destination', () async {
      await move(id, fromId: headOfficeId, fromName: headOffice, toId: 'A', toName: 'Bazaar A', quantity: 4);
      await expectRejected(() => move(id, fromId: 'A', fromName: 'Bazaar A', toId: 'A', toName: 'Bazaar A', quantity: 1), 'A -> A');
      await expectRejected(() => move(id, fromId: headOfficeId, fromName: headOffice, toId: headOfficeId, toName: headOffice, quantity: 1), 'HO -> HO');
    });

    test('disabled or missing destination Bazaar', () async {
      await expectRejected(() => move(id, fromId: headOfficeId, fromName: headOffice, toId: 'C', toName: 'Bazaar C', quantity: 1), 'disabled');
      await expectRejected(() => move(id, fromId: headOfficeId, fromName: headOffice, toId: 'nope', toName: 'Ghost', quantity: 1), 'missing');
    });

    test('more than the source Bazaar holds', () async {
      await move(id, fromId: headOfficeId, fromName: headOffice, toId: 'A', toName: 'Bazaar A', quantity: 4);
      await expectRejected(() => move(id, fromId: 'A', fromName: 'Bazaar A', toId: 'B', toName: 'Bazaar B', quantity: 5), 'A holds 4');
    });

    test('lost / disposed stock cannot move', () async {
      await db.collection('assets').doc(id).update({'status': 'Lost'});
      await expectRejected(() => move(id, fromId: headOfficeId, fromName: headOffice, toId: 'A', toName: 'Bazaar A', quantity: 1), 'lost');
    });

    test('same-named Bazaars in different cities never share stock', () async {
      await move(id, fromId: headOfficeId, fromName: headOffice, toId: 'A', toName: 'Bazaar A', quantity: 4);
      await move(id, fromId: headOfficeId, fromName: headOffice, toId: 'A2', toName: 'Bazaar A', quantity: 2);

      expect(await bazaarStock(id), {'A': 4, 'A2': 2});

      await expectRejected(() => move(id, fromId: 'A2', fromName: 'Bazaar A', toId: 'B', toName: 'Bazaar B', quantity: 3), 'A2 holds only 2');
      await expectInvariant(id);
    });
  });

  test('damaged status survives a movement', () async {
    final id = await createLaptop(quantity: 5);
    await db.collection('assets').doc(id).update({'status': 'Damaged'});

    await move(id, fromId: headOfficeId, fromName: headOffice, toId: 'A', toName: 'Bazaar A', quantity: 2);

    expect((await assetData(id))['status'], 'Damaged');
  });

  // ===========================================================================
  // SECTION 11: HISTORY PRESERVATION
  // ===========================================================================

  test('returning stock never erases the original movement history', () async {
    final id = await createLaptop(quantity: 50);

    final firstMovementId = await move(id, fromId: headOfficeId, fromName: headOffice, toId: 'A', toName: 'Bazaar A', quantity: 20);

    await move(id, fromId: 'A', fromName: 'Bazaar A', toId: 'B', toName: 'Bazaar B', quantity: 20);
    await move(id, fromId: 'B', fromName: 'Bazaar B', toId: headOfficeId, toName: headOffice, quantity: 20);

    final original = (await db.collection('deployments').doc(firstMovementId).get()).data()!;

    expect(original['fromLocation'], headOffice);
    expect(original['toLocation'], 'Bazaar A');
    expect(original['toBazaarId'], 'A');
    expect(original['originalQuantity'], 20);
    expect(original['status'], 'Transferred');

    final history = await db
        .collection('deployments')
        .where('assetDocumentId', isEqualTo: id)
        .get();

    expect(history.docs.length, 3);
    expect((await assetData(id))['headOfficeQuantity'], 50);
    await expectInvariant(id);
  });

  test('the same movement record cannot be returned twice', () async {
    final id = await createLaptop(quantity: 10);

    final movementId = await move(id, fromId: headOfficeId, fromName: headOffice, toId: 'A', toName: 'Bazaar A', quantity: 3);
    await move(id, fromId: headOfficeId, fromName: headOffice, toId: 'A', toName: 'Bazaar A', quantity: 3);

    await movements.returnAsset(deploymentId: movementId, assetDocumentId: id);

    await expectLater(
      movements.returnAsset(deploymentId: movementId, assetDocumentId: id),
      throwsA(isA<Exception>()),
    );

    // Only one record (3 units) came back; the other 3 are still at A.
    expect(await bazaarStock(id), {'A': 3});
    expect((await assetData(id))['headOfficeQuantity'], 7);
    await expectInvariant(id);
  });

  // ===========================================================================
  // SECTION 14 / 28: EXACTLY-ONCE APPROVAL AND CONCURRENCY
  // ===========================================================================

  test('an approved transfer request moves stock exactly once', () async {
    final id = await createLaptop(quantity: 10);

    final requestRef = db.collection('requests').doc('r1');
    await requestRef.set({'status': 'Pending', 'requestedBy': 'user-1'});

    Future<String> approve() => movements.transferAsset(
      assetDocumentId: id,
      sourceId: headOfficeId,
      sourceName: headOffice,
      destinationId: 'A',
      destinationName: 'Bazaar A',
      quantity: 4,
      approvalRequestRef: requestRef,
      approvalRequestUpdate: const {'approvedBy': 'Admin'},
    );

    await approve();

    await expectLater(approve(), throwsA(isA<Exception>()));

    expect(await bazaarStock(id), {'A': 4});
    expect((await requestRef.get()).data()!['status'], 'Approved');
    await expectInvariant(id);
  });

  // NOTE: fake_cloud_firestore does not simulate optimistic-concurrency
  // conflicts between transactions. Truly simultaneous transfers/approvals
  // are verified against the real Firestore emulator in
  // integration_test/emulator_test.dart. Here the stock check inside the
  // transaction is verified for back-to-back requests.
  test('a second transfer can never over-allocate stock', () async {
    final id = await createLaptop(quantity: 100);

    await move(id, fromId: headOfficeId, fromName: headOffice, toId: 'A', toName: 'Bazaar A', quantity: 60);

    await expectLater(
      move(id, fromId: headOfficeId, fromName: headOffice, toId: 'B', toName: 'Bazaar B', quantity: 60),
      throwsA(isA<Exception>()),
    );

    final data = await assetData(id);
    expect(data['headOfficeQuantity'], 40);
    await expectInvariant(id);
  });

  // ===========================================================================
  // EDIT AND DELETE SAFETY
  // ===========================================================================

  test('editing quantity keeps stock consistent and refuses to drop below allocated', () async {
    final id = await createLaptop(quantity: 10);
    await move(id, fromId: headOfficeId, fromName: headOffice, toId: 'A', toName: 'Bazaar A', quantity: 6);

    final current = AssetModel.fromMap(await assetData(id), id);

    // A stale form still carrying old stock fields must not overwrite them.
    await assets.updateAsset(
      id,
      current.copyWith(quantity: 15, headOfficeQuantity: 999, deployedQuantity: 0),
    );

    var data = await assetData(id);
    expect(data['quantity'], 15);
    expect(data['deployedQuantity'], 6);
    expect(data['headOfficeQuantity'], 9);
    await expectInvariant(id);

    await expectLater(
      assets.updateAsset(id, current.copyWith(quantity: 5)),
      throwsA(isA<Exception>()),
    );

    data = await assetData(id);
    expect(data['quantity'], 15);
  });

  test('an asset with stock at a Bazaar cannot be deleted', () async {
    final id = await createLaptop(quantity: 10);
    await move(id, fromId: headOfficeId, fromName: headOffice, toId: 'A', toName: 'Bazaar A', quantity: 1);

    await expectLater(assets.deleteAsset(id), throwsA(isA<Exception>()));
    expect((await db.collection('assets').doc(id).get()).exists, isTrue);

    await move(id, fromId: 'A', fromName: 'Bazaar A', toId: headOfficeId, toName: headOffice, quantity: 1);
    await assets.deleteAsset(id);
    expect((await db.collection('assets').doc(id).get()).exists, isFalse);
  });

  test('new assets are created with a consistent stock distribution', () async {
    final id = await createLaptop(quantity: 7);
    final data = await assetData(id);

    expect(data['headOfficeQuantity'], 7);
    expect(data['assignedQuantity'], 0);
    expect(data['deployedQuantity'], 0);
    expect(data['adminId'], 'admin-1');
    expect(data['createdAt'], isA<Timestamp>());
  });

  test('an asset cannot be marked Lost while stock is out at a Bazaar', () async {
    final id = await createLaptop(quantity: 10);
    await move(id, fromId: headOfficeId, fromName: headOffice, toId: 'A', toName: 'Bazaar A', quantity: 4);

    await expectLater(
      assets.updateAssetStatus(assetId: id, status: 'Lost'),
      throwsA(isA<Exception>()),
    );
    expect((await assetData(id))['status'], isNot('Lost'));

    // Damaged is a condition, not a loss: allowed, and the stock can return.
    await assets.updateAssetStatus(assetId: id, status: 'Damaged');
    await move(id, fromId: 'A', fromName: 'Bazaar A', toId: headOfficeId, toName: headOffice, quantity: 4);

    await assets.updateAssetStatus(assetId: id, status: 'Lost');
    expect((await assetData(id))['status'], 'Lost');
    await expectInvariant(id);
  });

  test('assign and return keep a Damaged status and the invariant', () async {
    final id = await createLaptop(quantity: 6);
    await assets.updateAssetStatus(assetId: id, status: 'Damaged');

    await assets.assignAsset(assetId: id, userId: 'user-1');
    var data = await assetData(id);
    expect(data['status'], 'Damaged');
    expect(data['assignedQuantity'], 6);
    expect(data['headOfficeQuantity'], 0);

    await assets.returnAsset(id);
    data = await assetData(id);
    expect(data['status'], 'Damaged');
    expect(data['assignedQuantity'], 0);
    expect(data['headOfficeQuantity'], 6);
    await expectInvariant(id);
  });

  test('movement records carry the owner of the moved asset', () async {
    final id = await createLaptop(quantity: 5);
    final movementId = await move(id, fromId: headOfficeId, fromName: headOffice, toId: 'A', toName: 'Bazaar A', quantity: 2);

    final movement = await db.collection('deployments').doc(movementId).get();
    expect(movement.data()!['adminId'], 'admin-1');
  });

  test('duplicate Asset IDs and serials are detected case-insensitively', () async {
    await assets.addAsset(
      AssetModel(
        id: '',
        assetId: 'LAP-01',
        name: 'Laptop',
        category: 'Laptop',
        status: 'Available',
        quantity: 1,
        serialNumber: 'SN-ABC',
        adminId: 'admin-1',
      ),
    );

    expect(await assets.checkDuplicateAssetId(' lap-01 '), isTrue);
    expect(await assets.checkDuplicateSerial('sn-abc'), isTrue);
    expect(await assets.checkDuplicateAssetId('LAP-02'), isFalse);

    // Creating the same Asset ID again (any case) is refused, and the
    // reserved document ID makes concurrent creations collide.
    await expectLater(
      assets.addAsset(
        AssetModel(id: '', assetId: 'lap-01', name: 'Copy', category: 'Laptop', status: 'Available', quantity: 1),
      ),
      throwsA(isA<Exception>()),
    );
    expect(
      AssetService.documentIdForAssetId('LAP-01 '),
      AssetService.documentIdForAssetId(' lap-01'),
    );
    expect((await db.collection('assets').get()).docs.length, 1);

    final index = await assets.loadIdentifierIndex();
    expect(index.assetIds, contains('lap-01'));
    expect(index.serials, contains('sn-abc'));
  });
}
