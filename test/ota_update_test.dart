/// Tests for the over-the-air update system.
///
/// The thing that must never go wrong is a downgrade: a phone must not be
/// walked backwards onto an older build because somebody published the wrong
/// number or rolled a document back. That, HTTPS-only downloads, and "no
/// forced update unless it was asked for" are what most of these cover.
library;

import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:flutter/foundation.dart' show debugDefaultTargetPlatformOverride;
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:it_management_system/core/ota/app_release.dart';
import 'package:it_management_system/core/ota/ota_installer.dart';
import 'package:it_management_system/core/ota/ota_update_check.dart';
import 'package:it_management_system/core/ota/ota_update_gate.dart';
import 'package:shared_preferences/shared_preferences.dart';

AppRelease release({
  int versionCode = 2,
  String versionName = '1.1.0',
  String apkUrl = 'https://example.org/app.apk',
  String notes = '',
  bool mandatory = false,
  String sha256 = '',
}) => AppRelease(
  versionCode: versionCode,
  versionName: versionName,
  apkUrl: apkUrl,
  notes: notes,
  mandatory: mandatory,
  sha256: sha256,
);

/// Hands back whatever the test wants, without Firestore.
class FakeReleaseSource implements AppReleaseSource {
  FakeReleaseSource(this._release);

  final AppRelease? _release;
  int fetches = 0;

  @override
  Future<AppRelease?> fetch() async {
    fetches++;
    return _release;
  }
}

/// Records what it was asked to install, and can fail on demand.
class FakeInstaller implements OtaInstaller {
  FakeInstaller({this.failWith});

  final OtaInstallException? failWith;
  final List<AppRelease> installed = [];

  @override
  Future<void> downloadAndInstall(
    AppRelease release, {
    required void Function(double? fraction) onProgress,
  }) async {
    installed.add(release);
    onProgress(0.5);
    if (failWith != null) throw failWith!;
  }
}

Widget harness({
  AppReleaseSource? source,
  OtaInstaller? installer,
  int installedVersionCode = 1,
}) => MaterialApp(
  home: OtaUpdateGate(
    enabled: true,
    source: source,
    installer: installer,
    installedVersion: () async => installedVersionCode,
    child: const Scaffold(body: Text('the app')),
  ),
);

