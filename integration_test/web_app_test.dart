// In-browser integration tests for the WEB build, against the Firebase Local
// Emulator Suite (same firestore.rules as production).
//
//   1. firebase emulators:start --only firestore,auth --project it-inventory-8e690
//   2. chromedriver --port=4444
//   3. flutter drive -d chrome --driver=test_driver/integration_test.dart \
//        --target=integration_test/web_app_test.dart \
//        --dart-define=EMULATOR_HOST=localhost
//
// Nothing here touches the production Firebase project.

// Provider state is inspected between UI steps in this end-to-end test.
// ignore_for_file: use_build_context_synchronously

import 'package:firebase_auth/firebase_auth.dart' hide AuthProvider;
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:integration_test/integration_test.dart';

import 'package:it_management_system/core/providers/asset_provider.dart';
import 'package:it_management_system/core/providers/deployment_provider.dart';
import 'package:it_management_system/core/providers/notification_provider.dart';
import 'package:it_management_system/core/providers/request_provider.dart';
import 'package:it_management_system/core/providers/user_provider.dart';
import 'package:it_management_system/core/services/deployment_service.dart';
import 'package:it_management_system/core/services/request_service.dart';
import 'package:it_management_system/core/services/user_service.dart';
import 'package:it_management_system/models/request_model.dart';

import 'emulator_support.dart';
import 'support/fixtures.dart';
import 'support/ui.dart';

const webRoutes = [
  '/dashboard',
  '/inventory',
  '/inventory/head-office',
  '/inventory/assigned',
  '/inventory/damaged',
  '/inventory/under-repair',
  '/inventory/lost-disposed',
  '/import-assets',
  '/bazaars',
  '/bazaars/active',
  '/bazaars/disabled',
  '/transfers/new',
  '/transfers/history',
  '/transfers/current-stock',
  '/requests',
  '/users',
  '/roles',
  '/reports',
  '/activity-logs',
  '/notifications',
  '/settings',
];

const viewports = <Size>[
  Size(1920, 1080),
  Size(1440, 900),
  Size(1366, 768),
  Size(1280, 720),
  Size(1024, 768),
  Size(768, 1024),
  Size(412, 915),
];

/// Movement + request data so every page renders real rows.
Future<void> seedActivity() async {
  await signInAs(superAdminEmail, password);

  final movements = DeploymentService();

  await movements.transferAsset(assetDocumentId: 'assetA', sourceId: '__head_office__', sourceName: 'Head Office', destinationId: 'A', destinationName: 'Bazaar A', quantity: 20, transferredBy: superAdminUid, transferredByName: 'Sara Super');
  await movements.transferAsset(assetDocumentId: 'assetA', sourceId: 'A', sourceName: 'Bazaar A', destinationId: 'B', destinationName: 'Bazaar B', quantity: 5, transferredBy: superAdminUid, transferredByName: 'Sara Super');

  await signInAs(userAEmail, password);

  await RequestService().createRequest(
    RequestModel(
      requestType: 'Transfer',
      assetId: 'assetA',
      assetName: 'LaptopA',
      requestedBy: userAUid,
      requestedUserName: 'Usman UserA',
      sourceBazaarId: '__head_office__',
      sourceBazaarName: 'Head Office',
      destinationBazaarId: 'B',
      destinationBazaarName: 'Bazaar B',
      transferQuantity: 7,
      reason: 'Web integration test',
    ),
  );

  await signOutAndWait();
}

Future<void> loginThroughUi(WidgetTester tester, String email) async {
  await pumpUntil(tester, find.text('Sign in'));
  await tester.enterText(find.widgetWithText(TextFormField, 'Email address'), email);
  await tester.enterText(find.widgetWithText(TextFormField, 'Password'), password);
  await tester.tap(find.text('Sign in').last);
  await pumpUntilTrue(
    tester,
    () => find.text('Sign in').evaluate().isEmpty &&
        readProvider<UserProvider>(tester).hasLoadedCurrentUser,
    description: 'login of $email',
  );
}

Future<void> logoutThroughUi(WidgetTester tester) async {
  await tester.tap(find.text('Logout').first);
  await pumpUntil(tester, find.widgetWithText(FilledButton, 'Logout'));
  await tester.tap(find.widgetWithText(FilledButton, 'Logout'));
  await pumpUntil(tester, find.text('Sign in'));
}

Future<void> goTo(WidgetTester tester, String path) async {
  GoRouter.of(routedContext(tester)).go(path);
  for (var i = 0; i < 6; i++) {
    await tester.pump(const Duration(milliseconds: 150));
  }
}

