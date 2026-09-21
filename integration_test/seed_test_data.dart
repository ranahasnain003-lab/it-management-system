// Creates a TEST inventory dataset in the Firebase Local Emulator Suite.
//
// This is a seeding utility, not a test. It is deliberately kept out of the
// normal suite; run it on purpose:
//
//   1. firebase emulators:start --only firestore,auth --project it-inventory-8e690
//   2. flutter test integration_test/seed_test_data.dart -d <android-emulator>
//   3. adb install -r build/testing/app-emulator-test-debug.apk
//
// Step 3 is NOT optional. `flutter test` rebuilds and installs its own
// app-debug.apk, which is compiled WITHOUT
// --dart-define=FIREBASE_EMULATOR_HOST and therefore talks to PRODUCTION
// Firebase. Left in place it looks like the test app but rejects every test
// account with "Incorrect email or password", because those accounts only
// exist in the emulator. Reinstalling the emulator-pointed build afterwards
// is what makes the seeded data reachable from the UI.
//
// It never touches the production project. Everything it writes goes through
// the app's own services - AssetService, BazaarService, DeploymentService - so
// the stock arithmetic, the movement records and the Firestore structure are
// exactly what the app itself would produce. No business logic is duplicated
// here; this file only decides WHAT to create, never HOW it is stored.
//
// Every record it creates is marked:
//   - assets   : assetId starts with "TEST-", notes say TEST DATA
//   - bazaars  : name starts with "TEST "
//   - users    : email ends with @test.local, name starts with "TEST"
//
// so the whole dataset can be identified and removed later.

import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';

import 'package:it_management_system/core/services/asset_service.dart';
import 'package:it_management_system/core/services/bazaar_service.dart';
import 'package:it_management_system/core/services/deployment_service.dart';
import 'package:it_management_system/models/asset_model.dart';

import 'emulator_support.dart';
import 'support/fixtures.dart';

/// Marker written into every seeded asset so the dataset is obvious in the UI
/// and in Firestore, and can be found again for cleanup.
const String testMarker = 'TEST DATA - safe to delete';

/// One asset to create, described the way the Add Asset form would.
/// Public so the const catalogue below can be a public top-level constant.
class TestAsset {
  const TestAsset({
    required this.assetId,
    required this.name,
    required this.category,
    required this.quantity,
    required this.price,
    required this.brand,
    required this.model,
    required this.serial,
    this.warrantyMonths = 12,
    this.purchase = '2025-06-15',
    this.condition = 'Good',
  });

  final String assetId;
  final String name;
  final String category;
  final int quantity;
  final double price;
  final String brand;
  final String model;
  final String serial;
  final int warrantyMonths;
  final String purchase;
  final String condition;
}

