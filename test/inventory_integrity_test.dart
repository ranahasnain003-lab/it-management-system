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

  // ===========================================================================
  // AUDIT: MONETARY VALUE (quantity x unit price) AND STOCK DISTRIBUTION
  //
  // purchasePrice is the price of ONE unit: the asset detail sheet shows
  // 'Purchase Price' and a separate 'Total Value' of purchasePrice * quantity
  // (assets_screen.dart), and both value getters multiply by quantity.
  // ===========================================================================

  group('AUDIT: inventory value', () {
    Future<AssetProvider> dashboard() async {
      final provider = AssetProvider(assetService: AssetService(firestore: db));
      provider.listenToAssets();
      await Future<void>.delayed(const Duration(milliseconds: 80));
      addTearDown(provider.dispose);

      return provider;
    }

    Future<String> createAsset({
      required String assetId,
      required int quantity,
      required double unitPrice,
      String name = 'Laptop',
      String status = 'Available',
    }) {
      return assets.addAsset(
        AssetModel(
          id: '',
          assetId: assetId,
          name: name,
          category: 'Laptop',
          status: status,
          quantity: quantity,
          purchasePrice: unitPrice,
          adminId: 'admin-1',
          createdAt: DateTime(2026, 1, 1),
        ),
      );
    }

    for (final quantity in [1, 5, 10]) {
      test('$quantity x Rs 10,000 = Rs ${quantity * 10000}', () async {
        final id = await createAsset(assetId: 'AUD-$quantity', quantity: quantity, unitPrice: 10000);

        final data = await assetData(id);
        expect(data['quantity'], quantity, reason: 'quantity stored as entered');
        expect(data['purchasePrice'], 10000, reason: 'unit price stored as entered');

        final provider = await dashboard();
        expect(provider.totalQuantity, quantity);
        expect(provider.totalInventoryValue, quantity * 10000.0);
        expect(await assets.getTotalInventoryValue(), quantity * 10000.0);
      });
    }

    test('three assets: 5x10,000 + 3x20,000 + 2x5,000 = Rs 120,000', () async {
      await createAsset(assetId: 'AUD-A', quantity: 5, unitPrice: 10000, name: 'Asset A');
      await createAsset(assetId: 'AUD-B', quantity: 3, unitPrice: 20000, name: 'Asset B');
      await createAsset(assetId: 'AUD-C', quantity: 2, unitPrice: 5000, name: 'Asset C');

      final provider = await dashboard();
      expect(provider.totalAssets, 3, reason: 'three asset records');
      expect(provider.totalQuantity, 10, reason: '5 + 3 + 2 pieces');
      expect(provider.totalInventoryValue, 120000.0);
      expect(await assets.getTotalInventoryValue(), 120000.0);
    });

    test('moving stock changes the distribution but never the value', () async {
      final id = await createAsset(assetId: 'AUD-LAP', quantity: 100, unitPrice: 10000);

      var provider = await dashboard();
      expect(provider.totalInventoryValue, 1000000.0);
      expect(provider.headOfficeStock, 100);

      await move(id, fromId: headOfficeId, fromName: headOffice, toId: 'A', toName: 'Bazaar A', quantity: 30);
      await move(id, fromId: headOfficeId, fromName: headOffice, toId: 'B', toName: 'Bazaar B', quantity: 20);

      provider = await dashboard();
      expect(provider.headOfficeStock, 50);
      expect(provider.deployedToBazaarsQuantity, 50);
      expect(await bazaarStock(id), {'A': 30, 'B': 20});
      expect(provider.totalQuantity, 100, reason: 'pieces are moved, never created');
      expect(provider.totalInventoryValue, 1000000.0);
      expect(provider.isStockBalanced, isTrue);
      await expectInvariant(id);

      // Assignment takes the stock that is still at Head Office.
      await assets.assignAsset(assetId: id, userId: 'user-1');

      provider = await dashboard();
      expect(provider.headOfficeStock, 0);
      expect(provider.assignedQuantity, 50);
      expect(provider.deployedToBazaarsQuantity, 50);
      expect(provider.totalQuantity, 100);
      expect(provider.totalInventoryValue, 1000000.0);
      expect(provider.isStockBalanced, isTrue);

      // Returning 10 pieces from Bazaar A puts them back at Head Office.
      await move(id, fromId: 'A', fromName: 'Bazaar A', toId: headOfficeId, toName: headOffice, quantity: 10);

      provider = await dashboard();
      expect(provider.headOfficeStock, 10);
      expect(provider.assignedQuantity, 50);
      expect(provider.deployedToBazaarsQuantity, 40);
      expect(await bazaarStock(id), {'A': 20, 'B': 20});
      expect(provider.totalQuantity, 100, reason: 'a return never duplicates stock');
      expect(provider.totalInventoryValue, 1000000.0);
      expect(provider.isStockBalanced, isTrue);
      await expectInvariant(id);

      // History is kept, and history never inflates current stock: only the
      // Active movement records describe where the pieces are now.
      final movements = await db.collection('deployments').get();
      expect(movements.docs.length, greaterThanOrEqualTo(3), reason: 'transfer history is retained');

      int sumOf(bool Function(Map<String, dynamic>) where) => movements.docs
          .where((doc) => where(doc.data()))
          .fold<int>(0, (running, doc) => running + (doc.data()['quantity'] as int));

      final active = sumOf((data) => data['status'] == 'Active');
      final all = sumOf((_) => true);

      expect(active, provider.deployedToBazaarsQuantity, reason: 'current Bazaar stock = Active records');
      expect(all, greaterThan(active), reason: 'closed movements stay on record');
      expect(provider.totalQuantity, 100, reason: 'history never adds to current stock');
    });

    test('five mixed assets reconcile piece by piece and rupee by rupee', () async {
      // 1: plain stock          10 x 1,000  = 10,000
      final plain = await createAsset(assetId: 'MIX-1', quantity: 10, unitPrice: 1000);
      // 2: partly at a Bazaar    8 x 2,500  = 20,000
      final atBazaar = await createAsset(assetId: 'MIX-2', quantity: 8, unitPrice: 2500);
      // 3: assigned              4 x 7,250  = 29,000
      final assigned = await createAsset(assetId: 'MIX-3', quantity: 4, unitPrice: 7250);
      // 4: damaged               6 x 500    = 3,000
      final damaged = await createAsset(assetId: 'MIX-4', quantity: 6, unitPrice: 500);
      // 5: under repair          2 x 12,000 = 24,000
      final repair = await createAsset(assetId: 'MIX-5', quantity: 2, unitPrice: 12000);

      await move(atBazaar, fromId: headOfficeId, fromName: headOffice, toId: 'A', toName: 'Bazaar A', quantity: 3);
      await assets.assignAsset(assetId: assigned, userId: 'user-9');
      await assets.updateAssetStatus(assetId: damaged, status: 'Damaged');
      await assets.updateAssetStatus(assetId: repair, status: 'Under Repair');

      final provider = await dashboard();

      // Pieces: 10 + 8 + 4 + 6 + 2 = 30.
      expect(provider.totalQuantity, 30);
      expect(provider.totalAssets, 5);

      // Value: 10,000 + 20,000 + 29,000 + 3,000 + 24,000 = 86,000.
      expect(provider.totalInventoryValue, 86000.0);
      expect(await assets.getTotalInventoryValue(), 86000.0);

      // Distribution: HO usable 10 + 5 = 15, at Bazaar 3, assigned 4,
      // unusable at HO (damaged 6 + repair 2) = 8.  15 + 3 + 4 + 8 = 30.
      expect(provider.headOfficeStock, 15);
      expect(provider.deployedToBazaarsQuantity, 3);
      expect(provider.assignedQuantity, 4);
      expect(provider.damagedQuantity, 6);
      expect(provider.underRepairQuantity, 2);
      expect(provider.unavailableAtHeadOfficeQuantity, 8);
      expect(provider.isStockBalanced, isTrue);

      await expectInvariant(plain);
      await expectInvariant(atBazaar);
      await expectInvariant(assigned);
    });

    test('decimals, zero and very large numbers stay exact', () async {
      await createAsset(assetId: 'DEC-1', quantity: 3, unitPrice: 10000.50);
      await createAsset(assetId: 'DEC-2', quantity: 1000000, unitPrice: 250000.75);

      final provider = await dashboard();

      // 3 x 10,000.50 = 30,001.50 and 1,000,000 x 250,000.75 = 250,000,750,000.
      expect(provider.totalInventoryValue, 30001.5 + 250000750000.0);
      expect(provider.totalQuantity, 1000003);
    });

    test('a legacy asset without stock fields is counted at Head Office AND at its Bazaar', () async {
      // A document written before the stock fields existed: the dashboard
      // derives the distribution, the Bazaar pages read movement records.
      await db.collection('assets').doc('legacy-split').set({
        'assetId': 'LEGACY-SPLIT',
        'name': 'Legacy Laptop',
        'category': 'Laptop',
        'status': 'Available',
        'quantity': 10,
        'purchasePrice': 1000,
        'location': 'Bazaar A',
        'adminId': 'admin-1',
        'createdAt': Timestamp.fromDate(DateTime(2026, 1, 1)),
      });
      await db.collection('deployments').add({
        'assetDocumentId': 'legacy-split',
        'toBazaarId': 'A',
        'toBazaarName': 'Bazaar A',
        'quantity': 4,
        'status': 'Active',
      });

      final provider = await dashboard();

      expect(provider.totalQuantity, 10);
      expect(provider.headOfficeStock, 10, reason: 'dashboard puts every unit at Head Office');
      expect(provider.deployedToBazaarsQuantity, 0, reason: 'dashboard sees no Bazaar stock');

      final atBazaar = await bazaarStock('legacy-split');
      expect(atBazaar, {'A': 4}, reason: 'the Bazaar pages read 4 units at Bazaar A');

      // The same 4 pieces are therefore reported in two places at once.
      expect(
        provider.headOfficeStock + atBazaar.values.fold<int>(0, (a, b) => a + b),
        greaterThan(provider.totalQuantity),
        reason: 'DEFECT: Head Office count and Bazaar records overlap for legacy documents',
      );
    });

    test('a text quantity is read by both paths; only a missing one is invented', () async {
      await db.collection('assets').doc('no-qty').set({
        'assetId': 'NOQTY-1',
        'name': 'Quantity Missing',
        'category': 'Laptop',
        'status': 'Available',
        'purchasePrice': 1000,
        'adminId': 'admin-1',
      });
      await db.collection('assets').doc('text-qty').set({
        'assetId': 'TEXTQTY-1',
        'name': 'Quantity As Text',
        'category': 'Laptop',
        'status': 'Available',
        'quantity': '5',
        'purchasePrice': 1000,
        'adminId': 'admin-1',
      });

      final provider = await dashboard();

      // AssetModel falls back to 1 for a missing field and parses numeric text.
      expect(provider.totalQuantity, 6, reason: '1 invented + 5 parsed');
      // The service reads the same text, but never invents a missing quantity.
      expect(await assets.getTotalQuantity(), 5);
    });

    test('a price stored as text is valued the same way by both paths', () async {
      // Legacy documents can hold a string price; the two value paths disagree.
      await db.collection('assets').doc('legacy').set({
        'assetId': 'LEGACY-1',
        'name': 'Legacy Laptop',
        'category': 'Laptop',
        'status': 'Available',
        'quantity': 4,
        'purchasePrice': '10000',
        'headOfficeQuantity': 4,
        'assignedQuantity': 0,
        'deployedQuantity': 0,
        'adminId': 'admin-1',
      });

      final provider = await dashboard();

      expect(provider.totalInventoryValue, 40000.0, reason: 'AssetModel parses a numeric string');
      expect(await assets.getTotalInventoryValue(), 40000.0, reason: 'the service parses it too');
    });
  });
}
