// On-device integration tests against the Firebase Local Emulator Suite.
//
//   1. firebase emulators:start --only firestore,auth --project it-inventory-8e690
//      (the emulator loads this project's firestore.rules)
//   2. flutter test integration_test/emulator_test.dart -d <android-emulator>
//
// Nothing here touches the production Firebase project.

// Provider state is inspected between UI steps in this end-to-end test.
// ignore_for_file: use_build_context_synchronously

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart' hide AuthProvider;
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:integration_test/integration_test.dart';
import 'package:provider/provider.dart';

import 'package:it_management_system/app.dart';
import 'package:it_management_system/core/providers/asset_provider.dart';
import 'package:it_management_system/core/providers/auth_provider.dart';
import 'package:it_management_system/core/providers/bazaar_provider.dart';
import 'package:it_management_system/core/providers/deployment_provider.dart';
import 'package:it_management_system/core/providers/log_provider.dart';
import 'package:it_management_system/core/providers/notification_provider.dart';
import 'package:it_management_system/core/providers/request_provider.dart';
import 'package:it_management_system/core/providers/theme_provider.dart';
import 'package:it_management_system/core/providers/user_provider.dart';
import 'package:it_management_system/core/services/asset_service.dart';
import 'package:it_management_system/core/services/deployment_service.dart';
import 'package:it_management_system/core/services/request_service.dart';
import 'package:it_management_system/core/services/user_service.dart';
import 'package:it_management_system/models/asset_model.dart';
import 'package:it_management_system/models/request_model.dart';
import 'package:it_management_system/models/user_model.dart';

import 'emulator_support.dart';
import 'support/fixtures.dart';


RequestModel editRequest(String uid, String assetId, Map<String, dynamic> proposed) {
  return RequestModel(
    requestType: 'Edit',
    assetId: assetId,
    assetName: proposed['name']?.toString() ?? 'Asset',
    requestedBy: uid,
    reason: 'Integration test edit',
    proposedAssetData: proposed,
  );
}

Future<String> latestRequestIdBy(String uid) async {
  final snapshot = await db
      .collection('requests')
      .where('requestedBy', isEqualTo: uid)
      .get();

  final docs = snapshot.docs.toList()
    ..sort((a, b) {
      final at = a.data()['requestDate'] as Timestamp?;
      final bt = b.data()['requestDate'] as Timestamp?;
      return (bt?.millisecondsSinceEpoch ?? 0).compareTo(at?.millisecondsSinceEpoch ?? 0);
    });

  return docs.first.id;
}

