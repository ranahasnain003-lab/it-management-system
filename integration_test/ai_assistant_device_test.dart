// On-device tests for the AI Assistant and the signed-in router shell.
//
//   1. firebase emulators:start --only firestore,auth --project it-inventory-8e690
//      (the emulator loads this project's firestore.rules)
//   2. flutter test integration_test/ai_assistant_device_test.dart -d emulator-5554
//
// Nothing here touches the production Firebase project. The OpenAI Cloud
// Function is deliberately NOT deployed, so these tests exercise the state the
// app ships in today: the assistant answers from the grounded, permission
// scoped data it computed locally, and the language model is skipped.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:provider/provider.dart';

import 'package:it_management_system/app.dart';
import 'package:it_management_system/core/ai/ai_assistant_panel.dart';
import 'package:it_management_system/core/providers/asset_provider.dart';
import 'package:it_management_system/core/providers/auth_provider.dart';
import 'package:it_management_system/core/providers/bazaar_provider.dart';
import 'package:it_management_system/core/providers/deployment_provider.dart';
import 'package:it_management_system/core/providers/log_provider.dart';
import 'package:it_management_system/core/providers/notification_provider.dart';
import 'package:it_management_system/core/providers/request_provider.dart';
import 'package:it_management_system/core/providers/theme_provider.dart';
import 'package:it_management_system/core/providers/user_provider.dart';

import 'emulator_support.dart';
import 'support/fixtures.dart';

// ---------------------------------------------------------------------------
// FINDERS
// ---------------------------------------------------------------------------

/// The floating assistant button. Its only stable handle is its label; the
/// icon beside it is a CustomPaint, not an IconData.
final buttonFinder = find.text('AI Assistant');

/// Unique to the open panel's header, so it never collides with the button.
final panelFinder = find.text('Answers from your live inventory');

/// The panel's composer, matched on its hint so the screen behind the panel
/// cannot contribute a second TextField.
final composerFinder = find.byWidgetPredicate(
  (w) =>
      w is TextField &&
      w.decoration?.hintText == 'Ask about stock, a Bazaar or an Asset ID...',
);

/// The send control. Icons.arrow_upward_rounded appears once in lib/.
final sendFinder = find.byIcon(Icons.arrow_upward_rounded);

final bubbleFinder =
    find.byWidgetPredicate((w) => w.runtimeType.toString() == '_Bubble');

final typingFinder =
    find.byWidgetPredicate((w) => w.runtimeType.toString() == '_TypingBubble');

// ---------------------------------------------------------------------------
// HARNESS
// ---------------------------------------------------------------------------

/// Boots the real app with the providers main.dart installs.
Future<void> pumpApp(WidgetTester tester) async {
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

  // Firebase is a process-wide singleton across these tests, so a provider
  // left mounted keeps its Firestore listeners attached into the next test -
  // which begins by deleting every document and account underneath them. That
  // wedged the shared client and made whichever test ran last fail. Replacing
  // the tree here disposes the providers, and therefore their listeners,
  // before that happens. Registered on the tester so it also runs when the
  // test body fails part way through.
  addTearDown(() async {
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump(const Duration(milliseconds: 300));
  });
}

Future<void> pumpUntil(
  WidgetTester tester,
  Finder finder, {
  Duration timeout = const Duration(seconds: 40),
  String? describe,
}) async {
  final end = DateTime.now().add(timeout);

  while (DateTime.now().isBefore(end)) {
    await tester.pump(const Duration(milliseconds: 200));
    if (finder.evaluate().isNotEmpty) return;
  }

  throw TestFailure('Timed out waiting for ${describe ?? finder}');
}

Future<void> pumpUntilGone(
  WidgetTester tester,
  Finder finder, {
  Duration timeout = const Duration(seconds: 20),
  String? describe,
}) async {
  final end = DateTime.now().add(timeout);

  while (DateTime.now().isBefore(end)) {
    await tester.pump(const Duration(milliseconds: 200));
    if (finder.evaluate().isEmpty) return;
  }

  throw TestFailure('Timed out waiting for ${describe ?? finder} to disappear');
}

