import 'package:flutter/widgets.dart';
import 'package:provider/provider.dart';

import 'asset_provider.dart';
import 'user_provider.dart';

/// The single place that decides which slice of the inventory an account may
/// stream.
///
/// The Dashboard, the Assets screen and the AI Assistant all go through here,
/// so "what this account is allowed to see" has exactly one definition. In
/// particular the assistant can never read a wider scope than the screens do:
/// it starts the same listener, against the same service, under the same
/// Firestore rules.
///
/// This replaces the copy of this branching that previously lived in both
/// dashboard_screen.dart and assets_screen.dart.
class AssetScope {
  const AssetScope._();

  /// Starts (or restarts) the inventory stream for the signed-in account.
  ///
  /// Safe to call repeatedly: [AssetProvider] ignores a request for a scope it
  /// is already streaming unless [forceRestart] is set.
  static void listenForRole({
    required UserProvider users,
    required AssetProvider assets,
    bool forceRestart = false,
  }) {
    // ============================================================
    // SUPER ADMIN - organization-wide inventory.
    // ============================================================
    if (users.isSuperAdmin) {
      assets.listenToAssets(forceRestart: forceRestart);
      return;
    }

    // ============================================================
    // ADMIN - the inventory this Admin owns.
    //
    // Write permissions stay controlled separately by the services
    // and by firestore.rules.
    // ============================================================
    if (users.isAdmin) {
      final adminUid = users.currentUserUid?.trim() ?? '';

      if (adminUid.isEmpty) {
        assets.clearAssets();
        return;
      }

      assets.listenToAdminAssets(adminUid, forceRestart: forceRestart);
      return;
    }

    // ============================================================
    // USER - never organization-wide. Their scope is the Admin who
    // created and manages their profile.
    // ============================================================
    final assignedAdminUid = users.currentUserProfile?.createdBy.trim() ?? '';

    if (assignedAdminUid.isEmpty) {
      assets.clearAssets();
      return;
    }

    assets.listenToUserAssets(assignedAdminUid, forceRestart: forceRestart);
  }

  /// [listenForRole] for callers that have a [BuildContext] rather than the
  /// providers themselves.
  static void listenFromContext(
    BuildContext context, {
    bool forceRestart = false,
  }) {
    listenForRole(
      users: context.read<UserProvider>(),
      assets: context.read<AssetProvider>(),
      forceRestart: forceRestart,
    );
  }

  /// True while the inventory for this account is still on its way.
  ///
  /// An empty list means "nothing to show" only once this is false. Before
  /// that it means "not here yet", which is a different answer.
  /// The profile decides the scope, and [AssetProvider.isLoading] is true from
  /// the moment a listener starts until its first snapshot arrives, so those
  /// two together are the whole of "not here yet". An account that really owns
  /// nothing settles with an empty list, which is a real answer.
  static bool isSettling({
    required UserProvider users,
    required AssetProvider assets,
  }) {
    return !users.hasLoadedCurrentUser || assets.isLoading;
  }
}
