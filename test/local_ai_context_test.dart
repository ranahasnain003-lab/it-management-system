// Tests for the Local AI `appContext`: what the IT Management System sends the
// Local AI server with one question.
//
// Two layers are covered:
//
//   * LocalAiInventoryContext, the pure builder. Every rule about what may
//     leave the app lives there - the role scoping, the fields that are never
//     sent, the size budget - so it is tested directly from model fixtures,
//     the same way the other assistant tests build their snapshots.
//   * ProviderInventoryContextService, which feeds it. It is run against the
//     app's real providers and services, backed by an in-memory Firestore and
//     a mock Firebase login, to check that it starts the right listeners
//     once, waits for them, and turns a failed or silent stream into a note.

import 'dart:async';
import 'dart:convert';
import 'dart:io' show Platform;
import 'dart:math';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart' show FirebaseAuth;
import 'package:firebase_auth_mocks/firebase_auth_mocks.dart';
import 'package:flutter/foundation.dart' show debugPrint;
import 'package:flutter_test/flutter_test.dart';

import 'package:it_management_system/core/ai/inventory_assistant.dart';
import 'package:it_management_system/core/ai/local/local_ai_context_service.dart';
import 'package:it_management_system/core/ai/local/local_ai_inventory_context.dart';
import 'package:it_management_system/core/ai/local/local_ai_provider_context_service.dart';
import 'package:it_management_system/core/providers/asset_provider.dart';
import 'package:it_management_system/core/providers/bazaar_provider.dart';
import 'package:it_management_system/core/providers/deployment_provider.dart';
import 'package:it_management_system/core/providers/request_provider.dart';
import 'package:it_management_system/core/providers/user_provider.dart';
import 'package:it_management_system/core/services/asset_service.dart';
import 'package:it_management_system/core/services/bazaar_service.dart';
import 'package:it_management_system/core/services/deployment_service.dart';
import 'package:it_management_system/core/services/request_service.dart';
import 'package:it_management_system/core/services/user_service.dart';
import 'package:it_management_system/models/asset_model.dart';
import 'package:it_management_system/models/deployment_model.dart';
import 'package:it_management_system/models/request_model.dart';
import 'package:it_management_system/models/user_model.dart';

// =============================================================================
// FIXTURES
// =============================================================================

// Account ids shaped exactly like Firebase Auth uids (28 letters and digits),
// so the scrubber's uid pattern is exercised by every test, not just one.
const saUid = 'SAsuperAdmin0000000000000001';
const adminAUid = 'AdminAlpha000000000000000001';
const adminBUid = 'AdminBravo000000000000000002';
const usmanUid = 'UserUsman0000000000000000003';
const ayeshaUid = 'UserAyesha000000000000000004';
const imranUid = 'UserImran0000000000000000005';

const allUids = [saUid, adminAUid, adminBUid, usmanUid, ayeshaUid, imranUid];

final now = DateTime(2026, 9, 28, 17, 5);

UserModel person(
  String uid,
  String name,
  String role, {
  String status = 'active',
  String department = '',
  String designation = '',
  String createdBy = '',
}) {
  return UserModel(
    uid: uid,
    name: name,
    email: '${name.toLowerCase().replaceAll(' ', '.')}@psba.gov.pk',
    role: role,
    status: status,
    department: department,
    designation: designation,
    createdBy: createdBy,
    createdByEmail: createdBy.isEmpty ? '' : 'owner@psba.gov.pk',
    employeeId: 'EMP-${uid.substring(0, 4)}',
  );
}

final sara = person(
  saUid,
  'Sara Super',
  'super_admin',
  department: 'Administration',
);
final ali = person(
  adminAUid,
  'Ali Admin',
  'admin',
  department: 'IT',
  designation: 'IT Manager',
);
final bilal = person(adminBUid, 'Bilal Admin', 'admin', department: 'Accounts');
final usman = person(
  usmanUid,
  'Usman User',
  'user',
  department: 'IT',
  createdBy: adminAUid,
);
final ayesha = person(
  ayeshaUid,
  'Ayesha Khan',
  'user',
  department: 'IT',
  createdBy: adminAUid,
);
final imran = person(
  imranUid,
  'Imran Qureshi',
  'user',
  status: 'disabled',
  department: 'Procurement',
  createdBy: adminBUid,
);

final everybody = [sara, ali, bilal, usman, ayesha, imran];

AssetModel asset(
  String id,
  String tag,
  String name,
  String category, {
  int quantity = 1,
  int headOffice = 0,
  int deployed = 0,
  int assigned = 0,
  String status = 'Available',
  String? assignedTo,
  String adminId = adminAUid,
  double price = 10000,
  String serial = '',
  String brand = '',
  int warrantyMonths = 0,
  DateTime? purchaseDate,
  String notes = '',
}) {
  return AssetModel(
    id: id,
    assetId: tag,
    name: name,
    category: category,
    status: status,
    quantity: quantity,
    headOfficeQuantity: headOffice,
    deployedQuantity: deployed,
    assignedQuantity: assigned,
    assignedTo: assignedTo,
    adminId: adminId,
    adminName: 'Ali Admin',
    purchasePrice: price,
    serialNumber: serial,
    brand: brand,
    warrantyMonths: warrantyMonths,
    purchaseDate: purchaseDate,
    notes: notes,
  );
}

final abc123 = asset(
  'assetDocAbc123',
  'ABC-123',
  'Dell Latitude 5420',
  'Laptop',
  quantity: 10,
  headOffice: 4,
  deployed: 5,
  assigned: 1,
  assignedTo: ayeshaUid,
  price: 150000,
  serial: 'SN-DL-5420-01',
  brand: 'Dell',
  warrantyMonths: 24,
  purchaseDate: DateTime(2025, 1, 10),
  notes: 'Handed over by ali.admin@psba.gov.pk',
);

final lap002 = asset(
  'assetDocLap002',
  'LAP-002',
  'HP ProBook 450',
  'Laptop',
  quantity: 6,
  headOffice: 6,
  brand: 'HP',
  price: 120000,
);

final mon001 = asset(
  'assetDocMon001',
  'MON-001',
  'Samsung Monitor 24',
  'Monitor',
  quantity: 20,
  headOffice: 12,
  deployed: 8,
  brand: 'Samsung',
  price: 30000,
);

final prn001 = asset(
  'assetDocPrn001',
  'PRN-001',
  'Canon Printer LBP',
  'Printer',
  quantity: 3,
  headOffice: 3,
  status: 'Damaged',
  brand: 'Canon',
);

final rtr001 = asset(
  'assetDocRtr001',
  'RTR-001',
  'TP-Link Router',
  'Networking',
  quantity: 4,
  headOffice: 4,
  status: 'Under Repair',
);

final ups001 = asset(
  'assetDocUps001',
  'UPS-001',
  'APC UPS 1100',
  'Power',
  quantity: 2,
  headOffice: 2,
  status: 'Lost',
);

final scn001 = asset(
  'assetDocScn001',
  'SCN-001',
  'Old Scanner',
  'Scanner',
  quantity: 1,
  headOffice: 1,
  status: 'Retired',
);

final inventory = [abc123, lap002, mon001, prn001, rtr001, ups001, scn001];

const township = BazaarModel(
  id: 'bazaarDocTownship',
  name: 'Township Bazaar',
  location: 'Lahore',
  contactPerson: 'Kamran Contact',
  contactNumber: '0300-1234567',
  address: '12 Main Boulevard, Township',
);
const sahiwal = BazaarModel(
  id: 'bazaarDocSahiwal',
  name: 'Sahiwal Bazaar',
  location: 'Sahiwal',
  contactNumber: '+92 321 7654321',
);
const modelTown = BazaarModel(
  id: 'bazaarDocModelTown',
  name: 'Model Town Bazaar',
  location: 'Lahore',
  isActive: false,
);

const allBazaars = [township, sahiwal, modelTown];

DeploymentModel movement(
  String id,
  AssetModel a,
  BazaarModel to,
  int quantity, {
  String status = 'Active',
  String action = 'deploy',
  int daysAgo = 3,
  BazaarModel? from,
}) {
  final date = now.subtract(Duration(days: daysAgo));
  return DeploymentModel(
    id: id,
    assetDocumentId: a.id,
    assetId: a.assetId,
    assetName: a.name,
    assetType: a.category,
    action: action,
    fromLocation: from?.name ?? 'Head Office',
    fromBazaarId: from?.id,
    fromBazaarName: from?.name,
    toLocation: to.name,
    toBazaarId: to.id,
    toBazaarName: to.name,
    quantity: quantity,
    sentBy: adminAUid,
    sentByName: 'Ali Admin',
    receiverName: 'Kamran Contact',
    receiverContact: '0300-1234567',
    attachmentUrl:
        'https://storage.example/receipt.pdf?token=eyJhbGciOiJIUzI1NiJ9.eyJzdWIiOiIxIn0.c2lnbmF0dXJl',
    deploymentDate: date,
    status: status,
    createdAt: date,
  );
}

final movements = [
  movement('moveDoc1', abc123, township, 3),
  movement('moveDoc2', abc123, sahiwal, 2, daysAgo: 40),
  movement('moveDoc3', mon001, township, 8, daysAgo: 10),
  movement(
    'moveDoc4',
    abc123,
    township,
    2,
    status: 'Returned',
    action: 'return',
    daysAgo: 60,
  ),
];

RequestModel request(
  String id,
  String type,
  AssetModel a,
  String status, {
  required String by,
  required String byName,
  String receiver = adminAUid,
  String receiverName = 'Ali Admin',
  int daysAgo = 2,
  String assigneeId = '',
  String assigneeName = '',
  String destination = '',
  int quantity = 0,
}) {
  return RequestModel(
    id: id,
    requestType: type,
    assetId: a.id,
    assetName: a.name,
    category: a.category,
    reason: 'Please call me on 0300-7654321 or mail usman.user@psba.gov.pk',
    attachmentUrl: 'https://storage.example/attach.png',
    requestedBy: by,
    requestedUserName: byName,
    receiverId: receiver,
    receiverName: receiverName,
    receiverContact: '0333-1112223',
    status: status,
    requestDate: now.subtract(Duration(days: daysAgo)),
    approvedBy: status == 'Pending' ? '' : 'Ali Admin',
    destinationBazaarName: destination,
    destinationBazaarId: destination.isEmpty ? '' : 'bazaarDocTownship',
    transferQuantity: quantity,
    assigneeId: assigneeId,
    assigneeName: assigneeName,
  );
}

