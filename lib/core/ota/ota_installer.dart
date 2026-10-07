/// Fetching the published APK and handing it to Android's installer.
///
/// The app never installs anything itself: it downloads the file and opens it,
/// and Android's own package installer asks the person to confirm. That keeps
/// the final decision, and the permission, with the user and the system.
library;

import 'dart:async';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:open_filex/open_filex.dart';
import 'package:path_provider/path_provider.dart';

import 'app_release.dart';

/// Something went wrong that is worth telling the person about, in words they
/// can act on.
class OtaInstallException implements Exception {
  const OtaInstallException(this.message);

  final String message;

  @override
  String toString() => message;
}

/// Downloads and opens a release. An interface so the prompt can be driven in
/// tests without a network or a platform channel.
abstract class OtaInstaller {
  /// Downloads [release] and opens it in the system installer.
  ///
  /// [onProgress] receives a fraction between 0 and 1, or null while the size
  /// is still unknown.
  Future<void> downloadAndInstall(
    AppRelease release, {
    required void Function(double? fraction) onProgress,
  });
}

/// The real one.
class AndroidOtaInstaller implements OtaInstaller {
  AndroidOtaInstaller({http.Client? client}) : _client = client ?? http.Client();

  final http.Client _client;

  @override
  Future<void> downloadAndInstall(
    AppRelease release, {
    required void Function(double? fraction) onProgress,
  }) async {
    // Checked again here rather than trusting the caller: this is the moment
    // executable code is about to be fetched.
    if (!isSecureApkUrl(release.apkUrl)) {
      throw const OtaInstallException(
        'The update address is not a secure HTTPS link, so it was not downloaded.',
      );
    }

    final file = await _download(release, onProgress);

    final result = await OpenFilex.open(
      file.path,
      type: 'application/vnd.android.package-archive',
    );

    if (result.type != ResultType.done) {
      throw OtaInstallException(
        'The update was downloaded but the installer could not be opened '
        '(${result.message}). You may need to allow this app to install '
        'unknown apps in Android settings.',
      );
    }
  }

  Future<File> _download(
    AppRelease release,
    void Function(double? fraction) onProgress,
  ) async {
    // The app's own cache directory: no storage permission needed, and
    // Android reclaims it on its own if space runs short.
    final directory = await getTemporaryDirectory();
    final file = File('${directory.path}/psba-it-inventory-${release.versionCode}.apk');

    http.StreamedResponse response;
    try {
      response = await _client.send(
        http.Request('GET', Uri.parse(release.apkUrl)),
      );
    } on SocketException {
      throw const OtaInstallException(
        'The update could not be downloaded. Check your internet connection '
        'and try again.',
      );
    } on HttpException {
      throw const OtaInstallException(
        'The update could not be downloaded. Please try again.',
      );
    }

    if (response.statusCode != 200) {
      throw OtaInstallException(
        'The update is not available at the moment (server said '
        '${response.statusCode}). Please try again later.',
      );
    }

    final total = response.contentLength;
    var received = 0;

    final sink = file.openWrite();
    try {
      await for (final chunk in response.stream) {
        sink.add(chunk);
        received += chunk.length;
        onProgress(total == null || total == 0 ? null : received / total);
      }
      await sink.flush();
    } on SocketException {
      await sink.close();
      await _discard(file);
      throw const OtaInstallException(
        'The download stopped before it finished. Check your connection and '
        'try again.',
      );
    } finally {
      await sink.close();
    }

    if (release.sha256.isNotEmpty) {
      // Streamed back off disk rather than held in memory: an APK is tens of
      // megabytes and this runs on a phone.
      final actual = (await sha256.bind(file.openRead()).first).toString();
      if (actual != release.sha256) {
        // Refuse rather than install: the bytes are not the ones the
        // administrator published.
        await _discard(file);
        throw const OtaInstallException(
          'The downloaded update did not match its expected fingerprint, so '
          'it was discarded. Please try again.',
        );
      }
    }

    return file;
  }

  static Future<void> _discard(File file) async {
    try {
      if (file.existsSync()) await file.delete();
    } catch (error) {
      debugPrint('OTA: could not remove a failed download ($error)');
    }
  }
}
