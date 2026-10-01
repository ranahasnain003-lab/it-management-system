import '../providers/asset_provider.dart';
import '../providers/asset_scope.dart';
import '../providers/bazaar_provider.dart';
import '../providers/category_provider.dart';
import '../providers/deployment_provider.dart';
import '../providers/user_provider.dart';
import '../services/permission_service.dart';
import 'inventory_assistant.dart';

/// Builds everything the assistant may talk about from the providers the
/// signed-in account already uses, so its answers inherit that account's
/// permissions exactly.
///
/// Takes the providers themselves rather than a BuildContext so that code
/// which lives above the widget tree, or outside it altogether (the Local AI
/// context service), reads the inventory through exactly the same figures as
/// the in-app assistant panel does, instead of a second copy of this mapping
/// that could drift from it.
InventorySnapshot inventorySnapshotFromProviders({
  required AssetProvider assets,
  required BazaarProvider bazaars,
  required DeploymentProvider deployments,
  required UserProvider users,
  CategoryProvider? categories,
}) {
  final role = users.currentUserRole;

  // Whose inventory the figures actually describe, taken from the stream
  // [AssetScope] starts for this role rather than from an assumption about it.
  // A Super Admin and a User both read the whole organisation now, so a note
  // would only be noise; an Admin reads the assets it owns, so its totals are
  // not organisation-wide and saying nothing would make them look as if they
  // were. This text is shown to the user and sent to the model as a fact, so a
  // stale version of it is a wrong answer, not a cosmetic one.
  final scope = users.isAdmin
      ? 'These figures cover the inventory your own account owns.'
      : '';

  return InventorySnapshot(
    assets: assets.assets,
    bazaars: bazaars.bazaars,
    deployments: deployments.deployments,
    totalQuantity: assets.totalQuantity,
    headOfficeStock: assets.headOfficeStock,
    assignedQuantity: assets.assignedQuantity,
    bazaarQuantity: assets.deployedToBazaarsQuantity,
    damagedQuantity: assets.damagedQuantity,
    underRepairQuantity: assets.underRepairQuantity,
    lostQuantity: assets.lostQuantity,
    disposedQuantity: assets.disposedQuantity,
    unavailableAtHeadOffice: assets.unavailableAtHeadOfficeQuantity,
    totalInventoryValue: assets.totalInventoryValue,
    roleLabel: PermissionService.roleLabel(role),
    scopeNote: scope,
    // Without these the Bazaar figures would read as a confident zero.
    bazaarDataLoaded:
        deployments.deployments.isNotEmpty || bazaars.bazaars.isNotEmpty,
    // Separates "this account owns nothing" from "the stream has not answered
    // yet". Only the first is a real answer.
    inventoryLoading: AssetScope.isSettling(users: users, assets: assets),
    // Display names for the accounts this user can already see under Users, so
    // "who has IT-LAP-001" can be answered. Account ids and email addresses
    // stay in the app: InventorySnapshot.toFacts never emits either.
    holders: {
      for (final person in users.users)
        if (person.uid.trim().isNotEmpty && person.name.trim().isNotEmpty)
          person.uid: person.name,
    },
    // The category catalogue, when the caller has it. Optional because the
    // categories a typed command is checked against are merged with the ones
    // the visible assets already use, so a caller without the provider still
    // gets every category the account can see - just not an empty one nobody
    // has used yet.
    categories: categories?.categoryNames ?? const <String>[],
  );
}