final requests = [
  request(
    'reqDoc1',
    'Transfer',
    abc123,
    'Pending',
    by: usmanUid,
    byName: 'Usman User',
    destination: 'Township Bazaar',
    quantity: 2,
  ),
  request(
    'reqDoc2',
    'Edit',
    mon001,
    'Approved',
    by: ayeshaUid,
    byName: 'Ayesha Khan',
  ),
  request(
    'reqDoc3',
    'Assignment',
    lap002,
    'Pending',
    by: adminAUid,
    byName: 'Ali Admin',
    receiver: saUid,
    receiverName: 'Sara Super',
    assigneeId: usmanUid,
    assigneeName: 'Usman User',
  ),
  request(
    'reqDoc4',
    'Delete',
    prn001,
    'Rejected',
    by: imranUid,
    byName: 'Imran Qureshi',
    receiver: adminBUid,
    receiverName: 'Bilal Admin',
  ),
];

/// A snapshot with the figures AssetProvider would report for [assets].
InventorySnapshot snapshotOf(
  List<AssetModel> assets, {
  List<BazaarModel> bazaars = allBazaars,
  List<DeploymentModel>? deployments,
  Map<String, String>? holders,
  bool loading = false,
}) {
  int sum(bool Function(AssetModel) test, int Function(AssetModel) of) =>
      assets.where(test).fold<int>(0, (s, a) => s + of(a));
  int ho(AssetModel a) => a.calculatedHeadOfficeQuantity;

  return InventorySnapshot(
    assets: assets,
    bazaars: bazaars,
    deployments: deployments ?? movements,
    totalQuantity: sum((_) => true, (a) => a.quantity),
    headOfficeStock: sum((a) => !LocalAiInventoryContext.isUnusable(a), ho),
    assignedQuantity: sum((_) => true, (a) => a.calculatedAssignedQuantity),
    bazaarQuantity: sum((_) => true, (a) => a.calculatedDeployedQuantity),
    damagedQuantity: sum(LocalAiInventoryContext.isDamaged, ho),
    underRepairQuantity: sum(LocalAiInventoryContext.isUnderRepair, ho),
    lostQuantity: sum(LocalAiInventoryContext.isLost, ho),
    disposedQuantity: sum(LocalAiInventoryContext.isDisposed, ho),
    unavailableAtHeadOffice: sum(LocalAiInventoryContext.isUnusable, ho),
    totalInventoryValue: assets.fold<double>(
      0,
      (s, a) => s + a.quantity * a.purchasePrice,
    ),
    roleLabel: 'Admin',
    scopeNote: '',
    inventoryLoading: loading,
    holders: holders ?? {for (final p in everybody) p.uid: p.name},
  );
}

UserModel profileFor(String role) => switch (role) {
  'super_admin' => sara,
  'admin' => ali,
  _ => usman,
};

LocalAiContextResult ask(
  String question, {
  String role = 'admin',
  String? previous,
  InventorySnapshot? snapshot,
  List<RequestModel>? requestList,
  List<UserModel>? people,
  UserModel? profile,
  String? askedFor,
  String? signedIn,
  int budget = 2867,
  LocalAiSourceState inventoryState = LocalAiSourceState.ready,
  LocalAiSourceState movementState = LocalAiSourceState.ready,
  LocalAiSourceState requestState = LocalAiSourceState.ready,
  LocalAiSourceState peopleState = LocalAiSourceState.ready,
  bool inScope = true,
  String? rememberedAssetId,
  String? rememberedBazaar,
}) {
  final who = profile ?? profileFor(role);
  return LocalAiInventoryContext.build(
    LocalAiContextInputs(
      question: question,
      previousQuestion: previous,
      askedForUid: askedFor ?? who.uid,
      signedInUid: signedIn ?? who.uid,
      role: role,
      profile: who,
      snapshot: snapshot ?? snapshotOf(inventory),
      requests: requestList ?? requests,
      people: people ?? everybody,
      inventoryState: inventoryState,
      movementState: movementState,
      requestState: requestState,
      peopleState: peopleState,
      inventoryInScope: inScope,
      rememberedAssetId: rememberedAssetId,
      rememberedBazaar: rememberedBazaar,
      retrievedAt: now,
      budgetTokens: budget,
    ),
  );
}

String wire(LocalAiAppContext context) => jsonEncode(context.toJson());

LocalAiContextSection? sectionOf(LocalAiAppContext context, String prefix) {
  for (final section in context.sections) {
    if (section.title.startsWith(prefix)) return section;
  }
  return null;
}

List<String> titles(LocalAiAppContext context) => [
  for (final s in context.sections) s.title,
];

Map<String, dynamic> dataOf(LocalAiContextSection? section) =>
    Map<String, dynamic>.from(section!.data as Map);

/// The rows of a `{columns, rows}` section, each as a column -> value map.
List<Map<String, Object?>> rowsOf(LocalAiContextSection? section) {
  final data = dataOf(section);
  final columns = (data['columns'] as List).cast<String>();
  return [
    for (final row in data['rows'] as List)
      {for (var i = 0; i < columns.length; i++) columns[i]: (row as List)[i]},
  ];
}

/// Everything that must never reach the server, whatever the question.
void expectNoIdentifiers(LocalAiAppContext context) {
  final text = wire(context);

  for (final uid in allUids) {
    expect(text, isNot(contains(uid)), reason: 'uid $uid leaked');
  }

  expect(text, isNot(contains('@')), reason: 'an e-mail address leaked');
  expect(text, isNot(contains('eyJ')), reason: 'a token leaked');
  expect(text, isNot(contains('0300-')), reason: 'a phone number leaked');
  expect(text, isNot(contains('+92')), reason: 'a phone number leaked');
  expect(text, isNot(contains('0333-')), reason: 'a phone number leaked');
  expect(text, isNot(contains('http')), reason: 'an attachment leaked');
  expect(text, isNot(contains('Main Boulevard')), reason: 'an address leaked');
  expect(text, isNot(contains('EMP-')), reason: 'an employee id leaked');
  expect(text, isNot(contains('assetDoc')), reason: 'a document id leaked');
  expect(text, isNot(contains('bazaarDoc')), reason: 'a document id leaked');
  expect(text, isNot(contains('reqDoc')), reason: 'a document id leaked');
  expect(text, isNot(contains('moveDoc')), reason: 'a document id leaked');

  for (final key in const [
    '"uid"',
    '"email"',
    '"assignedTo"',
    '"adminId"',
    '"requestedBy"',
    '"receiverId"',
    '"sentBy"',
    '"createdBy"',
    '"attachmentUrl"',
    '"contactNumber"',
    '"receiverContact"',
    '"address"',
  ]) {
    expect(text, isNot(contains(key)), reason: '$key was sent');
  }
}

// =============================================================================
// GENERATED ORGANISATIONS, for size
// =============================================================================

class Org {
  Org(this.assets, this.bazaars, this.movements, this.requests, this.people);

  final List<AssetModel> assets;
  final List<BazaarModel> bazaars;
  final List<DeploymentModel> movements;
  final List<RequestModel> requests;
  final List<UserModel> people;

  InventorySnapshot get snapshot => snapshotOf(
    assets,
    bazaars: bazaars,
    deployments: movements,
    holders: {for (final p in people) p.uid: p.name},
  );
}

