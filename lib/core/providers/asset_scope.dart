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
/// Reading inventory is organisation-wide for every active account: the
/// `assets` read rule is `isActiveUser()`, so a Super Admin and a User stream
/// the very same query. Only the Admin scope still narrows, and what an
/// account may WRITE is decided by the services and by firestore.rules, never
/// by which listener started here.
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
    // USER - the whole inventory, read-only.
    //
    // The same unscoped listener the Super Admin uses, because every
    // active account may now read every asset. Scoping a User to the
    // Admin in their createdBy hid inventory they are allowed to see,
    // and a self-registered account (whose createdBy is '') was shown
    // nothing at all - which is why the clearAssets() path is gone.
    // ============================================================
    assets.listenToAssets(forceRestart: forceRestart);
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
