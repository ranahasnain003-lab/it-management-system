// Concurrency verification for the D1/D2 approval paths, against the REAL
// Firestore in the Firebase Local Emulator Suite.
//
// Why this file exists: fake_cloud_firestore's runTransaction is a
// pass-through. It does not serialize, so the unit tests can prove the
// exactly-once guard refuses a non-Pending request, but they cannot prove that
// two Admins approving at the same instant end up with one approval. Only a
// real Firestore transaction can show that, because only it aborts and retries
// on contention.
//
// Run it on purpose - it is not part of `flutter test`:
//
//   1. firebase emulators:start --only firestore,auth --project it-inventory-8e690
//   2. create the two emulator accounts below (_approverEmail, _requesterEmail)
//   3. flutter test integration_test/approval_concurrency_test.dart \
//        -d emulator-5554 --dart-define=FIREBASE_EMULATOR_HOST=10.0.2.2
//
// 10.0.2.2 is how the Android emulator reaches the host's loopback. Without
// the define this would talk to PRODUCTION, so the test refuses to run.
//
// firestore.rules are enforced by the emulator exactly as in production and
// are NOT modified for this test. That is what forces two real identities:
// the rules say a request is created by its requester and may not then be
// approved by that same person.

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';

import 'package:it_management_system/core/services/asset_service.dart';
import 'package:it_management_system/core/services/bazaar_service.dart';
import 'package:it_management_system/core/services/deployment_service.dart';
import 'package:it_management_system/firebase_options.dart';
import 'package:it_management_system/models/asset_model.dart';

const String _emulatorHost = String.fromEnvironment('FIREBASE_EMULATOR_HOST');

/// How many approvals race for the same request.
const int _racers = 6;