/// Twenty assets across ten categories, with a spread of quantities, prices,
/// brands, models, serials, warranties and purchase dates so totals, value,
/// warranty answers and lookup by ID / name / serial all have something real
/// to work with.
const List<TestAsset> catalogue = [
  TestAsset(assetId: 'TEST-LAP-001', name: 'Dell Latitude 5420', category: 'Laptop', quantity: 40, price: 185000, brand: 'Dell', model: 'Latitude 5420', serial: 'TEST-SN-LAP-001', warrantyMonths: 36, purchase: '2025-01-20'),
  TestAsset(assetId: 'TEST-LAP-002', name: 'HP ProBook 450 G9', category: 'Laptop', quantity: 25, price: 165000, brand: 'HP', model: 'ProBook 450 G9', serial: 'TEST-SN-LAP-002', warrantyMonths: 24, purchase: '2025-03-11'),
  TestAsset(assetId: 'TEST-LAP-003', name: 'Lenovo ThinkPad E14', category: 'Laptop', quantity: 18, price: 172000, brand: 'Lenovo', model: 'ThinkPad E14 Gen4', serial: 'TEST-SN-LAP-003', warrantyMonths: 24, purchase: '2024-11-05'),
  TestAsset(assetId: 'TEST-LAP-004', name: 'Apple MacBook Air M2', category: 'Laptop', quantity: 5, price: 420000, brand: 'Apple', model: 'MacBook Air M2', serial: 'TEST-SN-LAP-004', warrantyMonths: 12, purchase: '2026-02-01', condition: 'Excellent'),
  TestAsset(assetId: 'TEST-DSK-001', name: 'Dell OptiPlex 7090', category: 'Desktop', quantity: 30, price: 145000, brand: 'Dell', model: 'OptiPlex 7090', serial: 'TEST-SN-DSK-001', warrantyMonths: 36, purchase: '2024-09-18'),
  TestAsset(assetId: 'TEST-DSK-002', name: 'HP EliteDesk 800 G6', category: 'Desktop', quantity: 11, price: 152000, brand: 'HP', model: 'EliteDesk 800 G6', serial: 'TEST-SN-DSK-002', warrantyMonths: 0, purchase: '2024-04-22', condition: 'Poor'),
  TestAsset(assetId: 'TEST-MON-001', name: 'Dell P2422H Monitor', category: 'Monitor', quantity: 60, price: 42000, brand: 'Dell', model: 'P2422H', serial: 'TEST-SN-MON-001', warrantyMonths: 36, purchase: '2025-02-14'),
  TestAsset(assetId: 'TEST-MON-002', name: 'HP E24 G5 Monitor', category: 'Monitor', quantity: 35, price: 39500, brand: 'HP', model: 'E24 G5', serial: 'TEST-SN-MON-002', warrantyMonths: 24, purchase: '2025-07-30'),
  TestAsset(assetId: 'TEST-PRN-001', name: 'HP LaserJet Pro M404dn', category: 'Printer', quantity: 12, price: 88000, brand: 'HP', model: 'M404dn', serial: 'TEST-SN-PRN-001', warrantyMonths: 12, purchase: '2025-05-09'),
  TestAsset(assetId: 'TEST-PRN-002', name: 'Epson EcoTank L3250', category: 'Printer', quantity: 8, price: 62000, brand: 'Epson', model: 'EcoTank L3250', serial: 'TEST-SN-PRN-002', warrantyMonths: 12, purchase: '2024-12-01', condition: 'Fair'),
  TestAsset(assetId: 'TEST-MOB-001', name: 'Samsung Galaxy A54', category: 'Mobile', quantity: 22, price: 135000, brand: 'Samsung', model: 'Galaxy A54 5G', serial: 'TEST-SN-MOB-001', warrantyMonths: 12, purchase: '2025-08-19'),
  TestAsset(assetId: 'TEST-TAB-001', name: 'Samsung Galaxy Tab A8', category: 'Tablet', quantity: 15, price: 78000, brand: 'Samsung', model: 'Galaxy Tab A8', serial: 'TEST-SN-TAB-001', warrantyMonths: 12, purchase: '2025-04-03'),
  TestAsset(assetId: 'TEST-SWT-001', name: 'Cisco Catalyst 2960X', category: 'Switch', quantity: 10, price: 240000, brand: 'Cisco', model: 'Catalyst 2960X-24TS', serial: 'TEST-SN-SWT-001', warrantyMonths: 36, purchase: '2024-07-15'),
  TestAsset(assetId: 'TEST-SWT-002', name: 'TP-Link TL-SG1024D', category: 'Switch', quantity: 20, price: 34000, brand: 'TP-Link', model: 'TL-SG1024D', serial: 'TEST-SN-SWT-002', warrantyMonths: 24, purchase: '2025-09-27'),
  TestAsset(assetId: 'TEST-RTR-001', name: 'MikroTik CCR2004 Router', category: 'Router', quantity: 6, price: 195000, brand: 'MikroTik', model: 'CCR2004-16G-2S+', serial: 'TEST-SN-RTR-001', warrantyMonths: 24, purchase: '2025-10-08'),
  TestAsset(assetId: 'TEST-UPS-001', name: 'APC Smart-UPS 1500VA', category: 'UPS', quantity: 14, price: 115000, brand: 'APC', model: 'SMT1500I', serial: 'TEST-SN-UPS-001', warrantyMonths: 24, purchase: '2024-10-12'),
  TestAsset(assetId: 'TEST-UPS-002', name: 'Vertiv Liebert PSA5', category: 'UPS', quantity: 9, price: 68000, brand: 'Vertiv', model: 'PSA5-1500MT120', serial: 'TEST-SN-UPS-002', warrantyMonths: 12, purchase: '2024-06-25', condition: 'Fair'),
  TestAsset(assetId: 'TEST-CAM-001', name: 'Hikvision DS-2CD2143G2', category: 'Camera', quantity: 28, price: 33000, brand: 'Hikvision', model: 'DS-2CD2143G2-IS', serial: 'TEST-SN-CAM-001', warrantyMonths: 24, purchase: '2025-11-16'),
  TestAsset(assetId: 'TEST-CAM-002', name: 'Dahua IPC-HDW2431T', category: 'Camera', quantity: 16, price: 29500, brand: 'Dahua', model: 'IPC-HDW2431T-AS', serial: 'TEST-SN-CAM-002', warrantyMonths: 12, purchase: '2024-08-30'),
  TestAsset(assetId: 'TEST-OTH-001', name: 'Logitech MK270 Combo', category: 'Other', quantity: 50, price: 8500, brand: 'Logitech', model: 'MK270', serial: 'TEST-SN-OTH-001', warrantyMonths: 0, purchase: '2025-12-05'),
];

