// Tests for what actually happens when an Admin approves a request the
// assistant filed on a normal user's behalf.
//
// A normal user cannot assign, unassign or move stock directly: Action Mode
// files a request and an Admin approves it. Two of those paths were broken in
// ways that reported success and left the database wrong, so these tests drive
// the real thing end to end - the real RequestService, the real AssetService
// and DeploymentService, against an in-memory Firestore - and assert on the
// stored document afterwards rather than on a return value.

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:firebase_auth_mocks/firebase_auth_mocks.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:it_management_system/core/ai/action_executor.dart';
import 'package:it_management_system/core/ai/action_planner.dart';
import 'package:it_management_system/core/ai/inventory_assistant.dart';
import 'package:it_management_system/core/ai/assistant_actions.dart';
import 'package:it_management_system/core/services/asset_service.dart';
import 'package:it_management_system/core/services/bazaar_service.dart';
import 'package:it_management_system/core/services/deployment_service.dart';
import 'package:it_management_system/core/services/request_service.dart';
import 'package:it_management_system/models/asset_model.dart';
import 'package:it_management_system/models/deployment_model.dart';

void main() {
  late FakeFirebaseFirestore db;
  late AssetService assets;
  late DeploymentService movements;
  late BazaarService bazaars;
  late RequestService requests;
  late ActionExecutor executor;
  late String townshipId;

  const adminUid = 'admin-1';
  const userUid = 'user-1';
  const holderUid = 'holder-1';

  /// The account doing the approving. RequestService reads the role from the
  /// stored profile, so the Admin has to exist in Firestore as well as in Auth.
  MockFirebaseAuth authAs(String uid) => MockFirebaseAuth(
        signedIn: true,
        mockUser: MockUser(uid: uid, email: '$uid@test.local'),
      );

  setUp(() async {
    db = FakeFirebaseFirestore();
    assets = AssetService(firestore: db);
    movements = DeploymentService(firestore: db);
    bazaars = BazaarService(firestore: db);

    requests = RequestService(firestore: db, auth: authAs(adminUid));

    executor = ActionExecutor(
      assetService: assets,
      deploymentService: movements,
      bazaarService: bazaars,
      // Filing runs as the USER; approving runs as the Admin.
      requestService: RequestService(firestore: db, auth: authAs(userUid)),
    );

    await db.collection('users').doc(adminUid).set({
      'uid': adminUid,
      'name': 'Adeel Admin',
      'email': 'admin@test.local',
      'role': 'admin',
      'status': 'active',
    });

    await db.collection('users').doc(userUid).set({
      'uid': userUid,
      'name': 'Usman User',
      'email': 'usman@test.local',
      'role': 'user',
      'status': 'active',
      'createdBy': adminUid,
    });

    await db.collection('users').doc(holderUid).set({
      'uid': holderUid,
      'name': 'Ayesha Khan',
      'email': 'ayesha@test.local',
      'role': 'user',
      'status': 'active',
      'createdBy': adminUid,
    });

    townshipId = await bazaars.createBazaar(name: 'Township Bazaar', location: 'Lahore');
  });

  /// The account Action Mode runs as: a normal user, who may only file
  /// requests.
  const normalUser = AssistantPermissions(
    role: 'user',
    uid: userUid,
    displayName: 'Usman User',
  );

  Future<AssetModel> seedAsset({int quantity = 40}) async {
    final id = await assets.addAsset(
      AssetModel(
        id: '',
        assetId: 'IT-LAP-001',
        name: 'Dell Latitude 5420',
        category: 'Laptop',
        status: 'Available',
        condition: 'Good',
        quantity: quantity,
        headOfficeQuantity: quantity,
        purchasePrice: 1000,
        location: 'Head Office',
        adminId: adminUid,
      ),
    );

    final snapshot = await db.collection('assets').doc(id).get();
    return AssetModel.fromMap(snapshot.data()!, id);
  }

  Future<AssetModel> reload(String id) async {
    final snapshot = await db.collection('assets').doc(id).get();
    return AssetModel.fromMap(snapshot.data()!, id);
  }

  /// The one request the assistant just filed.
  Future<({String id, Map<String, dynamic> data})> onlyRequest() async {
    final all = await db.collection('requests').get();
    expect(all.docs, hasLength(1));
    return (id: all.docs.single.id, data: all.docs.single.data());
  }

  // =========================================================================
  // 1. ASSIGN
  // =========================================================================

  test('an approved assign request really hands the asset over', () async {
    final asset = await seedAsset(quantity: 40);

    // The user asks the assistant to assign it. Being a normal user, this is
    // filed for approval rather than carried out.
    final filed = await executor.run(
      AssistantAction(
        kind: AssistantActionKind.assign,
        title: 'Request an assignment',
        details: const ['Asset: IT-LAP-001'],
        asset: asset,
        assigneeUid: holderUid,
        assigneeName: 'Ayesha Khan',
        viaRequest: true,
      ),
      normalUser,
    );

    expect(filed.ok, isTrue);

    // Nothing has changed yet - that is the whole point of the workflow.
    final beforeApproval = await reload(asset.id);
    expect(beforeApproval.assignedTo, isNull);
    expect(beforeApproval.calculatedHeadOfficeQuantity, 40);

    final request = await onlyRequest();
    expect(request.data['requestType'], 'Assignment');
    expect(request.data['assigneeId'], holderUid);

    await requests.approveRequest(requestId: request.id, approvedBy: 'Adeel Admin');

    final after = await reload(asset.id);

    // The holder, the status and the stock split all moved together.
    expect(after.assignedTo, holderUid);
    expect(after.status, 'Assigned');
    expect(after.calculatedAssignedQuantity, 40);
    expect(after.calculatedHeadOfficeQuantity, 0);
    expect(after.quantity, 40);

    // The invariant the whole inventory rests on.
    expect(
      after.calculatedHeadOfficeQuantity +
          after.calculatedAssignedQuantity +
          after.calculatedDeployedQuantity,
      after.quantity,
    );

    final settled = await db.collection('requests').doc(request.id).get();
    expect(settled.data()!['status'], 'Approved');
  });

  // =========================================================================
  // 2. UNASSIGN
  // =========================================================================

  test('an approved unassign request really takes the asset back', () async {
    final asset = await seedAsset(quantity: 40);

    // Start from an asset that is genuinely out with somebody.
    await assets.assignAsset(assetId: asset.id, userId: holderUid);

    final held = await reload(asset.id);
    expect(held.assignedTo, holderUid);
    expect(held.calculatedAssignedQuantity, 40);

    final filed = await executor.run(
      AssistantAction(
        kind: AssistantActionKind.unassign,
        title: 'Request a return',
        details: const ['Asset: IT-LAP-001'],
        asset: held,
        viaRequest: true,
      ),
      normalUser,
    );

    expect(filed.ok, isTrue);

    final request = await onlyRequest();
    expect(request.data['requestType'], 'Assignment');
    expect(request.data['assigneeId'], '');

    await requests.approveRequest(requestId: request.id, approvedBy: 'Adeel Admin');

    final after = await reload(asset.id);

    // No contradiction left behind: the holder is cleared, the status matches
    // the stock, and the units are back at Head Office.
    expect(after.assignedTo, isNull);
    expect(after.status, 'Available');
    expect(after.calculatedAssignedQuantity, 0);
    expect(after.calculatedHeadOfficeQuantity, 40);
    expect(
      after.calculatedHeadOfficeQuantity +
          after.calculatedAssignedQuantity +
          after.calculatedDeployedQuantity,
      after.quantity,
    );

    final settled = await db.collection('requests').doc(request.id).get();
    expect(settled.data()!['status'], 'Approved');
  });

  // =========================================================================
  // 3. RETURN TO HEAD OFFICE
  // =========================================================================

  test('an approved return to Head Office brings the stock back', () async {
    final asset = await seedAsset(quantity: 40);

    // Put stock out at a Bazaar first, so there is something to bring back.
    await movements.transferAsset(
      assetDocumentId: asset.id,
      sourceId: '',
      sourceName: 'Head Office',
      destinationId: townshipId,
      destinationName: 'Township Bazaar',
      quantity: 10,
      transferredBy: adminUid,
      transferredByName: 'Adeel Admin',
    );

    final deployed = await reload(asset.id);
    expect(deployed.calculatedDeployedQuantity, 10);
    expect(deployed.calculatedHeadOfficeQuantity, 30);

    final filed = await executor.run(
      AssistantAction(
        kind: AssistantActionKind.returnToHeadOffice,
        title: 'Request a transfer of 10 units',
        details: const ['Asset: IT-LAP-001'],
        asset: deployed,
        quantity: 10,
        sourceId: townshipId,
        sourceName: 'Township Bazaar',
        // The id the transfer service itself uses for Head Office. The
        // assistant used to send an empty string here, which transferAsset
        // refuses outright - so no return could be carried out at all.
        destinationId: DeploymentService.headOfficeId,
        destinationName: 'Head Office',
        viaRequest: true,
      ),
      normalUser,
    );

    expect(filed.ok, isTrue);

    final request = await onlyRequest();
    expect(request.data['requestType'], 'Transfer');
    expect(request.data['destinationBazaarId'], DeploymentService.headOfficeId);
    expect(request.data['destinationBazaarName'], 'Head Office');

    final movementsBefore = (await db.collection('deployments').get()).docs.length;

    // This is the call that used to throw "Destination Bazaar is missing."
    await requests.approveRequest(requestId: request.id, approvedBy: 'Adeel Admin');

    final after = await reload(asset.id);

    expect(after.calculatedHeadOfficeQuantity, 40);
    expect(after.calculatedDeployedQuantity, 0);
    expect(after.quantity, 40);
    expect(
      after.calculatedHeadOfficeQuantity +
          after.calculatedAssignedQuantity +
          after.calculatedDeployedQuantity,
      after.quantity,
    );

    final settled = await db.collection('requests').doc(request.id).get();
    expect(settled.data()!['status'], 'Approved');

    // The history is a ledger, not a cache: the original movement out is
    // still there, and the return was added rather than overwriting it.
    final movementsAfter = (await db.collection('deployments').get()).docs;
    expect(movementsAfter.length, greaterThan(movementsBefore));

    final outbound = movementsAfter.where(
      (d) => (d.data()['toBazaarName'] ?? '').toString() == 'Township Bazaar',
    );
    expect(outbound, isNotEmpty, reason: 'the original transfer out was lost');
  });

  test('a return filed the OLD way, with an empty destination id, still approves', () async {
    // Requests already sitting Pending were written before the assistant knew
    // the sentinel, so they carry an empty destination id. Accepting them at
    // the guard is not enough: transferAsset requires a non-empty id, so the
    // refusal simply moved one call deeper and the request stayed stuck.
    final asset = await seedAsset(quantity: 40);

    await movements.transferAsset(
      assetDocumentId: asset.id,
      sourceId: '',
      sourceName: 'Head Office',
      destinationId: townshipId,
      destinationName: 'Township Bazaar',
      quantity: 10,
      transferredBy: adminUid,
      transferredByName: 'Adeel Admin',
    );

    final legacy = await db.collection('requests').add({
      'requestType': 'Transfer',
      'assetId': asset.id,
      'assetName': asset.name,
      'status': 'Pending',
      'requestedBy': userUid,
      'receiverId': adminUid,
      'sourceBazaarId': townshipId,
      'sourceBazaarName': 'Township Bazaar',
      'destinationBazaarId': '',
      'destinationBazaarName': 'Head Office',
      'transferQuantity': 10,
    });

    await requests.approveRequest(requestId: legacy.id, approvedBy: 'Adeel Admin');

    final after = await reload(asset.id);
    expect(after.calculatedHeadOfficeQuantity, 40);
    expect(after.calculatedDeployedQuantity, 0);

    final settled = await db.collection('requests').doc(legacy.id).get();
    expect(settled.data()!['status'], 'Approved');
  });

  test('a genuinely missing destination is still refused', () async {
    // The mapping above must not turn every empty destination into Head
    // Office - only one that actually names it.
    final asset = await seedAsset(quantity: 40);

    final broken = await db.collection('requests').add({
      'requestType': 'Transfer',
      'assetId': asset.id,
      'assetName': asset.name,
      'status': 'Pending',
      'requestedBy': userUid,
      'receiverId': adminUid,
      'sourceBazaarId': townshipId,
      'sourceBazaarName': 'Township Bazaar',
      'destinationBazaarId': '',
      'destinationBazaarName': '',
      'transferQuantity': 10,
    });

    await expectLater(
      requests.approveRequest(requestId: broken.id, approvedBy: 'Adeel Admin'),
      throwsA(isA<Exception>()),
    );

    final untouched = await reload(asset.id);
    expect(untouched.calculatedHeadOfficeQuantity, 40);
  });

  test('an Admin returning stock directly works too', () async {
    // The same defect broke the direct path: the assistant named Head Office
    // with an empty id, and transferAsset refuses an empty destination before
    // it ever checks the name. So no return worked at all - requested or not.
    const admin = AssistantPermissions(
      role: 'admin',
      uid: adminUid,
      displayName: 'Adeel Admin',
    );

    final asset = await seedAsset(quantity: 40);

    await movements.transferAsset(
      assetDocumentId: asset.id,
      sourceId: '',
      sourceName: 'Head Office',
      destinationId: townshipId,
      destinationName: 'Township Bazaar',
      quantity: 10,
      transferredBy: adminUid,
      transferredByName: 'Adeel Admin',
    );

    final deployed = await reload(asset.id);
    expect(deployed.calculatedDeployedQuantity, 10);

    final done = await executor.run(
      AssistantAction(
        kind: AssistantActionKind.returnToHeadOffice,
        title: 'Move 10 units',
        details: const ['Asset: IT-LAP-001'],
        asset: deployed,
        quantity: 10,
        sourceId: townshipId,
        sourceName: 'Township Bazaar',
        destinationId: DeploymentService.headOfficeId,
        destinationName: 'Head Office',
      ),
      admin,
    );

    expect(done.ok, isTrue, reason: done.message);

    final after = await reload(asset.id);
    expect(after.calculatedHeadOfficeQuantity, 40);
    expect(after.calculatedDeployedQuantity, 0);
  });

  test('the planner names Head Office the way the transfer service does', () async {
    // The two had drifted apart: the assistant used an empty id,
    // DeploymentService requires its own sentinel. This is the seam, and a
    // plan built by the planner itself has to land on the right side of it.
    final asset = await seedAsset(quantity: 40);

    await movements.transferAsset(
      assetDocumentId: asset.id,
      sourceId: '',
      sourceName: 'Head Office',
      destinationId: townshipId,
      destinationName: 'Township Bazaar',
      quantity: 10,
      transferredBy: adminUid,
      transferredByName: 'Adeel Admin',
    );

    final deployed = await reload(asset.id);

    final movementRecords = (await db.collection('deployments').get())
        .docs
        .map((d) => DeploymentModel.fromMap(d.data(), d.id))
        .toList();

    final plan = ActionPlanner().plan(
      'return 10 units of IT-LAP-001 from Township Bazaar',
      InventorySnapshot(
        assets: [deployed],
        bazaars: [BazaarModel(id: townshipId, name: 'Township Bazaar')],
        deployments: movementRecords,
        totalQuantity: 40,
        headOfficeStock: 30,
        assignedQuantity: 0,
        bazaarQuantity: 10,
        damagedQuantity: 0,
        underRepairQuantity: 0,
        lostQuantity: 0,
        disposedQuantity: 0,
        unavailableAtHeadOffice: 0,
        totalInventoryValue: 0,
        roleLabel: 'Admin',
        scopeNote: '',
      ),
      const AssistantPermissions(
        role: 'admin',
        uid: adminUid,
        displayName: 'Adeel Admin',
      ),
    )!;

    expect(plan.isProposal, isTrue, reason: plan.message);
    expect(plan.action!.kind, AssistantActionKind.returnToHeadOffice);
    expect(plan.action!.destinationId, DeploymentService.headOfficeId);
    expect(plan.action!.destinationName, 'Head Office');
  });

  // =========================================================================
  // LEGACY REQUESTS
  //
  // Before the 'Assignment' type existed, assign and unassign were filed as
  // Edits. Approving one applied buildSafeEditUpdate, which never touches
  // assignedTo - so the status changed, the holder did not, and both sides
  // were told it worked. Any database predating the fix still has these
  // sitting Pending.
  // =========================================================================

  /// An Edit request shaped exactly as the old assistant filed one.
  Future<DocumentReference<Map<String, dynamic>>> legacyEdit(
    AssetModel asset, {
    required Map<String, dynamic> changes,
  }) {
    final previous = asset.toMap();

    return db.collection('requests').add({
      'requestType': 'Edit',
      'assetId': asset.id,
      'assetName': asset.name,
      'status': 'Pending',
      'requestedBy': userUid,
      'receiverId': adminUid,
      'previousAssetData': previous,
      'proposedAssetData': {...previous, ...changes},
    });
  }

  test('a legacy Edit-typed assign request is carried out properly', () async {
    final asset = await seedAsset(quantity: 40);

    final legacy = await legacyEdit(
      asset,
      changes: {'assignedTo': holderUid, 'status': 'Assigned'},
    );

    await requests.approveRequest(requestId: legacy.id, approvedBy: 'Adeel Admin');

    final after = await reload(asset.id);

    // The holder really moved - this is what used to be silently skipped.
    expect(after.assignedTo, holderUid);
    expect(after.status, 'Assigned');
    expect(after.calculatedAssignedQuantity, 40);
    expect(after.calculatedHeadOfficeQuantity, 0);
    expect(
      after.calculatedHeadOfficeQuantity +
          after.calculatedAssignedQuantity +
          after.calculatedDeployedQuantity,
      after.quantity,
    );

    final settled = await db.collection('requests').doc(legacy.id).get();
    expect(settled.data()!['status'], 'Approved');
  });

  test('a legacy Edit-typed unassign request is carried out properly', () async {
    final asset = await seedAsset(quantity: 40);
    await assets.assignAsset(assetId: asset.id, userId: holderUid);

    final held = await reload(asset.id);
    expect(held.assignedTo, holderUid);

    final legacy = await legacyEdit(
      held,
      changes: {'assignedTo': null, 'status': 'Available'},
    );

    await requests.approveRequest(requestId: legacy.id, approvedBy: 'Adeel Admin');

    final after = await reload(asset.id);

    expect(after.assignedTo, isNull);
    expect(after.status, 'Available');
    expect(after.calculatedAssignedQuantity, 0);
    expect(after.calculatedHeadOfficeQuantity, 40);
    expect(
      after.calculatedHeadOfficeQuantity +
          after.calculatedAssignedQuantity +
          after.calculatedDeployedQuantity,
      after.quantity,
    );
  });

  test('an ordinary edit is never mistaken for an assignment', () async {
    // The holder does not move, so nothing is diverted: this stays an Edit
    // and the descriptive field is applied as it always was.
    final asset = await seedAsset(quantity: 40);

    final ordinary = await legacyEdit(asset, changes: {'name': 'Dell Latitude 5430'});

    await requests.approveRequest(requestId: ordinary.id, approvedBy: 'Adeel Admin');

    final after = await reload(asset.id);
    expect(after.name, 'Dell Latitude 5430');
    expect(after.assignedTo, isNull);
    expect(after.calculatedHeadOfficeQuantity, 40);
  });

  test('a mixed edit is ambiguous, so it keeps ordinary Edit behaviour', () async {
    // The holder AND a descriptive field changed together. That is not
    // unmistakably an assignment, so it must not be guessed at: the edit path
    // runs, which applies the name and leaves the holder alone.
    final asset = await seedAsset(quantity: 40);

    final mixed = await legacyEdit(
      asset,
      changes: {
        'assignedTo': holderUid,
        'status': 'Assigned',
        'name': 'Renamed While Assigning',
      },
    );

    await requests.approveRequest(requestId: mixed.id, approvedBy: 'Adeel Admin');

    final after = await reload(asset.id);

    expect(after.name, 'Renamed While Assigning');
    // Untouched by the edit path, exactly as before this work.
    expect(after.assignedTo, isNull);
    expect(after.calculatedAssignedQuantity, 0);
    expect(after.calculatedHeadOfficeQuantity, 40);
  });

  // =========================================================================
  // THE GUARANTEE THAT MAKES APPROVAL SAFE
  // =========================================================================

  test('the exactly-once guard refuses a request that is no longer Pending', () async {
    // approveRequest rejects a non-Pending request in a pre-flight check, so
    // the double-approval test above never reaches this guard. This one calls
    // the service directly, which is the only way to exercise it: it is what
    // stops two Admins, or one double-tap, assigning the same stock twice.
    final asset = await seedAsset(quantity: 40);

    final alreadyDone = await db.collection('requests').add({
      'requestType': 'Assignment',
      'assetId': asset.id,
      'assetName': asset.name,
      'status': 'Approved',
      'requestedBy': userUid,
      'receiverId': adminUid,
      'assigneeId': holderUid,
    });

    await expectLater(
      assets.assignAsset(
        assetId: asset.id,
        userId: holderUid,
        approvalRequestRef: alreadyDone,
        approvalRequestUpdate: const {'approvedBy': 'Adeel Admin'},
      ),
      throwsA(
        isA<Exception>().having(
          (e) => e.toString(),
          'message',
          contains('This request has already been processed'),
        ),
      ),
    );

    // The asset is untouched: a refused attempt queues no writes, so the
    // transaction commits nothing.
    final after = await reload(asset.id);
    expect(after.assignedTo, isNull);
    expect(after.calculatedAssignedQuantity, 0);
    expect(after.calculatedHeadOfficeQuantity, 40);
    expect(after.quantity, 40);
  });

  test('the same guard protects unassignment', () async {
    final asset = await seedAsset(quantity: 40);
    await assets.assignAsset(assetId: asset.id, userId: holderUid);

    final alreadyDone = await db.collection('requests').add({
      'requestType': 'Assignment',
      'assetId': asset.id,
      'status': 'Approved',
      'requestedBy': userUid,
      'receiverId': adminUid,
      'assigneeId': '',
    });

    await expectLater(
      assets.returnAsset(asset.id, approvalRequestRef: alreadyDone),
      throwsA(isA<Exception>()),
    );

    // Still with its holder: nothing was taken back.
    final after = await reload(asset.id);
    expect(after.assignedTo, holderUid);
    expect(after.calculatedAssignedQuantity, 40);
    expect(after.calculatedHeadOfficeQuantity, 0);
  });

  test('a request document that has vanished is refused too', () async {
    final asset = await seedAsset(quantity: 40);

    await expectLater(
      assets.assignAsset(
        assetId: asset.id,
        userId: holderUid,
        approvalRequestRef: db.collection('requests').doc('never-existed'),
      ),
      throwsA(isA<Exception>()),
    );

    final after = await reload(asset.id);
    expect(after.assignedTo, isNull);
    expect(after.calculatedHeadOfficeQuantity, 40);
  });

  test('a request cannot be approved twice', () async {
    final asset = await seedAsset(quantity: 40);

    await executor.run(
      AssistantAction(
        kind: AssistantActionKind.assign,
        title: 'Request an assignment',
        details: const ['Asset: IT-LAP-001'],
        asset: asset,
        assigneeUid: holderUid,
        assigneeName: 'Ayesha Khan',
        viaRequest: true,
      ),
      normalUser,
    );

    final request = await onlyRequest();

    await requests.approveRequest(requestId: request.id, approvedBy: 'Adeel Admin');

    // A second tap, or a second Admin, must not assign the same stock again.
    await expectLater(
      requests.approveRequest(requestId: request.id, approvedBy: 'Adeel Admin'),
      throwsA(isA<Exception>()),
    );

    final after = await reload(asset.id);
    expect(after.calculatedAssignedQuantity, 40);
    expect(after.quantity, 40);
  });
}