/// Two verified accounts that exist in the emulator only.
///
/// The approver is a super_admin, the requester a plain admin. They have to be
/// different people: firestore.rules refuse an update where
/// `resource.data.requestedBy == request.auth.uid`.
const String _approverEmail = 'conc.admin@test.local';
const String _requesterEmail = 'conc.user@test.local';
const String _password = 'Passw0rd!';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  late FirebaseFirestore db;
  late AssetService assets;
  late DeploymentService movements;
  late BazaarService bazaars;
  late String runId;

  Future<String> signInAs(String email) async {
    final credential = await FirebaseAuth.instance.signInWithEmailAndPassword(
      email: email,
      password: _password,
    );

    final user = credential.user!;
    expect(
      user.emailVerified,
      isTrue,
      reason: 'firestore.rules require a verified address for $email',
    );

    return user.uid;
  }

  setUpAll(() async {
    // Refuse to run against production. This test writes and deletes.
    expect(
      _emulatorHost,
      isNotEmpty,
      reason: 'Run with --dart-define=FIREBASE_EMULATOR_HOST=10.0.2.2. '
          'Without it this would write to the real project.',
    );

    await Firebase.initializeApp(
      options: DefaultFirebaseOptions.currentPlatform,
    );

    // Auth first: Firestore initialises Auth, which would otherwise start
    // restoring a session against the wrong endpoint.
    await FirebaseAuth.instance.useAuthEmulator(_emulatorHost, 9099);
    FirebaseFirestore.instance.useFirestoreEmulator(_emulatorHost, 8080);

    db = FirebaseFirestore.instance;
    assets = AssetService(firestore: db);
    movements = DeploymentService(firestore: db);
    bazaars = BazaarService(firestore: db);

    // Names have to be unique per run: the services reject duplicates, and the
    // rules forbid deleting deployments and bazaars, so earlier runs linger.
    runId = DateTime.now().millisecondsSinceEpoch.toRadixString(36);

    await signInAs(_approverEmail);
  });

  /// A fresh asset for one scenario. Created as the approver (super_admin).
  Future<AssetModel> seedAsset(String tag, {int quantity = 40}) async {
    final id = await assets.addAsset(
      AssetModel(
        id: '',
        assetId: 'CONC-$tag-$runId',
        name: 'Concurrency probe $tag $runId',
        category: 'Laptop',
        status: 'Available',
        condition: 'Good',
        quantity: quantity,
        headOfficeQuantity: quantity,
        purchasePrice: 1000,
        location: 'Head Office',
        adminId: 'conc-admin',
        notes: 'TEST DATA - concurrency probe',
      ),
    );

    final snapshot = await db.collection('assets').doc(id).get();
    return AssetModel.fromMap(snapshot.data()!, id);
  }

  /// Files a Pending request the way a real requester would, then hands the
  /// session back to the approver.
  Future<DocumentReference<Map<String, dynamic>>> fileRequest(
    Map<String, dynamic> fields,
  ) async {
    final requesterUid = await signInAs(_requesterEmail);

    final ref = await db.collection('requests').add({
      ...fields,
      'status': 'Pending',
      'requestedBy': requesterUid,
      'notes': 'TEST DATA - concurrency probe',
    });

    await signInAs(_approverEmail);
    return ref;
  }

  Future<AssetModel> reload(String id) async {
    final snapshot = await db.collection('assets').doc(id).get();
    return AssetModel.fromMap(snapshot.data()!, id);
  }

  Future<int> movementCount(String assetDocumentId) async {
    final all = await db
        .collection('deployments')
        .where('assetDocumentId', isEqualTo: assetDocumentId)
        .get();

    return all.docs.length;
  }

  /// Runs [attempt] [_racers] times at once and reports how many committed.
  ///
  /// The futures are created without awaiting, so they are genuinely in
  /// flight together and really do contend inside Firestore.
  Future<({int ok, int failed, List<String> errors})> race(
    Future<void> Function(int attempt) attempt,
  ) async {
    final outcomes = await Future.wait(
      List.generate(
        _racers,
        (i) => attempt(i).then<String?>((_) => null).catchError((Object e) {
          return e.toString().replaceAll('\n', ' ');
        }),
      ),
    );

    final errors = outcomes.whereType<String>().toList();

    return (
      ok: outcomes.length - errors.length,
      failed: errors.length,
      errors: errors,
    );
  }

  // =========================================================================
  // D1 - ASSIGNMENT
  // =========================================================================

  testWidgets('concurrent approvals of one Assignment request', (_) async {
    final asset = await seedAsset('ASSIGN');
    final movementsBefore = await movementCount(asset.id);

    final request = await fileRequest({
      'requestType': 'Assignment',
      'assetId': asset.id,
      'assetName': asset.name,
      'receiverId': FirebaseAuth.instance.currentUser?.uid ?? '',
      'assigneeId': 'conc-holder',
      'assigneeName': 'Concurrency Holder',
    });

    // The service call an approval makes, bypassing RequestService's
    // pre-flight so that every racer really reaches the transaction and the
    // exactly-once guard is what has to separate them.
    final result = await race(
      (i) => assets.assignAsset(
        assetId: asset.id,
        userId: 'conc-holder',
        approvalRequestRef: request,
        approvalRequestUpdate: {'approvedBy': 'Admin $i'},
      ),
    );

    final after = await reload(asset.id);
    final settled = await request.get();
    final movementsAfter = await movementCount(asset.id);

    // ignore: avoid_print
    print('D1 RESULT ok=${result.ok} failed=${result.failed} '
        'status=${settled.data()!['status']} '
        'approvedBy=${settled.data()!['approvedBy']} '
        'assignedTo=${after.assignedTo} statusField=${after.status} '
        'assigned=${after.calculatedAssignedQuantity} '
        'headOffice=${after.calculatedHeadOfficeQuantity} '
        'deployed=${after.calculatedDeployedQuantity} qty=${after.quantity} '
        'movements=$movementsBefore->$movementsAfter');
    // ignore: avoid_print
    print('D1 ERRORS ${result.errors.join(" || ")}');

    expect(result.ok, 1, reason: 'exactly one approval may commit');
    expect(result.failed, _racers - 1);

    expect(settled.data()!['status'], 'Approved');

    // Exactly ONE stock movement happened: the 40 at Head Office became 40
    // assigned, once. A second commit would read 80 assigned / -40 at Head
    // Office, or be refused outright.
    expect(after.assignedTo, 'conc-holder');
    expect(after.status, 'Assigned');
    expect(after.calculatedAssignedQuantity, 40);
    expect(after.calculatedHeadOfficeQuantity, 0);
    expect(after.calculatedDeployedQuantity, 0);
    expect(
      after.calculatedHeadOfficeQuantity +
          after.calculatedAssignedQuantity +
          after.calculatedDeployedQuantity,
      after.quantity,
    );

    // An assignment is not a bazaar movement, so it must not have written one.
    expect(movementsAfter, movementsBefore);

    await db.collection('assets').doc(asset.id).delete();
    await request.delete();
  });

  // =========================================================================
  // D2 - RETURN TO HEAD OFFICE
  // =========================================================================

  testWidgets('concurrent approvals of one Return request', (_) async {
    final asset = await seedAsset('RETURN');

    final bazaarId = await bazaars.createBazaar(
      name: 'CONC Township Bazaar $runId',
      location: 'Lahore',
    );

    // Send stock out, so there is something to bring back.
    await movements.transferAsset(
      assetDocumentId: asset.id,
      sourceId: '',
      sourceName: 'Head Office',
      destinationId: bazaarId,
      destinationName: 'CONC Township Bazaar $runId',
      quantity: 10,
      transferredBy: 'conc-admin',
      transferredByName: 'Concurrency Admin',
    );

    final deployed = await reload(asset.id);
    expect(deployed.calculatedDeployedQuantity, 10);

    final movementsBefore = await movementCount(asset.id);

    final request = await fileRequest({
      'requestType': 'Transfer',
      'assetId': asset.id,
      'assetName': asset.name,
      'receiverId': FirebaseAuth.instance.currentUser?.uid ?? '',
      'sourceBazaarId': bazaarId,
      'sourceBazaarName': 'CONC Township Bazaar $runId',
      'destinationBazaarId': DeploymentService.headOfficeId,
      'destinationBazaarName': 'Head Office',
      'transferQuantity': 10,
    });

    final result = await race(
      (i) => movements.transferAsset(
        assetDocumentId: asset.id,
        sourceId: bazaarId,
        sourceName: 'CONC Township Bazaar $runId',
        destinationId: DeploymentService.headOfficeId,
        destinationName: 'Head Office',
        quantity: 10,
        transferredBy: 'conc-admin',
        transferredByName: 'Admin $i',
        approvalRequestRef: request,
        approvalRequestUpdate: {'approvedBy': 'Admin $i'},
      ),
    );

    final after = await reload(asset.id);
    final settled = await request.get();
    final movementsAfter = await movementCount(asset.id);

    // ignore: avoid_print
    print('D2 RESULT ok=${result.ok} failed=${result.failed} '
        'status=${settled.data()!['status']} '
        'approvedBy=${settled.data()!['approvedBy']} '
        'movements=$movementsBefore->$movementsAfter '
        'headOffice=${after.calculatedHeadOfficeQuantity} '
        'deployed=${after.calculatedDeployedQuantity} '
        'assigned=${after.calculatedAssignedQuantity} qty=${after.quantity}');
    // ignore: avoid_print
    print('D2 ERRORS ${result.errors.join(" || ")}');

    expect(result.ok, 1, reason: 'exactly one return may commit');
    expect(result.failed, _racers - 1);

    expect(settled.data()!['status'], 'Approved');

    // Exactly ONE return movement was added.
    expect(movementsAfter, movementsBefore + 1);

    // The original outbound record is still there.
    final outbound = await db
        .collection('deployments')
        .where('assetDocumentId', isEqualTo: asset.id)
        .where('toBazaarId', isEqualTo: bazaarId)
        .get();
    expect(outbound.docs, isNotEmpty, reason: 'the transfer out was lost');

    expect(after.calculatedHeadOfficeQuantity, 40);
    expect(after.calculatedDeployedQuantity, 0);
    expect(
      after.calculatedHeadOfficeQuantity +
          after.calculatedAssignedQuantity +
          after.calculatedDeployedQuantity,
      after.quantity,
    );

    // deployments and bazaars are append-only by rule (`allow delete: if
    // false`) - that audit trail is deliberately not deletable, so only the
    // asset and the request are cleaned up.
    await db.collection('assets').doc(asset.id).delete();
    await request.delete();
  });
}