/// Bazaars to create. The last one is inactive on purpose, so the assistant's
/// "that Bazaar is disabled" refusal can be exercised.
const List<({String name, String city, bool active})> bazaarPlan = [
  (name: 'TEST Township Bazaar', city: 'Lahore', active: true),
  (name: 'TEST Model Town Bazaar', city: 'Lahore', active: true),
  (name: 'TEST Gulberg Bazaar', city: 'Lahore', active: true),
  (name: 'TEST Faisalabad Bazaar', city: 'Faisalabad', active: true),
  (name: 'TEST Closed Bazaar', city: 'Multan', active: false),
];

/// Stock to push out to Bazaars: (assetId, bazaar, quantity). Chosen so that
/// several Bazaars hold several different assets, which is what makes
/// Bazaar -> Bazaar and Bazaar -> Head Office transfers testable.
const List<({String asset, String bazaar, int quantity})> deployPlan = [
  (asset: 'TEST-LAP-001', bazaar: 'TEST Township Bazaar', quantity: 12),
  (asset: 'TEST-LAP-001', bazaar: 'TEST Model Town Bazaar', quantity: 8),
  (asset: 'TEST-MON-001', bazaar: 'TEST Township Bazaar', quantity: 20),
  (asset: 'TEST-MON-001', bazaar: 'TEST Gulberg Bazaar', quantity: 15),
  (asset: 'TEST-CAM-001', bazaar: 'TEST Faisalabad Bazaar', quantity: 10),
  (asset: 'TEST-SWT-002', bazaar: 'TEST Model Town Bazaar', quantity: 6),
  (asset: 'TEST-PRN-001', bazaar: 'TEST Gulberg Bazaar', quantity: 4),
  (asset: 'TEST-OTH-001', bazaar: 'TEST Township Bazaar', quantity: 15),
  (asset: 'TEST-TAB-001', bazaar: 'TEST Faisalabad Bazaar', quantity: 5),
];

/// Statuses to set. Deliberately includes the wordings the app recognises as
/// the same bucket ("Under Maintenance" and "In Repair" both count as under
/// repair; "Disposed" and "Retired" both count as disposed).
const List<({String asset, String status})> statusPlan = [
  (asset: 'TEST-PRN-002', status: 'Damaged'),
  (asset: 'TEST-UPS-001', status: 'Under Maintenance'),
  (asset: 'TEST-UPS-002', status: 'In Repair'),
  (asset: 'TEST-CAM-002', status: 'Lost'),
  (asset: 'TEST-DSK-002', status: 'Disposed'),
];

