// Tests for the natural-language layer of the AI Assistant.
//
// The language model itself is not exercised here - it lives behind a Cloud
// Function and there is no network in `flutter test`. What IS exercised is the
// half of the contract this app is responsible for, which is the half that
// matters for safety: given whatever a model claims a sentence meant, the app
// must resolve, re-check and constrain it entirely on its own.
//
// So each case below states a real sentence a user might type - in English,
// Urdu script, Roman Urdu, in someone's own phrasing - together with the intent
// a model would plausibly return for it, and asserts what the deterministic
// planner then does with it. The model's reading is treated throughout as what
// it is: an untrusted hint.

import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';

import 'package:it_management_system/core/ai/action_planner.dart';
import 'package:it_management_system/core/ai/ai_assistant_panel.dart' show shouldActOnPlan;
import 'package:it_management_system/core/ai/assistant_actions.dart';
import 'package:it_management_system/core/ai/inventory_assistant.dart';
import 'package:it_management_system/core/services/bazaar_service.dart';
import 'package:it_management_system/models/asset_model.dart';
import 'package:it_management_system/models/deployment_model.dart';
import 'package:it_management_system/models/user_model.dart';

// ---------------------------------------------------------------------------
// FIXTURES
// ---------------------------------------------------------------------------

const superAdmin = AssistantPermissions(
  role: 'super_admin',
  uid: 'sa-1',
  displayName: 'Sara Super',
);

const normalUser = AssistantPermissions(
  role: 'user',
  uid: 'us-1',
  displayName: 'Usman User',
);

const people = [
  UserModel(
    uid: 'us-1',
    name: 'Usman User',
    email: 'usman@test.local',
    role: 'user',
    status: 'active',
  ),
  UserModel(
    uid: 'us-2',
    name: 'Ayesha Khan',
    email: 'ayesha@test.local',
    role: 'user',
    status: 'active',
  ),
];

AssetModel asset({
  String id = 'asset-1',
  String assetId = 'IT-LAP-001',
  String name = 'Dell Latitude 5420',
  String category = 'Laptop',
  String condition = 'Good',
  String status = 'Available',
  int quantity = 100,
  int headOffice = 60,
  int assigned = 0,
  int deployed = 40,
  double price = 1000,
  String brand = 'Dell',
  String? assignedTo,
  int warrantyMonths = 0,
  DateTime? purchaseDate,
}) {
  return AssetModel(
    id: id,
    assetId: assetId,
    name: name,
    category: category,
    status: status,
    condition: condition,
    quantity: quantity,
    headOfficeQuantity: headOffice,
    assignedQuantity: assigned,
    deployedQuantity: deployed,
    brand: brand,
    assignedTo: assignedTo,
    adminId: 'ad-1',
    purchasePrice: price,
    location: 'Head Office',
    warrantyMonths: warrantyMonths,
    purchaseDate: purchaseDate,
  );
}

BazaarModel bazaar(String id, String name, {bool active = true}) =>
    BazaarModel(id: id, name: name, location: 'Lahore', isActive: active);

DeploymentModel movement({
  String bazaarId = 'b1',
  String bazaarName = 'Township Bazaar',
  int quantity = 40,
  String status = 'Active',
  String assetId = 'IT-LAP-001',
  String assetName = 'Dell Latitude 5420',
  String assetDocumentId = 'asset-1',
  DateTime? date,
}) {
  return DeploymentModel(
    id: 'mv-$bazaarId-$assetId-$quantity',
    assetDocumentId: assetDocumentId,
    assetId: assetId,
    assetName: assetName,
    assetType: 'Laptop',
    serialNumber: '',
    action: 'Transfer',
    fromLocation: 'Head Office',
    toLocation: bazaarName,
    toBazaarId: bazaarId,
    toBazaarName: bazaarName,
    quantity: quantity,
    sentBy: 'ad-1',
    sentByName: 'Adeel Admin',
    deploymentDate: date ?? DateTime(2026, 1, 1),
    status: status,
    createdAt: date ?? DateTime(2026, 1, 1),
  );
}

InventorySnapshot snapshot({
  List<AssetModel>? assets,
  List<BazaarModel>? bazaars,
  List<DeploymentModel>? deployments,
  Map<String, String> holders = const <String, String>{},
}) {
  final items = assets ?? [asset()];

  return InventorySnapshot(
    assets: items,
    bazaars: bazaars ??
        [
          bazaar('b1', 'Township Bazaar'),
          bazaar('b2', 'Model Town Bazaar'),
          bazaar('b3', 'Old Anarkali Bazaar', active: false),
        ],
    deployments: deployments ?? [movement()],
    totalQuantity: items.fold(0, (sum, a) => sum + a.quantity),
    headOfficeStock:
        items.fold(0, (sum, a) => sum + a.calculatedHeadOfficeQuantity),
    assignedQuantity:
        items.fold(0, (sum, a) => sum + a.calculatedAssignedQuantity),
    bazaarQuantity:
        items.fold(0, (sum, a) => sum + a.calculatedDeployedQuantity),
    damagedQuantity: 0,
    underRepairQuantity: 0,
    lostQuantity: 0,
    disposedQuantity: 0,
    unavailableAtHeadOffice: 0,
    totalInventoryValue:
        items.fold(0, (sum, a) => sum + a.purchasePrice * a.quantity),
    roleLabel: 'Super Admin',
    scopeNote: '',
    holders: holders,
  );
}

/// The intent a language model returns for a sentence.
AssistantIntent intent(
  String kind, {
  String assetRef = '',
  int? quantity,
  String from = '',
  String to = '',
  String person = '',
  String status = '',
  String bazaarName = '',
  String screen = '',
  Map<String, dynamic> newAsset = const <String, dynamic>{},
}) {
  return AssistantIntent(
    kind: kind,
    assetRef: assetRef,
    quantity: quantity,
    fromLocation: from,
    toLocation: to,
    personName: person,
    status: status,
    bazaarName: bazaarName,
    screen: screen,
    newAsset: newAsset,
  );
}

