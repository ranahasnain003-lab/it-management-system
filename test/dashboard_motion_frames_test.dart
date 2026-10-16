/// Proof that the dashboard actually moves.
///
/// Every other motion test in this repo checks a mechanism - that a controller
/// exists, that a widget does not rebuild, that a value lands where it should.
/// None of them would notice if the whole thing were wired up correctly and
/// still looked like a photograph, which is exactly the complaint this round
/// of work started from.
///
/// So this one renders the real dashboard and compares pixels. It takes a
/// frame at 0, 300, 600, 1000, 3000 and 6000 ms after opening and measures how
/// much of the screen changed between them:
///
///   * **0 -> 1000 ms** is the opening sequence. Consecutive frames have to
///     differ substantially, which is the difference between "it animates" and
///     "it appears".
///   * **3000 -> 6000 ms** is long after the sequence has finished. If those
///     two frames are identical the screen is static once it has settled,
///     which is the thing that was asked for and did not happen.
///   * With motion off, every frame has to be **identical**, or the Settings
///     switch and the operating system's reduce-motion preference are lies.
///
/// The frames are written to `test/goldens/dashboard_motion/` on every run, so
/// they can be looked at rather than trusted.
library;

import 'dart:io';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';

import 'package:it_management_system/core/dashboard/screens/dashboard_screen.dart';
import 'package:it_management_system/core/providers/asset_provider.dart';
import 'package:it_management_system/core/providers/auth_provider.dart';
import 'package:it_management_system/core/providers/bazaar_provider.dart';
import 'package:it_management_system/core/providers/deployment_provider.dart';
import 'package:it_management_system/core/providers/notification_provider.dart';
import 'package:it_management_system/core/providers/request_provider.dart';
import 'package:it_management_system/core/providers/theme_provider.dart';
import 'package:it_management_system/core/providers/user_provider.dart';
import 'package:it_management_system/core/theme/app_brand.dart';
import 'package:it_management_system/core/theme/app_motion.dart';
import 'package:it_management_system/core/theme/app_theme.dart';

import 'goldens/support/fake_providers.dart';
import 'goldens/support/golden_harness.dart';

/// Where the frames land, so they can be looked at.
const String _outputDirectory = 'test/goldens/dashboard_motion';

/// The boundary the frames are photographed from. Its own, rather than one of
/// the hundreds the screen contains, so the capture is unambiguous.
final GlobalKey _captureKey = GlobalKey();

/// The moments sampled, in milliseconds after the screen is mounted.
///
/// 3000 and 6000 are deliberately not a whole number of loop periods apart:
/// every continuous effect here is driven by a sine or a cosine, and sampling
/// two mirror-image phases of one would show no change for a reason that has
/// nothing to do with whether it is moving.
const List<int> _checkpoints = [0, 300, 600, 1000, 3000, 6000];

Widget _dashboard({required AnimationLevel level}) {
  return RepaintBoundary(
    key: _captureKey,
    child: MultiProvider(
      providers: [
        ChangeNotifierProvider<AuthProvider>(create: (_) => FakeAuthProvider()),
        ChangeNotifierProvider<UserProvider>(create: (_) => FakeUserProvider()),
        ChangeNotifierProvider<AssetProvider>(
          create: (_) => FakeAssetProvider(),
        ),
        ChangeNotifierProvider<BazaarProvider>(
          create: (_) => FakeBazaarProvider(),
        ),
        ChangeNotifierProvider<DeploymentProvider>(
          create: (_) => FakeDeploymentProvider(),
        ),
        ChangeNotifierProvider<RequestProvider>(
          create: (_) => FakeRequestProvider(),
        ),
        ChangeNotifierProvider<NotificationProvider>(
          create: (_) => FakeNotificationProvider(),
        ),
        ChangeNotifierProvider<ThemeProvider>(
          create: (_) => FakeThemeProvider(level: level),
        ),
      ],
      child: MotionScope(
        level: level,
        child: MaterialApp(
          debugShowCheckedModeBanner: false,
          theme: withGoldenFont(AppTheme.light(), AppType.family),
          // Pinned, so a frame comparison is never a comparison of two
          // different dates.
          home: DashboardScreen(today: DateTime(2026, 10, 13, 9, 40)),
        ),
      ),
    ),
  );
}

/// One frame, as raw pixels plus the PNG to look at.
class _Frame {
  const _Frame(this.rgba, this.png, this.width, this.height);

  final Uint8List rgba;
  final Uint8List png;
  final int width;
  final int height;
}

Future<_Frame> _grab(WidgetTester tester) async {
  final boundary =
      _captureKey.currentContext!.findRenderObject() as RenderRepaintBoundary;

  // runAsync, because the engine resolves toImage and toByteData on the real
  // event loop. Under the test binding's fake clock those futures simply
  // never complete, and the test hangs rather than failing - which is what it
  // did before this was here.
  final frame = await tester.runAsync(() async {
    final image = await boundary.toImage();

    final rgba = await image.toByteData(format: ui.ImageByteFormat.rawRgba);
    final png = await image.toByteData(format: ui.ImageByteFormat.png);

    final captured = _Frame(
      rgba!.buffer.asUint8List(),
      png!.buffer.asUint8List(),
      image.width,
      image.height,
    );

    image.dispose();

    return captured;
  });

  return frame!;
}