/// A believable organisation: IT equipment spread over Head Office and the
/// Bazaars, with transfers, requests and staff. Deterministic for a [seed].
Org generateOrg({
  required int assets,
  required int bazaars,
  required int moves,
  required int requestCount,
  required int users,
  int seed = 7,
}) {
  final random = Random(seed);

  const kinds = [
    (
      'LAP',
      'Laptop',
      ['Dell Latitude 5420', 'HP ProBook 450', 'Lenovo ThinkPad E14'],
    ),
    ('DSK', 'Desktop', ['Dell OptiPlex 7090', 'HP EliteDesk 800']),
    ('MON', 'Monitor', ['Samsung Monitor 24', 'Dell P2422H']),
    ('PRN', 'Printer', ['Canon LBP 6030', 'HP LaserJet M404']),
    ('SCN', 'Scanner', ['Epson DS-530']),
    ('UPS', 'UPS', ['APC Back-UPS 1100']),
    ('RTR', 'Router', ['TP-Link Archer C6', 'Cisco RV340']),
    ('SWT', 'Switch', ['Cisco SG350 24-port']),
    ('PRJ', 'Projector', ['Epson EB-X49']),
    ('TAB', 'Tablet', ['Samsung Galaxy Tab A8']),
    ('BIO', 'Biometric', ['ZKTeco K40']),
    ('CAM', 'Camera', ['Hikvision DS-2CD']),
  ];

  const places = [
    ('Township', 'Lahore'),
    ('Model Town', 'Lahore'),
    ('Wahdat Road', 'Lahore'),
    ('Johar Town', 'Lahore'),
    ('Sabzazar', 'Lahore'),
    ('Shadman', 'Lahore'),
    ('Gulberg', 'Lahore'),
    ('Baghbanpura', 'Lahore'),
    ('Shahdara', 'Lahore'),
    ('Raiwind', 'Lahore'),
    ('Kasur', 'Kasur'),
    ('Sheikhupura', 'Sheikhupura'),
    ('Gujranwala', 'Gujranwala'),
    ('Faisalabad', 'Faisalabad'),
    ('Sahiwal', 'Sahiwal'),
    ('Multan', 'Multan'),
    ('Okara', 'Okara'),
    ('Sialkot', 'Sialkot'),
    ('Jhelum', 'Jhelum'),
    ('Rawalpindi', 'Rawalpindi'),
  ];

  const firstNames = [
    'Ali',
    'Ayesha',
    'Usman',
    'Fatima',
    'Bilal',
    'Hina',
    'Kamran',
    'Sana',
    'Imran',
    'Zainab',
    'Hamza',
    'Mariam',
    'Faisal',
    'Amna',
    'Tariq',
    'Nida',
  ];
  const lastNames = [
    'Khan',
    'Ahmed',
    'Raza',
    'Iqbal',
    'Malik',
    'Qureshi',
    'Butt',
    'Sheikh',
  ];
  const departments = [
    'IT',
    'Accounts',
    'Procurement',
    'Administration',
    'Operations',
    'HR',
  ];

  String uidFor(int i) => 'U${i.toString().padLeft(27, '0')}';

  final people = <UserModel>[];
  for (var i = 0; i < users; i++) {
    final role = i == 0
        ? 'super_admin'
        : (i <= max(1, users ~/ 6) ? 'admin' : 'user');
    final name =
        '${firstNames[i % firstNames.length]} ${lastNames[(i ~/ firstNames.length) % lastNames.length]}'
        '${i >= firstNames.length * lastNames.length ? ' ${i + 1}' : ''}';
    people.add(
      UserModel(
        uid: uidFor(i),
        name: name,
        email: 'staff$i@psba.gov.pk',
        role: role,
        status: random.nextInt(12) == 0 ? 'disabled' : 'active',
        department: departments[i % departments.length],
        designation: role == 'user' ? 'Assistant' : 'Manager',
        createdBy: role == 'user' ? uidFor(1) : '',
      ),
    );
  }

  final bazaarList = [
    for (var i = 0; i < bazaars; i++)
      BazaarModel(
        id: 'bazaarDoc$i',
        name: i < places.length
            ? '${places[i].$1} Bazaar'
            : '${places[i % places.length].$1} Bazaar ${i ~/ places.length + 1}',
        location: places[i % places.length].$2,
        contactNumber: '0300-${(1000000 + i).toString()}',
        isActive: random.nextInt(10) != 0,
      ),
  ];

  // Stock first, then movements drawn from it so the figures add up.
  final assetList = <AssetModel>[];
  final deployedOf = <int, int>{};
  final quantities = <int>[];

  for (var i = 0; i < assets; i++) {
    quantities.add(1 + random.nextInt(40));
  }

  final moveList = <DeploymentModel>[];
  for (var i = 0; i < moves; i++) {
    final a = random.nextInt(assets);
    final b = bazaarList[random.nextInt(bazaarList.length)];
    final roll = random.nextInt(20);
    final status = roll < 12
        ? 'Active'
        : (roll < 17 ? 'Transferred' : 'Returned');
    final quantity = 1 + random.nextInt(3);

    if (status == 'Active') {
      final already = deployedOf[a] ?? 0;
      if (already + quantity > quantities[a]) continue;
      deployedOf[a] = already + quantity;
    }

    final kind = kinds[a % kinds.length];
    final date = now.subtract(
      Duration(days: random.nextInt(180), hours: random.nextInt(24)),
    );
    moveList.add(
      DeploymentModel(
        id: 'moveDoc$i',
        assetDocumentId: 'assetDoc$a',
        assetId: a == 0
            ? 'ABC-123'
            : '${kind.$1}-${a.toString().padLeft(4, '0')}',
        assetName: kind.$3[a % kind.$3.length],
        action: status == 'Returned'
            ? 'return'
            : (random.nextBool() ? 'deploy' : 'transfer'),
        fromLocation: 'Head Office',
        toLocation: b.name,
        toBazaarId: b.id,
        toBazaarName: b.name,
        quantity: quantity,
        sentBy: uidFor(1),
        sentByName: people.length > 1 ? people[1].name : 'Admin',
        receiverContact: '0300-1234567',
        deploymentDate: date,
        status: status,
        createdAt: date,
      ),
    );
  }

  for (var i = 0; i < assets; i++) {
    final kind = kinds[i % kinds.length];
    final quantity = quantities[i];
    final deployed = deployedOf[i] ?? 0;
    final roll = random.nextInt(100);
    final status = roll < 72
        ? 'Available'
        : roll < 82
        ? 'Assigned'
        : roll < 88
        ? 'Damaged'
        : roll < 93
        ? 'Under Repair'
        : roll < 95
        ? 'Lost'
        : roll < 98
        ? 'Retired'
        : 'Missing';
    final assigned = status == 'Assigned' && quantity - deployed > 0
        ? 1 + random.nextInt(quantity - deployed)
        : 0;
    final holder = assigned > 0 && users > 2
        ? people[2 + random.nextInt(users - 2)].uid
        : null;

    assetList.add(
      AssetModel(
        id: 'assetDoc$i',
        assetId: i == 0
            ? 'ABC-123'
            : '${kind.$1}-${i.toString().padLeft(4, '0')}',
        name: kind.$3[i % kind.$3.length],
        category: kind.$2,
        status: status,
        quantity: quantity,
        headOfficeQuantity: quantity - deployed - assigned,
        deployedQuantity: deployed,
        assignedQuantity: assigned,
        assignedTo: holder,
        adminId: uidFor(1),
        brand: kind.$3[i % kind.$3.length].split(' ').first,
        serialNumber: 'SN${(100000 + i * 7).toString()}',
        purchasePrice: (5 + random.nextInt(300)) * 1000.0,
        purchaseDate: now.subtract(Duration(days: 30 + random.nextInt(1500))),
        warrantyMonths: random.nextInt(3) == 0
            ? 0
            : 12 * (1 + random.nextInt(3)),
        notes: 'Checked by staff$i@psba.gov.pk',
      ),
    );
  }

  const types = ['Transfer', 'Assignment', 'Edit', 'Delete'];
  const statuses = ['Pending', 'Approved', 'Rejected'];
  final requestList = [
    for (var i = 0; i < requestCount; i++)
      () {
        final a = random.nextInt(assets);
        final by = people[users > 2 ? 2 + random.nextInt(users - 2) : 0];
        final type = types[random.nextInt(types.length)];
        final status = statuses[random.nextInt(statuses.length)];
        return RequestModel(
          id: 'reqDoc$i',
          requestType: type,
          assetId: 'assetDoc$a',
          assetName: assetList[a].name,
          category: assetList[a].category,
          reason: 'Needed for the counter, call ${by.email}',
          requestedBy: by.uid,
          requestedUserName: by.name,
          receiverId: uidFor(1),
          receiverName: people.length > 1 ? people[1].name : '',
          receiverContact: '0300-7654321',
          status: status,
          requestDate: now.subtract(Duration(days: random.nextInt(90))),
          approvedBy: status == 'Pending'
              ? ''
              : (people.length > 1 ? people[1].name : ''),
          destinationBazaarName: type == 'Transfer'
              ? bazaarList[random.nextInt(bazaarList.length)].name
              : '',
          transferQuantity: type == 'Transfer' ? 1 + random.nextInt(3) : 0,
        );
      }(),
  ];

  return Org(assetList, bazaarList, moveList, requestList, people);
}

/// The example questions the context has to handle, with the question before
/// each (for the follow-ups).
const examples = <(String, String?)>[
  ('What is our total inventory?', null),
  ('How many assets are currently at Head Office?', null),
  ('How many assets are in each Bazaar?', null),
  ('Show me damaged assets.', null),
  ('Which assets are under repair?', null),
  ('Where is asset ABC-123?', null),
  ('How many assets are assigned?', null),
  ('Which requests are pending?', null),
  ('Show the current stock of laptops.', null),
  ('Which bazaars have this asset?', 'Where is asset ABC-123?'),
  ('Give me the details of this asset.', 'Where is asset ABC-123?'),
  ('What assets are at Township Bazaar?', null),
  ('Which assets were transferred?', null),
  ('What is the status of ABC-123?', null),
  ('kitne laptop head office mein hain?', null),
  ('Show users in the IT department', null),
  ('How many users are there?', null),
];

// =============================================================================
// SERVICE HARNESS
// =============================================================================

class CountingAssetService extends AssetService {
  CountingAssetService(FirebaseFirestore db) : super(firestore: db);

  int streams = 0;

  @override
  Stream<List<AssetModel>> getAssets() {
    streams++;
    return super.getAssets();
  }

  @override
  Stream<List<AssetModel>> getAssetsForAdmin(String adminId) {
    streams++;
    return super.getAssetsForAdmin(adminId);
  }
}

class CountingBazaarService extends BazaarService {
  CountingBazaarService(FirebaseFirestore db) : super(firestore: db);

  int streams = 0;

  @override
  Stream<List<BazaarModel>> getBazaars() {
    streams++;
    return super.getBazaars();
  }
}

class CountingDeploymentService extends DeploymentService {
  CountingDeploymentService(
    FirebaseFirestore db,
    FirebaseAuth auth, {
    this.silent = false,
  }) : super(firestore: db, auth: auth);

  /// Never delivers, like a listener stuck on a dead connection.
  final bool silent;
  int streams = 0;

  @override
  Stream<List<DeploymentModel>> getDeployments() {
    streams++;
    if (silent) return StreamController<List<DeploymentModel>>().stream;
    return super.getDeployments();
  }
}

class CountingRequestService extends RequestService {
  CountingRequestService(
    FirebaseFirestore db,
    FirebaseAuth auth, {
    this.denied = false,
  }) : super(firestore: db, auth: auth);

  /// Fails the way Firestore does when the rules refuse the query.
  final bool denied;
  int streams = 0;

  @override
  Stream<List<RequestModel>> getRequests() {
    streams++;
    if (denied) {
      return Stream.error(
        FirebaseException(
          plugin: 'cloud_firestore',
          code: 'permission-denied',
          message: 'Missing or insufficient permissions.',
        ),
      );
    }
    return super.getRequests();
  }
}

class World {
  World._(
    this.db,
    this.auth, {
    bool silentMovements = false,
    bool deniedRequests = false,
  }) {
    users = UserProvider(
      userService: UserService(firestore: db),
      firebaseAuth: auth,
    );
    assetService = CountingAssetService(db);
    bazaarService = CountingBazaarService(db);
    deploymentService = CountingDeploymentService(
      db,
      auth,
      silent: silentMovements,
    );
    requestService = CountingRequestService(db, auth, denied: deniedRequests);
    assets = AssetProvider(assetService: assetService);
    bazaars = BazaarProvider(bazaarService: bazaarService);
    deployments = DeploymentProvider(deploymentService: deploymentService);
    requestProvider = RequestProvider(requestService: requestService);
    service = ProviderInventoryContextService(
      assets: assets,
      bazaars: bazaars,
      deployments: deployments,
      users: users,
      requests: requestProvider,
      settleTimeout: const Duration(milliseconds: 1500),
      pollInterval: const Duration(milliseconds: 10),
      clock: () => now,
    );
  }