Future<void> pumpUntil(
  WidgetTester tester,
  Finder finder, {
  Duration timeout = const Duration(seconds: 30),
}) async {
  final end = DateTime.now().add(timeout);

  while (DateTime.now().isBefore(end)) {
    await tester.pump(const Duration(milliseconds: 200));

    if (finder.evaluate().isNotEmpty) {
      return;
    }
  }

  throw TestFailure('Timed out waiting for $finder');
}

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  setUpAll(() async {
    await initFirebaseForEmulator();
  });

  // ===========================================================================
  // SECURITY RULES: normal User
  // ===========================================================================

  testWidgets('User: scoped reads only, no direct writes, no self-promotion', (tester) async {
    await seedFixtures();
    await signInAs(userAEmail, password);

    // Own profile readable; other profiles are not.
    await db.collection('users').doc(userAUid).get();
    expect(await isDenied(() => db.collection('users').doc(adminAUid).get()), isTrue);

    // Cannot change own role / status / ownership.
    expect(await isDenied(() => db.collection('users').doc(userAUid).update({'role': 'super_admin', 'roles': ['super_admin']})), isTrue);
    expect(await isDenied(() => db.collection('users').doc(userAUid).update({'status': 'active', 'createdBy': adminBUid})), isTrue);

    // Descriptive self-update is allowed.
    await UserService().updateOwnProfileName(uid: userAUid, name: 'Usman Updated');

    // Inventory: only the assigned Admin's inventory (scoped list query).
    final scoped = await db.collection('assets').where('adminId', isEqualTo: adminAUid).get();
    expect(scoped.docs.map((d) => d.id), ['assetA']);
    expect(await isDenied(() => db.collection('assets').doc('assetB').get()), isTrue);
    expect(await isDenied(() => db.collection('assets').get()), isTrue);

    // No direct inventory / movement writes.
    expect(await isDenied(() => db.collection('assets').doc('assetA').update({'quantity': 1, 'headOfficeQuantity': 1})), isTrue);
    expect(await isDenied(() => db.collection('assets').doc('assetA').delete()), isTrue);
    expect(await isDenied(() => db.collection('assets').add(assetFixture(adminId: adminAUid, name: 'X', quantity: 1))), isTrue);
    expect(await isDenied(() => db.collection('deployments').add({'assetDocumentId': 'assetA', 'quantity': 5, 'status': 'Active'})), isTrue);
    expect(await isDenied(() => db.collection('bazaars').doc('Z').set({'name': 'Hack'})), isTrue);

    // Requests: allowed for own Admin's inventory, atomically with notifications.
    await RequestService().createRequest(editRequest(userAUid, 'assetA', {'name': 'LaptopA', 'quantity': 120}));

    final requestId = await latestRequestIdBy(userAUid);
    final request = (await db.collection('requests').doc(requestId).get()).data()!;
    expect(request['status'], 'Pending');
    expect(request['receiverId'], adminAUid);
    expect(request['assetAdminId'], adminAUid);

    final myNotifications = await db.collection('notifications').where('userId', isEqualTo: userAUid).get();
    expect(myNotifications.docs, isNotEmpty);

    // The original asset is untouched before approval.
    expect((await db.collection('assets').where('adminId', isEqualTo: adminAUid).get()).docs.single.data()['quantity'], 100);

    // Cannot request changes to another Admin's inventory, or approve own request.
    expect(await isDenied(() => RequestService().createRequest(editRequest(userAUid, 'assetB', {'quantity': 1}))), isTrue);
    expect(await isDenied(() => db.collection('requests').doc(requestId).update({'status': 'Approved'})), isTrue);
  });

  testWidgets('Disabled user and unassigned public signup are locked out of data', (tester) async {
    await seedFixtures();

    await signInAs(disabledEmail, password);
    final own = await db.collection('users').doc(disabledUid).get();
    expect(own.data()!['status'], 'disabled', reason: 'disabled accounts can read why they are blocked');
    expect(await isDenied(() => db.collection('assets').where('adminId', isEqualTo: adminAUid).get()), isTrue);
    expect(await isDenied(() => db.collection('bazaars').get()), isTrue);
    expect(await isDenied(() => db.collection('requests').add({'requestedBy': disabledUid, 'status': 'Pending'})), isTrue);

    final signupUid = await createAuthUser('new.signup@test.local', password);
    await signInAs('new.signup@test.local', password);

    expect(
      await isDenied(() => db.collection('users').doc(signupUid).set(userProfile(uid: signupUid, name: 'Evil', email: 'x', role: 'admin'))),
      isTrue,
      reason: 'public signup cannot create an Admin',
    );
    expect(
      await isDenied(() => db.collection('users').doc(signupUid).set({
        ...userProfile(uid: signupUid, name: 'Evil', email: 'x', role: 'user'),
        'roles': ['super_admin'],
      })),
      isTrue,
      reason: 'roles cannot be injected',
    );

    await db.collection('users').doc(signupUid).set(userProfile(uid: signupUid, name: 'New', email: 'new.signup@test.local', role: 'user'));

    expect(await isDenied(() => db.collection('deployments').limit(1).get()), isTrue);
    expect(await isDenied(() => db.collection('assets').where('adminId', isEqualTo: '').get()), isTrue);
  });

  // ===========================================================================
  // SECURITY RULES: Admin
  // ===========================================================================

  testWidgets('Admin: own inventory, no ownership/stock tampering, cannot escalate', (tester) async {
    await seedFixtures();
    await signInAs(adminAEmail, password);

    final assets = AssetService();

    await assets.addAsset(AssetModel(id: '', assetId: 'NEW-1', name: 'New', category: 'Laptop', status: 'Available', quantity: 5, adminId: adminAUid));
    expect(
      await isDenied(() => assets.addAsset(AssetModel(id: '', assetId: 'NEW-2', name: 'New', category: 'Laptop', status: 'Available', quantity: 5, adminId: adminBUid))),
      isTrue,
    );

    // Server-side stock invariant.
    expect(await isDenied(() => db.collection('assets').doc('assetA').update({'headOfficeQuantity': 999})), isTrue);
    expect(await isDenied(() => db.collection('assets').doc('assetB').update({'adminId': adminAUid})), isTrue);

    // Movement through the transactional service; history cannot be deleted.
    final movementId = await DeploymentService().transferAsset(
      assetDocumentId: 'assetA',
      sourceId: '__head_office__',
      sourceName: 'Head Office',
      destinationId: 'A',
      destinationName: 'Bazaar A',
      quantity: 10,
    );
    expect((await assetData('assetA'))['headOfficeQuantity'], 90);
    expect(await isDenied(() => db.collection('deployments').doc(movementId).delete()), isTrue);
    expect(await isDenied(() => db.collection('deployments').doc(movementId).update({'assetDocumentId': 'assetA', 'quantity': 500})), isTrue);

    await expectLater(
      DeploymentService().transferAsset(assetDocumentId: 'assetA', sourceId: '__head_office__', sourceName: 'Head Office', destinationId: 'C', destinationName: 'Bazaar C', quantity: 1),
      throwsA(isA<Exception>()),
      reason: 'disabled Bazaar',
    );

    // User management boundaries.
    final newUid = await createAuthUser('made.by.admin@test.local', password);
    expect(await isDenied(() => db.collection('users').doc(newUid).set(userProfile(uid: newUid, name: 'N', email: 'n', role: 'admin', createdBy: adminAUid))), isTrue);
    await db.collection('users').doc(newUid).set(userProfile(uid: newUid, name: 'N', email: 'n', role: 'user', createdBy: adminAUid));
    expect(await isDenied(() => db.collection('users').doc(userAUid).update({'role': 'admin', 'roles': ['admin']})), isTrue);
    expect(await isDenied(() => db.collection('users').doc(adminAUid).update({'role': 'super_admin', 'roles': ['super_admin']})), isTrue);

    expect(await isDenied(() => db.collection('bazaars').doc('A').update({'name': 'Renamed', 'isActive': false})), isTrue);
  });

  testWidgets('Edit approval applies exactly once, recomputes stock, respects ownership', (tester) async {
    await seedFixtures();

    // Stock already at a Bazaar before the edit is approved.
    await signInAs(adminAEmail, password);
    await DeploymentService().transferAsset(assetDocumentId: 'assetA', sourceId: '__head_office__', sourceName: 'Head Office', destinationId: 'A', destinationName: 'Bazaar A', quantity: 30);

    await signInAs(userAEmail, password);
    await RequestService().createRequest(editRequest(userAUid, 'assetA', {'name': 'LaptopA Pro', 'quantity': 120, 'headOfficeQuantity': 120, 'deployedQuantity': 0}));
    final requestId = await latestRequestIdBy(userAUid);

    // Another Admin cannot process it.
    await signInAs(adminBEmail, password);
    expect(await isDenied(() => db.collection('requests').doc(requestId).update({'status': 'Approved'})), isTrue);

    await signInAs(adminAEmail, password);
    await RequestService().updateRequestStatus(requestId: requestId, status: 'Approved', remarks: 'ok', approvedBy: 'Adeel');

    final data = await assetData('assetA');
    expect(data['name'], 'LaptopA Pro');
    expect(data['quantity'], 120);
    expect(data['deployedQuantity'], 30, reason: 'stale proposed stock fields are ignored');
    expect(data['headOfficeQuantity'], 90);

    await expectLater(
      RequestService().updateRequestStatus(requestId: requestId, status: 'Approved', remarks: 'again', approvedBy: 'Adeel'),
      throwsA(isA<Exception>()),
    );
    expect((await assetData('assetA'))['quantity'], 120);

    // Reducing below allocated stock is refused at approval time.
    await signInAs(userAEmail, password);
    await RequestService().createRequest(editRequest(userAUid, 'assetA', {'quantity': 10}));
    final lowRequest = await latestRequestIdBy(userAUid);

    await signInAs(adminAEmail, password);
    await expectLater(
      RequestService().updateRequestStatus(requestId: lowRequest, status: 'Approved', remarks: '', approvedBy: 'Adeel'),
      throwsA(isA<Exception>()),
    );
    expect((await db.collection('requests').doc(lowRequest).get()).data()!['status'], 'Pending');
  });

  // ===========================================================================
  // SUPER ADMIN
  // ===========================================================================

  testWidgets('Super Admin: create User for an Admin, Bazaar master, soft delete, no self-approval', (tester) async {
    await seedFixtures();
    await signInAs(superAdminEmail, password);

    final newUid = await createAuthUser('assigned.user@test.local', password);

    await UserService().createUserProfileForSuperAdmin(
      user: UserModel(uid: newUid, name: 'Assigned', email: 'assigned.user@test.local', role: 'user', status: 'active'),
      superAdminUid: superAdminUid,
      superAdminEmail: superAdminEmail,
      adminUid: adminAUid,
    );
    expect((await db.collection('users').doc(newUid).get()).data()!['createdBy'], adminAUid);

    // Bazaar master: create / disable allowed, delete denied.
    final bazaarRef = await db.collection('bazaars').add({'name': 'Test Bazaar', 'location': 'Lahore', 'isActive': true, 'status': 'Active'});
    await bazaarRef.update({'name': 'Test Bazaar', 'isActive': false, 'status': 'Disabled'});
    expect(await isDenied(() => bazaarRef.delete()), isTrue);

    // Soft delete keeps the profile so the Auth account cannot re-register.
    await UserService().deleteUser(userAUid);
    expect((await db.collection('users').doc(userAUid).get()).data()!['status'], 'deleted');

    await signInAs(userAEmail, password);
    expect(await isDenied(() => db.collection('assets').where('adminId', isEqualTo: adminAUid).get()), isTrue);
    expect(await isDenied(() => db.collection('users').doc(userAUid).set(userProfile(uid: userAUid, name: 'Back', email: userAEmail, role: 'user'))), isTrue);

    // Nobody approves their own request.
    await signInAs(superAdminEmail, password);
    await RequestService().createRequest(editRequest(superAdminUid, 'assetA', {'name': 'Self'}));
    final ownRequest = await latestRequestIdBy(superAdminUid);
    await expectLater(
      RequestService().updateRequestStatus(requestId: ownRequest, status: 'Approved', remarks: '', approvedBy: 'Sara'),
      throwsA(isA<Exception>()),
    );
    expect(await isDenied(() => db.collection('requests').doc(ownRequest).update({'status': 'Approved'})), isTrue);
  });

  // ===========================================================================
  // USER MANAGEMENT: signup profile, profile editing, role changes
  // ===========================================================================

  testWidgets('Public signup collects the profile and always creates a plain User', (tester) async {
    await seedFixtures();
    await signOutAndWait();

    final themeProvider = ThemeProvider();
    await themeProvider.loadTheme();

    await tester.pumpWidget(
      MultiProvider(
        providers: [
          ChangeNotifierProvider<AuthProvider>(create: (_) => AuthProvider()..initialize()),
          ChangeNotifierProvider<AssetProvider>(create: (_) => AssetProvider()),
          ChangeNotifierProvider<UserProvider>(create: (_) => UserProvider()),
          ChangeNotifierProvider<RequestProvider>(create: (_) => RequestProvider()),
          ChangeNotifierProvider<NotificationProvider>(create: (_) => NotificationProvider()),
          ChangeNotifierProvider<LogProvider>(create: (_) => LogProvider()),
          ChangeNotifierProvider<ThemeProvider>.value(value: themeProvider),
          ChangeNotifierProvider<DeploymentProvider>(create: (_) => DeploymentProvider()),
          ChangeNotifierProvider<BazaarProvider>(create: (_) => BazaarProvider()),
        ],
        child: const App(),
      ),
    );

    await pumpUntil(tester, find.text('Sign in'));
    GoRouter.of(tester.element(find.text('Sign in').first)).go('/signup');
    await pumpUntil(tester, find.widgetWithText(TextFormField, 'Full name'));

    const email = 'signup.e2e@test.local';

    await tester.enterText(find.widgetWithText(TextFormField, 'Full name'), 'Signup E2E User');
    await tester.enterText(find.widgetWithText(TextFormField, 'Department'), 'Finance');
    await tester.enterText(find.widgetWithText(TextFormField, 'Designation'), 'Accounts Officer');
    await tester.enterText(find.widgetWithText(TextFormField, 'Employee ID (optional)'), 'EMP-9001');
    await tester.enterText(find.widgetWithText(TextFormField, 'Email address'), email);
    await tester.enterText(find.widgetWithText(TextFormField, 'Password'), password);
    await tester.enterText(find.widgetWithText(TextFormField, 'Confirm password'), password);

    await tester.tap(find.widgetWithText(FilledButton, 'Create account'));

    // The profile is written under the Firebase Auth UID, as a plain User.
    // Read with the emulator owner token: the account signs out right after
    // signup, and the rules (correctly) do not allow querying users by email.
    Map<String, dynamic>? profile;
    final deadline = DateTime.now().add(const Duration(seconds: 30));
    while (DateTime.now().isBefore(deadline)) {
      await tester.pump(const Duration(milliseconds: 250));
      final docs = await adminListCollection('users');
      final match = docs.where((d) => d['email'] == email);
      if (match.isNotEmpty) {
        profile = match.first;
        signupUid = match.first['id'] as String;
        break;
      }
    }

    if (profile == null) {
      final visible = find
          .byType(Text)
          .evaluate()
          .map((e) => (e.widget as Text).data ?? '')
          .where((t) => t.trim().isNotEmpty)
          .join(' | ');
      debugPrint('DIAG signup screen: $visible');
    }

    expect(profile, isNotNull, reason: 'signup wrote the profile');
    expect(profile!['name'], 'Signup E2E User');
    expect(profile['department'], 'Finance');
    expect(profile['designation'], 'Accounts Officer');
    expect(profile['employeeId'], 'EMP-9001');
    expect(profile['role'], 'user');
    expect(profile['roles'], ['user']);
    expect(profile['status'], 'active');
    expect(profile['createdBy'], '');
    expect(profile['uid'], signupUid, reason: 'profile stays bound to its Auth UID');
  });

  testWidgets('A self-signed-up account cannot inject privileges or extra fields', (tester) async {
    await seedFixtures();
    // A verified account with no profile yet (an unverified one is refused
    // everywhere by design, which is covered by its own test).
    final uid = await createAuthUser('selfmade@test.local', password);
    await signInAs('selfmade@test.local', password);

    Map<String, dynamic> base(Map<String, dynamic> overrides) => {
      'uid': uid,
      'name': 'Self Made',
      'email': 'selfmade@test.local',
      'role': 'user',
      'roles': ['user'],
      'status': 'active',
      'employeeId': '',
      'department': '',
      'designation': '',
      'createdBy': '',
      'createdByEmail': '',
      'organizationId': '',
      ...overrides,
    };

    // Privileged role, foreign ownership, a spoofed email and unknown keys are
    // all refused by the rules, whatever the client sends.
    expect(await isDenied(() => db.collection('users').doc(uid).set(base({'role': 'admin', 'roles': ['admin']}))), isTrue);
    expect(await isDenied(() => db.collection('users').doc(uid).set(base({'role': 'super_admin', 'roles': ['super_admin']}))), isTrue);
    expect(await isDenied(() => db.collection('users').doc(uid).set(base({'createdBy': adminAUid}))), isTrue);
    expect(await isDenied(() => db.collection('users').doc(uid).set(base({'adminId': adminAUid}))), isTrue);
    expect(await isDenied(() => db.collection('users').doc(uid).set(base({'email': 'someone.else@test.local'}))), isTrue);
    expect(await isDenied(() => db.collection('users').doc(uid).set(base({'status': 'approved'}))), isTrue);

    // The honest profile is accepted.
    await db.collection('users').doc(uid).set(base({}));
    expect((await db.collection('users').doc(uid).get()).data()!['role'], 'user');

    // ... and cannot then promote itself or change its own status.
    expect(await isDenied(() => db.collection('users').doc(uid).update({'role': 'admin', 'roles': ['admin']})), isTrue);
    expect(await isDenied(() => db.collection('users').doc(uid).update({'status': 'blocked'})), isTrue);
    expect(await isDenied(() => db.collection('users').doc(uid).update({'createdBy': adminAUid})), isTrue);

    // Descriptive self-edits are allowed.
    await db.collection('users').doc(uid).update({'department': 'Audit'});
    expect((await db.collection('users').doc(uid).get()).data()!['department'], 'Audit');
  });

  testWidgets('Super Admin edits a profile: details, status, role and assigned Admin', (tester) async {
    await seedFixtures();
    await signInAs(superAdminEmail, password);

    final users = UserProvider();
    addTearDown(users.dispose);
    await users.loadCurrentUserProfile(forceRefresh: true);

    final target = await UserService().getUserById(userAUid);
    expect(target, isNotNull);

    // Descriptive fields.
    await users.updateUser(
      target!.copyWith(
        name: 'Usman Updated',
        department: 'Operations',
        designation: 'Store Keeper',
        employeeId: 'EMP-7007',
      ),
    );

    var stored = (await db.collection('users').doc(userAUid).get()).data()!;
    expect(stored['name'], 'Usman Updated');
    expect(stored['department'], 'Operations');
    expect(stored['designation'], 'Store Keeper');
    expect(stored['employeeId'], 'EMP-7007');
    expect(stored['role'], 'user', reason: 'a details edit never changes the role');

    // Assigned Admin (inventory scope).
    await users.updateAssignedAdmin(userAUid, adminBUid);
    stored = (await db.collection('users').doc(userAUid).get()).data()!;
    expect(stored['createdBy'], adminBUid);
    expect(stored['adminId'], adminBUid);

    await users.updateAssignedAdmin(userAUid, '');
    stored = (await db.collection('users').doc(userAUid).get()).data()!;
    expect(stored['createdBy'], '');

    // Status.
    await users.updateUserStatus(userAUid, 'blocked');
    expect((await db.collection('users').doc(userAUid).get()).data()!['status'], 'blocked');
    await users.updateUserStatus(userAUid, 'active');

    // Role: user -> admin, and the roles array follows the primary role.
    await users.updateUserRole(userAUid, 'admin');
    stored = (await db.collection('users').doc(userAUid).get()).data()!;
    expect(stored['role'], 'admin');
    expect(stored['roles'], ['admin']);

    // Promotion to Super Admin keeps the existing Super Admin untouched.
    await users.promoteToSuperAdmin(userAUid);
    expect((await db.collection('users').doc(userAUid).get()).data()!['role'], 'super_admin');
    expect((await db.collection('users').doc(superAdminUid).get()).data()!['role'], 'super_admin');
  });

  testWidgets('An Admin may fix user details but never role, status or ownership', (tester) async {
    await seedFixtures();

    // A self-signed-up account: no owning Admin yet.
    await signOutAndWait();
    final credential = await FirebaseAuth.instance.createUserWithEmailAndPassword(
      email: 'unassigned@test.local',
      password: password,
    );
    final unassignedUid = credential.user!.uid;
    await seedDocument('users/$unassignedUid', userProfile(uid: unassignedUid, name: 'Unassigned Person', email: 'unassigned@test.local', role: 'user'));

    await signInAs(adminAEmail, password);

    final users = UserProvider();
    addTearDown(users.dispose);
    await users.loadCurrentUserProfile(forceRefresh: true);

    final target = await UserService().getUserById(unassignedUid);

    // Allowed: descriptive maintenance of an unassigned account.
    await users.updateUser(
      target!.copyWith(name: 'Unassigned Person', department: 'IT', designation: 'Technician', employeeId: 'EMP-3003'),
    );

    final stored = (await db.collection('users').doc(unassignedUid).get()).data()!;
    expect(stored['department'], 'IT');
    expect(stored['designation'], 'Technician');
    expect(stored['employeeId'], 'EMP-3003');

    // Refused by the provider AND by the rules.
    await expectLater(users.updateUserRole(unassignedUid, 'admin'), throwsA(isA<Exception>()));
    await expectLater(users.updateUserStatus(unassignedUid, 'blocked'), throwsA(isA<Exception>()));
    await expectLater(users.updateAssignedAdmin(unassignedUid, adminAUid), throwsA(isA<Exception>()));
    await expectLater(users.promoteToSuperAdmin(unassignedUid), throwsA(isA<Exception>()));

    expect(await isDenied(() => db.collection('users').doc(unassignedUid).update({'role': 'admin', 'roles': ['admin']})), isTrue);
    expect(await isDenied(() => db.collection('users').doc(unassignedUid).update({'status': 'blocked'})), isTrue);
    expect(await isDenied(() => db.collection('users').doc(unassignedUid).update({'createdBy': adminAUid})), isTrue);

    // Profiles are soft-deleted, never removed (a leftover Auth account must
    // not be able to re-register itself).
    expect(await isDenied(() => db.collection('users').doc(unassignedUid).delete()), isTrue);
    await UserService().deleteUser(unassignedUid);
    expect((await db.collection('users').doc(unassignedUid).get()).data()!['status'], 'deleted');
  });

  testWidgets('Android: Super Admin changes the owning Admin from the profile editor', (tester) async {
    await seedFixtures();
    await signOutAndWait();

    final themeProvider = ThemeProvider();
    await themeProvider.loadTheme();

    await tester.pumpWidget(
      MultiProvider(
        providers: [
          ChangeNotifierProvider<AuthProvider>(create: (_) => AuthProvider()..initialize()),
          ChangeNotifierProvider<AssetProvider>(create: (_) => AssetProvider()),
          ChangeNotifierProvider<UserProvider>(create: (_) => UserProvider()),
          ChangeNotifierProvider<RequestProvider>(create: (_) => RequestProvider()),
          ChangeNotifierProvider<NotificationProvider>(create: (_) => NotificationProvider()),
          ChangeNotifierProvider<LogProvider>(create: (_) => LogProvider()),
          ChangeNotifierProvider<ThemeProvider>.value(value: themeProvider),
          ChangeNotifierProvider<DeploymentProvider>(create: (_) => DeploymentProvider()),
          ChangeNotifierProvider<BazaarProvider>(create: (_) => BazaarProvider()),
        ],
        child: const App(),
      ),
    );

    await pumpUntil(tester, find.text('Sign in'));
    await tester.enterText(find.widgetWithText(TextFormField, 'Email address'), superAdminEmail);
    await tester.enterText(find.widgetWithText(TextFormField, 'Password'), password);
    await tester.tap(find.text('Sign in'));
    await pumpUntil(tester, find.text('Sara Super'));

    // The route guard only lets /users through once the profile and its
    // permissions are loaded, so the navigation is repeated until it sticks.
    final router = GoRouter.of(tester.element(find.text('Sara Super').first));
    final userRow = find.text('Usman UserA');

    for (var attempt = 0; attempt < 6 && userRow.evaluate().isEmpty; attempt++) {
      router.go('/users');
      for (var i = 0; i < 30 && userRow.evaluate().isEmpty; i++) {
        await tester.pump(const Duration(milliseconds: 200));
      }
    }

    if (userRow.evaluate().isEmpty) {
      final users = Provider.of<UserProvider>(
        tester.element(find.byType(Scaffold).first),
        listen: false,
      );
      final onScreen = tester
          .widgetList<Text>(find.byType(Text))
          .map((text) => text.data)
          .whereType<String>()
          .join(' | ');

      fail(
        'The Users page never listed the seeded user. '
        'location=${router.state.uri} loading=${users.isLoading} '
        'count=${users.users.length} error=${users.errorMessage} '
        'screen="$onScreen"',
      );
    }

    for (var i = 0; i < 12; i++) {
      await tester.pump(const Duration(milliseconds: 150));
    }

    Future<void> openEditorFor(String displayName) async {
      final row = find.ancestor(of: find.text(displayName), matching: find.byType(Card));
      final menu = find.descendant(of: row, matching: find.byType(PopupMenuButton<String>));
      await tester.ensureVisible(menu);
      await tester.pump(const Duration(milliseconds: 300));
      await tester.tap(menu);
      await pumpUntil(tester, find.text('Edit Profile'));
      await tester.tap(find.text('Edit Profile'));
      await pumpUntil(tester, find.text('Save Changes'));
      for (var i = 0; i < 6; i++) {
        await tester.pump(const Duration(milliseconds: 150));
      }
    }

    Future<void> chooseAssignedAdmin(String label) async {
      final field = find.byType(DropdownButtonFormField<String>);
      await tester.ensureVisible(field);
      await tester.pump(const Duration(milliseconds: 300));
      await tester.tap(field);
      for (var i = 0; i < 12; i++) {
        await tester.pump(const Duration(milliseconds: 150));
      }
      // The open menu is the last route, so its entry comes last in the tree.
      await tester.tap(find.text(label).last);
      for (var i = 0; i < 10; i++) {
        await tester.pump(const Duration(milliseconds: 150));
      }
    }

    Future<Map<String, dynamic>> waitForOwner(String expected) async {
      final deadline = DateTime.now().add(const Duration(seconds: 25));
      var stored = <String, dynamic>{};
      while (DateTime.now().isBefore(deadline)) {
        await tester.pump(const Duration(milliseconds: 250));
        stored = (await db.collection('users').doc(userAUid).get()).data() ?? {};
        if (stored['createdBy'] == expected) return stored;
      }
      return stored;
    }

    // ----- reassign the plain user from Admin A to Admin B -----
    await openEditorFor('Usman UserA');
    expect(find.text('Assigned Admin'), findsOneWidget);
    expect(
      find.descendant(
        of: find.byType(DropdownButtonFormField<String>),
        matching: find.text('Adeel AdminA'),
      ),
      findsWidgets,
      reason: 'the current owner is preselected in the field itself',
    );

    await chooseAssignedAdmin('Bilal AdminB');
    await tester.tap(find.widgetWithText(FilledButton, 'Save Changes'));

    var stored = await waitForOwner(adminBUid);
    expect(stored['createdBy'], adminBUid, reason: 'owning Admin stored in Firestore');
    expect(stored['adminId'], adminBUid);
    expect(stored['role'], 'user', reason: 'ownership never changes the role');
    await pumpUntil(tester, find.text('User profile updated successfully.'));

    // ----- detach the user from every Admin -----
    for (var i = 0; i < 20; i++) {
      await tester.pump(const Duration(milliseconds: 150));
    }
    await openEditorFor('Usman UserA');
    await chooseAssignedAdmin('Unassigned');
    await tester.tap(find.widgetWithText(FilledButton, 'Save Changes'));

    stored = await waitForOwner('');
    expect(stored['createdBy'], '', reason: 'the user is detached from its Admin');
    // Unassigning removes the ownership fields instead of blanking them.
    expect(stored['adminId'] ?? '', '');

    // ----- ownership applies to plain users only -----
    for (var i = 0; i < 20; i++) {
      await tester.pump(const Duration(milliseconds: 150));
    }
    await openEditorFor('Adeel AdminA');
    expect(find.text('Role'), findsOneWidget);
    expect(find.text('Assigned Admin'), findsNothing);
    await tester.tap(find.widgetWithText(TextButton, 'Cancel'));
    for (var i = 0; i < 10; i++) {
      await tester.pump(const Duration(milliseconds: 150));
    }
  });

  // ===========================================================================
  // SUPER ADMIN HANDOVER (no account is special; always >= 1 Super Admin)
  // ===========================================================================

  testWidgets('Super Admin handover: appoint, independent control, remove, step down, audit log', (tester) async {
    await seedFixtures();

    Future<List<String>> auditActions() async {
      final logs = await db.collection('logs').get();
      return logs.docs.map((d) => d.data()['action'] as String).toList();
    }

    // An Admin cannot make anyone (including itself) Super Admin.
    await signInAs(adminAEmail, password);
    expect(await isDenied(() => db.collection('users').doc(adminBUid).update({'role': 'super_admin', 'roles': ['super_admin']})), isTrue);
    expect(await isDenied(() => db.collection('users').doc(adminAUid).update({'role': 'super_admin', 'roles': ['super_admin']})), isTrue);

    // 1. The current Super Admin appoints Admin A as an additional Super Admin.
    await signInAs(superAdminEmail, password);
    await UserService().promoteToSuperAdmin(actorUid: superAdminUid, targetUid: adminAUid);
    expect((await db.collection('users').doc(adminAUid).get()).data()!['role'], 'super_admin');
    expect(await auditActions(), contains('super_admin_appointed'));

    // A Super Admin can never remove its own role directly.
    await expectLater(UserService().demoteSuperAdmin(actorUid: superAdminUid, targetUid: superAdminUid), throwsA(isA<Exception>()));
    expect(await isDenied(() => db.collection('users').doc(superAdminUid).update({'role': 'admin', 'roles': ['admin']})), isTrue);

    // A User files a request before the handover completes.
    await signInAs(userAEmail, password);
    await RequestService().createRequest(editRequest(userAUid, 'assetA', {'name': 'LaptopA', 'notes': 'Needs label'}));
    final pendingRequest = await latestRequestIdBy(userAUid);

    // 2. The new Super Admin has full, independent control ...
    await signInAs(adminAEmail, password);
    await RequestService().updateRequestStatus(requestId: pendingRequest, status: 'Approved', remarks: 'ok', approvedBy: 'Adeel');
    expect((await db.collection('requests').doc(pendingRequest).get()).data()!['status'], 'Approved');
    await UserService().changeUserStatus(userAUid, 'blocked');
    await UserService().changeUserStatus(userAUid, 'active');
    await UserService().changeUserRole(disabledUid, 'admin');
    expect((await db.collection('users').doc(disabledUid).get()).data()!['role'], 'admin');
    expect((await db.collection('requests').get()).docs, isNotEmpty);
    expect((await db.collection('users').get()).docs.length, 5);
    await db.collection('assets').doc('assetB').update({'notes': 'Checked by new Super Admin'});
    await db.collection('bazaars').add({'name': 'Handover Bazaar', 'location': 'Lahore', 'isActive': true, 'status': 'Active'});

    // ... and removes the original Super Admin, who becomes Admin.
    await UserService().demoteSuperAdmin(actorUid: adminAUid, targetUid: superAdminUid);
    expect((await db.collection('users').doc(superAdminUid).get()).data()!['role'], 'admin');
    expect(await auditActions(), contains('super_admin_removed'));

    // 3. Hand over and step down in one commit: A -> Admin, B -> Super Admin.
    await UserService().transferSuperAdmin(currentSuperAdminUid: adminAUid, targetAdminUid: adminBUid);
    expect((await db.collection('users').doc(adminAUid).get()).data()!['role'], 'admin');
    expect((await db.collection('users').doc(adminBUid).get()).data()!['role'], 'super_admin');
    expect(await auditActions(), contains('super_admin_handover'));

    // Business data is untouched by every step.
    final assets = await db.collection('assets').get();
    expect(assets.docs.length, 2);
    expect((await assetData('assetA'))['quantity'], 100);

    // The former Super Admins have no Super Admin powers left.
    expect(await isDenied(() => db.collection('users').doc(adminBUid).update({'role': 'admin', 'roles': ['admin'], 'designation': 'Admin'})), isTrue);

    // Audit entries: only in one's own name, server-timed, never editable.
    expect(await isDenied(() => db.collection('logs').add({'action': 'fake', 'userId': adminBUid, 'createdAt': FieldValue.serverTimestamp()})), isTrue);
    expect(await isDenied(() => db.collection('logs').add({'action': 'backdated', 'userId': adminAUid, 'createdAt': Timestamp.fromDate(DateTime(2020))})), isTrue);
    final anyLog = (await db.collection('logs').limit(1).get()).docs.first.reference;
    expect(await isDenied(() => anyLog.update({'description': 'edited'})), isTrue);
    expect(await isDenied(() => anyLog.delete()), isTrue);

    // 4. The new Super Admin (B) standardizes legacy profiles; never promotes.
    await seedDocument('users/legacyAdmin', {'uid': 'legacyAdmin', 'name': 'Legacy', 'email': 'legacy@test.local', 'role': 'Admin', 'roles': ['Admin'], 'status': 'enabled', 'createdBy': ''});
    await seedDocument('users/legacyUser', {'uid': 'legacyUser', 'name': 'NoStatus', 'email': 'nostatus@test.local', 'role': 'user', 'createdBy': adminAUid});
    await seedDocument('users/legacySuper', {'uid': 'legacySuper', 'name': 'Odd', 'email': 'odd@test.local', 'role': 'Super Admin', 'status': 'Active', 'createdBy': ''});

    await signInAs(adminBEmail, password);
    expect(await UserService().standardizeLegacyProfiles(), 2);

    final legacyAdmin = (await db.collection('users').doc('legacyAdmin').get()).data()!;
    expect(legacyAdmin['role'], 'admin');
    expect(legacyAdmin['roles'], ['admin']);
    expect(legacyAdmin['status'], 'active');
    expect((await db.collection('users').doc('legacyUser').get()).data()!['status'], 'active');
    expect((await db.collection('users').doc('legacySuper').get()).data()!['role'], 'Super Admin');
  });

  testWidgets('Unverified email and movement visibility are enforced by the rules', (tester) async {
    await seedFixtures();

    // A real, active Admin profile whose Auth email is NOT verified.
    await signOutAndWait();
    final credential = await FirebaseAuth.instance.createUserWithEmailAndPassword(email: 'unverified@test.local', password: password);
    final unverifiedUid = credential.user!.uid;
    await seedDocument('users/$unverifiedUid', userProfile(uid: unverifiedUid, name: 'Unverified', email: 'unverified@test.local', role: 'admin', createdBy: superAdminUid));

    expect(await isDenied(() => db.collection('assets').get()), isTrue);
    expect(await isDenied(() => db.collection('users').get()), isTrue);
    // Its own profile stays readable, so the app can show the reason.
    expect((await db.collection('users').doc(unverifiedUid).get()).exists, isTrue);

    // Movement records created by the app carry the asset owner.
    await signInAs(adminAEmail, password);
    final movementA = await DeploymentService().transferAsset(assetDocumentId: 'assetA', sourceId: '__head_office__', sourceName: 'Head Office', destinationId: 'A', destinationName: 'Bazaar A', quantity: 2);
    await signInAs(superAdminEmail, password);
    await DeploymentService().transferAsset(assetDocumentId: 'assetB', sourceId: '__head_office__', sourceName: 'Head Office', destinationId: 'B', destinationName: 'Bazaar B', quantity: 1);

    // A closed record can never be re-opened as Active stock.
    await DeploymentService().transferAsset(assetDocumentId: 'assetA', sourceId: 'A', sourceName: 'Bazaar A', destinationId: '__head_office__', destinationName: 'Head Office', quantity: 2);
    expect(await isDenied(() => db.collection('deployments').doc(movementA).update({'status': 'Active'})), isTrue);

    // A User under Admin A sees only Admin A's movements.
    await signInAs(userAEmail, password);
    expect(await isDenied(() => db.collection('deployments').get()), isTrue);
    final visible = await DeploymentService().getDeployments().first;
    expect(visible, isNotEmpty);
    expect(visible.every((m) => m.assetDocumentId == 'assetA'), isTrue);
  });

  // ===========================================================================
  // CONCURRENCY (real Firestore transaction contention)
  // ===========================================================================

  testWidgets('Concurrent transfers and concurrent approvals never corrupt stock', (tester) async {
    await seedFixtures();
    await signInAs(superAdminEmail, password);

    Future<bool> attempt(Future<Object?> Function() action) async {
      try {
        await action();
        return true;
      } catch (_) {
        return false;
      }
    }

    final results = await Future.wait([
      attempt(() => DeploymentService().transferAsset(assetDocumentId: 'assetA', sourceId: '__head_office__', sourceName: 'Head Office', destinationId: 'A', destinationName: 'Bazaar A', quantity: 60)),
      attempt(() => DeploymentService().transferAsset(assetDocumentId: 'assetA', sourceId: '__head_office__', sourceName: 'Head Office', destinationId: 'B', destinationName: 'Bazaar B', quantity: 60)),
    ]);

    expect(results.where((ok) => ok).length, 1);

    var data = await assetData('assetA');
    expect(data['headOfficeQuantity'], 40);
    expect(data['deployedQuantity'], 60);

    // A transfer request approved twice at the same time moves stock once.
    await signInAs(userAEmail, password);
    await RequestService().createRequest(
      RequestModel(
        requestType: 'Transfer',
        assetId: 'assetA',
        assetName: 'LaptopA',
        requestedBy: userAUid,
        sourceBazaarId: '__head_office__',
        sourceBazaarName: 'Head Office',
        destinationBazaarId: 'B',
        destinationBazaarName: 'Bazaar B',
        transferQuantity: 5,
      ),
    );
    final transferRequest = await latestRequestIdBy(userAUid);

    await signInAs(adminAEmail, password);
    final approvals = await Future.wait([
      attempt(() => RequestService().updateRequestStatus(requestId: transferRequest, status: 'Approved', remarks: '', approvedBy: 'Adeel')),
      attempt(() => RequestService().updateRequestStatus(requestId: transferRequest, status: 'Approved', remarks: '', approvedBy: 'Adeel')),
    ]);

    expect(approvals.where((ok) => ok).length, 1);

    data = await assetData('assetA');
    expect(data['headOfficeQuantity'], 35);
    expect(data['deployedQuantity'], 65);
    expect(data['quantity'], 100);
  });

  // ===========================================================================
  // ADD ASSET FORM (Android navigation)
  // ===========================================================================

  testWidgets('Android: Add Asset opens the existing form with every section', (tester) async {
    await seedFixtures();
    await FirebaseAuth.instance.signOut();

    final themeProvider = ThemeProvider();
    await themeProvider.loadTheme();

    await tester.pumpWidget(
      MultiProvider(
        providers: [
          ChangeNotifierProvider<AuthProvider>(create: (_) => AuthProvider()..initialize()),
          ChangeNotifierProvider<AssetProvider>(create: (_) => AssetProvider()),
          ChangeNotifierProvider<UserProvider>(create: (_) => UserProvider()),
          ChangeNotifierProvider<RequestProvider>(create: (_) => RequestProvider()),
          ChangeNotifierProvider<NotificationProvider>(create: (_) => NotificationProvider()),
          ChangeNotifierProvider<LogProvider>(create: (_) => LogProvider()),
          ChangeNotifierProvider<ThemeProvider>.value(value: themeProvider),
          ChangeNotifierProvider<DeploymentProvider>(create: (_) => DeploymentProvider()),
          ChangeNotifierProvider<BazaarProvider>(create: (_) => BazaarProvider()),
        ],
        child: const App(),
      ),
    );

    await pumpUntil(tester, find.text('Sign in'));
    // Signed in as Super Admin: the form then also shows the Inventory Owner
    // selector, which an Admin does not see.
    await tester.enterText(find.widgetWithText(TextFormField, 'Email address'), superAdminEmail);
    await tester.enterText(find.widgetWithText(TextFormField, 'Password'), password);
    await tester.tap(find.text('Sign in'));
    await pumpUntil(tester, find.text('Sara Super'));

    // Inventory screen -> Add Asset.
    GoRouter.of(tester.element(find.text('Sara Super').first)).go('/assets');
    await pumpUntil(tester, find.byType(FloatingActionButton));
    await tester.tap(find.byType(FloatingActionButton));
    await pumpUntil(tester, find.text('Register New Asset'));

    for (final section in [
      'Basic Information',
      'Asset Details',
      'Purchase & Warranty',
      'Location & Condition',
      'Notes',
    ]) {
      expect(find.text(section), findsOneWidget, reason: section);
    }

    expect(find.widgetWithText(TextFormField, 'Asset ID / Tag'), findsOneWidget);
    expect(find.widgetWithText(TextFormField, 'Asset Name'), findsOneWidget);
    expect(find.widgetWithText(FilledButton, 'Save Asset'), findsOneWidget);
    expect(find.text('Inventory Owner (Admin)'), findsOneWidget);
  });

  testWidgets('Android: create a Bazaar and add an asset through the real forms', (tester) async {
    await seedFixtures();
    await FirebaseAuth.instance.signOut();

    final themeProvider = ThemeProvider();
    await themeProvider.loadTheme();

    await tester.pumpWidget(
      MultiProvider(
        providers: [
          ChangeNotifierProvider<AuthProvider>(create: (_) => AuthProvider()..initialize()),
          ChangeNotifierProvider<AssetProvider>(create: (_) => AssetProvider()),
          ChangeNotifierProvider<UserProvider>(create: (_) => UserProvider()),
          ChangeNotifierProvider<RequestProvider>(create: (_) => RequestProvider()),
          ChangeNotifierProvider<NotificationProvider>(create: (_) => NotificationProvider()),
          ChangeNotifierProvider<LogProvider>(create: (_) => LogProvider()),
          ChangeNotifierProvider<ThemeProvider>.value(value: themeProvider),
          ChangeNotifierProvider<DeploymentProvider>(create: (_) => DeploymentProvider()),
          ChangeNotifierProvider<BazaarProvider>(create: (_) => BazaarProvider()),
        ],
        child: const App(),
      ),
    );

    await pumpUntil(tester, find.text('Sign in'));
    await tester.enterText(find.widgetWithText(TextFormField, 'Email address'), superAdminEmail);
    await tester.enterText(find.widgetWithText(TextFormField, 'Password'), password);
    await tester.tap(find.text('Sign in'));
    await pumpUntil(tester, find.text('Sara Super'));

    final router = GoRouter.of(tester.element(find.text('Sara Super').first));

    // ----- Bazaar Master: add a Bazaar -----
    router.go('/locations');
    await pumpUntil(tester, find.byType(FloatingActionButton));
    for (var i = 0; i < 12; i++) {
      await tester.pump(const Duration(milliseconds: 150));
    }
    await tester.tap(find.byType(FloatingActionButton));
    await pumpUntil(tester, find.widgetWithText(TextFormField, 'Bazaar Name'));

    await tester.enterText(find.widgetWithText(TextFormField, 'Bazaar Name'), 'E2E Android Bazaar');
    await tester.enterText(find.widgetWithText(TextFormField, 'City'), 'Multan');
    await tester.enterText(find.widgetWithText(TextFormField, 'Address'), '5 Test Street');
    await tester.enterText(find.widgetWithText(TextFormField, 'Contact Person'), 'Test Person');
    await tester.enterText(find.widgetWithText(TextFormField, 'Contact Number'), '03007654321');
    await tester.pump(const Duration(milliseconds: 200));

    await tester.tap(find.widgetWithText(FilledButton, 'Add Bazaar').last);

    Map<String, dynamic>? bazaar;
    final bazaarDeadline = DateTime.now().add(const Duration(seconds: 25));
    while (DateTime.now().isBefore(bazaarDeadline)) {
      await tester.pump(const Duration(milliseconds: 250));
      final snapshot = await db.collection('bazaars').where('name', isEqualTo: 'E2E Android Bazaar').get();
      if (snapshot.docs.isNotEmpty) {
        bazaar = snapshot.docs.first.data();
        break;
      }
    }

    expect(bazaar, isNotNull, reason: 'Bazaar document written to Firestore');
    expect(bazaar!['location'], 'Multan');
    expect(bazaar['isActive'], isTrue);
    await pumpUntil(tester, find.text('E2E Android Bazaar'));

    // ----- Inventory: add an asset -----
    router.go('/assets');
    await pumpUntil(tester, find.byType(FloatingActionButton));
    for (var i = 0; i < 12; i++) {
      await tester.pump(const Duration(milliseconds: 150));
    }
    await tester.tap(find.byType(FloatingActionButton));
    await pumpUntil(tester, find.text('Register New Asset'));

    await tester.enterText(find.widgetWithText(TextFormField, 'Asset ID / Tag'), 'E2E-AND-001');
    await tester.enterText(find.widgetWithText(TextFormField, 'Asset Name'), 'E2E Android Printer');
    await tester.enterText(find.widgetWithText(TextFormField, 'Quantity'), '4');
    await tester.enterText(find.widgetWithText(TextFormField, 'Unit Purchase Price'), '12000');
    await tester.pump(const Duration(milliseconds: 200));

    await tester.tap(find.widgetWithText(FilledButton, 'Save Asset'));

    Map<String, dynamic>? asset;
    final assetDeadline = DateTime.now().add(const Duration(seconds: 25));
    while (DateTime.now().isBefore(assetDeadline)) {
      await tester.pump(const Duration(milliseconds: 250));
      final snapshot = await db.collection('assets').where('assetId', isEqualTo: 'E2E-AND-001').get();
      if (snapshot.docs.isNotEmpty) {
        asset = snapshot.docs.first.data();
        break;
      }
    }

    expect(asset, isNotNull, reason: 'asset written to Firestore');
    expect(asset!['name'], 'E2E Android Printer');
    expect(asset['quantity'], 4);
    expect(asset['headOfficeQuantity'], 4);
  });

  // ===========================================================================
  // CRITICAL: SESSION ISOLATION THROUGH THE REAL UI
  // ===========================================================================

  testWidgets('Logout clears every account-specific state; disabled account is signed out live', (tester) async {
    await seedFixtures();
    await FirebaseAuth.instance.signOut();

    final themeProvider = ThemeProvider();
    await themeProvider.loadTheme();

    await tester.pumpWidget(
      MultiProvider(
        providers: [
          ChangeNotifierProvider<AuthProvider>(create: (_) => AuthProvider()..initialize()),
          ChangeNotifierProvider<AssetProvider>(create: (_) => AssetProvider()),
          ChangeNotifierProvider<UserProvider>(create: (_) => UserProvider()),
          ChangeNotifierProvider<RequestProvider>(create: (_) => RequestProvider()),
          ChangeNotifierProvider<NotificationProvider>(create: (_) => NotificationProvider()),
          ChangeNotifierProvider<LogProvider>(create: (_) => LogProvider()),
          ChangeNotifierProvider<ThemeProvider>.value(value: themeProvider),
          ChangeNotifierProvider<DeploymentProvider>(create: (_) => DeploymentProvider()),
          ChangeNotifierProvider<BazaarProvider>(create: (_) => BazaarProvider()),
        ],
        child: const App(),
      ),
    );

    Future<void> login(String email) async {
      await pumpUntil(tester, find.text('Sign in'));
      await tester.enterText(find.widgetWithText(TextFormField, 'Email address'), email);
      await tester.enterText(find.widgetWithText(TextFormField, 'Password'), password);
      await tester.tap(find.text('Sign in'));
    }

    Future<void> logoutViaDrawer() async {
      await tester.tap(find.byTooltip('Open navigation menu'));
      await pumpUntil(tester, find.text('Logout'));
      await tester.tap(find.text('Logout').first);
      await pumpUntil(tester, find.widgetWithText(FilledButton, 'Logout'));
      await tester.tap(find.widgetWithText(FilledButton, 'Logout'));
    }

    BuildContext appContext() => tester.element(find.byType(App));

    // ----- User A: Admin with full inventory and requests -----
    await login(adminAEmail);
    await pumpUntil(tester, find.text('Adeel AdminA'));

    // Admin sees organization-wide inventory: both fixture assets.
    final end = DateTime.now().add(const Duration(seconds: 20));
    while (appContext().read<AssetProvider>().assets.length < 2 &&
        DateTime.now().isBefore(end)) {
      await tester.pump(const Duration(milliseconds: 200));
    }
    expect(appContext().read<AssetProvider>().assets.length, 2);
    expect(appContext().read<AssetProvider>().totalQuantity, 110);

    await logoutViaDrawer();
    await pumpUntil(tester, find.text('Sign in'));

    final ctx = appContext();
    expect(ctx.read<UserProvider>().currentUserProfile, isNull);
    expect(ctx.read<UserProvider>().users, isEmpty);
    expect(ctx.read<AssetProvider>().assets, isEmpty);
    expect(ctx.read<RequestProvider>().requests, isEmpty);
    expect(ctx.read<NotificationProvider>().notifications, isEmpty);
    expect(ctx.read<DeploymentProvider>().deployments, isEmpty);

    // ----- User B: normal User under Admin A -----
    await login(userAEmail);
    await pumpUntil(tester, find.text('Usman UserA'));

    expect(find.text('Adeel AdminA'), findsNothing);
    expect(find.text('Administrator'), findsNothing);

    final userCtx = appContext();
    expect(userCtx.read<UserProvider>().isNormalUser, isTrue);
    expect(userCtx.read<UserProvider>().users, isEmpty);
    for (final asset in userCtx.read<AssetProvider>().assets) {
      expect(asset.adminId, adminAUid);
    }

    // ----- Direct navigation to a restricted route is blocked -----
    await pumpUntil(tester, find.byType(App));
    tester.element(find.byType(Scaffold).first).go('/users');
    await tester.pump(const Duration(seconds: 1));
    await pumpUntil(tester, find.text('Usman UserA'));

    // ----- Account disabled while signed in: signed out immediately -----
    await seedDocument('users/$userAUid', userProfile(uid: userAUid, name: 'Usman UserA', email: userAEmail, role: 'user', createdBy: adminAUid, status: 'disabled'));

    await pumpUntil(tester, find.text('Sign in'), timeout: const Duration(seconds: 30));
    expect(FirebaseAuth.instance.currentUser, isNull);
  });
}