/// Pumps frames for a bounded stretch of time.
///
/// tester.pumpAndSettle() must not be used anywhere in this file: the
/// assistant button's sparkle runs `AnimationController..repeat(reverse: true)`
/// (ai_assistant_panel.dart:208-211), so while the button is on screen the
/// frame queue never empties and pumpAndSettle would pump until it times out.
Future<void> settleFor(
  WidgetTester tester, [
  Duration duration = const Duration(milliseconds: 900),
]) async {
  final end = DateTime.now().add(duration);
  while (DateTime.now().isBefore(end)) {
    await tester.pump(const Duration(milliseconds: 60));
  }
}

/// Taps [finder] and fails loudly if the pointer did not land on it.
Future<void> tapOn(WidgetTester tester, Finder finder, String what) async {
  expect(finder, findsWidgets, reason: 'expected to find $what to tap');
  debugPrint('TEST-STEP: tapping $what');
  await tester.tap(finder.first, warnIfMissed: true);
  await settleFor(tester);
}

Future<void> signInThroughUi(WidgetTester tester, String email, String displayName) async {
  await pumpUntil(tester, find.text('Sign in'), describe: 'the login form');
  await tester.enterText(find.widgetWithText(TextFormField, 'Email address'), email);
  await tester.enterText(find.widgetWithText(TextFormField, 'Password'), password);
  await tester.tap(find.text('Sign in'));
  await pumpUntil(tester, find.text(displayName), describe: 'the signed-in name "$displayName"');
}

/// Text of the newest assistant bubble, or '' when there is none yet.
String latestBubbleText(WidgetTester tester) {
  if (bubbleFinder.evaluate().isEmpty) return '';

  final text = find.descendant(
    of: bubbleFinder.last,
    matching: find.byType(SelectableText),
  );

  if (text.evaluate().isEmpty) return '';

  return tester.widget<SelectableText>(text).data ?? '';
}

/// Types [question], sends it and returns the assistant's answer.
///
/// The Cloud Function is not deployed, so the call to it fails and the panel
/// falls back to the locally computed answer. That fallback is what is asserted.
Future<String> ask(WidgetTester tester, String question) async {
  final before = latestBubbleText(tester);

  expect(composerFinder, findsOneWidget, reason: 'the assistant panel must be open');

  await tester.enterText(composerFinder, question);
  await tester.pump();
  await tester.tap(sendFinder);
  await tester.pump();

  final end = DateTime.now().add(const Duration(seconds: 90));

  while (DateTime.now().isBefore(end)) {
    await tester.pump(const Duration(milliseconds: 200));

    if (typingFinder.evaluate().isNotEmpty) continue;

    final now = latestBubbleText(tester);
    if (now.isNotEmpty && now != before && now != question) return now;
  }

  throw TestFailure('The assistant did not answer "$question" in time.');
}

