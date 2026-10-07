/// Deciding whether to offer an update.
///
/// Kept apart from Firestore, the network and the widget tree on purpose: this
/// is the part that must be right, so it is plain functions over plain values
/// and is tested directly.
library;

import 'package:flutter/foundation.dart';

import 'app_release.dart';

/// Why an update is not being offered, or that it is.
enum OtaUpdateStatus {
  /// Nothing published, or what was published is unusable.
  noRelease,

  /// The published build is the one already installed, or older. This is the
  /// case that prevents a downgrade.
  upToDate,

  /// A newer build is available and the person may install it.
  updateAvailable,
}

/// The outcome of one check.
@immutable
class OtaUpdateDecision {
  const OtaUpdateDecision._(this.status, this.release);

  const OtaUpdateDecision.noRelease() : this._(OtaUpdateStatus.noRelease, null);

  const OtaUpdateDecision.upToDate(AppRelease release)
    : this._(OtaUpdateStatus.upToDate, release);

  const OtaUpdateDecision.available(AppRelease release)
    : this._(OtaUpdateStatus.updateAvailable, release);

  final OtaUpdateStatus status;

  /// The published release, when there was a usable one.
  final AppRelease? release;

  bool get isUpdateAvailable => status == OtaUpdateStatus.updateAvailable;

  /// True only when an update is available AND was published as mandatory.
  /// Anything else leaves the prompt dismissible.
  bool get isMandatory => isUpdateAvailable && (release?.mandatory ?? false);

  @override
  String toString() => 'OtaUpdateDecision($status, $release)';
}

/// Whether [release] should be offered to a device running
/// [installedVersionCode].
///
/// The comparison is strictly greater than, which is what prevents a
/// downgrade: publishing an older or equal versionCode offers nothing, so a
/// mistaken or rolled-back document can never walk a phone backwards.
///
/// An unusable release - no version, or an APK URL that is not HTTPS - is
/// treated as nothing published rather than as something to offer.
OtaUpdateDecision decideUpdate({
  required AppRelease? release,
  required int installedVersionCode,
}) {
  if (release == null || !release.isUsable) {
    return const OtaUpdateDecision.noRelease();
  }
  if (release.versionCode > installedVersionCode) {
    return OtaUpdateDecision.available(release);
  }
  return OtaUpdateDecision.upToDate(release);
}