/// The share of pixels that differ between two frames, 0 to 1.
///
/// A pixel counts as changed only if a channel moved by more than 6/255, so
/// anti-aliasing jitter on static text does not read as motion.
double _changed(_Frame a, _Frame b) {
  expect(a.width, b.width);
  expect(a.height, b.height);

  const threshold = 6;
  var differing = 0;

  for (var i = 0; i < a.rgba.length; i += 4) {
    final dr = (a.rgba[i] - b.rgba[i]).abs();
    final dg = (a.rgba[i + 1] - b.rgba[i + 1]).abs();
    final db = (a.rgba[i + 2] - b.rgba[i + 2]).abs();

    if (dr > threshold || dg > threshold || db > threshold) differing++;
  }

  return differing / (a.width * a.height);
}

/// Mounts the dashboard, then samples it at each checkpoint.
Future<Map<int, _Frame>> _timeline(
  WidgetTester tester, {
  required AnimationLevel level,
  required String prefix,
}) async {
  tester.view
    ..physicalSize = GoldenDevice.phone.size
    ..devicePixelRatio = 1.0;

  addTearDown(tester.view.reset);

  await tester.pumpWidget(
    MediaQuery(
      data: MediaQueryData(
        size: GoldenDevice.phone.size,
        devicePixelRatio: 1.0,
      ),
      child: _dashboard(level: level),
    ),
  );

  // The dashboard opens a Bazaar stream through its provider; in a widget test
  // the platform channel behind it has no implementation and reports an error
  // during the first build. It says nothing about how the screen moves.
  while (tester.takeException() != null) {}

  final directory = Directory(_outputDirectory);
  if (!directory.existsSync()) directory.createSync(recursive: true);

  final frames = <int, _Frame>{};
  var elapsed = 0;

  for (final checkpoint in _checkpoints) {
    // Stepped in small increments rather than jumped, because one long pump
    // would skip every intermediate value and land the controllers somewhere
    // the real screen never passes through. Never pumpAndSettle: the alive
    // loops repeat forever and it would time out.
    while (elapsed < checkpoint) {
      final step = (checkpoint - elapsed).clamp(0, 16);
      await tester.pump(Duration(milliseconds: step));
      elapsed += step;
    }

    if (checkpoint == 0) await tester.pump(Duration.zero);

    final frame = await _grab(tester);
    frames[checkpoint] = frame;

    File(
      '$_outputDirectory/${prefix}_${checkpoint.toString().padLeft(4, '0')}ms.png',
    ).writeAsBytesSync(frame.png);
  }

  while (tester.takeException() != null) {}

  return frames;
}

void main() {
  setUpAll(() async {
    setupFirebaseMocks();
    await Firebase.initializeApp();
    await loadGoldenFonts();
  });

  group('the opening sequence is visible', () {
    testWidgets('every frame of the first second differs from the last', (
      tester,
    ) async {
      final frames = await _timeline(
        tester,
        level: AnimationLevel.rich,
        prefix: 'rich',
      );

      // Each consecutive pair inside the sequence. 5% of the screen is a low
      // bar on purpose - it is the floor below which a person would not
      // notice, not a description of what this actually does.
      for (final pair in [(0, 300), (300, 600), (600, 1000)]) {
        final change = _changed(frames[pair.$1]!, frames[pair.$2]!);

        expect(
          change,
          greaterThan(0.05),
          reason:
              'Only ${(change * 100).toStringAsFixed(1)}% of the screen '
              'changed between ${pair.$1}ms and ${pair.$2}ms. The opening '
              'sequence is not visible.',
        );
      }

      // And the whole first second against the settled screen, which is the
      // thing somebody actually sees when they open it.
      expect(_changed(frames[0]!, frames[1000]!), greaterThan(0.20));
    });

    testWidgets('the screen is still alive long after it has settled', (
      tester,
    ) async {
      final frames = await _timeline(
        tester,
        level: AnimationLevel.rich,
        prefix: 'alive',
      );

      final change = _changed(frames[3000]!, frames[6000]!);

      expect(
        change,
        greaterThan(0.01),
        reason:
            'Only ${(change * 100).toStringAsFixed(1)}% of the screen '
            'changed between 3s and 6s. The dashboard stops moving once the '
            'entrance is over.',
      );
    });
  });

  group('the levels mean what they say', () {
    testWidgets('off: every frame is identical', (tester) async {
      final frames = await _timeline(
        tester,
        level: AnimationLevel.off,
        prefix: 'off',
      );

      for (final checkpoint in _checkpoints.skip(1)) {
        expect(
          _changed(frames[_checkpoints.first]!, frames[checkpoint]!),
          0,
          reason:
              'The screen changed by ${checkpoint}ms with animation off. '
              'Nothing may move at this level, including under the operating '
              'system\'s reduce-motion setting.',
        );
      }
    });

    testWidgets('subtle: it opens, then holds still', (tester) async {
      final frames = await _timeline(
        tester,
        level: AnimationLevel.subtle,
        prefix: 'subtle',
      );

      // The opening sequence is kept at this level...
      expect(
        _changed(frames[0]!, frames[1000]!),
        greaterThan(0.10),
        reason: 'Subtle drops the opening sequence, which it should keep.',
      );

      // ...and every self-starting loop is dropped, so the settled screen is
      // completely static.
      expect(
        _changed(frames[3000]!, frames[6000]!),
        0,
        reason:
            'Something is still looping at the subtle level. Subtle keeps the '
            'entrance and nothing that moves on its own.',
      );
    });
  });
}