void main() {
  late ActionPlanner planner;

  setUp(() => planner = ActionPlanner());

  ActionPlan? planIntent(
    AssistantIntent value, {
    InventorySnapshot? data,
    AssistantPermissions who = superAdmin,
    List<UserModel> staff = people,
  }) {
    return planner.planFromIntent(
      value,
      data ?? snapshot(),
      who,
      people: staff,
    );
  }

  // =========================================================================
  // NATURAL SENTENCES, IN EVERY LANGUAGE THE APP SUPPORTS
  //
  // The sentence is what the user typed; the intent is what a model reports
  // it to mean. The assertion is on what the app does about it.
  // =========================================================================

  group('instructions in the user\'s own words become checked proposals', () {
    final cases = <({String sentence, AssistantIntent read, AssistantActionKind kind})>[
      // Plain English, imperative.
      (
        sentence: 'Send 10 laptops to Township Bazaar',
        read: intent('sendToBazaar',
            assetRef: 'IT-LAP-001', quantity: 10, to: 'Township Bazaar'),
        kind: AssistantActionKind.sendToBazaar,
      ),
      // English, polite and indirect - no imperative verb at all.
      (
        sentence: 'Could you please arrange for ten of the Dell laptops to go '
            'out to Township?',
        read: intent('sendToBazaar',
            assetRef: 'Dell Latitude 5420', quantity: 10, to: 'Township Bazaar'),
        kind: AssistantActionKind.sendToBazaar,
      ),
      // Roman Urdu.
      (
        sentence: 'Township Bazaar mein 5 laptop bhej do',
        read: intent('sendToBazaar',
            assetRef: 'IT-LAP-001', quantity: 5, to: 'Township Bazaar'),
        kind: AssistantActionKind.sendToBazaar,
      ),
      // Urdu script.
      (
        sentence: 'ٹاؤن شپ بازار میں پانچ لیپ ٹاپ بھیج دیں',
        read: intent('sendToBazaar',
            assetRef: 'IT-LAP-001', quantity: 5, to: 'Township Bazaar'),
        kind: AssistantActionKind.sendToBazaar,
      ),
      // Bazaar to Bazaar, stated back to front.
      (
        sentence: 'From Township, move 15 over to Model Town please',
        read: intent('moveBetweenBazaars',
            assetRef: 'IT-LAP-001',
            quantity: 15,
            from: 'Township Bazaar',
            to: 'Model Town Bazaar'),
        kind: AssistantActionKind.moveBetweenBazaars,
      ),
      // Return, Roman Urdu, different verb.
      (
        sentence: 'Township se 10 wapas manga lo',
        read: intent('returnToHeadOffice',
            assetRef: 'IT-LAP-001', quantity: 10, from: 'Township Bazaar'),
        kind: AssistantActionKind.returnToHeadOffice,
      ),
      // Assign, by first name only.
      (
        sentence: 'give the Dell to Ayesha',
        read: intent('assign', assetRef: 'IT-LAP-001', person: 'Ayesha Khan'),
        kind: AssistantActionKind.assign,
      ),
      // Unassign, colloquial.
      (
        sentence: 'take that laptop back off her',
        read: intent('unassign', assetRef: 'IT-LAP-001'),
        kind: AssistantActionKind.unassign,
      ),
      // Status, Roman Urdu synonym ("kharab" = broken).
      (
        sentence: 'ye laptop kharab hai, mark kar do',
        read: intent('updateStatus', assetRef: 'IT-LAP-001', status: 'Damaged'),
        kind: AssistantActionKind.updateStatus,
      ),
      // Add stock, phrased as a receipt rather than a command.
      (
        sentence: 'we just received 25 more of these',
        read: intent('addStock', assetRef: 'IT-LAP-001', quantity: 25),
        kind: AssistantActionKind.addStock,
      ),
    ];

    for (final c in cases) {
      test('"${c.sentence}" -> ${c.kind.name}', () {
        final data = snapshot(
          assets: [asset(assignedTo: 'us-2', assigned: 10, headOffice: 50)],
        );

        final plan = planIntent(c.read, data: data);

        expect(plan, isNotNull, reason: c.sentence);
        expect(plan!.isProposal, isTrue, reason: '${plan.message}\n${c.sentence}');
        expect(plan.action!.kind, c.kind, reason: c.sentence);
      });
    }
  });

  group('the details come from the database, never from the model', () {
    test('a transfer is priced, sourced and counted from the snapshot', () {
      final plan = planIntent(intent('sendToBazaar',
          assetRef: 'IT-LAP-001', quantity: 10, to: 'Township Bazaar'))!;

      final action = plan.action!;
      expect(action.asset!.id, 'asset-1');
      expect(action.quantity, 10);
      expect(action.sourceName, 'Head Office');
      expect(action.sourceId, isEmpty);
      expect(action.destinationName, 'Township Bazaar');
      expect(action.destinationId, 'b1');
      expect(action.details, contains('Available at Head Office: 60 units'));
    });

    test('a return reads the real stock at that Bazaar', () {
      final plan = planIntent(intent('returnToHeadOffice',
          assetRef: 'IT-LAP-001', quantity: 40, from: 'Township Bazaar'))!;

      expect(plan.isProposal, isTrue);
      expect(plan.action!.sourceId, 'b1');
      expect(plan.action!.destinationName, 'Head Office');
    });

    test('the person is resolved to a real account, not to the typed name', () {
      final plan = planIntent(
        intent('assign', assetRef: 'IT-LAP-001', person: 'Ayesha Khan'),
      )!;

      expect(plan.action!.assigneeUid, 'us-2');
      expect(plan.action!.assigneeName, 'Ayesha Khan');
    });
  });

  // =========================================================================
  // THE MODEL IS NOT BELIEVED
  // =========================================================================

  group('a model suggestion is re-checked, never taken on trust', () {
    test('more units than exist is refused with the real figure', () {
      final plan = planIntent(intent('sendToBazaar',
          assetRef: 'IT-LAP-001', quantity: 5000, to: 'Township Bazaar'))!;

      expect(plan.isProposal, isFalse);
      expect(plan.message, contains('only has 60 units'));
    });

    test('stock that is not at the named Bazaar is refused', () {
      final plan = planIntent(intent('returnToHeadOffice',
          assetRef: 'IT-LAP-001', quantity: 5, from: 'Model Town Bazaar'))!;

      expect(plan.isProposal, isFalse);
      expect(plan.message, contains('no stock'));
    });

    test('a disabled Bazaar is refused as a destination', () {
      final plan = planIntent(intent('sendToBazaar',
          assetRef: 'IT-LAP-001', quantity: 5, to: 'Old Anarkali Bazaar'))!;

      expect(plan.isProposal, isFalse);
      expect(plan.message, contains('is disabled'));
    });

    test('an asset the account cannot see is asked about, never invented', () {
      final plan = planIntent(intent('updateStatus',
          assetRef: 'IT-SRV-999', status: 'Damaged'))!;

      expect(plan.isProposal, isFalse);
      expect(plan.message, contains('Which asset'));
    });

    test('a Bazaar the app does not have is asked about', () {
      final plan = planIntent(intent('sendToBazaar',
          assetRef: 'IT-LAP-001', quantity: 5, to: 'Narnia Bazaar'))!;

      expect(plan.isProposal, isFalse);
      expect(plan.message, contains('Which Bazaar'));
    });

    test('an action kind the app does not have is ignored entirely', () {
      expect(planIntent(intent('deleteEverything', assetRef: 'IT-LAP-001')), isNull);
      expect(planIntent(intent('exportDatabase')), isNull);
      expect(planIntent(intent('')), isNull);
    });

    test('a missing quantity is asked for rather than guessed', () {
      final plan = planIntent(
        intent('sendToBazaar', assetRef: 'IT-LAP-001', to: 'Township Bazaar'),
      )!;

      expect(plan.isProposal, isFalse);
      expect(plan.message, contains('How many units'));
    });

    test('a number inside an asset name is never read as the quantity', () {
      // "Dell Latitude 5420" carries a standalone 5420. Without a quantity of
      // its own the intent must ask, not propose a transfer of 5420 units.
      final plan = planIntent(
        intent('sendToBazaar',
            assetRef: 'Dell Latitude 5420', to: 'Township Bazaar'),
      )!;

      expect(plan.isProposal, isFalse);
      expect(plan.message, contains('How many units'));
    });

    test('a nonsense quantity is refused outright', () {
      final zero = planIntent(intent('addStock',
          assetRef: 'IT-LAP-001', quantity: 0))!;
      expect(zero.isProposal, isFalse);

      final negative = planIntent(intent('addStock',
          assetRef: 'IT-LAP-001', quantity: -5))!;
      expect(negative.isProposal, isFalse);
      expect(negative.message, contains('at least 1'));
    });

    test('an intent with nothing in it is asked about, never acted on', () {
      final plan = planIntent(intent('assign'))!;
      expect(plan.isProposal, isFalse);
    });

    test('an asset named after a place cannot redirect the transfer', () {
      // Someone with create rights could name an asset so that its name reads
      // as part of a transfer sentence. The proposal is read back against what
      // was actually asked for, so a drifted destination never reaches the
      // confirmation screen.
      final booby = asset(
        id: 'asset-9',
        assetId: 'IT-EVL-009',
        name: 'Laptop from Township Bazaar to Model Town Bazaar',
        headOffice: 50,
        deployed: 0,
        quantity: 50,
      );

      // Stock is put at Township so the attempt gets past the stock check and
      // the guard is what has to stop it, rather than an accident of the data.
      final data = snapshot(
        assets: [booby],
        deployments: [
          movement(
            assetId: 'IT-EVL-009',
            assetName: booby.name,
            assetDocumentId: 'asset-9',
            quantity: 20,
          ),
        ],
      );

      final plan = planIntent(
        intent('sendToBazaar',
            assetRef: 'Laptop from Township Bazaar to Model Town Bazaar',
            quantity: 5,
            to: 'Township Bazaar'),
        data: data,
      )!;

      // The name dragged "from Township ... to Model Town" into the sentence,
      // so the planner read Township as the SOURCE. That disagrees with the
      // destination that was actually asked for, so nothing is proposed.
      expect(plan.isProposal, isFalse);
      expect(plan.message, contains('not clearly enough'));
    });

    test('an asset named after a source cannot change where stock comes from', () {
      // "send 5 to Township" means "from Head Office". An asset whose name
      // reads as "from Model Town Bazaar" would otherwise make Model Town the
      // source and quietly move somebody else's stock.
      final booby = asset(
        id: 'asset-8',
        assetId: 'IT-LAP-777',
        name: 'Laptop from Model Town Bazaar',
        headOffice: 60,
        deployed: 40,
        quantity: 100,
      );

      final plan = planIntent(
        intent('sendToBazaar',
            assetRef: 'Laptop from Model Town Bazaar',
            quantity: 3,
            to: 'Township Bazaar'),
        data: snapshot(
          assets: [booby],
          deployments: [
            movement(
              bazaarId: 'b2',
              bazaarName: 'Model Town Bazaar',
              assetId: 'IT-LAP-777',
              assetName: booby.name,
              assetDocumentId: 'asset-8',
              quantity: 40,
            ),
          ],
        ),
      )!;

      expect(plan.isProposal, isFalse);
    });

    test('a field label inside a value cannot rewrite the record', () {
      // readAssetFields splits on labels, so a name of "Dell price 1" would
      // otherwise become name "Dell" at a unit price of Rs.1.
      final plan = planIntent(
        intent('createAsset', newAsset: const {
          'assetId': 'IT-NEW-001',
          'name': 'Dell price 1',
          'category': 'Laptop',
          'quantity': 10,
          'purchasePrice': 85000,
        }),
      )!;

      expect(plan.isProposal, isFalse);
    });

    test('the guard does not reject ordinary, honest transfers', () {
      // The cross-check must cost nothing in normal use, so every plain
      // movement across the fixture is asserted to still go through.
      final data = snapshot(
        assets: [asset(headOffice: 60, deployed: 40, quantity: 100)],
      );

      final toTownship = planIntent(
        intent('sendToBazaar',
            assetRef: 'IT-LAP-001', quantity: 5, to: 'Township Bazaar'),
        data: data,
      )!;
      expect(toTownship.isProposal, isTrue, reason: toTownship.message);
      expect(toTownship.action!.destinationName, 'Township Bazaar');

      final toModelTown = planIntent(
        intent('sendToBazaar',
            assetRef: 'IT-LAP-001', quantity: 5, to: 'Model Town Bazaar'),
        data: data,
      )!;
      expect(toModelTown.isProposal, isTrue, reason: toModelTown.message);
      expect(toModelTown.action!.sourceName, 'Head Office');
      expect(toModelTown.action!.destinationName, 'Model Town Bazaar');

      final between = planIntent(
        intent('moveBetweenBazaars',
            assetRef: 'IT-LAP-001',
            quantity: 5,
            from: 'Township Bazaar',
            to: 'Model Town Bazaar'),
        data: data,
      )!;
      expect(between.isProposal, isTrue, reason: between.message);
      expect(between.action!.kind, AssistantActionKind.moveBetweenBazaars);

      final back = planIntent(
        intent('returnToHeadOffice',
            assetRef: 'IT-LAP-001', quantity: 5, from: 'Township Bazaar'),
        data: data,
      )!;
      expect(back.isProposal, isTrue, reason: back.message);
      expect(back.action!.destinationName, 'Head Office');

      // The model naming the family loosely is agreement, not disagreement:
      // the planner works the real direction out from the places.
      final loose = planIntent(
        intent('sendToBazaar',
            assetRef: 'IT-LAP-001',
            quantity: 5,
            from: 'Township Bazaar',
            to: 'Model Town Bazaar'),
        data: data,
      )!;
      expect(loose.isProposal, isTrue, reason: loose.message);
      expect(loose.action!.kind, AssistantActionKind.moveBetweenBazaars);
    });

    test('an honest createAsset still goes through the cross-check', () {
      final plan = planIntent(
        intent('createAsset', newAsset: const {
          'assetId': 'IT-SW-010',
          'name': 'Cisco Catalyst Switch',
          'category': 'Switch',
          'quantity': 5,
          'purchasePrice': 45000,
          'model': '2960X',
        }),
      )!;

      expect(plan.isProposal, isTrue, reason: plan.message);
      expect(plan.action!.draft!.purchasePrice, 45000);
      expect(plan.action!.draft!.model, '2960X');
    });

    test('a status word inside an asset name cannot change the status set', () {
      // "Repair Bench PC" contains "repair", which is a longer status word
      // than "lost", so the planner would otherwise set Under Repair.
      final bench = asset(
        id: 'asset-7',
        assetId: 'IT-PC-070',
        name: 'Repair Bench PC',
        status: 'Available',
        deployed: 0,
        headOffice: 100,
      );

      final plan = planIntent(
        intent('updateStatus', assetRef: 'Repair Bench PC', status: 'Lost'),
        data: snapshot(assets: [bench], deployments: const []),
      )!;

      expect(plan.isProposal, isFalse);
    });

    test('a Roman Urdu status word resolves to the status it means', () {
      final plan = planIntent(
        intent('updateStatus', assetRef: 'IT-LAP-001', status: 'kharab'),
      )!;

      expect(plan.isProposal, isTrue);
      expect(plan.action!.status, 'Damaged');
    });

    test('a status the app has no word for is refused, not guessed at', () {
      // The model is told the five statuses by name. If it goes off script the
      // planner cannot have got its status from that word, so whatever it did
      // settle on came from somewhere else in the sentence.
      final plan = planIntent(
        intent('updateStatus',
            assetRef: 'IT-LAP-001', status: 'beyond economical repair'),
      )!;

      expect(plan.isProposal, isFalse);
    });

    test('a destination nobody named is asked for, not taken from a name', () {
      // "Township Bazaar Printer" carries a Bazaar name. With no destination
      // given, the right outcome is the planner's question.
      final printer = asset(
        id: 'asset-6',
        assetId: 'IT-PRN-009',
        name: 'Township Bazaar Printer',
        headOffice: 50,
        deployed: 0,
        quantity: 50,
      );

      final plan = planIntent(
        intent('sendToBazaar',
            assetRef: 'Township Bazaar Printer', quantity: 3),
        data: snapshot(assets: [printer], deployments: const []),
      )!;

      expect(plan.isProposal, isFalse);
    });

    test('a field the model never mentioned cannot appear on the new asset', () {
      // "serial" is a field label, so a note mentioning it would otherwise
      // become the serial number of the asset being created.
      final plan = planIntent(
        intent('createAsset', newAsset: const {
          'assetId': 'IT-PRN-020',
          'name': 'HP LaserJet 1020',
          'category': 'Printer',
          'quantity': 2,
          'purchasePrice': 30000,
          'notes': 'serial to be confirmed by vendor',
        }),
      )!;

      expect(plan.isProposal, isFalse);
    });

    test('an assign with nobody named asks who, and never picks someone', () {
      // The canonical sentence still carries the asset's own name, and a
      // person whose name appears in it must not become the recipient.
      final named = asset(
        id: 'asset-5',
        assetId: 'IT-LAP-009',
        name: 'Usman Laptop',
        deployed: 0,
        headOffice: 100,
      );

      final plan = planIntent(
        intent('assign', assetRef: 'Usman Laptop'),
        data: snapshot(assets: [named], deployments: const []),
      )!;

      expect(plan.isProposal, isFalse);
      expect(plan.message, contains('Who should I assign it to'));
    });

    test('a Bazaar is created under the name that was actually asked for', () {
      final plan = planIntent(
        intent('createBazaar', bazaarName: 'Shahdara Bazaar'),
      )!;

      expect(plan.isProposal, isTrue, reason: plan.message);
      expect(plan.action!.subjectName, 'Shahdara Bazaar');
    });

    test('a quote in a Bazaar name cannot cut the name short', () {
      // The planner reads the name out of the first quoted run, so an embedded
      // quote would otherwise end it early and create "Foo" instead.
      final plan = planIntent(
        intent('createBazaar', bazaarName: 'Foo" and "Bar'),
      )!;

      if (plan.isProposal) {
        expect(plan.action!.subjectName, isNot('Foo'));
      }
    });

    test('disabling resolves to the Bazaar that was named, or not at all', () {
      final right = planIntent(
        intent('disableBazaar', bazaarName: 'Township Bazaar'),
      )!;
      expect(right.isProposal || right.message.isNotEmpty, isTrue);
      if (right.isProposal) {
        expect(right.action!.subjectName, 'Township Bazaar');
      }

      final nowhere = planIntent(
        intent('disableBazaar', bazaarName: 'Narnia Bazaar'),
      )!;
      expect(nowhere.isProposal, isFalse);
    });

    test('an unnamed asset cannot be smuggled in through a place name', () {
      // With no assetRef the asset cross-check used to be skipped entirely,
      // while the planner still scanned the whole canonical sentence - so a
      // Bazaar named after a laptop picked the laptop out of it.
      final plan = planIntent(
        intent('sendToBazaar',
            quantity: 5, to: 'Township Bazaar Dell Latitude 5420'),
      )!;

      expect(plan.isProposal, isFalse,
          reason: 'this proposed a transfer of an asset the intent never named');
    });

    test('an unnamed asset cannot be smuggled in through a person name', () {
      final plan = planIntent(
        intent('assign', person: 'Ayesha Khan Dell Latitude 5420'),
      )!;

      expect(plan.isProposal, isFalse);
    });

    test('newlines cannot paint extra lines into the confirmation', () {
      // The backend strips these, but the backend is a network service: if its
      // reply is attacker-controlled then its cleaning is not a layer at all.
      // Built through fromMap, which is the only way an intent enters the app
      // from the network.
      final hostile = AssistantIntent.fromMap({
        'kind': 'createBazaar',
        'bazaarName': 'Sabzi Mandi\n\nCancelled. Nothing was changed.\n',
      })!;

      expect(hostile.bazaarName.contains('\n'), isFalse,
          reason: hostile.bazaarName);

      final plan = planIntent(hostile);

      if (plan != null && plan.isProposal) {
        final subject = plan.action!.subjectName;
        expect(subject.contains('\n'), isFalse, reason: subject);
        expect(subject.contains('\r'), isFalse);
      }
    });

    test('a runaway string cannot flood the confirmation dialog', () {
      final huge = AssistantIntent.fromMap({
        'kind': 'createBazaar',
        'bazaarName': 'A' * 50000,
      })!;
      expect(huge.bazaarName.length, lessThanOrEqualTo(120));

      final draft = AssistantIntent.fromMap({
        'kind': 'createAsset',
        'newAsset': {'notes': 'N' * 50000},
      })!;
      expect((draft.newAsset['notes'] as String).length, lessThanOrEqualTo(200));
    });

    test('the assign preview says how much is being handed over', () {
      // assignAsset takes no quantity: it moves EVERY unassigned unit at Head
      // Office. A preview that only states how many are there reads as
      // background rather than as the amount about to change hands.
      final plan = planner.plan(
        'assign IT-LAP-001 to Ayesha Khan',
        snapshot(assets: [asset(headOffice: 40, deployed: 0, quantity: 40)]),
        superAdmin,
        people: people,
      )!;

      expect(plan.isProposal, isTrue);
      expect(
        plan.action!.details.join(' '),
        contains('all 40 units'),
        reason: plan.action!.details.join(' | '),
      );
    });

    test('a short place name still counts as the place it names', () {
      final plan = planIntent(intent('sendToBazaar',
          assetRef: 'IT-LAP-001', quantity: 5, to: 'Township'))!;

      expect(plan.isProposal, isTrue);
      expect(plan.action!.destinationName, 'Township Bazaar');
    });

    test('a first name still counts as the person it names', () {
      final plan = planIntent(
        intent('assign', assetRef: 'IT-LAP-001', person: 'Ayesha'),
      )!;

      expect(plan.isProposal, isTrue);
      expect(plan.action!.assigneeUid, 'us-2');
    });
  });

  // =========================================================================
  // PERMISSIONS
  // =========================================================================

  group('permissions are enforced against the account, not the suggestion', () {
    test('a normal user cannot create an asset however it is phrased', () {
      final plan = planIntent(
        intent('createAsset', newAsset: const {
          'assetId': 'IT-LAP-777',
          'name': 'New Laptop',
          'category': 'Laptop',
          'quantity': 5,
          'purchasePrice': 1000,
        }),
        who: normalUser,
      )!;

      expect(plan.isProposal, isFalse);
      expect(plan.message.toLowerCase(), contains('only an admin or super admin'));
    });

    test('a normal user cannot disable a Bazaar', () {
      final plan = planIntent(
        intent('disableBazaar', bazaarName: 'Township Bazaar'),
        who: normalUser,
      )!;

      expect(plan.isProposal, isFalse);
    });

    test('a normal user\'s transfer becomes a request for an Admin', () {
      final plan = planIntent(
        intent('sendToBazaar',
            assetRef: 'IT-LAP-001', quantity: 5, to: 'Township Bazaar'),
        who: normalUser,
      )!;

      expect(plan.isProposal, isTrue);
      expect(plan.action!.viaRequest, isTrue);
      expect(plan.action!.confirmLabel, 'Send request');
    });

    test('the capability hint matches what the role may actually propose', () {
      expect(
        superAdmin.assistantCapabilities,
        containsAll(<String>['createAsset', 'createBazaar', 'disableBazaar']),
      );
      expect(normalUser.assistantCapabilities, isNot(contains('createAsset')));
      expect(normalUser.assistantCapabilities, isNot(contains('createBazaar')));
      expect(normalUser.assistantCapabilities, contains('sendToBazaar'));
      expect(AssistantPermissions.none.assistantCapabilities, isEmpty);
      // Navigation is never advertised: the model is not allowed to do it.
      for (final who in [superAdmin, normalUser]) {
        expect(who.assistantCapabilities, isNot(contains('openScreen')));
      }
    });
  });

  // =========================================================================
  // FOLLOW-UP QUESTIONS
  // =========================================================================

  group('a follow-up must still name its asset', () {
    // The keyword engine's "last asset" pointer is only updated when IT
    // recognises an asset, so once the model is carrying the conversation the
    // two drift apart. Rather than let a stale pointer retarget a write, the
    // intent path requires the asset to be named - which the model can do,
    // because it has the whole conversation in front of it.
    test('an instruction naming no asset is asked about, not guessed', () {
      final plan = planIntent(intent('addStock', quantity: 5))!;

      expect(plan.isProposal, isFalse);
      expect(plan.message, contains('Which asset'));
    });

    test('the asset the model names is the asset that is used', () {
      final other = asset(
        id: 'asset-2',
        assetId: 'IT-PRN-002',
        name: 'HP LaserJet',
        category: 'Printer',
        deployed: 0,
        headOffice: 30,
        quantity: 30,
      );

      final plan = planIntent(
        intent('addStock', assetRef: 'IT-PRN-002', quantity: 5),
        data: snapshot(assets: [asset(), other]),
      )!;

      expect(plan.action!.asset!.assetId, 'IT-PRN-002');
    });

    test('a typed follow-up still follows the conversation', () {
      // plan() is untouched: "aur 5 add karo" after talking about an asset
      // still works exactly as it did before the model was added.
      final previous = asset();
      final plan = planner.plan(
        'add stock 5 units',
        snapshot(),
        superAdmin,
        lastAsset: previous,
      )!;

      expect(plan.isProposal, isTrue);
      expect(plan.action!.asset!.assetId, 'IT-LAP-001');
    });
  });

  // =========================================================================
  // THE KEYWORD PLANNER MUST NOT INTERCEPT NATURAL QUESTIONS
  //
  // The deterministic planner runs before the model on every message, and its
  // verb list is keyword-based, so it also trips on ordinary questions that
  // merely contain a verb. Answering one of those with "which asset do you
  // mean?" is exactly the fixed-command behaviour the model is here to
  // replace. These are the real sentences that showed the problem.
  // =========================================================================

  group('a natural question is never answered by the keyword planner', () {
    const questions = [
      'what was moved to Township Bazaar last week?',
      'Township Bazaar ko kya kya bheja gaya?',
      'which assets were transferred this month?',
      'is IT-LAP-001 assigned to anyone?',
      'kya IT-LAP-001 kisi ko assign hua hai?',
      'how many laptops do we have?',
      'tell me about our laptop stock',
      'has anything been sent to Township Bazaar?',
    ];

    for (final question in questions) {
      test('"$question" reaches the model', () {
        final plan = planner.plan(question, snapshot(), superAdmin);

        // Either the planner did not claim the message at all, or it managed
        // only a question back - and in that case the model gets it instead.
        if (plan != null) {
          expect(plan.isProposal, isFalse, reason: question);
          expect(
            shouldActOnPlan(plan, modelAvailable: true, message: question),
            isFalse,
            reason: 'this half-understood plan would have been shown instead '
                'of letting the model answer: $question',
          );
        }
      });
    }

    test('a real command is still handled without asking the model', () {
      const command = 'send 5 units of IT-LAP-001 to Township Bazaar';
      final plan = planner.plan(command, snapshot(), superAdmin)!;

      expect(plan.isProposal, isTrue);
      expect(
        shouldActOnPlan(plan, modelAvailable: true, message: command),
        isTrue,
      );
      expect(
        shouldActOnPlan(plan, modelAvailable: false, message: command),
        isTrue,
      );
    });

    test('a question that resolves to a whole command is still a question', () {
      // "assign" is a substring of "assigned", no word here is in the
      // question-word list, and both the asset and the person resolve - so
      // the planner produces a complete, confirmable assignment for a message
      // that only asked whether one exists.
      const asked = 'is IT-LAP-001 assigned to Ayesha Khan?';
      final plan = planner.plan(asked, snapshot(), superAdmin, people: people)!;

      expect(plan.isProposal, isTrue,
          reason: 'the planner does resolve this into an action, which is '
              'exactly why it must not be the one to answer it');
      expect(
        shouldActOnPlan(plan, modelAvailable: true, message: asked),
        isFalse,
        reason: 'this would have put a one-tap Confirm in front of someone '
            'who only asked a question',
      );
    });

    test('a navigation word inside a question does not close the panel', () {
      // "dikhao" is both "show me" and a navigation verb, and "bazaar" is a
      // screen name. Navigation happens instantly and with no confirmation,
      // so this would have answered a stock question by walking away from it.
      const asked = 'Township Bazaar ka poora stock dikhao';
      final plan = planner.plan(asked, snapshot(), superAdmin);

      if (plan != null && plan.isProposal) {
        expect(plan.action!.writes, isFalse);
        expect(
          shouldActOnPlan(plan, modelAvailable: true, message: asked),
          isFalse,
        );
      }
    });

    test('a question asked in statement form is still a question', () {
      // No question mark, so the trailing-'?' test does not fire; "assign" is
      // a substring of "assigned"; and both the asset and the person resolve.
      // Without an opening-word test the planner turns a read-only question
      // into a one-tap Confirm.
      const asked = [
        'is IT-LAP-001 assigned to Ayesha Khan',
        'has IT-LAP-001 been sent to Township Bazaar',
        'IT-LAP-001 Ayesha Khan ko assign hai ya nahi',
        'kya IT-LAP-001 Ayesha Khan ko assign kiya gaya',
      ];

      for (final question in asked) {
        final plan = planner.plan(question, snapshot(), superAdmin, people: people);

        if (plan != null) {
          expect(
            shouldActOnPlan(plan, modelAvailable: true, message: question),
            isFalse,
            reason: 'this would have been answered by the keyword planner: '
                '$question',
          );
        }
      }
    });

    test('an opening question word is only a signal in first position', () {
      // "is ka price" and "kya kya bheja" are ordinary Roman Urdu; testing for
      // these words anywhere would make every command look like a question.
      expect(ActionPlanner.readsAsQuestion('is IT-LAP-001 assigned'), isTrue);
      expect(ActionPlanner.readsAsQuestion('send 5 of is ka wala to Township'), isFalse);
      expect(ActionPlanner.readsAsQuestion('kya stock hai'), isTrue);
      expect(ActionPlanner.readsAsQuestion('send 5 units to Township Bazaar'), isFalse);
      expect(ActionPlanner.readsAsQuestion('assign IT-LAP-001 to Ayesha Khan'), isFalse);
    });

    test('mentioning a screen does not navigate away from the question', () {
      // Navigation happens instantly and with no confirmation, so a bare
      // mention of a screen name must not trigger it - that closed the panel
      // and threw the whole conversation away.
      const complaints = [
        'assets screen par Dell laptop nahi mil raha',
        'dashboard screen dekhne ke baad settings samajh nahi aa rahi',
      ];

      for (final message in complaints) {
        final plan = planner.plan(message, snapshot(), superAdmin);

        if (plan != null && plan.isProposal) {
          expect(
            plan.action!.writes,
            isTrue,
            reason: 'a non-writing (navigation) proposal would fire with no '
                'confirmation at all: $message',
          );
        }
      }
    });

    test('explicit navigation still navigates', () {
      const command = 'open assets';
      final plan = planner.plan(command, snapshot(), superAdmin)!;

      expect(plan.isProposal, isTrue);
      expect(plan.action!.route, '/assets');
      expect(
        shouldActOnPlan(plan, modelAvailable: true, message: command),
        isTrue,
      );
    });

    test('with no model the planner still has the last word, as before', () {
      // Free mode must behave exactly as it does today: the planner's question
      // is the answer, because there is nothing else to ask.
      const command = 'is IT-LAP-001 assigned to anyone?';
      final plan = planner.plan(command, snapshot(), superAdmin)!;

      expect(plan.isProposal, isFalse);
      expect(
        shouldActOnPlan(plan, modelAvailable: false, message: command),
        isTrue,
      );
    });
  });

  // =========================================================================
  // NOTHING IS WRITTEN BY PLANNING
  // =========================================================================

  test('planning an intent produces a proposal and nothing else', () {
    final data = snapshot();
    final before = data.assets.single.quantity;

    final plan = planIntent(intent('sendToBazaar',
        assetRef: 'IT-LAP-001', quantity: 10, to: 'Township Bazaar'))!;

    expect(plan.isProposal, isTrue);
    expect(plan.action!.writes, isTrue);
    // The snapshot is untouched: a proposal is a description, not a change.
    expect(data.assets.single.quantity, before);
    expect(data.assets.single.calculatedHeadOfficeQuantity, 60);
  });

  test('the model cannot navigate the app on its own', () {
    // Navigation is the one action that happens with no confirmation, so a
    // question the model merely misread as an instruction would close the
    // assistant and lose the conversation instead of answering it. Typed
    // navigation still works: the deterministic planner reads "open assets"
    // and "users screen kholo" before the model is ever asked.
    expect(planIntent(intent('openScreen', screen: 'assets')), isNull);
    expect(planIntent(intent('openScreen', screen: 'users')), isNull);
    expect(planIntent(intent('openScreen', screen: 'admin-console')), isNull);
  });

  test('typed navigation is untouched', () {
    final plan = planner.plan('open assets', snapshot(), superAdmin)!;

    expect(plan.isProposal, isTrue);
    expect(plan.action!.writes, isFalse);
    expect(plan.action!.route, '/assets');
  });

  // =========================================================================
  // CREATING AN ASSET FROM A DESCRIBED RECORD
  // =========================================================================

  group('a new asset is built from named fields only', () {
    test('a full description becomes a confirmable draft', () {
      final plan = planIntent(
        intent('createAsset', newAsset: const {
          'assetId': 'IT-MON-010',
          'name': 'Dell P2422H Monitor',
          'category': 'Monitor',
          'quantity': 12,
          'purchasePrice': 45000,
          'brand': 'Dell',
          'warrantyMonths': 36,
        }),
      )!;

      expect(plan.isProposal, isTrue);
      expect(plan.action!.kind, AssistantActionKind.createAsset);

      final draft = plan.action!.draft!;
      expect(draft.assetId, 'IT-MON-010');
      expect(draft.name, 'Dell P2422H Monitor');
      expect(draft.category, 'Monitor');
      expect(draft.quantity, 12);
      expect(draft.purchasePrice, 45000);
      expect(draft.brand, 'Dell');
      expect(draft.warrantyMonths, 36);
      // Every stored value is shown, so nothing is filled in unseen.
      expect(plan.action!.details, equals(draft.previewLines()));
    });

    test('a half-described asset is asked about, never completed by guesswork', () {
      final plan = planIntent(
        intent('createAsset', newAsset: const {
          'assetId': 'IT-MON-011',
          'name': 'Some Monitor',
        }),
      )!;

      expect(plan.isProposal, isFalse);
      expect(plan.message, contains('category'));
    });

    test('a duplicate Asset ID is refused', () {
      final plan = planIntent(
        intent('createAsset', newAsset: const {
          'assetId': 'IT-LAP-001',
          'name': 'Another Laptop',
          'category': 'Laptop',
          'quantity': 5,
          'purchasePrice': 1000,
        }),
      )!;

      expect(plan.isProposal, isFalse);
      expect(plan.message.toLowerCase(), contains('already'));
    });
  });

  // =========================================================================
  // THE FACTS THE MODEL IS GIVEN
  // =========================================================================

  group('the facts payload carries totals the model must not compute', () {
    final laptops = asset(quantity: 100, headOffice: 60, deployed: 40, price: 1000);
    final printer = asset(
      id: 'asset-2',
      assetId: 'IT-PRN-002',
      name: 'HP LaserJet',
      category: 'Printer',
      condition: 'Fair',
      status: 'Damaged',
      brand: 'HP',
      quantity: 20,
      headOffice: 20,
      deployed: 0,
      price: 50000,
    );

    final data = snapshot(
      assets: [laptops, printer],
      holders: const {'us-2': 'Ayesha Khan'},
    );

    test('every breakdown covers all assets, not the sample', () {
      final facts = data.toFacts(now: DateTime(2026, 6, 1));

      expect(facts['byCategory']['Laptop']['quantity'], 100);
      expect(facts['byCategory']['Printer']['quantity'], 20);
      expect(facts['byCategory']['Printer']['records'], 1);
      expect(facts['byCategory']['Printer']['value'], 1000000);
      expect(facts['byStatus']['Damaged']['quantity'], 20);
      expect(facts['byCondition']['Fair']['records'], 1);
      expect(facts['byBrand']['HP']['quantity'], 20);
      expect(facts['byLocation']['Head Office']['records'], 2);
    });

    test('the Bazaar directory and its contents are both present', () {
      final facts = data.toFacts(now: DateTime(2026, 6, 1));

      final names = (facts['bazaarDirectory'] as List)
          .map((b) => (b as Map)['name'])
          .toList();
      expect(names, contains('Old Anarkali Bazaar'));

      final disabled = (facts['bazaarDirectory'] as List)
          .firstWhere((b) => (b as Map)['name'] == 'Old Anarkali Bazaar');
      expect((disabled as Map)['isActive'], isFalse);

      expect(facts['bazaarStock']['Township Bazaar'], 40);
      expect(facts['bazaarContents']['Township Bazaar'], [
        {'assetId': 'IT-LAP-001', 'quantity': 40},
      ]);
    });

    test('today\'s date is supplied, so "this month" can be grounded', () {
      expect(data.toFacts(now: DateTime(2026, 6, 1))['today'], '2026-06-01');
    });

    test('warranty is worked out against that same date', () {
      final covered = asset(
        warrantyMonths: 24,
        purchaseDate: DateTime(2025, 1, 15),
      );

      final facts = snapshot(assets: [covered]).toFacts(now: DateTime(2026, 6, 1));

      expect(facts['warranty']['soonestToExpire'].single['expires'], '2027-01-15');
      expect(facts['warranty']['expired'], 0);
      expect(facts['warranty']['expiringWithin90Days'], 0);

      final late = snapshot(assets: [covered]).toFacts(now: DateTime(2027, 6, 1));
      expect(late['warranty']['expired'], 1);
    });

    test('who holds what is answerable, by name and by name only', () {
      final held = asset(assignedTo: 'us-2', assigned: 10, headOffice: 50);
      final facts = snapshot(
        assets: [held],
        holders: const {'us-2': 'Ayesha Khan'},
      ).toFacts(now: DateTime(2026, 6, 1));

      expect(facts['assignments']['items'].single['heldBy'], 'Ayesha Khan');

      final encoded = facts.toString();
      expect(encoded, isNot(contains('us-2')));
      expect(encoded, isNot(contains('@')));
    });

    test('an unknown holder is left unnamed rather than invented', () {
      final held = asset(assignedTo: 'us-9', assigned: 10, headOffice: 50);
      final facts = snapshot(assets: [held]).toFacts(now: DateTime(2026, 6, 1));

      expect(facts['assignments']['items'].single.containsKey('heldBy'), isFalse);
      expect(facts['assignments']['items'].single['quantity'], 10);
    });

    test('ranking is done here, because the model only sees a sample', () {
      final facts = data.toFacts(now: DateTime(2026, 6, 1));
      expect(facts['mostValuable'].first['assetId'], 'IT-PRN-002');
    });

    test('a breakdown past its cap still adds up to the whole inventory', () {
      // 45 distinct categories against a cap of 30. Dropping the tail would
      // have the model report a total short by fifteen categories' worth.
      final many = [
        for (var i = 0; i < 45; i++)
          asset(
            id: 'a$i',
            assetId: 'IT-X-$i',
            category: 'Category $i',
            quantity: 10,
            headOffice: 10,
            deployed: 0,
          ),
      ];

      final byCategory =
          snapshot(assets: many).toFacts(now: DateTime(2026, 6, 1))['byCategory']
              as Map<String, dynamic>;

      expect(byCategory.containsKey('(everything else)'), isTrue);
      expect(byCategory['(everything else)']['distinctValues'], 15);

      final counted = byCategory.values
          .fold<int>(0, (sum, b) => sum + (b as Map)['quantity'] as int);
      expect(counted, 450);
    });

    test('a breakdown inside its cap carries no remainder bucket', () {
      final byCategory = data.toFacts(now: DateTime(2026, 6, 1))['byCategory']
          as Map<String, dynamic>;
      expect(byCategory.containsKey('(everything else)'), isFalse);
    });

    test('a truncated list says how many there really are', () {
      final held = [
        for (var i = 0; i < 40; i++)
          asset(
            id: 'h$i',
            assetId: 'IT-H-$i',
            assignedTo: 'us-2',
            assigned: 5,
            headOffice: 5,
            quantity: 10,
            deployed: 0,
          ),
      ];

      final facts = snapshot(
        assets: held,
        holders: const {'us-2': 'Ayesha Khan'},
      ).toFacts(now: DateTime(2026, 6, 1));

      expect(facts['assignments']['assetRecordsAssigned'], 40);
      expect(facts['assignments']['listed'], 25);
      expect((facts['assignments']['items'] as List).length, 25);
    });

    test('warranties are listed soonest first, not in storage order', () {
      final fleet = [
        asset(
          id: 'w1',
          assetId: 'IT-W-001',
          warrantyMonths: 60,
          purchaseDate: DateTime(2025, 1, 1),
        ),
        asset(
          id: 'w2',
          assetId: 'IT-W-002',
          warrantyMonths: 12,
          purchaseDate: DateTime(2025, 1, 1),
        ),
      ];

      final facts =
          snapshot(assets: fleet).toFacts(now: DateTime(2025, 6, 1));

      expect(facts['warranty']['soonestToExpire'].first['assetId'], 'IT-W-002');
    });

    test('a warranty bought at month end does not roll into the next month', () {
      // 31 January plus one month is 28 February, not 3 March.
      final endOfMonth = asset(
        warrantyMonths: 1,
        purchaseDate: DateTime(2026, 1, 31),
      );

      final facts =
          snapshot(assets: [endOfMonth]).toFacts(now: DateTime(2026, 1, 1));

      expect(facts['warranty']['soonestToExpire'].single['expires'], '2026-02-28');
    });

    test('transfer activity is counted, not just listed', () {
      final recent = [
        for (var i = 0; i < 40; i++)
          movement(
            assetId: 'IT-LAP-001',
            assetDocumentId: 'asset-1',
            quantity: 1,
            date: DateTime(2026, 6, 1).subtract(Duration(days: i)),
          ),
      ];

      final facts = snapshot(deployments: recent).toFacts(now: DateTime(2026, 6, 1));

      expect(facts['movements']['total'], 40);
      expect(facts['movements']['inLast7Days'], 8);
      expect(facts['movements']['inLast30Days'], 31);
      expect((facts['movements']['recent'] as List).length, 15);
    });

    test('the two ways of counting a status are labelled as different', () {
      final facts = data.toFacts(now: DateTime(2026, 6, 1));
      expect(facts['fieldNotes']['totals'], contains('Head Office'));
      expect(facts['fieldNotes']['byStatus'], contains('do not compare'));
    });

    test('a large inventory still fits the backend limit', () {
      // functions/index.js refuses a payload over MAX_FACTS_BYTES (60000) with
      // "Too much data for one question." Every list in toFacts is capped, and
      // this is what proves the caps add up to less than that on a database
      // far bigger than the one this app runs on today.
      final many = [
        for (var i = 0; i < 5000; i++)
          asset(
            id: 'asset-$i',
            assetId: 'IT-CAT${i % 40}-${i.toString().padLeft(5, '0')}',
            name: 'A rather long asset name for record number $i',
            category: 'Category ${i % 40}',
            brand: 'Brand ${i % 40}',
            condition: 'Condition ${i % 5}',
            status: 'Status ${i % 6}',
            warrantyMonths: 24,
            purchaseDate: DateTime(2024, (i % 12) + 1, 15),
          ),
      ];

      final bazaarList = [
        for (var i = 0; i < 80; i++)
          bazaar('b$i', 'A Reasonably Long Bazaar Name Number $i'),
      ];

      final movements = [
        for (var i = 0; i < 20000; i++)
          movement(
            bazaarId: 'b${i % 80}',
            bazaarName: 'A Reasonably Long Bazaar Name Number ${i % 80}',
            assetId: 'IT-CAT${i % 40}-${(i % 5000).toString().padLeft(5, '0')}',
            assetDocumentId: 'asset-${i % 5000}',
            quantity: 3,
          ),
      ];

      final facts = snapshot(
        assets: many,
        bazaars: bazaarList,
        deployments: movements,
      ).toFacts(now: DateTime(2026, 6, 1));

      final bytes = jsonEncode(facts).length;

      expect(
        bytes,
        lessThan(50000),
        reason: 'the facts payload would be refused by the backend ($bytes bytes)',
      );
    });

    test('the sample is still labelled as a sample', () {
      final many = [for (var i = 0; i < 60; i++) asset(id: 'a$i', assetId: 'IT-X-$i')];
      final facts = snapshot(assets: many).toFacts(maxAssets: 40);

      expect(facts['scope']['assetsVisible'], 60);
      expect(facts['scope']['assetsIncludedHere'], 40);
      expect((facts['assets'] as List).length, 40);
      // ...but the totals still cover all 60.
      expect(facts['byCategory']['Laptop']['records'], 60);
    });
  });
}