void setViewport(WidgetTester tester, Size size) {
  tester.view.devicePixelRatio = 1.0;
  tester.view.physicalSize = size;
}

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  setUpAll(() async {
    await initFirebaseForEmulator();
  });

  testWidgets('Web: a newly appointed Super Admin can open every page at every viewport', (tester) async {
    await seedFixtures();
    await seedActivity();

    // Handover: the original Super Admin appoints Admin B, and nothing below
    // uses the original account any more.
    await signInAs(superAdminEmail, password);
    await UserService().promoteToSuperAdmin(actorUid: superAdminUid, targetUid: adminBUid);
    await signOutAndWait();

    setViewport(tester, viewports.first);
    addTearDown(tester.view.reset);

    await tester.pumpWidget(await buildRealApp());
    await loginThroughUi(tester, adminBEmail);
    expect(readProvider<UserProvider>(tester).isSuperAdmin, isTrue);

    await pumpUntilTrue(tester, () => readProvider<AssetProvider>(tester).assets.length == 2, description: 'inventory loaded');
    await pumpUntilTrue(tester, () => readProvider<DeploymentProvider>(tester).deployments.length >= 2, description: 'movements loaded');

    final collector = ErrorCollector.install();
    final problems = <String>[];

    try {
      for (final size in viewports) {
        setViewport(tester, size);

        for (final route in webRoutes) {
          await goTo(tester, route);

          final errors = collector.drain();
          final uncaught = tester.takeException();

          if (errors.isNotEmpty || uncaught != null) {
            problems.add(
              '[$route @ ${size.width.toInt()}x${size.height.toInt()}] '
              '${errors.toSet().join(' || ')}${uncaught == null ? '' : ' || uncaught: $uncaught'}',
            );
          }

          if (currentPath(tester) != route) {
            problems.add('[$route] Super Admin was redirected to ${currentPath(tester)}');
          }
        }
      }
    } finally {
      collector.restore();
    }

    expect(problems, isEmpty, reason: problems.take(25).join('\n'));

    // Real data is shown (not placeholders).
    setViewport(tester, viewports.first);
    await goTo(tester, '/inventory');
    await pumpUntil(tester, find.text('LaptopA'));
    expect(find.text('LaptopB'), findsOneWidget);

    final assets = readProvider<AssetProvider>(tester);
    expect(assets.totalQuantity, 110);
    expect(assets.headOfficeStock, 90);
    expect(assets.deployedToBazaarsQuantity, 20);

    // The new Super Admin sees and manages every account, including the
    // original Super Admin, whom it removes.
    expect(readProvider<UserProvider>(tester).users.length, 5);
    await UserService().demoteSuperAdmin(actorUid: adminBUid, targetUid: superAdminUid);

    // Logout -> the former Super Admin signs in: now an Admin, no Super Admin
    // pages, and none of the previous session's state.
    await goTo(tester, '/dashboard');
    await logoutThroughUi(tester);
    expect(readProvider<UserProvider>(tester).currentUserProfile, isNull);
    expect(readProvider<AssetProvider>(tester).assets, isEmpty);

    await loginThroughUi(tester, superAdminEmail);
    final former = readProvider<UserProvider>(tester);
    expect(former.currentUserProfile?.uid, superAdminUid);
    expect(former.isSuperAdmin, isFalse);
    expect(former.isAdmin, isTrue);
    await goTo(tester, '/roles');
    await pumpUntilTrue(tester, () => currentPath(tester) == '/dashboard', description: 'former Super Admin redirected away from /roles');
  });

  testWidgets('Web: Add Asset opens the existing form with every section', (tester) async {
    await seedFixtures();

    setViewport(tester, const Size(1440, 900));
    addTearDown(tester.view.reset);

    await tester.pumpWidget(await buildRealApp());
    await loginThroughUi(tester, superAdminEmail);

    await goTo(tester, '/inventory');
    await pumpUntil(tester, find.text('LaptopA'));

    await tester.tap(find.widgetWithText(FilledButton, 'Add Asset'));
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

    // The same dialog must stay usable at phone width in a browser.
    setViewport(tester, const Size(412, 915));
    await tester.pump(const Duration(milliseconds: 300));
    await tester.pump(const Duration(milliseconds: 300));
    expect(find.text('Register New Asset'), findsOneWidget);
    expect(find.text('Basic Information'), findsOneWidget);
    expect(find.widgetWithText(TextFormField, 'Asset Name'), findsOneWidget);
    setViewport(tester, const Size(1440, 900));
    await tester.pump(const Duration(milliseconds: 300));

    // Closing the dialog returns to the inventory page unchanged.
    await tester.tap(find.byTooltip('Close'));
    await pumpUntilTrue(
      tester,
      () => find.text('Register New Asset').evaluate().isEmpty,
      description: 'Add Asset dialog closed',
    );
    expect(find.text('LaptopA'), findsWidgets);
  });

  testWidgets('Web: create, edit and disable a Bazaar through the UI', (tester) async {
    await seedFixtures();
    final collector = ErrorCollector.install();
    addTearDown(collector.restore);

    setViewport(tester, const Size(1440, 900));
    addTearDown(tester.view.reset);

    await tester.pumpWidget(await buildRealApp());
    await loginThroughUi(tester, superAdminEmail);

    await goTo(tester, '/bazaars');
    await pumpUntil(tester, find.text('Bazaar A'));

    // --- CREATE ---
    await tester.tap(find.widgetWithText(FilledButton, 'Add Bazaar'));
    await pumpUntil(tester, find.text('Add Bazaar').last);

    await tester.enterText(find.widgetWithText(TextFormField, 'Bazaar name *'), 'E2E Web Bazaar');
    await tester.enterText(find.widgetWithText(TextFormField, 'City / Location *'), 'Lahore');
    await tester.enterText(find.widgetWithText(TextFormField, 'Address'), '12 Test Road');
    await tester.enterText(find.widgetWithText(TextFormField, 'Contact person'), 'Test Person');
    await tester.enterText(find.widgetWithText(TextFormField, 'Contact number'), '03001234567');

    await tester.tap(find.widgetWithText(FilledButton, 'Save'));

    for (var i = 0; i < 12; i++) {
      await tester.pump(const Duration(milliseconds: 250));
    }

    final diag = StringBuffer();
    diag.writeln('exception after save: ${tester.takeException()}');
    diag.writeln('dialog still open: ${find.text('Add Bazaar').evaluate().length}');
    for (final element in find.byType(Text).evaluate()) {
      final text = (element.widget as Text).data ?? '';
      if (text.trim().isNotEmpty && text.length < 120) {
        diag.writeln('visible: $text');
      }
    }
    diag.writeln('bazaars in Firestore: ${(await db.collection('bazaars').get()).docs.length}');

    Map<String, dynamic>? created;
    final deadline = DateTime.now().add(const Duration(seconds: 20));
    while (DateTime.now().isBefore(deadline)) {
      await tester.pump(const Duration(milliseconds: 250));
      final snapshot = await db.collection('bazaars').where('name', isEqualTo: 'E2E Web Bazaar').get();
      if (snapshot.docs.isNotEmpty) {
        created = snapshot.docs.first.data();
        break;
      }
    }

    expect(created, isNotNull, reason: diag.toString());
    expect(created!['location'], 'Lahore');
    expect(created['isActive'], isTrue);

    // It appears in the list, and is still there after leaving and returning.
    await pumpUntil(tester, find.text('E2E Web Bazaar'));
    await goTo(tester, '/dashboard');
    await goTo(tester, '/bazaars');
    await pumpUntil(tester, find.text('E2E Web Bazaar'));

    // --- EDIT (search first so only this Bazaar is listed) ---
    final createdId = (await db.collection('bazaars').where('name', isEqualTo: 'E2E Web Bazaar').get()).docs.first.id;

    await tester.enterText(
      find.widgetWithText(TextField, 'Search name, city, address, contact…'),
      'E2E Web Bazaar',
    );
    await pumpUntilTrue(
      tester,
      () => find.byTooltip('Edit').evaluate().length == 1,
      description: 'search narrowed the Bazaar list to one row',
    );

    await tester.tap(find.byTooltip('Edit').first);
    await pumpUntil(tester, find.text('Edit Bazaar'));
    await tester.enterText(find.widgetWithText(TextFormField, 'Bazaar name *'), 'E2E Web Bazaar Renamed');
    await tester.tap(find.widgetWithText(FilledButton, 'Save'));

    await pumpUntilTrue(
      tester,
      () => true,
      description: 'edit submitted',
    );

    var renamed = '';
    final editDeadline = DateTime.now().add(const Duration(seconds: 20));
    while (DateTime.now().isBefore(editDeadline)) {
      await tester.pump(const Duration(milliseconds: 250));
      renamed = ((await db.collection('bazaars').doc(createdId).get()).data()?['name'] ?? '').toString();
      if (renamed == 'E2E Web Bazaar Renamed') break;
    }
    expect(renamed, 'E2E Web Bazaar Renamed');

    // --- DISABLE ---
    await tester.enterText(
      find.widgetWithText(TextField, 'Search name, city, address, contact…'),
      'E2E Web Bazaar Renamed',
    );
    await pumpUntilTrue(
      tester,
      () => find.byTooltip('Disable').evaluate().length == 1,
      description: 'renamed Bazaar is the only row',
    );
    await tester.tap(find.byTooltip('Disable').first);
    await pumpUntil(tester, find.widgetWithText(FilledButton, 'Disable'));
    await tester.tap(find.widgetWithText(FilledButton, 'Disable'));
    await pumpUntilTrue(tester, () => true, description: 'disable confirmed');

    var active = true;
    final disableDeadline = DateTime.now().add(const Duration(seconds: 20));
    while (DateTime.now().isBefore(disableDeadline)) {
      await tester.pump(const Duration(milliseconds: 250));
      active = ((await db.collection('bazaars').doc(createdId).get()).data()?['isActive'] ?? true) as bool;
      if (!active) break;
    }
    expect(active, isFalse, reason: 'Bazaar disabled in Firestore');
    expect(collector.messages, isEmpty, reason: collector.messages.join(' || '));
  });

  testWidgets('Web: add an asset through the form and verify Firestore + lists', (tester) async {
    await seedFixtures();

    setViewport(tester, const Size(1440, 900));
    addTearDown(tester.view.reset);

    await tester.pumpWidget(await buildRealApp());
    await loginThroughUi(tester, superAdminEmail);

    await goTo(tester, '/inventory');
    await pumpUntil(tester, find.text('LaptopA'));

    await tester.tap(find.widgetWithText(FilledButton, 'Add Asset'));
    await pumpUntil(tester, find.text('Register New Asset'));

    await tester.enterText(find.widgetWithText(TextFormField, 'Asset ID / Tag'), 'E2E-WEB-001');
    await tester.enterText(find.widgetWithText(TextFormField, 'Asset Name'), 'E2E Web Printer');
    await tester.enterText(find.widgetWithText(TextFormField, 'Quantity'), '7');
    await tester.enterText(find.widgetWithText(TextFormField, 'Unit Purchase Price'), '12000');

    await tester.tap(find.widgetWithText(FilledButton, 'Save Asset'));

    Map<String, dynamic>? saved;
    final deadline = DateTime.now().add(const Duration(seconds: 25));
    while (DateTime.now().isBefore(deadline)) {
      await tester.pump(const Duration(milliseconds: 250));
      final snapshot = await db.collection('assets').where('assetId', isEqualTo: 'E2E-WEB-001').get();
      if (snapshot.docs.isNotEmpty) {
        saved = snapshot.docs.first.data();
        break;
      }
    }

    expect(saved, isNotNull, reason: 'asset written to Firestore');
    expect(saved!['name'], 'E2E Web Printer');
    expect(saved['quantity'], 7);
    expect(saved['headOfficeQuantity'], 7);
    expect(saved['assignedQuantity'], 0);
    expect(saved['deployedQuantity'], 0);

    // Visible in the inventory list and counted on the dashboard.
    await pumpUntil(tester, find.text('E2E Web Printer'));
    await pumpUntilTrue(
      tester,
      () => readProvider<AssetProvider>(tester).totalQuantity == 117,
      description: 'dashboard quantity includes the new asset (110 + 7)',
    );
  });

  testWidgets('Web: RBAC navigation, direct URL protection and session isolation', (tester) async {
    await seedFixtures();
    await seedActivity();

    setViewport(tester, const Size(1440, 900));
    addTearDown(tester.view.reset);

    await tester.pumpWidget(await buildRealApp());

    // Direct URL while signed out -> login, then back to the requested page.
    await pumpUntil(tester, find.text('Sign in'));
    GoRouter.of(tester.element(find.text('Sign in').first)).go('/transfers/history');
    await pumpUntil(tester, find.text('Sign in'));
    expect(currentPath(tester), '/login');

    // ---- Super Admin (User A of the session test) ----
    await loginThroughUi(tester, superAdminEmail);
    await pumpUntilTrue(tester, () => currentPath(tester) == '/transfers/history', description: 'redirect back to requested page');
    await pumpUntil(tester, find.text('Sara Super'));
    await pumpUntilTrue(tester, () => readProvider<UserProvider>(tester).users.length >= 5, description: 'users loaded');

    expect(find.text('Users'), findsWidgets);
    expect(find.text('Roles & Permissions'), findsOneWidget);

    await logoutThroughUi(tester);

    // Nothing of the previous account remains in memory.
    expect(readProvider<UserProvider>(tester).currentUserProfile, isNull);
    expect(readProvider<UserProvider>(tester).users, isEmpty);
    expect(readProvider<AssetProvider>(tester).assets, isEmpty);
    expect(readProvider<RequestProvider>(tester).requests, isEmpty);
    expect(readProvider<NotificationProvider>(tester).notifications, isEmpty);
    expect(readProvider<DeploymentProvider>(tester).deployments, isEmpty);

    // ---- Normal User (User B) ----
    await loginThroughUi(tester, userAEmail);
    await pumpUntil(tester, find.text('Usman UserA'));

    expect(find.text('Sara Super'), findsNothing);
    expect(find.text('Roles & Permissions'), findsNothing);
    expect(find.text('Activity Logs'), findsNothing);
    expect(find.text('Reports'), findsNothing);
    expect(find.text('New Transfer'), findsNothing);
    expect(readProvider<UserProvider>(tester).users, isEmpty);

    for (final restricted in ['/users', '/roles', '/reports', '/activity-logs', '/transfers/new', '/import-assets']) {
      await goTo(tester, restricted);
      await pumpUntilTrue(tester, () => currentPath(tester) == '/dashboard', description: '$restricted blocked for User');
    }

    await pumpUntilTrue(tester, () => readProvider<AssetProvider>(tester).assets.isNotEmpty, description: 'user inventory');
    for (final asset in readProvider<AssetProvider>(tester).assets) {
      expect(asset.adminId, adminAUid, reason: 'User sees only the assigned Admin inventory');
    }

    // Account disabled while signed in -> signed out immediately.
    await seedDocument('users/$userAUid', userProfile(uid: userAUid, name: 'Usman UserA', email: userAEmail, role: 'user', createdBy: adminAUid, status: 'disabled'));
    await pumpUntil(tester, find.text('Sign in'));
    expect(FirebaseAuth.instance.currentUser, isNull);
  });

  testWidgets('Web: return stock and approve a transfer request through the web UI', (tester) async {
    await seedFixtures();
    await seedActivity();

    setViewport(tester, const Size(1920, 1080));
    addTearDown(tester.view.reset);

    await tester.pumpWidget(await buildRealApp());
    await loginThroughUi(tester, adminAEmail);

    // ---- Return 3 units from Bazaar B via Current Bazaar Stock ----
    await goTo(tester, '/transfers/current-stock');
    await pumpUntil(tester, find.text('Bazaar B'));

    final bazaarBRow = find.ancestor(of: find.text('Bazaar B'), matching: find.byType(Row));
    expect(bazaarBRow, findsWidgets);

    // Rows: Bazaar A (15) and Bazaar B (5), sorted by Bazaar name.
    await tester.tap(find.text('Return').at(1));
    await pumpUntil(tester, find.text('Return to Head Office'));
    await tester.enterText(find.widgetWithText(TextField, 'Quantity to return'), '3');
    await tester.tap(find.widgetWithText(FilledButton, 'Return'));

    await pumpUntilTrue(tester, () => readProvider<AssetProvider>(tester).assets.any((a) => a.id == 'assetA' && a.headOfficeQuantity == 83), description: 'HO = 83 after web return');

    var data = await assetData('assetA');
    expect(data['headOfficeQuantity'], 83);
    expect(data['deployedQuantity'], 17);
    expect(data['quantity'], 100);

    // ---- Approve the User's transfer request (7 units HO -> Bazaar B) ----
    await goTo(tester, '/requests');
    await pumpUntil(tester, find.byTooltip('Approve'));
    await tester.tap(find.byTooltip('Approve').first);
    await pumpUntil(tester, find.widgetWithText(FilledButton, 'Approve'));
    await tester.tap(find.widgetWithText(FilledButton, 'Approve'));

    await pumpUntilTrue(
      tester,
      () => readProvider<RequestProvider>(tester).requests.any((r) => r.isApproved),
      description: 'request approved',
    );

    data = await assetData('assetA');
    expect(data['headOfficeQuantity'], 76);
    expect(data['deployedQuantity'], 24);
    expect(data['quantity'], 100);

    // Approving again is impossible (exactly once).
    final approved = readProvider<RequestProvider>(tester).requests.firstWhere((r) => r.isApproved);
    await expectLater(
      RequestService().updateRequestStatus(requestId: approved.id, status: 'Approved', remarks: '', approvedBy: 'x'),
      throwsA(isA<Exception>()),
    );
    expect((await assetData('assetA'))['headOfficeQuantity'], 76);
  });
}