void main() {
  setUp(() {
    OtaUpdateGate.resetSessionForTest();
    SharedPreferences.setMockInitialValues({});
  });

  group('a secure download address', () {
    test('accepts https', () {
      expect(isSecureApkUrl('https://example.org/app.apk'), isTrue);
    });

    test('refuses plain http, because an APK is executable code', () {
      expect(isSecureApkUrl('http://example.org/app.apk'), isFalse);
    });

    test('refuses anything that is not an absolute https URL', () {
      for (final url in [
        '',
        '   ',
        'app.apk',
        '/app.apk',
        'ftp://example.org/app.apk',
        'https://',
        'not a url at all',
      ]) {
        expect(isSecureApkUrl(url), isFalse, reason: 'should refuse "$url"');
      }
    });
  });

  group('deciding whether to offer an update', () {
    test('offers a strictly newer build', () {
      final decision = decideUpdate(
        release: release(versionCode: 3),
        installedVersionCode: 2,
      );
      expect(decision.status, OtaUpdateStatus.updateAvailable);
      expect(decision.isUpdateAvailable, isTrue);
    });

    test('offers nothing when the published build is the one installed', () {
      final decision = decideUpdate(
        release: release(versionCode: 2),
        installedVersionCode: 2,
      );
      expect(decision.status, OtaUpdateStatus.upToDate);
      expect(decision.isUpdateAvailable, isFalse);
    });

    test('refuses a downgrade, however far back it is published', () {
      for (final published in [1, 2, 5]) {
        final decision = decideUpdate(
          release: release(versionCode: published),
          installedVersionCode: 7,
        );
        expect(
          decision.isUpdateAvailable,
          isFalse,
          reason: 'installed 7 must never be offered $published',
        );
        expect(decision.status, OtaUpdateStatus.upToDate);
      }
    });

    test('offers nothing when no release is published', () {
      final decision = decideUpdate(release: null, installedVersionCode: 1);
      expect(decision.status, OtaUpdateStatus.noRelease);
    });

    test('treats a non-HTTPS release as nothing published', () {
      final decision = decideUpdate(
        release: release(versionCode: 9, apkUrl: 'http://example.org/app.apk'),
        installedVersionCode: 1,
      );
      expect(decision.status, OtaUpdateStatus.noRelease);
    });

    test('treats a release with no version as nothing published', () {
      final decision = decideUpdate(
        release: release(versionCode: 0),
        installedVersionCode: 0,
      );
      expect(decision.status, OtaUpdateStatus.noRelease);
    });
  });

  group('forcing an update', () {
    test('is off unless it was published as mandatory', () {
      final decision = decideUpdate(
        release: release(versionCode: 3),
        installedVersionCode: 1,
      );
      expect(decision.isUpdateAvailable, isTrue);
      expect(decision.isMandatory, isFalse);
    });

    test('is on only when mandatory is explicitly true', () {
      final decision = decideUpdate(
        release: release(versionCode: 3, mandatory: true),
        installedVersionCode: 1,
      );
      expect(decision.isMandatory, isTrue);
    });

    test('cannot be mandatory when there is nothing to offer', () {
      final decision = decideUpdate(
        release: release(versionCode: 1, mandatory: true),
        installedVersionCode: 5,
      );
      expect(decision.isMandatory, isFalse);
    });
  });

  group('reading the published release from Firestore', () {
    test('reads every field', () async {
      final firestore = FakeFirebaseFirestore();
      await firestore.collection('appConfig').doc('androidRelease').set({
        'versionCode': 4,
        'versionName': '1.3.0',
        'apkUrl': 'https://example.org/v4.apk',
        'notes': 'Faster dashboard.',
        'mandatory': true,
        'sha256': 'ABCDEF',
      });

      final found = await FirestoreAppReleaseSource(
        firestore: firestore,
      ).fetch();

      expect(found, isNotNull);
      expect(found!.versionCode, 4);
      expect(found.versionName, '1.3.0');
      expect(found.apkUrl, 'https://example.org/v4.apk');
      expect(found.notes, 'Faster dashboard.');
      expect(found.mandatory, isTrue);
      expect(found.sha256, 'abcdef', reason: 'compared lower case');
      expect(found.isUsable, isTrue);
    });

    test('returns null when nothing has been published', () async {
      final found = await FirestoreAppReleaseSource(
        firestore: FakeFirebaseFirestore(),
      ).fetch();
      expect(found, isNull);
    });

    test('copes with a versionCode typed in by hand', () async {
      final firestore = FakeFirebaseFirestore();
      await firestore.collection('appConfig').doc('androidRelease').set({
        'versionCode': '6',
        'apkUrl': 'https://example.org/v6.apk',
      });

      final found = await FirestoreAppReleaseSource(
        firestore: firestore,
      ).fetch();

      expect(found!.versionCode, 6);
    });

    test('a missing mandatory field is not a forced update', () async {
      final firestore = FakeFirebaseFirestore();
      await firestore.collection('appConfig').doc('androidRelease').set({
        'versionCode': 6,
        'apkUrl': 'https://example.org/v6.apk',
      });

      final found = await FirestoreAppReleaseSource(
        firestore: firestore,
      ).fetch();

      expect(found!.mandatory, isFalse);
    });
  });

  group('the prompt on screen', () {
    testWidgets('shows nothing, and keeps the screen, when up to date', (
      tester,
    ) async {
      await tester.pumpWidget(
        harness(
          source: FakeReleaseSource(release(versionCode: 2)),
          installedVersionCode: 2,
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('Update Available'), findsNothing);
      expect(find.text('the app'), findsOneWidget);
    });

    testWidgets('shows nothing when nothing is published', (tester) async {
      await tester.pumpWidget(harness(source: FakeReleaseSource(null)));
      await tester.pumpAndSettle();

      expect(find.text('Update Available'), findsNothing);
      expect(find.text('the app'), findsOneWidget);
    });

    testWidgets('offers a newer build, over the screen', (tester) async {
      await tester.pumpWidget(
        harness(
          source: FakeReleaseSource(
            release(versionCode: 3, versionName: '1.2.0', notes: 'Bug fixes.'),
          ),
          installedVersionCode: 1,
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('Update Available'), findsOneWidget);
      expect(find.textContaining('1.2.0'), findsOneWidget);
      expect(find.text('Bug fixes.'), findsOneWidget);
      expect(find.text('Later'), findsOneWidget);
      expect(find.text('the app'), findsOneWidget);
    });

    testWidgets('downloads and installs when Update is tapped', (tester) async {
      final installer = FakeInstaller();
      await tester.pumpWidget(
        harness(
          source: FakeReleaseSource(release(versionCode: 3)),
          installer: installer,
          installedVersionCode: 1,
        ),
      );
      await tester.pumpAndSettle();

      await tester.tap(find.text('Update'));
      await tester.pumpAndSettle();

      expect(installer.installed, hasLength(1));
      expect(installer.installed.single.versionCode, 3);
      expect(find.text('Update Available'), findsNothing);
    });

    testWidgets('a download failure is explained and can be retried', (
      tester,
    ) async {
      final installer = FakeInstaller(
        failWith: const OtaInstallException('No internet connection.'),
      );
      await tester.pumpWidget(
        harness(
          source: FakeReleaseSource(release(versionCode: 3)),
          installer: installer,
          installedVersionCode: 1,
        ),
      );
      await tester.pumpAndSettle();

      await tester.tap(find.text('Update'));
      await tester.pumpAndSettle();

      expect(find.text('No internet connection.'), findsOneWidget);
      expect(find.text('Try again'), findsOneWidget);
      expect(find.text('Update Available'), findsOneWidget);
    });

    testWidgets('Later dismisses it and is remembered', (tester) async {
      await tester.pumpWidget(
        harness(
          source: FakeReleaseSource(release(versionCode: 3)),
          installedVersionCode: 1,
        ),
      );
      await tester.pumpAndSettle();

      await tester.tap(find.text('Later'));
      await tester.pumpAndSettle();

      expect(find.text('Update Available'), findsNothing);

      final prefs = await SharedPreferences.getInstance();
      expect(prefs.getInt('ota_postponed_version_code'), 3);
    });

    testWidgets('a postponed version is not offered again', (tester) async {
      SharedPreferences.setMockInitialValues({
        'ota_postponed_version_code': 3,
      });
      OtaUpdateGate.resetSessionForTest();

      await tester.pumpWidget(
        harness(
          source: FakeReleaseSource(release(versionCode: 3)),
          installedVersionCode: 1,
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('Update Available'), findsNothing);
    });

    testWidgets('a mandatory release is offered even if once postponed', (
      tester,
    ) async {
      SharedPreferences.setMockInitialValues({
        'ota_postponed_version_code': 3,
      });
      OtaUpdateGate.resetSessionForTest();

      await tester.pumpWidget(
        harness(
          source: FakeReleaseSource(release(versionCode: 3, mandatory: true)),
          installedVersionCode: 1,
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('Update Available'), findsOneWidget);
      expect(find.text('Later'), findsNothing, reason: 'cannot be dismissed');
      expect(
        find.text('This update is required to keep using the app.'),
        findsOneWidget,
      );
    });

    testWidgets('does nothing at all when disabled, as on the web', (
      tester,
    ) async {
      final source = FakeReleaseSource(release(versionCode: 9));
      await tester.pumpWidget(
        MaterialApp(
          home: OtaUpdateGate(
            enabled: false,
            source: source,
            installedVersion: () async => 1,
            child: const Scaffold(body: Text('the app')),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(source.fetches, 0, reason: 'must not even look');
      expect(find.text('Update Available'), findsNothing);
      expect(find.text('the app'), findsOneWidget);
    });

    testWidgets('checks once per session, not on every rebuild', (
      tester,
    ) async {
      final source = FakeReleaseSource(release(versionCode: 1));
      await tester.pumpWidget(harness(source: source, installedVersionCode: 1));
      await tester.pumpAndSettle();

      await tester.pumpWidget(harness(source: source, installedVersionCode: 1));
      await tester.pumpAndSettle();

      expect(source.fetches, 1);
    });

    testWidgets('a source that throws leaves the app untouched', (
      tester,
    ) async {
      await tester.pumpWidget(
        MaterialApp(
          home: OtaUpdateGate(
            enabled: true,
            source: _ThrowingSource(),
            installedVersion: () async => 1,
            child: const Scaffold(body: Text('the app')),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('the app'), findsOneWidget);
      expect(find.text('Update Available'), findsNothing);
      expect(tester.takeException(), isNull);
    });
  });

  // The updater exists only for the sideloaded Android build. Apple does not
  // permit installing an application from outside the App Store, so an update
  // prompt on an iPhone would offer something the device must refuse. These
  // tests pin that down against the REAL platform gate - no `enabled` override
  // - because an iOS build is now shipped from this same source tree.
  group('the platform gate itself', () {
    Widget realGate(FakeReleaseSource source) => MaterialApp(
      home: OtaUpdateGate(
        source: source,
        installedVersion: () async => 1,
        child: const Scaffold(body: Text('the app')),
      ),
    );

    /// Pumps the gate with its REAL platform check under [platform].
    ///
    /// The override is cleared before returning, inside a finally: the test
    /// framework asserts that foundation debug variables are back to normal
    /// as soon as the test body ends, which is before any tearDown runs.
    Future<FakeReleaseSource> pumpOn(
      WidgetTester tester,
      TargetPlatform platform,
    ) async {
      debugDefaultTargetPlatformOverride = platform;
      final source = FakeReleaseSource(release(versionCode: 99));
      try {
        await tester.pumpWidget(realGate(source));
        await tester.pumpAndSettle();
      } finally {
        debugDefaultTargetPlatformOverride = null;
      }
      return source;
    }

    testWidgets('never looks for an update on iOS', (tester) async {
      final source = await pumpOn(tester, TargetPlatform.iOS);

      expect(source.fetches, 0, reason: 'must not even read the release');
      expect(find.text('Update Available'), findsNothing);
      expect(find.text('the app'), findsOneWidget);
    });

    testWidgets('never looks for an update on macOS either', (tester) async {
      final source = await pumpOn(tester, TargetPlatform.macOS);

      expect(source.fetches, 0);
      expect(find.text('Update Available'), findsNothing);
    });

    testWidgets('does run on Android, so the gate is not simply off', (
      tester,
    ) async {
      final source = await pumpOn(tester, TargetPlatform.android);

      expect(source.fetches, 1);
      expect(find.text('Update Available'), findsOneWidget);
    });
  });
}

class _ThrowingSource implements AppReleaseSource {
  @override
  Future<AppRelease?> fetch() async => throw Exception('offline');
}
