/// Mounts the update check above the signed-in screens.
///
/// It adds nothing to the layout: [build] returns the child untouched. The
/// only thing this widget ever does is, once per app session, ask whether a
/// newer build has been published and - if one has - show a dialog.
///
/// It is deliberately silent about everything else. No release published, no
/// network, not signed in, no permission: all of them leave the app behaving
/// exactly as it did before.
library;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'app_release.dart';
import 'ota_installer.dart';
import 'ota_update_check.dart';

/// Reads the versionCode of the build that is running.
typedef InstalledVersionReader = Future<int> Function();

Future<int> _installedVersionFromPlatform() async {
  final info = await PackageInfo.fromPlatform();
  return int.tryParse(info.buildNumber.trim()) ?? 0;
}

/// Remembers the one version the person chose to postpone, so a dismissed
/// prompt does not reappear on every launch. A mandatory release ignores it.
const String _postponedKey = 'ota_postponed_version_code';

/// Checked once per app session, not once per navigation: the shell this sits
/// in is rebuilt as the person moves between screens.
bool _checkedThisSession = false;

class OtaUpdateGate extends StatefulWidget {
  const OtaUpdateGate({
    super.key,
    required this.child,
    this.source,
    this.installer,
    this.installedVersion,
    this.enabled,
  });

  final Widget child;

  /// Defaults to the real Firestore document. Tests pass a fake.
  final AppReleaseSource? source;

  /// Defaults to the real downloader. Tests pass a fake.
  final OtaInstaller? installer;

  /// Defaults to the running build's versionCode.
  final InstalledVersionReader? installedVersion;

  /// Defaults to "Android only". Over-the-air APK updates mean nothing on the
  /// web build, which is served from Hosting and is always current.
  final bool? enabled;

  /// Lets a test run the check again in the same process.
  @visibleForTesting
  static void resetSessionForTest() => _checkedThisSession = false;

  @override
  State<OtaUpdateGate> createState() => _OtaUpdateGateState();
}

class _OtaUpdateGateState extends State<OtaUpdateGate> {
  @override
  void initState() {
    super.initState();
    // After the first frame, so the dialog has a mounted Navigator and the
    // screen underneath has already been drawn.
    WidgetsBinding.instance.addPostFrameCallback((_) => _check());
  }

  bool get _enabled =>
      widget.enabled ??
      (!kIsWeb && defaultTargetPlatform == TargetPlatform.android);

  Future<void> _check() async {
    if (!_enabled || _checkedThisSession) return;
    _checkedThisSession = true;

    try {
      final source = widget.source ?? FirestoreAppReleaseSource();
      final release = await source.fetch();
      final installed =
          await (widget.installedVersion ?? _installedVersionFromPlatform)();

      final decision = decideUpdate(
        release: release,
        installedVersionCode: installed,
      );
      if (!decision.isUpdateAvailable) return;

      if (!decision.isMandatory && await _wasPostponed(decision.release!)) {
        return;
      }

      if (!mounted) return;
      await showDialog<void>(
        context: context,
        barrierDismissible: !decision.isMandatory,
        builder: (_) => OtaUpdatePrompt(
          release: decision.release!,
          mandatory: decision.isMandatory,
          installer: widget.installer ?? AndroidOtaInstaller(),
        ),
      );
    } catch (error) {
      // An update check is never allowed to break the app it is checking.
      debugPrint('OTA: update check skipped ($error)');
    }
  }

  Future<bool> _wasPostponed(AppRelease release) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      return prefs.getInt(_postponedKey) == release.versionCode;
    } catch (error) {
      debugPrint('OTA: could not read the postponed version ($error)');
      return false;
    }
  }

  @override
  Widget build(BuildContext context) => widget.child;
}

/// The "Update Available" dialog, and the download it runs.
class OtaUpdatePrompt extends StatefulWidget {
  const OtaUpdatePrompt({
    super.key,
    required this.release,
    required this.mandatory,
    required this.installer,
  });

  final AppRelease release;
  final bool mandatory;
  final OtaInstaller installer;

  @override
  State<OtaUpdatePrompt> createState() => _OtaUpdatePromptState();
}

class _OtaUpdatePromptState extends State<OtaUpdatePrompt> {
  bool _downloading = false;
  double? _fraction;
  String? _error;

  Future<void> _start() async {
    setState(() {
      _downloading = true;
      _fraction = null;
      _error = null;
    });

    try {
      await widget.installer.downloadAndInstall(
        widget.release,
        onProgress: (fraction) {
          if (mounted) setState(() => _fraction = fraction);
        },
      );
      // Android's installer is now in front of the person. Close the dialog so
      // they do not return to it behind the system screen.
      if (mounted) Navigator.of(context).pop();
    } on OtaInstallException catch (failure) {
      if (mounted) {
        setState(() {
          _downloading = false;
          _error = failure.message;
        });
      }
    } catch (error) {
      if (mounted) {
        setState(() {
          _downloading = false;
          _error = 'The update could not be installed. Please try again.';
        });
      }
    }
  }

  Future<void> _later() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setInt(_postponedKey, widget.release.versionCode);
    } catch (error) {
      debugPrint('OTA: could not remember the postponed version ($error)');
    }
    if (mounted) Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    final release = widget.release;

    return AlertDialog(
      title: const Text('Update Available'),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            release.versionName.isEmpty
                ? 'A newer version of PSBA IT Inventory is available.'
                : 'Version ${release.versionName} of PSBA IT Inventory is '
                      'available.',
          ),
          if (release.notes.isNotEmpty) ...[
            const SizedBox(height: 12),
            Text(release.notes, style: Theme.of(context).textTheme.bodySmall),
          ],
          if (widget.mandatory) ...[
            const SizedBox(height: 12),
            Text(
              'This update is required to keep using the app.',
              style: Theme.of(context).textTheme.bodySmall,
            ),
          ],
          if (_downloading) ...[
            const SizedBox(height: 16),
            LinearProgressIndicator(value: _fraction),
            const SizedBox(height: 8),
            Text(
              _fraction == null
                  ? 'Downloading...'
                  : 'Downloading ${(_fraction! * 100).round()}%',
              style: Theme.of(context).textTheme.bodySmall,
            ),
          ],
          if (_error != null) ...[
            const SizedBox(height: 16),
            Text(
              _error!,
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                color: Theme.of(context).colorScheme.error,
              ),
            ),
          ],
        ],
      ),
      actions: [
        if (!widget.mandatory && !_downloading)
          TextButton(onPressed: _later, child: const Text('Later')),
        FilledButton(
          onPressed: _downloading ? null : _start,
          child: Text(_error == null ? 'Update' : 'Try again'),
        ),
      ],
    );
  }
}