/// Assets handed to a person. assignAsset moves ALL Head Office stock of that
/// asset to the holder, so these are assets with no Bazaar stock.
const List<({String asset, String holder})> assignPlan = [
  (asset: 'TEST-LAP-003', holder: 'staff.one@test.local'),
  (asset: 'TEST-MOB-001', holder: 'staff.two@test.local'),
  (asset: 'TEST-LAP-004', holder: 'staff.three@test.local'),
];

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  setUpAll(() async {
    await initFirebaseForEmulator();
  });

  testWidgets('seed the TEST inventory dataset', (tester) async {
    final assets = AssetService();
    final bazaars = BazaarService();
    final movements = DeploymentService();

    // A known starting point, so the dataset is the same every time and no
    // asset is ever created twice.
    await resetEmulators();

    // ---------------------------------------------------------------- people
    final superUid = await createAuthUser(superAdminEmail, password);
    final adminUid = await createAuthUser(adminAEmail, password);

    await seedDocument('users/$superUid', userProfile(uid: superUid, name: 'TEST Super Admin', email: superAdminEmail, role: 'super_admin'));
    await seedDocument('users/$adminUid', userProfile(uid: adminUid, name: 'TEST Inventory Admin', email: adminAEmail, role: 'admin', createdBy: superUid));

    final holders = <String, String>{};

    for (final person in [
      (email: 'staff.one@test.local', name: 'TEST Ayesha Khan'),
      (email: 'staff.two@test.local', name: 'TEST Bilal Ahmed'),
      (email: 'staff.three@test.local', name: 'TEST Fatima Noor'),
      (email: 'staff.four@test.local', name: 'TEST Hamza Iqbal'),
    ]) {
      final uid = await createAuthUser(person.email, password);
      await seedDocument('users/$uid', userProfile(uid: uid, name: person.name, email: person.email, role: 'user', createdBy: adminUid));
      holders[person.email] = uid;
    }

    // Everything below is written as the Super Admin, through the real
    // services, so ownership and movement records look exactly like the app's.
    await signInAs(superAdminEmail, password);

    // --------------------------------------------------------------- bazaars
    final bazaarIds = <String, String>{};

    for (final plan in bazaarPlan) {
      final id = await bazaars.createBazaar(
        name: plan.name,
        location: plan.city,
        contactPerson: 'TEST Contact',
        contactNumber: '0300-0000000',
      );

      bazaarIds[plan.name] = id;

      if (!plan.active) {
        await bazaars.updateBazaarStatus(bazaarId: id, isActive: false);
      }
    }

    // ---------------------------------------------------------------- assets
    final assetIds = <String, String>{};

    for (final item in catalogue) {
      final parts = item.purchase.split('-').map(int.parse).toList();

      final id = await assets.addAsset(
        AssetModel(
          id: '',
          assetId: item.assetId,
          name: item.name,
          category: item.category,
          status: 'Available',
          quantity: item.quantity,
          serialNumber: item.serial,
          brand: item.brand,
          model: item.model,
          purchasePrice: item.price,
          purchaseDate: DateTime(parts[0], parts[1], parts[2]),
          warrantyMonths: item.warrantyMonths,
          location: 'Head Office',
          condition: item.condition,
          notes: testMarker,
          adminId: superUid,
          adminName: 'TEST Super Admin',
          createdAt: DateTime(2026, 1, 1),
        ),
      );

      assetIds[item.assetId] = id;
    }

    // ------------------------------------------------- Head Office -> Bazaar
    for (final move in deployPlan) {
      await movements.transferAsset(
        assetDocumentId: assetIds[move.asset]!,
        destinationId: bazaarIds[move.bazaar]!,
        destinationName: move.bazaar,
        quantity: move.quantity,
        sourceName: 'Head Office',
        transferredBy: superUid,
        transferredByName: 'TEST Super Admin',
        reason: testMarker,
      );
    }

    // ------------------------------------------------------------ assignment
    for (final hand in assignPlan) {
      await assets.assignAsset(
        assetId: assetIds[hand.asset]!,
        userId: holders[hand.holder]!,
      );
    }

    // ---------------------------------------------------------------- status
    for (final change in statusPlan) {
      await assets.updateAssetStatus(
        assetId: assetIds[change.asset]!,
        status: change.status,
      );
    }

    // ============================================================
    // VERIFY, straight from Firestore
    // ============================================================
    final stored = await adminListCollection('assets');
    final movementDocs = await adminListCollection('deployments');
    final bazaarDocs = await adminListCollection('bazaars');
    final userDocs = await adminListCollection('users');

    var totalQuantity = 0;
    var headOffice = 0;
    var assigned = 0;
    var deployed = 0;
    var value = 0.0;

    final byStatus = <String, int>{};
    final perBazaar = <String, int>{};

    for (final doc in stored) {
      final q = (doc['quantity'] as num?)?.toInt() ?? 0;
      final ho = (doc['headOfficeQuantity'] as num?)?.toInt() ?? 0;
      final asg = (doc['assignedQuantity'] as num?)?.toInt() ?? 0;
      final dep = (doc['deployedQuantity'] as num?)?.toInt() ?? 0;

      totalQuantity += q;
      headOffice += ho;
      assigned += asg;
      deployed += dep;
      value += ((doc['purchasePrice'] as num?)?.toDouble() ?? 0) * q;

      final status = (doc['status'] ?? '').toString();
      byStatus[status] = (byStatus[status] ?? 0) + 1;

      expect(ho + asg + dep, q, reason: 'stock invariant broken for ${doc['assetId']}');
    }

    for (final doc in movementDocs) {
      if ((doc['status'] ?? '').toString().toLowerCase() != 'active') continue;
      final name = (doc['toBazaarName'] ?? doc['toLocation'] ?? '').toString();
      perBazaar[name] = (perBazaar[name] ?? 0) + ((doc['quantity'] as num?)?.toInt() ?? 0);
    }

    // ignore: avoid_print
    print('''

================ TEST DATASET CREATED ================
assets           : ${stored.length}
bazaars          : ${bazaarDocs.length}
users            : ${userDocs.length}
movement records : ${movementDocs.length}

total quantity   : $totalQuantity units
  head office    : $headOffice
  assigned       : $assigned
  at bazaars     : $deployed
inventory value  : Rs.${value.round()}

status counts    : $byStatus
bazaar stock     : $perBazaar
======================================================
''');

    // The invariant the whole app depends on.
    expect(headOffice + assigned + deployed, totalQuantity);
    expect(stored.length, catalogue.length);
    expect(bazaarDocs.length, bazaarPlan.length);
  }, timeout: const Timeout(Duration(minutes: 10)));
}
