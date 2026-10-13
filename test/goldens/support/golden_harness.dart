/// Renders real screens to PNG files so the design can actually be looked at.
///
/// These are not pass/fail golden comparisons. They exist so a screen can be
/// seen - before a redesign and after it - without running the app, signing
/// in, or waiting on Firestore. Nothing here asserts pixels; each test writes
/// an image and succeeds.
///
/// Two things make that possible:
///
///   * real fonts are loaded, so text renders as text instead of as the
///     boxes `flutter test` otherwise draws, and
///   * every provider is a fake holding fixed, realistic data, so no screen
///     reaches Firebase.
library;

import 'dart:io';

import 'package:firebase_core_platform_interface/firebase_core_platform_interface.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

/// One screen size to render at.
@immutable
class GoldenDevice {
  const GoldenDevice({
    required this.name,
    required this.size,
    this.pixelRatio = 1.0,
  });

  final String name;
  final Size size;
  final double pixelRatio;

  /// A tall phone.
  static const GoldenDevice phone = GoldenDevice(
    name: 'phone',
    size: Size(390, 844),
  );

  /// A laptop browser window.
  static const GoldenDevice desktop = GoldenDevice(
    name: 'desktop',
    size: Size(1440, 900),
  );

  static const List<GoldenDevice> all = [phone, desktop];
}

/// Lets `Firebase.initializeApp` and `X.instance` succeed without a real
/// Firebase.
///
/// Needed because several services resolve `FirebaseFirestore.instance` in a
/// field initialiser, so merely constructing a provider throws before any
/// screen is built. Nothing here answers a query: the fake providers supply
/// the data, and this only stops construction from failing.
void setupFirebaseMocks() {
  TestWidgetsFlutterBinding.ensureInitialized();

  // Replacing the platform implementation rather than mocking its channels:
  // firebase_core moved to Pigeon, whose channel names and codecs are an
  // implementation detail that would break on any upgrade. Swapping the
  // platform object is the supported seam and does not touch channels at all.
  FirebasePlatform.instance = _FakeFirebasePlatform();
}

const FirebaseOptions _fakeOptions = FirebaseOptions(
  apiKey: 'test-api-key',
  appId: 'test-app-id',
  messagingSenderId: 'test-sender',
  projectId: 'test-project',
);

class _FakeFirebasePlatform extends FirebasePlatform {
  final Map<String, FirebaseAppPlatform> _apps = {};

  @override
  FirebaseAppPlatform app([String name = defaultFirebaseAppName]) {
    return _apps[name] ??= _FakeFirebaseApp(name, _fakeOptions);
  }

  @override
  Future<FirebaseAppPlatform> initializeApp({
    String? name,
    FirebaseOptions? options,
  }) async {
    final appName = name ?? defaultFirebaseAppName;
    return _apps[appName] ??= _FakeFirebaseApp(appName, options ?? _fakeOptions);
  }

  @override
  List<FirebaseAppPlatform> get apps => _apps.values.toList();
}

class _FakeFirebaseApp extends FirebaseAppPlatform {
  _FakeFirebaseApp(super.name, super.options);
}

/// Loads the fonts the screenshots are rendered with.
///
/// Inter is the app's own bundled font. Roboto is loaded too, and used for the
/// "before" screenshots, because that is what the app actually renders in
/// today - it bundles no font, so Android and the web fall back to the
/// platform's own. Rendering "before" in Inter would quietly flatter it.
Future<void> loadGoldenFonts() async {
  Future<void> load(String family, String path) async {
    final file = File(path);
    if (!file.existsSync()) return;

    final bytes = await file.readAsBytes();
    final loader = FontLoader(family)
      ..addFont(Future.value(ByteData.view(Uint8List.fromList(bytes).buffer)));
    await loader.load();
  }

  await load('Inter', 'assets/fonts/Inter-Variable.ttf');
  await load('Roboto', 'test/goldens/support/fonts/Roboto-Variable.ttf');

  // Without this every Icon renders as an empty box, which hides half of what
  // a screenshot is for. Taken from the Flutter SDK, so it is exactly the
  // glyph set the app ships with.
  await load(
    'MaterialIcons',
    'test/goldens/support/fonts/MaterialIcons-Regular.otf',
  );
}

