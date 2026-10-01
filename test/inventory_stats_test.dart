// The inventory figures the dashboards read are now computed once per
// snapshot and cached. That is a performance change only: this file pins the
// two things that could go wrong with a cache.
//
//   1. The figures must still be the figures. Each one is compared against a
//      naive computation over the same assets, so a mistake in the single
//      pass shows up as a wrong number rather than as a slow screen.
//   2. The cache must be dropped whenever the inventory changes. A stale
//      dashboard is worse than a slow one.

import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:it_management_system/core/providers/asset_provider.dart';
import 'package:it_management_system/core/services/asset_service.dart';
import 'package:it_management_system/models/asset_model.dart';

void main() {
  late FakeFirebaseFirestore db;
  late AssetService service;
  late AssetProvider provider;

  setUp(() {
    db = FakeFirebaseFirestore();
    service = AssetService(firestore: db);
    provider = AssetProvider(assetService: service);
  });

  tearDown(() => provider.dispose());

  /// An asset with explicit stock figures, as the app always writes them.
  Future<void> add({
    required String tag,
    required int quantity,
    int headOffice = 0,
    int assigned = 0,
    int deployed = 0,
    String status = 'Available',
    double price = 1000,
  }) async {
    await db.collection('assets').add({
      'assetId': tag,
      'name': tag,
      'category': 'Laptop',
      'status': status,
      'quantity': quantity,
      'headOfficeQuantity': headOffice,
      'assignedQuantity': assigned,
      'deployedQuantity': deployed,
      'purchasePrice': price,
      'adminId': 'admin-1',
      'createdAt': DateTime(2026, 1, 1),
    });
  }

  /// Waits for the listener to deliver a snapshot holding [count] assets.
  Future<void> settle(int count) async {
    for (var i = 0; i < 100; i++) {
      if (provider.assets.length == count) return;
      await Future<void>.delayed(const Duration(milliseconds: 10));
    }

    fail('the inventory listener never delivered $count asset(s)');
  }

  group('the cached figures are the same figures', () {
    test('match a naive computation over the same assets', () async {
      await add(tag: 'A-1', quantity: 10, headOffice: 4, assigned: 1, deployed: 5);
      await add(tag: 'A-2', quantity: 6, headOffice: 6, price: 500);
      await add(
        tag: 'A-3',
        quantity: 3,
        headOffice: 3,
        status: 'Damaged',
        price: 250,
      );
      await add(
        tag: 'A-4',
        quantity: 4,
        headOffice: 4,
        status: 'Under Repair',
      );
      await add(tag: 'A-5', quantity: 2, headOffice: 2, status: 'Lost');
      await add(tag: 'A-6', quantity: 1, headOffice: 1, status: 'Retired');

      provider.listenToAssets();
      await settle(6);

      final assets = provider.assets;
      int sum(int Function(AssetModel) of) =>
          assets.fold<int>(0, (total, a) => total + of(a));

      expect(provider.totalAssets, 6);
      expect(provider.totalQuantity, sum((a) => a.quantity));
      expect(
        provider.assignedQuantity,
        sum((a) => a.calculatedAssignedQuantity),
      );
      expect(
        provider.deployedToBazaarsQuantity,
        sum((a) => a.calculatedDeployedQuantity),
      );

      // Available is Head Office stock of a usable asset; the Head Office
      // stock of a damaged, repairing, lost or disposed asset is unavailable.
      expect(provider.availableQuantity, 4 + 6);
      expect(provider.unavailableAtHeadOfficeQuantity, 3 + 4 + 2 + 1);
      expect(provider.availableAssets, 2);

      expect(provider.damagedQuantity, 3);
      expect(provider.damagedAssets, 1);
      expect(provider.underRepairQuantity, 4);
      expect(provider.underRepairAssets, 1);
      expect(provider.lostQuantity, 2);
      expect(provider.lostAssets, 1);
      expect(provider.disposedQuantity, 1);
      expect(provider.disposedAssets, 1);

      expect(provider.assignedAssets, 1);
      expect(provider.deployedToBazaarsAssets, 1);

      // Every unit is counted exactly once.
      expect(provider.isStockBalanced, isTrue);

      expect(
        provider.totalInventoryValue,
        10 * 1000 + 6 * 500 + 3 * 250 + 4 * 1000 + 2 * 1000 + 1 * 1000,
      );
      expect(provider.availableInventoryValue, 4 * 1000 + 6 * 500);
      expect(provider.assignedInventoryValue, 1 * 1000);
      expect(provider.deployedInventoryValue, 5 * 1000);
    });

    test('an empty inventory reports zeroes, not a crash', () async {
      provider.listenToAssets();
      await settle(0);

      expect(provider.totalQuantity, 0);
      expect(provider.availableQuantity, 0);
      expect(provider.totalInventoryValue, 0);
      expect(provider.damagedAssets, 0);
      expect(provider.isStockBalanced, isTrue);
    });

    test('reading a figure twice gives the same answer', () async {
      await add(tag: 'A-1', quantity: 10, headOffice: 10);
      provider.listenToAssets();
      await settle(1);

      expect(provider.totalQuantity, provider.totalQuantity);
      expect(provider.assets, same(provider.assets));
    });
  });

  group('the cache is dropped when the inventory changes', () {
    test('a new asset changes every affected figure', () async {
      await add(tag: 'A-1', quantity: 10, headOffice: 10);
      provider.listenToAssets();
      await settle(1);

      // Read first, so a stale cache would be there to catch us out.
      expect(provider.totalQuantity, 10);
      expect(provider.totalInventoryValue, 10000);
      final firstView = provider.assets;

      await add(tag: 'A-2', quantity: 5, headOffice: 5, price: 200);
      await settle(2);

      expect(provider.totalQuantity, 15);
      expect(provider.availableQuantity, 15);
      expect(provider.totalInventoryValue, 10000 + 1000);
      expect(provider.assets, isNot(same(firstView)));
    });

    test('clearing the inventory clears the figures', () async {
      await add(tag: 'A-1', quantity: 10, headOffice: 10);
      provider.listenToAssets();
      await settle(1);

      expect(provider.totalQuantity, 10);

      provider.clearAssets();

      expect(provider.assets, isEmpty);
      expect(provider.totalQuantity, 0);
      expect(provider.totalInventoryValue, 0);
    });

    test('an edited asset is reflected', () async {
      await add(tag: 'A-1', quantity: 10, headOffice: 10);
      provider.listenToAssets();
      await settle(1);

      expect(provider.totalQuantity, 10);

      final id = (await db.collection('assets').get()).docs.single.id;
      await db.collection('assets').doc(id).update({
        'quantity': 20,
        'headOfficeQuantity': 20,
      });

      for (var i = 0; i < 100; i++) {
        if (provider.totalQuantity == 20) break;
        await Future<void>.delayed(const Duration(milliseconds: 10));
      }

      expect(provider.totalQuantity, 20);
      expect(provider.availableQuantity, 20);
    });
  });
}