Future<void> openDrawer(WidgetTester tester) async {
  await tester.tap(find.byTooltip('Open navigation menu'));
  await settleFor(tester);
}

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  setUpAll(() async {
    await initFirebaseForEmulator();
  });

  setUp(() {
    // The observer is a top-level singleton; clear it so one test cannot leave
    // the button hidden for the next.
    assistantModalObserver.openModals.value = 0;
  });

  tearDown(() async {
    // Firebase is a process-wide singleton across these tests, so a listener
    // left running into the next test's resetEmulators() (which deletes every
    // document and every account) can be torn down mid-flight and leave the
    // Firestore client holding a broken query. Signing out first closes the
    // account's listeners the way the app does.
    await signOutAndWait();
    await Future<void>.delayed(const Duration(milliseconds: 500));
  });

  // =========================================================================
  // 1. THE ASSISTANT ANSWERS FROM REAL, PERMISSION-SCOPED INVENTORY
  //
  // Seeded inventory for a Super Admin: assetA "LaptopA" x100 and assetB
  // "LaptopB" x10, both at Rs 1,000 a unit, all at Head Office.
  //   2 asset records - 110 units - Rs 110,000
  // =========================================================================

  testWidgets('AI Assistant: opens, answers English and Roman Urdu, and follows up',
      (tester) async {
    await seedFixtures();
    await pumpApp(tester);
    await signInThroughUi(tester, superAdminEmail, 'Sara Super');

    // The dashboard's own figure, so the assistant's totals can be trusted to
    // come from the same live data rather than from the model.
    await pumpUntil(tester, find.text('Total Assets'), describe: 'the dashboard');

    // --- the button is there, and opens the panel ---------------------------
    debugPrint('TEST-STEP: signed in, dashboard visible');
    expect(buttonFinder, findsOneWidget);
    expect(panelFinder, findsNothing);

    await tapOn(tester, buttonFinder, 'the AI Assistant button');

    await pumpUntil(tester, panelFinder,
        timeout: const Duration(seconds: 15), describe: 'the assistant panel to open');
    expect(composerFinder, findsOneWidget);
    debugPrint('TEST-STEP: panel open');

    // Give the asset, bazaar and movement streams time to arrive.
    await settleFor(tester, const Duration(seconds: 4));

    // --- English: totals ----------------------------------------------------
    debugPrint('TEST-STEP: asking totals');
    final totals = await ask(tester, 'total stock');

    expect(totals, contains('Inventory overview'));
    expect(totals, contains('Asset records: 2'));
    expect(totals, contains('Total quantity: 110 units'));
    expect(totals, contains('Total value: Rs.110,000'));

    // --- Roman Urdu: inventory value ---------------------------------------
    final value = await ask(tester, 'inventory ki kul qeemat kitni hai');

    expect(value, contains('Total inventory value: Rs.110,000'));
    expect(value, contains('2 asset record(s)'));
    expect(value, contains('110 units'));

    // --- Roman Urdu: head office -------------------------------------------
    final headOffice = await ask(tester, 'head office mein kitne hain');

    expect(headOffice, contains('Head Office has 110 units available.'));

    // --- a named asset ------------------------------------------------------
    final asset = await ask(tester, 'LaptopA ki qeemat kya hai');

    expect(asset, contains('TAG-LaptopA (LaptopA)'));
    expect(asset, contains('Unit purchase price: Rs.1,000'));
    expect(asset, contains('Quantity: 100 units'));
    expect(asset, contains('Total value: Rs.100,000'));

    // --- follow-up: no asset is named, the context must carry --------------
    final followUp = await ask(tester, 'aur is ka stock kitna hai');

    expect(
      followUp,
      contains('TAG-LaptopA (LaptopA) has 100 units in total.'),
      reason: 'the follow-up must stay on the asset from the previous question',
    );

    // --- Bazaars: report the real position, never invent one ---------------
    final bazaar = await ask(tester, 'bazaar stock kitna hai');

    expect(
      bazaar,
      contains('No stock is at any Bazaar right now. All 110 units are at Head '
          'Office or assigned.'),
    );

    // Close it the way a user does, with the panel's own Close button.
    //
    // This used to tap a fixed point near the top of the screen to hit the
    // scrim. That only worked while the soft keyboard happened to be down: the
    // panel is bottom-aligned with maxHeight 0.82 x screen and padded by
    // viewInsets.bottom (ai_assistant_panel.dart:640-643), so with the keyboard
    // up it reaches the top of the screen and swallows that tap. A named
    // control is not sensitive to the keyboard's state.
    await tapOn(tester, find.byTooltip('Close'), 'the panel Close button');

    expect(panelFinder, findsNothing);
    expect(buttonFinder, findsOneWidget);
  });

  // =========================================================================
  // 2. LAYERING: THE BUTTON MUST NOT SIT ON TOP OF SHEETS OR DIALOGS
  // =========================================================================

  testWidgets('the assistant button yields to bottom sheets and dialogs',
      (tester) async {
    await seedFixtures();
    await pumpApp(tester);
    await signInThroughUi(tester, superAdminEmail, 'Sara Super');
    await pumpUntil(tester, find.text('Total Assets'), describe: 'the dashboard');

    expect(buttonFinder, findsOneWidget);

    // --- the button travels with the shell to another signed-in route ------
    await openDrawer(tester);
    await tester.tap(find.descendant(of: find.byType(Drawer), matching: find.text('Assets')));
    await settleFor(tester);

    await pumpUntil(
      tester,
      find.text('LaptopA'),
      timeout: const Duration(seconds: 90),
      describe: 'the asset list',
    );
    expect(buttonFinder, findsOneWidget, reason: 'the shell hosts the button on every signed-in route');

    // --- a bottom sheet takes the button away ------------------------------
    await tester.tap(find.text('LaptopA').first);
    await settleFor(tester);

    expect(find.text('Total Asset Quantity'), findsOneWidget, reason: 'the asset sheet must be open');
    expect(
      buttonFinder,
      findsNothing,
      reason: 'the assistant button must not float over a bottom sheet',
    );

    await tester.tap(find.byTooltip('Close'));
    await settleFor(tester);

    expect(find.text('Total Asset Quantity'), findsNothing);
    expect(buttonFinder, findsOneWidget, reason: 'the button must come back when the sheet closes');

    // --- back navigation still works from inside the shell -----------------
    await tester.tap(find.byTooltip('Back'));
    await settleFor(tester);

    expect(find.text('Total Assets'), findsOneWidget, reason: 'Back must return to the dashboard');
    expect(buttonFinder, findsOneWidget);

    // --- a confirm dialog is drawn above the button ------------------------
    final buttonCentre = tester.getCenter(buttonFinder);

    await openDrawer(tester);
    await tester.tap(find.text('Sign out of your account'));
    await settleFor(tester);

    expect(
      find.text('Are you sure you want to sign out of your account?'),
      findsOneWidget,
      reason: 'the logout confirmation must be open',
    );

    // Tap exactly where the button is. The dialog is on the root navigator,
    // above the shell, so the dialog must absorb this - not the button.
    await tester.tapAt(buttonCentre);
    await settleFor(tester);

    expect(
      panelFinder,
      findsNothing,
      reason: 'the assistant must not be reachable through a dialog, which '
          'means it is not painted above it',
    );

    // Leave the session signed in for the next test.
    if (find.widgetWithText(TextButton, 'Cancel').evaluate().isNotEmpty) {
      await tester.tap(find.widgetWithText(TextButton, 'Cancel'));
      await settleFor(tester);
    }
  });

  // =========================================================================
  // 3. ACTION MODE: PROPOSE, CANCEL, CONFIRM
  //
  // Seeded: assetA "LaptopA" x100, all at Head Office, and Bazaar A.
  // =========================================================================

  testWidgets('a command is previewed, cancelled safely, then confirmed and applied',
      (tester) async {
    await seedFixtures();
    await pumpApp(tester);
    await signInThroughUi(tester, superAdminEmail, 'Sara Super');
    await pumpUntil(tester, find.text('Total Assets'), describe: 'the dashboard');

    await tapOn(tester, buttonFinder, 'the AI Assistant button');
    await pumpUntil(tester, panelFinder,
        timeout: const Duration(seconds: 15), describe: 'the assistant panel');
    await settleFor(tester, const Duration(seconds: 4));

    // --- the command is previewed, not performed --------------------------
    final preview = await ask(tester, 'send 10 LaptopA to Bazaar A');
    debugPrint('TEST-STEP: preview shown');

    expect(preview, contains('From: Head Office'));
    expect(preview, contains('To: Bazaar A'));
    expect(preview, contains('Quantity: 10 units'));
    expect(preview, contains('Available at Head Office: 100 units'));

    expect(find.widgetWithText(FilledButton, 'Confirm'), findsOneWidget);
    expect(find.widgetWithText(TextButton, 'Cancel'), findsOneWidget);

    // Nothing has been written yet.
    var stored = (await db.collection('assets').doc('assetA').get()).data()!;
    expect(stored['deployedQuantity'] ?? 0, 0, reason: 'a preview must not move stock');

    // --- Cancel leaves the inventory exactly as it was ---------------------
    await tapOn(tester, find.widgetWithText(TextButton, 'Cancel'), 'Cancel');

    expect(find.widgetWithText(FilledButton, 'Confirm'), findsNothing);
    expect(latestBubbleText(tester), contains('Nothing was changed'));

    stored = (await db.collection('assets').doc('assetA').get()).data()!;
    expect(stored['deployedQuantity'] ?? 0, 0);
    expect(stored['quantity'], 100);

    // --- Confirm actually moves the stock ---------------------------------
    await ask(tester, 'send 10 LaptopA to Bazaar A now');
    expect(find.widgetWithText(FilledButton, 'Confirm'), findsOneWidget);

    await tapOn(tester, find.widgetWithText(FilledButton, 'Confirm'), 'Confirm');
    debugPrint('TEST-STEP: confirmed');

    await pumpUntil(
      tester,
      find.textContaining('Done.'),
      timeout: const Duration(seconds: 40),
      describe: 'the success message',
    );

    stored = (await db.collection('assets').doc('assetA').get()).data()!;
    expect(stored['quantity'], 100, reason: 'a transfer never changes the total');
    expect(stored['deployedQuantity'], 10);
    expect(stored['headOfficeQuantity'], 90);

    // The change is recorded in the movement history like any other transfer.
    final movements = await db
        .collection('deployments')
        .where('assetDocumentId', isEqualTo: 'assetA')
        .get();

    expect(movements.docs, hasLength(1));
    expect(movements.docs.first.data()['quantity'], 10);
    expect(movements.docs.first.data()['status'], 'Active');
  });

  // =========================================================================
  // 4. THE REST OF THE APP IS UNCHANGED BY THE SHELL
  // =========================================================================

  testWidgets('non-AI navigation, screens and sign-out still behave', (tester) async {
    await seedFixtures();
    await pumpApp(tester);
    await signInThroughUi(tester, superAdminEmail, 'Sara Super');
    await pumpUntil(tester, find.text('Total Assets'), describe: 'the dashboard');

    // Dashboard figures render.
    expect(find.text('Total Assets'), findsOneWidget);
    expect(find.text('Head Office Stock'), findsWidgets);

    // Drawer -> Assets -> both seeded assets are listed for a Super Admin.
    await openDrawer(tester);
    await tester.tap(find.descendant(of: find.byType(Drawer), matching: find.text('Assets')));
    await settleFor(tester);

    await pumpUntil(
      tester,
      find.text('LaptopA'),
      timeout: const Duration(seconds: 90),
      describe: 'the asset list',
    );
    expect(find.text('LaptopB'), findsOneWidget);

    await tester.tap(find.byTooltip('Back'));
    await settleFor(tester);
    expect(find.text('Total Assets'), findsOneWidget);

    // Drawer -> Users -> the seeded accounts are listed.
    await openDrawer(tester);
    await tester.tap(find.descendant(of: find.byType(Drawer), matching: find.text('Users')));
    await settleFor(tester);

    await pumpUntil(
      tester,
      find.text('Sara Super'),
      timeout: const Duration(seconds: 90),
      describe: 'the users list',
    );

    await tester.tap(find.byTooltip('Back'));
    await settleFor(tester);
    expect(find.text('Total Assets'), findsOneWidget);

    // Sign out: the route guard must still send the session back to login even
    // though every signed-in route now lives inside a ShellRoute.
    await openDrawer(tester);
    await tester.tap(find.text('Sign out of your account'));
    await settleFor(tester);

    await tester.tap(find.widgetWithText(FilledButton, 'Logout'));

    await pumpUntil(tester, find.text('Sign in'), describe: 'the login screen after sign-out');
    expect(buttonFinder, findsNothing, reason: 'the assistant must not appear when signed out');
  });
}