/// Returns [theme] with [family] applied everywhere text is drawn.
///
/// `textTheme.apply` alone is not enough: button, chip and tooltip styles
/// carry their own TextStyle, baked when the theme was built and without a
/// family, so they fall back to the test font and render their labels as
/// solid blocks. Those are patched here too.
ThemeData withGoldenFont(ThemeData theme, String family) {
  TextStyle? family_(TextStyle? style) => style?.copyWith(fontFamily: family);

  WidgetStateProperty<TextStyle?>? buttonText(
    WidgetStateProperty<TextStyle?>? property,
  ) {
    if (property == null) return null;
    return WidgetStateProperty.resolveWith(
      (states) => family_(property.resolve(states)),
    );
  }

  ButtonStyle? button(ButtonStyle? style) =>
      style?.copyWith(textStyle: buttonText(style.textStyle));

  return theme.copyWith(
    textTheme: theme.textTheme.apply(fontFamily: family),
    primaryTextTheme: theme.primaryTextTheme.apply(fontFamily: family),
    elevatedButtonTheme: ElevatedButtonThemeData(
      style: button(theme.elevatedButtonTheme.style),
    ),
    filledButtonTheme: FilledButtonThemeData(
      style: button(theme.filledButtonTheme.style),
    ),
    outlinedButtonTheme: OutlinedButtonThemeData(
      style: button(theme.outlinedButtonTheme.style),
    ),
    textButtonTheme: TextButtonThemeData(
      style: button(theme.textButtonTheme.style),
    ),
    inputDecorationTheme: theme.inputDecorationTheme.copyWith(
      labelStyle: family_(theme.inputDecorationTheme.labelStyle),
      hintStyle: family_(theme.inputDecorationTheme.hintStyle),
      floatingLabelStyle: family_(theme.inputDecorationTheme.floatingLabelStyle),
    ),
    chipTheme: theme.chipTheme.copyWith(
      labelStyle: family_(theme.chipTheme.labelStyle),
    ),
    appBarTheme: theme.appBarTheme.copyWith(
      titleTextStyle: family_(theme.appBarTheme.titleTextStyle),
      toolbarTextStyle: family_(theme.appBarTheme.toolbarTextStyle),
    ),
  );
}

/// Renders [child] at [device] and writes a PNG to
/// `test/goldens/<folder>/<name>_<device>_<light|dark>.png`.
///
/// [theme] decides light or dark; [label] names the file.
Future<void> captureScreen(
  WidgetTester tester, {
  required String folder,
  required String name,
  required GoldenDevice device,
  required ThemeData theme,
  required bool dark,
  required Widget child,
  Duration settle = const Duration(milliseconds: 1200),
}) async {
  tester.view
    ..physicalSize = device.size * device.pixelRatio
    ..devicePixelRatio = device.pixelRatio;

  addTearDown(tester.view.reset);

  await tester.pumpWidget(
    MediaQuery(
      data: MediaQueryData(size: device.size, devicePixelRatio: device.pixelRatio),
      child: child,
    ),
  );

  // A screen that opens a Firestore stream in a field initialiser raises its
  // channel error during the first build, before the loop below.
  while (tester.takeException() != null) {}

  // Let entrances, staggers and count-ups finish, so the screenshot shows the
  // settled screen rather than a frame mid-animation. Pumped in steps rather
  // than with pumpAndSettle, because a looping background never settles.
  for (var i = 0; i < 14; i++) {
    await tester.pump(settle ~/ 14);
  }

  final directory = Directory('test/goldens/$folder');
  if (!directory.existsSync()) directory.createSync(recursive: true);

  // Relative to the test FILE's directory, which is how matchesGoldenFile
  // resolves a path. Passing 'test/goldens/...' would nest the output under
  // test/goldens/ again.
  final relative =
      '$folder/${name}_${device.name}_${dark ? 'dark' : 'light'}.png';

  // Some screens build a Firestore stream directly rather than through a
  // provider, so a fake cannot reach it and the query reports a channel error
  // - there being no platform implementation in a widget test. That says
  // nothing about how the screen looks, so it is consumed here. Anything else
  // still fails the test, because takeException only clears what was raised.
  while (tester.takeException() != null) {}

  // The repaint boundary the test framework puts at the root of the tree.
  final finder = find.byType(MaterialApp).first;

  await expectLater(finder, matchesGoldenFile(relative));
}