  /// A Firestore holding two Admins' inventory, signed in as [uid].
  static Future<World> signedInAs(
    String? uid, {
    bool silentMovements = false,
    bool deniedRequests = false,
    Map<String, Object?> profileOverride = const {},
  }) async {
    final db = FakeFirebaseFirestore();

    for (final p in everybody) {
      await db.collection('users').doc(p.uid).set({
        'uid': p.uid,
        'name': p.name,
        'email': p.email,
        'role': p.role,
        'status': p.status,
        'department': p.department,
        'designation': p.designation,
        'createdBy': p.createdBy,
        'employeeId': p.employeeId,
        if (p.uid == uid) ...profileOverride,
      });
    }

    final bravoLaptop = asset(
      'assetDocBravo1',
      'BRV-777',
      'Bravo Secret Laptop',
      'Laptop',
      quantity: 9,
      headOffice: 9,
      adminId: adminBUid,
    );

    for (final a in [...inventory, bravoLaptop]) {
      await db.collection('assets').doc(a.id).set({
        ...a.toMap(),
        'purchaseDate': a.purchaseDate == null
            ? null
            : Timestamp.fromDate(a.purchaseDate!),
        'createdAt': Timestamp.fromDate(
          now.subtract(const Duration(days: 100)),
        ),
        'lastUpdated': null,
      });
    }

    for (final b in allBazaars) {
      await db.collection('bazaars').doc(b.id).set({
        ...b.toMap(),
        'createdAt': null,
        'lastUpdated': null,
      });
    }

    for (final m in [
      ...movements,
      movement('moveDocBravo', bravoLaptop, sahiwal, 4),
    ]) {
      await db.collection('deployments').doc(m.id).set({
        ...m.toMap(),
        'adminId': m.assetDocumentId == 'assetDocBravo1'
            ? adminBUid
            : adminAUid,
      });
    }

    for (final r in requests) {
      final data = r.toMap()..remove('id');
      await db.collection('requests').doc(r.id).set({
        ...data,
        'requestDate': Timestamp.fromDate(r.requestDate!),
        'approvedDate': null,
        'assetAdminId': adminAUid,
      });
    }

    final auth = uid == null
        ? MockFirebaseAuth()
        : MockFirebaseAuth(
            signedIn: true,
            mockUser: MockUser(
              uid: uid,
              email: 'signed.in@psba.gov.pk',
              isEmailVerified: true,
            ),
          );

    return World._(
      db,
      auth,
      silentMovements: silentMovements,
      deniedRequests: deniedRequests,
    );
  }

  final FakeFirebaseFirestore db;
  final MockFirebaseAuth auth;

  late final UserProvider users;
  late final CountingAssetService assetService;
  late final CountingBazaarService bazaarService;
  late final CountingDeploymentService deploymentService;
  late final CountingRequestService requestService;
  late final AssetProvider assets;
  late final BazaarProvider bazaars;
  late final DeploymentProvider deployments;
  late final RequestProvider requestProvider;
  late final ProviderInventoryContextService service;

  Future<LocalAiAppContext?> ask(
    String question, {
    String? previous,
    String? uid,
  }) {
    return service.contextFor(
      question: question,
      uid: uid ?? auth.currentUser?.uid,
      previousQuestion: previous,
      budgetTokens: 2867,
    );
  }

  void dispose() {
    assets.dispose();
    bazaars.dispose();
    deployments.dispose();
    requestProvider.dispose();
    users.dispose();
  }
}

// =============================================================================
// TESTS
// =============================================================================

void main() {
  // ---------------------------------------------------------------------------
  // THE EXAMPLE QUESTIONS
  // ---------------------------------------------------------------------------

  group('Example questions', () {
    test(
      '"What is our total inventory?" gets the totals and the breakdowns',
      () {
        final context = ask('What is our total inventory?').context;

        final totals = dataOf(sectionOf(context, 'Inventory totals'));
        expect(totals['assetRecords'], 7);
        expect(totals['totalQuantity'], 46);
        expect(totals['headOfficeAvailable'], 22);
        expect(totals['atBazaars'], 13);
        expect(totals['assigned'], 1);
        expect(totals['damaged'], 3);
        expect(totals['underRepair'], 4);
        expect(totals['lost'], 2);
        expect(totals['disposed'], 1);
        expect(
          totals.containsKey('totalInventoryValue'),
          isFalse,
          reason: 'value only when asked',
        );

        expect(sectionOf(context, 'Stock by category'), isNotNull);
        expect(sectionOf(context, 'Stock by status'), isNotNull);
        expectNoIdentifiers(context);
      },
    );

    test('"How many assets are currently at Head Office?"', () {
      final context = ask(
        'How many assets are currently at Head Office?',
      ).context;

      final section = sectionOf(context, 'Assets at Head Office');
      expect(section!.title, 'Assets at Head Office (showing 7 of 7)');
      expect((dataOf(section)['sumOfAll'] as Map)['headOffice'], 32);
      expect(
        dataOf(sectionOf(context, 'Inventory totals'))['headOfficeAvailable'],
        22,
      );
      expectNoIdentifiers(context);
    });

    test(
      '"How many assets are in each Bazaar?" lists every Bazaar, empty ones too',
      () {
        final context = ask('How many assets are in each Bazaar?').context;

        final section = sectionOf(context, 'Stock at each Bazaar');
        expect(section!.title, 'Stock at each Bazaar (showing 3 of 3)');

        final rows = {for (final r in rowsOf(section)) r['bazaar']: r};
        expect(rows['Township Bazaar']!['units'], 11);
        expect(rows['Township Bazaar']!['assetRecords'], 2);
        expect(rows['Sahiwal Bazaar']!['units'], 2);
        expect(rows['Model Town Bazaar']!['units'], 0);
        expect(rows['Model Town Bazaar']!['active'], false);
        expectNoIdentifiers(context);
      },
    );

    test('"Show me damaged assets."', () {
      final context = ask('Show me damaged assets.').context;

      final section = sectionOf(context, 'Damaged assets');
      expect(section!.title, 'Damaged assets (showing 1 of 1)');
      expect(rowsOf(section).single['assetId'], 'PRN-001');
      expect(sectionOf(context, 'Assets under repair'), isNull);
    });

    test('"Which assets are under repair?"', () {
      final context = ask('Which assets are under repair?').context;

      final section = sectionOf(context, 'Assets under repair');
      expect(section!.title, 'Assets under repair (showing 1 of 1)');
      expect(rowsOf(section).single['assetId'], 'RTR-001');
    });

    test('"Where is asset ABC-123?" says where every unit is', () {
      final result = ask('Where is asset ABC-123?');
      final context = result.context;

      final section = sectionOf(context, 'Asset ABC-123');
      expect(section!.title, 'Asset ABC-123 (Dell Latitude 5420)');

      final where = rowsOf(
        LocalAiContextSection(title: 'where', data: dataOf(section)['where']),
      );
      expect(where, [
        {'place': 'Head Office', 'units': 4},
        {'place': 'Township Bazaar', 'units': 3},
        {'place': 'Sahiwal Bazaar', 'units': 2},
        {'place': 'Assigned', 'units': 1},
      ]);
      expect(dataOf(section)['heldBy'], 'Ayesha Khan');
      expect(result.focusAsset, same(abc123));
      expectNoIdentifiers(context);
    });

    test(
      '"How many assets are assigned?" names the holder, never the account',
      () {
        final context = ask('How many assets are assigned?').context;

        final section = sectionOf(context, 'Assigned assets');
        expect(section!.title, 'Assigned assets (showing 1 of 1)');
        expect(rowsOf(section).single, containsPair('heldBy', 'Ayesha Khan'));
        expect(dataOf(sectionOf(context, 'Inventory totals'))['assigned'], 1);
        expectNoIdentifiers(context);
      },
    );

    test('"Which requests are pending?"', () {
      final context = ask('Which requests are pending?').context;

      final section = sectionOf(context, 'Pending requests');
      expect(section!.title, 'Pending requests (showing 2 of 2)');

      final rows = rowsOf(section);
      expect(
        rows.map((r) => r['type']),
        containsAll(['Transfer', 'Assignment']),
      );
      expect(rows.first['requester'], isNotNull);
      expect(
        rows.firstWhere((r) => r['type'] == 'Transfer')['detail'],
        '2 units to Township Bazaar',
      );
      expect(sectionOf(context, 'Requests summary'), isNotNull);
      expectNoIdentifiers(context);
    });

    test('"Show the current stock of laptops."', () {
      final context = ask('Show the current stock of laptops.').context;

      final section = sectionOf(context, 'Laptop stock');
      expect(section!.title, 'Laptop stock (showing 2 of 2)');
      expect((dataOf(section)['sumOfAll'] as Map)['quantity'], 16);
      expect(rowsOf(section).map((r) => r['assetId']), ['ABC-123', 'LAP-002']);
    });

    test('"Which bazaars have this asset?" after naming ABC-123', () {
      final context = ask(
        'Which bazaars have this asset?',
        previous: 'Where is asset ABC-123?',
      ).context;

      final section = sectionOf(context, 'Asset ABC-123');
      expect(section, isNotNull);
      final places = (dataOf(section)['where'] as Map)['rows'] as List;
      expect(places.map((r) => (r as List).first), contains('Township Bazaar'));
      expect(places.map((r) => (r as List).first), contains('Sahiwal Bazaar'));
      expect(
        sectionOf(context, 'Stock at each Bazaar'),
        isNull,
        reason: 'the question is about one asset',
      );
    });

    test('"Give me the details of this asset." after naming ABC-123', () {
      final context = ask(
        'Give me the details of this asset.',
        previous: 'Where is asset ABC-123?',
      ).context;

      final data = dataOf(sectionOf(context, 'Asset ABC-123'));
      expect(data['serialNumber'], 'SN-DL-5420-01');
      expect(data['warrantyEnds'], '2027-01-10');
      expect(data.containsKey('notes'), isFalse);
    });

    test('"What assets are at Township Bazaar?"', () {
      final context = ask('What assets are at Township Bazaar?').context;

      final section = sectionOf(context, 'Stock at Township Bazaar');
      expect(section!.title, 'Stock at Township Bazaar (showing 2 of 2)');
      final data = dataOf(section);
      expect((data['sumOfAll'] as Map)['units'], 11);
      expect(data['city'], 'Lahore');
      expect(rowsOf(section).map((r) => r['assetId']), ['MON-001', 'ABC-123']);
      expectNoIdentifiers(context);
    });

    test('"Which assets were transferred?"', () {
      final context = ask('Which assets were transferred?').context;

      final section = sectionOf(context, 'Movements');
      expect(section!.title, 'Movements (showing 4 of 4)');
      expect((dataOf(section)['sumOfAll'] as Map)['distinctAssets'], 2);

      final summary = dataOf(sectionOf(context, 'All movements, summary'));
      expect(summary['total'], 4);
      expect(summary.containsKey('recent'), isFalse);
      expectNoIdentifiers(context);
    });

    test('"What is the status of ABC-123?"', () {
      final context = ask('What is the status of ABC-123?').context;

      final data = dataOf(sectionOf(context, 'Asset ABC-123'));
      expect(data['status'], 'Available');
      expect(data['condition'], 'Good');
    });

    test('"kitne laptop head office mein hain?" (Roman Urdu)', () {
      final context = ask('kitne laptop head office mein hain?').context;

      final section = sectionOf(context, 'Assets at Head Office - Laptop');
      expect(section!.title, 'Assets at Head Office - Laptop (showing 2 of 2)');
      expect((dataOf(section)['sumOfAll'] as Map)['headOffice'], 10);
    });

    test('Urdu script: "ہیڈ آفس میں کتنے لیپ ٹاپ ہیں؟"', () {
      final context = ask('ہیڈ آفس میں کتنے لیپ ٹاپ ہیں؟').context;

      final section = sectionOf(context, 'Assets at Head Office - Laptop');
      expect((dataOf(section)['sumOfAll'] as Map)['headOffice'], 10);
    });

    test('"Show users in the IT department"', () {
      final context = ask('Show users in the IT department').context;

      final section = sectionOf(context, 'User accounts in the IT department');
      expect(
        section!.title,
        'User accounts in the IT department (showing 3 of 3)',
      );
      expect(rowsOf(section).map((r) => r['name']), [
        'Ali Admin',
        'Ayesha Khan',
        'Usman User',
      ]);
      expectNoIdentifiers(context);
    });

    test('"How many users are there?"', () {
      final context = ask(
        'How many users are there?',
        role: 'super_admin',
      ).context;

      final summary = dataOf(sectionOf(context, 'User accounts, summary'));
      expect(summary['total'], 6);
      expect(summary['byRole'], {'Super Admin': 1, 'Admin': 2, 'User': 3});
      expect(summary['byStatus'], {'active': 5, 'disabled': 1});
      expectNoIdentifiers(context);
    });

    test('every example carries the totals, the scope and the freshness', () {
      for (final (question, previous) in examples) {
        final context = ask(question, previous: previous).context;
        final json = context.toJson();

        expect(titles(context).first, 'Inventory totals', reason: question);
        expect(json['retrievedAt'], now.toUtc().toIso8601String());
        expect(json['source'], LocalAiAppContext.defaultSource);
        expect(json['scope'], startsWith('Asked by an Admin'));
        expectNoIdentifiers(context);
      }
    });
  });

  // ---------------------------------------------------------------------------
  // WHO MAY SEE WHAT
  // ---------------------------------------------------------------------------

  group('Role scoping', () {
    test('the scope is described in words, without names or ids', () {
      expect(
        ask('total?', role: 'admin').context.scope,
        'Asked by an Admin: all inventory, Bazaars and movements; requests the '
        'Admin received, owns or made; the user directory.',
      );
      expect(
        ask('total?', role: 'super_admin').context.scope,
        startsWith('Asked by a Super Admin'),
      );

      final user = ask(
        'total?',
        role: 'user',
        snapshot: snapshotOf(inventory, holders: const {}),
      ).context;
      expect(user.scope, startsWith('Asked by a User'));
      expect(user.scope, contains('No user directory'));
      for (final name in ['Ali', 'Usman', 'Sara']) {
        expect(user.scope, isNot(contains(name)));
      }
    });

    test('a Super Admin sees every request', () {
      final context = ask('Show all requests', role: 'super_admin').context;
      expect(
        sectionOf(context, 'Requests')!.title,
        'Requests (showing 4 of 4)',
      );
    });

    test('an Admin gets the request list the service already filtered', () {
      final scoped = requests
          .where((r) => r.receiverId == adminAUid || r.requestedBy == adminAUid)
          .toList();
      final context = ask('Show all requests', requestList: scoped).context;
      expect(
        sectionOf(context, 'Requests')!.title,
        'Requests (showing 3 of 3)',
      );
    });

    test('a User only ever gets their own requests, even if handed more', () {
      final context = ask('Show all requests', role: 'user').context;

      final section = sectionOf(context, 'Your requests');
      expect(section!.title, 'Your requests (showing 1 of 1)');
      expect(rowsOf(section).single['type'], 'Transfer');
      expect(dataOf(sectionOf(context, 'Your requests, summary'))['total'], 1);
      expect(wire(context), isNot(contains('Imran')));
    });

    test('a User gets no user directory, only a note saying so', () {
      for (final question in [
        'How many users are there?',
        'Show users in the IT department',
        'List all the admins',
      ]) {
        final context = ask(question, role: 'user').context;

        expect(
          titles(
            context,
          ).where((t) => t.startsWith('User') || t.startsWith('Person')),
          isEmpty,
          reason: question,
        );
        expect(context.notes.join(' '), contains('only available to Admins'));
      }
    });

    test(
      'a User never gets holder names, even if the snapshot carries them',
      () {
        final context = ask(
          'How many assets are assigned?',
          role: 'user',
        ).context;

        final section = sectionOf(context, 'Assigned assets');
        expect(rowsOf(section).single.containsKey('heldBy'), isFalse);
        expect(wire(context), isNot(contains('Ayesha')));
      },
    );

    test(
      'a User sees inventory of every Admin, because the read is '
      'organisation-wide',
      () {
        final stray = asset(
          'assetDocBravo1',
          'BRV-777',
          'Bravo Laptop',
          'Laptop',
          adminId: adminBUid,
          headOffice: 1,
        );
        final context = ask(
          'What is our total inventory?',
          role: 'user',
          snapshot: snapshotOf([...inventory, stray]),
        ).context;

        // A User reads all inventory read-only (the /assets read rule), so a
        // record owned by another Admin is part of the answer rather than a
        // reason to withhold everything.
        expect(
          dataOf(sectionOf(context, 'Inventory totals'))['assetRecords'],
          inventory.length + 1,
        );
        expect(context.notes, isEmpty);
      },
    );

    test('a User gets the movements of every asset', () {
      final stray = asset(
        'assetDocBravo1',
        'BRV-777',
        'Bravo Laptop',
        'Laptop',
        adminId: adminBUid,
      );
      final context = ask(
        'Which assets were transferred?',
        role: 'user',
        snapshot: snapshotOf(
          inventory,
          deployments: [
            ...movements,
            movement('moveDocBravo', stray, sahiwal, 4),
          ],
        ),
      ).context;

      expect(
        sectionOf(context, 'Movements')!.title,
        'Movements (showing 5 of 5)',
      );
      expect(wire(context), contains('BRV-777'));
    });

    test('a User not linked to an Admin still sees the inventory', () {
      final unlinked = person(usmanUid, 'Usman User', 'user');
      final context = ask(
        'total stock',
        role: 'user',
        profile: unlinked,
      ).context;

      // Being linked to an Admin decides who owns what this account ADDS, not
      // what it may read.
      expect(
        dataOf(sectionOf(context, 'Inventory totals'))['assetRecords'],
        inventory.length,
      );
      expect(context.notes, isEmpty);
    });

    group('a User whose inventory cannot be used is not told Bazaars are '
        'empty', () {
      final cases = <String, LocalAiContextResult Function(String)>{
        'inventory still loading': (q) => ask(
          q,
          role: 'user',
          snapshot: snapshotOf(const [], loading: true),
          inventoryState: const LocalAiSourceState(loading: true),
        ),
        'inventory out of scope': (q) => ask(q, role: 'user', inScope: false),
      };

      for (final entry in cases.entries) {
        test(entry.key, () {
          final perBazaar = entry
              .value('How many assets are in each Bazaar?')
              .context;
          expect(sectionOf(perBazaar, 'Stock at each Bazaar'), isNull);
          expect(
            perBazaar.notes.join(' '),
            contains('Bazaar stock and transfers are worked out'),
          );

          final township = entry
              .value('What assets are at Township Bazaar?')
              .context;
          expect(sectionOf(township, 'Stock at Township Bazaar'), isNull);
          // What is known about the Bazaar itself is not the inventory.
          expect(dataOf(sectionOf(township, 'Bazaar Township Bazaar')), {
            'city': 'Lahore',
            'active': true,
          });

          final moved = entry.value('Which assets were transferred?').context;
          expect(sectionOf(moved, 'Movements'), isNull);
          expect(sectionOf(moved, 'All movements'), isNull);
          expect(wire(moved), isNot(contains('"units":0')));
          expect(
            moved.notes.join(' '),
            contains('Bazaar stock and transfers are worked out'),
          );
        });
      }

      test('through the real providers, for a self-registered User', () async {
        // firestore.rules makes a self-registered account's createdBy ''.
        // Such an account still reads the whole inventory, so the Bazaar
        // figures are real rather than withheld.
        final world = await World.signedInAs(
          usmanUid,
          profileOverride: {'createdBy': ''},
        );
        addTearDown(world.dispose);

        final context = await world.ask('How many assets are in each Bazaar?');
        expect(sectionOf(context!, 'Stock at each Bazaar'), isNotNull);
        expect(context.notes, isEmpty);
      });
    });

    test('an inventory listener on the wrong scope sends nothing from it', () {
      final context = ask(
        'What is our total inventory?',
        role: 'user',
        inScope: false,
      ).context;

      expect(context.sections, isEmpty);
      expect(context.notes.single, contains('did not match'));
    });

    test('an inactive account gets no data at all', () {
      final disabled = person(
        adminAUid,
        'Ali Admin',
        'admin',
        status: 'disabled',
      );
      final context = ask(
        'What is our total inventory?',
        profile: disabled,
      ).context;

      expect(context.sections, isEmpty);
      expect(context.notes.single, contains('not active'));
      expect(context.hasData, isFalse);
    });

    test('an unrecognised role gets no data at all', () {
      final odd = person(adminAUid, 'Ali Admin', 'manager');
      final context = ask(
        'What is our total inventory?',
        role: 'manager',
        profile: odd,
      ).context;

      expect(context.sections, isEmpty);
      expect(context.notes.single, contains('no recognised role'));
      expect(context.scope, contains('could not be verified'));
    });

    test(
      'a question asked for another account than the signed-in one gets nothing',
      () {
        final context = ask(
          'What is our total inventory?',
          askedFor: usmanUid,
        ).context;

        expect(context.sections, isEmpty);
        expect(context.notes.single, contains('signed-in account changed'));
        expectNoIdentifiers(context);
      },
    );

    test(
      'a profile that does not belong to the signed-in account gets nothing',
      () {
        final context = ask(
          'What is our total inventory?',
          profile: usman,
          askedFor: adminAUid,
          signedIn: adminAUid,
        ).context;

        expect(context.sections, isEmpty);
        expect(context.notes.single, contains('does not match'));
      },
    );

    test('the access check itself', () {
      expect(
        LocalAiInventoryContext.accessProblem(
          askedForUid: null,
          signedInUid: null,
          profile: null,
          role: '',
        ),
        contains('Nobody is signed in'),
      );
      expect(
        LocalAiInventoryContext.accessProblem(
          askedForUid: adminAUid,
          signedInUid: adminAUid,
          profile: null,
          role: 'admin',
        ),
        contains('not loaded yet'),
      );
      expect(
        LocalAiInventoryContext.accessProblem(
          askedForUid: adminAUid,
          signedInUid: adminAUid,
          profile: ali,
          role: 'admin',
        ),
        isNull,
      );
    });
  });

  // ---------------------------------------------------------------------------
  // SANITIZATION
  // ---------------------------------------------------------------------------

  group('Sanitization', () {
    test(
      'uids, e-mail addresses, phone numbers and tokens planted everywhere never leave',
      () {
        // Identifiers typed into the fields that ARE sent, on top of the ones
        // in the fields that never are.
        final poisoned = [
          ...inventory,
          asset(
            'assetDocPoison',
            'PSN-001',
            'Laptop of ayesha.khan@psba.gov.pk',
            'Laptop',
            quantity: 2,
            headOffice: 2,
            status: 'Damaged',
            serial: adminAUid,
            brand: 'eyJhbGciOiJIUzI1NiJ9.eyJzdWIiOiIxIn0.c2lnbmF0dXJl',
            assignedTo: usmanUid,
          ),
        ];
        final people = [
          ...everybody,
          person(
            'UserPoison000000000000000009',
            'poison.name@psba.gov.pk',
            'user',
            department: 'IT',
          ),
        ];
        final poisonedRequests = [
          ...requests,
          request(
            'reqDocPoison',
            'Transfer',
            abc123,
            'Pending',
            by: usmanUid,
            byName: 'Call 0300-1234567',
            receiverName: 'Sara Super',
            destination: 'lai_ab12cd34_0123456789abcdef',
          ),
        ];

        for (final role in ['super_admin', 'admin', 'user']) {
          for (final (question, previous) in [
            ...examples,
            (
              'Show me everything: damaged, requests, users, transfers, warranty, value',
              null,
            ),
            ('Who has the Laptop of ayesha?', null),
          ]) {
            final context = ask(
              question,
              role: role,
              previous: previous,
              snapshot: snapshotOf(poisoned),
              people: people,
              requestList: poisonedRequests,
            ).context;

            expectNoIdentifiers(context);
            expect(wire(context), isNot(contains('lai_')), reason: question);
            expect(
              wire(context),
              isNot(contains('UserPoison')),
              reason: question,
            );
          }
        }
      },
    );

    test('the poisoned asset still appears, with the bad cells removed', () {
      final poisoned = asset(
        'assetDocPoison',
        'PSN-001',
        'Laptop of ayesha.khan@psba.gov.pk',
        'Laptop',
        quantity: 2,
        headOffice: 2,
        status: 'Damaged',
      );
      final context = ask(
        'Show me damaged assets.',
        snapshot: snapshotOf([...inventory, poisoned]),
      ).context;

      final rows = rowsOf(sectionOf(context, 'Damaged assets'));
      final row = rows.firstWhere((r) => r['assetId'] == 'PSN-001');
      expect(row['name'], isNull, reason: 'the name held an e-mail address');
      expect(row['quantity'], 2, reason: 'the rest of the row stays aligned');
    });

    test(
      'the scrubber drops sensitive keys at any depth and bad strings anywhere',
      () {
        const jwt = 'eyJhbGciOiJIUzI1NiJ9.eyJzdWIiOiIxIn0.c2lnbmF0dXJl';
        final dirty = {
          'uid': adminAUid,
          'name': 'Ali Admin',
          'Email': 'ali@psba.gov.pk',
          'fine': 42,
          'nested': {
            'assigned_to': usmanUid,
            'deep': [
              {'requestedBy': ayeshaUid, 'ok': true, 'photo': null},
              'plain text',
              'mail ali@psba.gov.pk now',
            ],
            'contact': {'phone': '0300-1234567'},
          },
          'table': {
            'columns': ['name', 'receiverId', 'email', 'units'],
            'rows': [
              ['Ali Admin', adminBUid, 'ali@psba.gov.pk', 3],
              [jwt, 'x', 'y', 4],
              ['Call +92 300 1234567', 'x', 'y', 5],
            ],
            'sumOfAll': {'units': 12, 'sentBy': saUid},
          },
          'jwt': jwt,
          'looseUid': 'owner is $saUid',
          'key': 'lai_ab12cd34_0123456789abcdef',
          'google': 'AIzaSyA1234567890abcdefghijklmnopqrstuv',
          adminAUid: 'a uid used as a key',
        };

        final clean = LocalAiInventoryContext.scrubData(dirty);

        expect(clean, {
          'name': 'Ali Admin',
          'fine': 42,
          'nested': {
            'deep': [
              {'ok': true, 'photo': null},
              'plain text',
              null,
            ],
          },
          'table': {
            'sumOfAll': {'units': 12},
            'columns': ['name', 'units'],
            'rows': [
              ['Ali Admin', 3],
              [null, 4],
              [null, 5],
            ],
          },
        });
      },
    );

    test('the scrubber leaves ordinary inventory data alone', () {
      final data = {
        'assetId': 'IT-LAP-001',
        'serialNumber': 'SN-DL-5420-01',
        'name': 'Dell Latitude 5420',
        'date': '2026-09-28',
        'units': 1234567,
        'price': 150000.5,
        'bazaar': 'Township Bazaar',
      };
      expect(LocalAiInventoryContext.scrubData(data), data);
    });

    test('the scrubber caps the depth the server accepts', () {
      Object nest(int levels) => levels == 0 ? 'leaf' : {'n': nest(levels - 1)};

      var node = LocalAiInventoryContext.scrubData(nest(20));
      var depth = 0;
      while (node is Map) {
        node = node['n'];
        depth++;
      }
      expect(depth, lessThanOrEqualTo(6));
    });

    test(
      'a provider error is shortened and scrubbed before it becomes a note',
      () {
        expect(
          LocalAiInventoryContext.shortReason(
            '[cloud_firestore/permission-denied] The caller does not have permission.',
          ),
          'permission denied',
        );
        expect(
          LocalAiInventoryContext.shortReason(
            '[cloud_firestore/unavailable] Service down',
          ),
          'the database is unreachable',
        );
        expect(
          LocalAiInventoryContext.shortReason(
            'Exception: No profile for ali@psba.gov.pk',
          ),
          'No profile for [hidden]',
        );
        expect(
          LocalAiInventoryContext.shortReason('x' * 500).length,
          lessThanOrEqualTo(120),
        );
      },
    );
  });

  // ---------------------------------------------------------------------------
  // SIZE
  // ---------------------------------------------------------------------------

  group('Budget', () {
    late Org big;

    setUpAll(() {
      big = generateOrg(
        assets: 5000,
        bazaars: 60,
        moves: 20000,
        requestCount: 2000,
        users: 500,
      );
    });

    test('a large organisation fits 1600 tokens for every kind of question', () {
      final questions = [
        for (final (q, _) in examples) q,
        'Show me everything: damaged, under repair, lost, disposed, available, '
            'assigned, requests, users, departments, transfers in the last 30 '
            'days, warranty, value, each bazaar and the bazaar list',
        'Which warranties expire soon?',
        'What is the total value of our inventory?',
        'Which bazaars are disabled?',
        'Show approved transfer requests from last month',
        'Show all movements',
      ];

      for (final question in questions) {
        for (final role in ['super_admin', 'admin', 'user']) {
          final profile = role == 'user'
              ? big.people.firstWhere((p) => p.role == 'user')
              : big.people.firstWhere((p) => p.role == role);

          final context = LocalAiInventoryContext.build(
            LocalAiContextInputs(
              question: question,
              previousQuestion: question.contains('this asset')
                  ? 'Where is asset ABC-123?'
                  : null,
              askedForUid: profile.uid,
              signedInUid: profile.uid,
              role: role,
              profile: profile,
              snapshot: big.snapshot,
              requests: big.requests,
              people: big.people,
              retrievedAt: now,
              budgetTokens: 1600,
            ),
          ).context;

          expect(
            context.estimatedTokens,
            lessThanOrEqualTo(1600),
            reason: '$role: $question',
          );
          expect(
            LocalAiInventoryContext.appDataTokens(context),
            lessThanOrEqualTo(1600),
            reason: 'as the server measures it; $role: $question',
          );
          expect(
            titles(context),
            contains('Inventory totals'),
            reason: '$role: $question',
          );
          expect(context.sections.length, lessThanOrEqualTo(24));
          expect(context.notes.length, lessThanOrEqualTo(12));
          for (final note in context.notes) {
            expect(note.length, lessThanOrEqualTo(300));
          }
          for (final s in context.sections) {
            expect(s.title.length, inInclusiveRange(1, 120));
          }
        }
      }
    });

    test('shortened lists keep their real totals in the title', () {
      final context = LocalAiInventoryContext.build(
        LocalAiContextInputs(
          question: 'Show me damaged assets.',
          askedForUid: big.people.first.uid,
          signedInUid: big.people.first.uid,
          role: 'super_admin',
          profile: big.people.first,
          snapshot: big.snapshot,
          requests: big.requests,
          people: big.people,
          retrievedAt: now,
          budgetTokens: 1600,
        ),
      ).context;

      final damaged = big.assets
          .where(LocalAiInventoryContext.isDamaged)
          .toList();
      final section = sectionOf(context, 'Damaged assets');
      final shown = rowsOf(section).length;

      expect(
        section!.title,
        'Damaged assets (showing $shown of ${damaged.length})',
      );
      expect(shown, lessThan(damaged.length));
      expect(
        (dataOf(section)['sumOfAll'] as Map)['quantity'],
        damaged.fold<int>(0, (s, a) => s + a.quantity),
        reason: 'the sum covers every damaged record, not just the rows shown',
      );
    });

    test('the lowest-priority sections are left out first, and said to be', () {
      final context = LocalAiInventoryContext.build(
        LocalAiContextInputs(
          question:
              'Show me everything: damaged, under repair, lost, disposed, '
              'available, assigned, requests, users, departments, transfers, '
              'warranty, value, each bazaar and the bazaar list',
          askedForUid: big.people.first.uid,
          signedInUid: big.people.first.uid,
          role: 'super_admin',
          profile: big.people.first,
          snapshot: big.snapshot,
          requests: big.requests,
          people: big.people,
          retrievedAt: now,
          budgetTokens: 1600,
        ),
      ).context;

      final note = context.notes.firstWhere(
        (n) => n.startsWith('Left out to stay within size:'),
      );
      expect(note, isNotEmpty);
      expect(titles(context).first, 'Inventory totals');
      expect(context.estimatedTokens, lessThanOrEqualTo(1600));
    });

    test('the totals are kept even when nothing else fits', () {
      final context = ask(
        'Show me everything: damaged, requests, users, transfers',
        budget: 300,
      ).context;
      expect(titles(context), ['Inventory totals']);
    });

    test('a small question stays small', () {
      final context = ask('Show me damaged assets.').context;
      expect(context.estimatedTokens, lessThan(700));
    });

    test('the server\'s token estimate is reproduced exactly', () {
      // Expected values printed by the server's own estimateTokens
      // (shared/tokens.ts) under Node 24 for the same strings.
      const samples = {
        'What is our total inventory?': 9,
        '{"columns":["assetId","name","units"],"rows":[["ABC-123","Dell '
                'Latitude 5420",3],["LAP-002","HP ProBook 450 G8",12]],'
                '"sumOfAll":{"assetRecords":2,"units":15}}':
            107,
        '## Stock at each Bazaar (showing 3 of 20)\nScope: Asked by an '
                'Admin: all inventory.\nNotes:\n- The inventory was still '
                'loading.':
            51,
        'ہیڈ آفس میں کتنے لیپ ٹاپ ہیں؟ لیپ ٹاپ': 28,
        'token eyJhbGciOiJIUzI1NiJ9.eyJzdWIiOiIxMjM0NTY3ODkwIn0.abcDEF123 '
                'end':
            53,
        'नमस्ते दुनिया and 🧪 test 😀  two  spaces\n\n  indented': 32,
      };

      for (final entry in samples.entries) {
        expect(
          LocalAiInventoryContext.serverTokens(entry.key),
          entry.value,
          reason: entry.key,
        );
      }
    });

    test('number-heavy lists are fitted to the server\'s larger count', () {
      final org = generateOrg(
        assets: 120,
        bazaars: 20,
        moves: 300,
        requestCount: 40,
        users: 30,
      );
      final admin = org.people.firstWhere((p) => p.role == 'admin');

      final context = LocalAiInventoryContext.build(
        LocalAiContextInputs(
          question: 'Which assets were transferred?',
          askedForUid: admin.uid,
          signedInUid: admin.uid,
          role: 'admin',
          profile: admin,
          snapshot: org.snapshot,
          requests: org.requests,
          people: org.people,
          retrievedAt: now,
          budgetTokens: 2867,
        ),
      ).context;

      final server = LocalAiInventoryContext.appDataTokens(context);
      expect(server, lessThanOrEqualTo(2867));
      expect(
        server,
        greaterThan(context.estimatedTokens),
        reason: 'the seam\'s estimate alone would under-count this context',
      );
    });
  });

  // ---------------------------------------------------------------------------
  // FOLLOW-UPS
  // ---------------------------------------------------------------------------

  group('Follow-ups', () {
    test('"and at Head Office?" keeps the category of the question before', () {
      final context = ask(
        'and at Head Office?',
        previous: 'Show the current stock of laptops.',
      ).context;

      final section = sectionOf(context, 'Assets at Head Office - Laptop');
      expect(section!.title, 'Assets at Head Office - Laptop (showing 2 of 2)');
    });

    test('"aur iska status?" keeps the asset of the question before', () {
      final context = ask(
        'aur iska status?',
        previous: 'Where is asset ABC-123?',
      ).context;
      expect(sectionOf(context, 'Asset ABC-123'), isNotNull);
    });

    test('"and the monitors?" keeps the topic and takes the new category', () {
      final context = ask(
        'and the monitors?',
        previous: 'Show me damaged assets.',
      ).context;
      expect(
        sectionOf(context, 'Damaged assets - Monitor')!.title,
        'Damaged assets - Monitor (none)',
      );
    });

    test(
      'a question with its own topic does not borrow the previous asset',
      () {
        final context = ask(
          'How many assets are assigned?',
          previous: 'Where is asset ABC-123?',
        ).context;

        expect(sectionOf(context, 'Asset ABC-123'), isNull);
        expect(sectionOf(context, 'Assigned assets'), isNotNull);
      },
    );

    test('a question about people does not borrow the previous asset', () {
      final context = ask(
        'and how many users are there?',
        previous: 'Where is asset ABC-123?',
      ).context;

      expect(sectionOf(context, 'Asset ABC-123'), isNull);
      expect(sectionOf(context, 'User accounts, summary'), isNotNull);
    });

    test(
      'an overview question after an asset question is about everything',
      () {
        for (final question in [
          'What is our total inventory?',
          'How many assets do we have?',
        ]) {
          final result = ask(
            question,
            previous: 'Where is asset ABC-123?',
            rememberedAssetId: abc123.id,
          );

          expect(sectionOf(result.context, 'Asset ABC-123'), isNull);
          expect(sectionOf(result.context, 'Stock by category'), isNotNull);
          expect(sectionOf(result.context, 'Stock by status'), isNotNull);
          expect(result.focusAsset, isNull, reason: question);
        }
      },
    );

    test('an overview question after a people or request question borrows '
        'nothing', () {
      final afterPeople = ask(
        'What is our total inventory?',
        previous: 'How many users are there?',
        rememberedAssetId: abc123.id,
      ).context;
      expect(titles(afterPeople).where((t) => t.startsWith('User')), isEmpty);
      expect(sectionOf(afterPeople, 'Asset ABC-123'), isNull);

      expect(
        LocalAiInventoryContext.needsRequests(
          'What is our total inventory?',
          previousQuestion: 'Which requests are pending?',
        ),
        isFalse,
      );
    });

    test('"and the total?" still continues the question before', () {
      final context = ask(
        'and the total?',
        previous: 'Where is asset ABC-123?',
      ).context;
      expect(sectionOf(context, 'Asset ABC-123'), isNotNull);
    });

    test('a remembered asset answers "its warranty?" two questions later', () {
      final result = ask(
        'and its warranty?',
        previous: 'How many users are there?',
        rememberedAssetId: abc123.id,
      );

      final data = dataOf(sectionOf(result.context, 'Asset ABC-123'));
      expect(data['warrantyEnds'], '2027-01-10');
      expect(data['warrantyDaysLeft'], 103);
      expect(result.focusAsset, same(abc123));
    });

    test(
      'a remembered asset the account can no longer see is not brought back',
      () {
        final context = ask(
          'and its warranty?',
          rememberedAssetId: 'assetDocGone',
          snapshot: snapshotOf([lap002]),
        ).context;

        expect(titles(context).where((t) => t.startsWith('Asset ')), isEmpty);
      },
    );

    test('a remembered Bazaar answers "wahan kya hai?"', () {
      final result = ask('wahan kya hai?', rememberedBazaar: 'Township Bazaar');

      expect(sectionOf(result.context, 'Stock at Township Bazaar'), isNotNull);
      expect(result.focusBazaar, 'Township Bazaar');
    });

    test('the requests of a follow-up need the request listener', () {
      expect(
        LocalAiInventoryContext.needsRequests('Which requests are pending?'),
        isTrue,
      );
      expect(
        LocalAiInventoryContext.needsRequests(
          'and the approved ones?',
          previousQuestion: 'Show my requests',
        ),
        isTrue,
      );
      expect(
        LocalAiInventoryContext.needsRequests('How many laptops?'),
        isFalse,
      );
    });
  });

  // ---------------------------------------------------------------------------
  // LOADING AND FAILURE
  // ---------------------------------------------------------------------------

  group('Loading and failure notes', () {
    test('inventory still loading and nothing yet: no figures, a note', () {
      final context = ask(
        'What is our total inventory?',
        snapshot: snapshotOf(const [], loading: true),
        inventoryState: const LocalAiSourceState(loading: true),
      ).context;

      expect(
        titles(context),
        isNot(contains('Inventory totals')),
        reason: 'zero would be a confident wrong answer',
      );
      expect(context.notes.join(' '), contains('still loading'));
    });

    test(
      'inventory still loading with records already here: figures and a warning',
      () {
        final context = ask(
          'What is our total inventory?',
          inventoryState: const LocalAiSourceState(loading: true),
        ).context;

        expect(titles(context), contains('Inventory totals'));
        expect(context.notes.join(' '), contains('may be incomplete'));
      },
    );

    test('inventory failed: a short reason, never a crash', () {
      final context = ask(
        'What is our total inventory?',
        snapshot: snapshotOf(const []),
        inventoryState: const LocalAiSourceState(
          error:
              '[cloud_firestore/permission-denied] Missing or insufficient permissions.',
        ),
      ).context;

      expect(context.sections, isEmpty);
      expect(context.notes, [
        'The inventory could not be loaded: permission denied.',
      ]);
    });

    test('requests failed: "Requests could not be loaded: <reason>"', () {
      final context = ask(
        'Which requests are pending?',
        requestList: const [],
        requestState: const LocalAiSourceState(
          error:
              '[cloud_firestore/permission-denied] Missing or insufficient permissions.',
        ),
      ).context;

      expect(
        context.notes,
        contains('Requests could not be loaded: permission denied.'),
      );
      expect(titles(context).where((t) => t.contains('request')), isEmpty);
      expect(titles(context), contains('Inventory totals'));
    });

    test('movements still loading: no Bazaar figures, a note', () {
      final context = ask(
        'How many assets are in each Bazaar?',
        snapshot: snapshotOf(inventory, deployments: const []),
        movementState: const LocalAiSourceState(loading: true),
      ).context;

      expect(sectionOf(context, 'Stock at each Bazaar'), isNull);
      expect(
        context.notes.join(' '),
        contains('Transfers and Bazaar stock were still loading'),
      );
    });

    test('the user directory failed: a note instead of an empty list', () {
      final context = ask(
        'How many users are there?',
        people: const [],
        peopleState: const LocalAiSourceState(error: 'network-request-failed'),
      ).context;

      expect(titles(context).where((t) => t.startsWith('User')), isEmpty);
      expect(
        context.notes.join(' '),
        contains('user directory could not be loaded'),
      );
    });
  });

  // ---------------------------------------------------------------------------
  // THE SERVICE, ON THE REAL PROVIDERS
  // ---------------------------------------------------------------------------

  group('ProviderInventoryContextService', () {
    test(
      'answers an Admin from Firestore, through the providers, without identifiers',
      () async {
        final world = await World.signedInAs(adminAUid);
        addTearDown(world.dispose);

        final context = await world.ask('Where is asset ABC-123?');

        expect(context, isNotNull);
        final section = sectionOf(context!, 'Asset ABC-123');
        expect(dataOf(section)['heldBy'], 'Ayesha Khan');
        expect(
          dataOf(sectionOf(context, 'Inventory totals'))['assetRecords'],
          8,
        );
        expectNoIdentifiers(context);
      },
    );

    test(
      'starts each listener once, and the request listener only when asked',
      () async {
        final world = await World.signedInAs(adminAUid);
        addTearDown(world.dispose);

        await world.ask('How many assets are at Head Office?');

        expect(world.assetService.streams, 1);
        expect(world.bazaarService.streams, 1);
        expect(world.deploymentService.streams, 1);
        expect(
          world.requestService.streams,
          0,
          reason: 'nobody asked about requests',
        );

        await world.ask('Which requests are pending?');
        await world.ask(
          'And the approved ones?',
          previous: 'Which requests are pending?',
        );
        await world.ask('How many assets are in each Bazaar?');

        expect(world.assetService.streams, 1);
        expect(world.bazaarService.streams, 1);
        expect(
          world.deploymentService.streams,
          1,
          reason: 'the movement stream restarts on every listen call',
        );
        expect(world.requestService.streams, 1);
      },
    );

    test(
      'a User sees all inventory but only their own requests',
      () async {
        final world = await World.signedInAs(usmanUid);
        addTearDown(world.dispose);

        final totals = await world.ask('What is our total inventory?');
        // Every asset in the organisation, including the one owned by the
        // other Admin: the read is organisation-wide, the writes are not.
        // The seeded inventory holds 7 records plus BRV-777, the other
        // Admin's laptop, which a User used to be unable to see at all.
        expect(
          dataOf(sectionOf(totals!, 'Inventory totals'))['assetRecords'],
          8,
        );
        final laptops = rowsOf(
          sectionOf(totals, 'Stock by category'),
        ).firstWhere((row) => row['category'] == 'Laptop');
        expect(laptops['records'], 3);

        final matching = await world.ask('Show me the laptops');
        expect(wire(matching!), contains('BRV-777'));

        expect(totals.scope, startsWith('Asked by a User'));

        final pending = await world.ask('Which requests are pending?');
        final section = sectionOf(pending!, 'Your pending requests');
        expect(rowsOf(section).single['type'], 'Transfer');

        final people = await world.ask('How many users are there?');
        expect(titles(people!).where((t) => t.startsWith('User')), isEmpty);
        expectNoIdentifiers(people);
      },
    );

    test('nobody signed in: null', () async {
      final world = await World.signedInAs(null);
      addTearDown(world.dispose);

      expect(
        await world.ask('What is our total inventory?', uid: null),
        isNull,
      );
      expect(
        await world.ask('What is our total inventory?', uid: adminAUid),
        isNull,
      );
    });

    test(
      'asked for another account than the signed-in one: no data, a note',
      () async {
        final world = await World.signedInAs(adminAUid);
        addTearDown(world.dispose);

        final context = await world.ask(
          'What is our total inventory?',
          uid: usmanUid,
        );
        expect(context!.sections, isEmpty);
        expect(context.notes.single, contains('signed-in account changed'));
      },
    );

    test(
      'a disabled account: no data, a note, and no listener started',
      () async {
        final world = await World.signedInAs(
          adminAUid,
          profileOverride: {'status': 'disabled'},
        );
        addTearDown(world.dispose);

        final context = await world.ask('What is our total inventory?');
        expect(context!.sections, isEmpty);
        expect(context.notes.single, contains('not active'));
        expect(world.assetService.streams, 0);
        expect(world.deploymentService.streams, 0);
      },
    );

    test('a refused request stream becomes a note, not a crash', () async {
      final world = await World.signedInAs(adminAUid, deniedRequests: true);
      addTearDown(world.dispose);

      final context = await world.ask('Which requests are pending?');
      expect(
        context!.notes,
        contains('Requests could not be loaded: permission denied.'),
      );
      expect(titles(context), contains('Inventory totals'));
    });

    test(
      'a movement stream that never answers is waited on, then reported',
      () async {
        final world = await World.signedInAs(adminAUid, silentMovements: true);
        addTearDown(world.dispose);

        final watch = Stopwatch()..start();
        final context = await world.ask('How many assets are in each Bazaar?');

        expect(watch.elapsed, lessThan(const Duration(seconds: 5)));
        expect(sectionOf(context!, 'Stock at each Bazaar'), isNull);
        expect(context.notes.join(' '), contains('still loading'));
      },
    );

    test(
      'an emptied movement listener is restarted after signing in again',
      () async {
        final world = await World.signedInAs(adminAUid);
        addTearDown(world.dispose);

        await world.ask('How many assets are in each Bazaar?');
        expect(world.deploymentService.streams, 1);

        // Sign-out clears the provider (app.dart), and the same account signs
        // back in, without anyone calling reset().
        await world.auth.signOut();
        world.deployments.clear();
        await world.auth.signInWithEmailAndPassword(
          email: 'ali.admin@psba.gov.pk',
          password: 'x',
        );

        final loaded = Stopwatch()..start();
        while (!world.users.hasLoadedCurrentUser &&
            loaded.elapsed < const Duration(seconds: 3)) {
          await Future<void>.delayed(const Duration(milliseconds: 10));
        }

        final context = await world.ask('How many assets are in each Bazaar?');

        expect(world.deploymentService.streams, 2);
        final rows = {
          for (final r in rowsOf(sectionOf(context!, 'Stock at each Bazaar')))
            r['bazaar']: r['units'],
        };
        expect(
          rows['Township Bazaar'],
          11,
          reason: 'an emptied provider is not "no movements"',
        );
      },
    );

    test('reset() forgets what the conversation was about', () async {
      final world = await World.signedInAs(adminAUid);
      addTearDown(world.dispose);

      await world.ask('Where is asset ABC-123?');

      final remembered = await world.ask('and its warranty?');
      expect(sectionOf(remembered!, 'Asset ABC-123'), isNotNull);

      world.service.reset();

      final forgotten = await world.ask('and its warranty?');
      expect(sectionOf(forgotten!, 'Asset ABC-123'), isNull);
    });
  });

  // ---------------------------------------------------------------------------
  // THE SIZE OF A REAL CONTEXT
  // ---------------------------------------------------------------------------

  test(
    'a realistic organisation: every example fits the server\'s default room',
    () {
      final org = generateOrg(
        assets: 120,
        bazaars: 20,
        moves: 300,
        requestCount: 40,
        users: 30,
      );
      final admin = org.people.firstWhere((p) => p.role == 'admin');
      final report = StringBuffer(
        '\nTokens per example, server measure / estimatedTokens (120 assets, '
        '20 Bazaars, ${org.movements.length} movements, 40 requests, 30 '
        'users; Admin; budget 2867):\n',
      );

      for (final (question, previous) in examples) {
        final context = LocalAiInventoryContext.build(
          LocalAiContextInputs(
            question: question,
            previousQuestion: previous,
            askedForUid: admin.uid,
            signedInUid: admin.uid,
            role: 'admin',
            profile: admin,
            snapshot: org.snapshot,
            requests: org.requests,
            people: org.people,
            retrievedAt: now,
            budgetTokens: 2867,
          ),
        ).context;

        final server = LocalAiInventoryContext.appDataTokens(context);
        expect(
          context.estimatedTokens,
          lessThanOrEqualTo(2867),
          reason: question,
        );
        expect(server, lessThanOrEqualTo(2867), reason: question);
        expect(titles(context).first, 'Inventory totals', reason: question);
        report.writeln(
          '  ${server.toString().padLeft(5)} / '
          '${context.estimatedTokens.toString().padLeft(5)}  '
          '${context.sections.length} sections  $question',
        );
      }

      // Printed on request only, to size the budget without cluttering a run:
      // LOCAL_AI_TOKEN_REPORT=1 flutter test test/local_ai_context_test.dart
      if (Platform.environment['LOCAL_AI_TOKEN_REPORT'] == '1') {
        debugPrint(report.toString());
      }
    },
  );
}
