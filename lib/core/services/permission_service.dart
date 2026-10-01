/// Centralized RBAC (Role-Based Access Control) service.
///
/// Exactly three roles exist, stored as these exact values:
/// - super_admin
/// - admin
/// - user
///
/// A stored role is read with [normalizeRole] (trim + lower case) and must
/// then equal one of the three. Anything else is an unknown role with NO
/// permissions, and the `roles` array is a mirror of `role` that never grants
/// anything - both of these match how firestore.rules reads a profile, so the
/// app can never offer an action the rules would refuse.
///
/// IMPORTANT:
/// This service controls application-side authorization and UI access.
///
/// Firestore Security Rules MUST independently enforce:
/// - organization isolation
/// - Super Admin access
/// - Admin ownership boundaries
/// - User read/request boundaries
///
/// Never rely on hidden buttons alone for security.
class PermissionService {
  PermissionService._();

  // ============================================================
  // MAIN ROLES
  // ============================================================

  static const String superAdminRole = 'super_admin';
  static const String adminRole = 'admin';
  static const String userRole = 'user';

  // Backward-compatible aliases.
  static const String employeeRole = userRole;
  static const String assigneeRole = userRole;
  static const String viewerRole = userRole;

  // ============================================================
  // PERMISSIONS
  // ============================================================

  static const String viewDashboard = 'view_dashboard';
  static const String viewAssets = 'view_assets';
  static const String addAsset = 'add_asset';
  static const String editAsset = 'edit_asset';
  static const String deleteAsset = 'delete_asset';
  static const String assignAsset = 'assign_asset';
  static const String reassignAsset = 'reassign_asset';
  static const String returnAsset = 'return_asset';
  static const String transferAsset = 'transfer_asset';
  static const String markDamaged = 'mark_damaged';
  static const String markUnderRepair = 'mark_under_repair';
  static const String markLost = 'mark_lost';
  static const String retireAsset = 'retire_asset';
  static const String disposeAsset = 'dispose_asset';
  static const String reserveAsset = 'reserve_asset';
  static const String viewAssetHistory = 'view_asset_history';

  static const String manageInventory = 'manage_inventory';
  static const String addCategory = 'add_category';
  static const String manageCategories = 'manage_categories';
  static const String addBazaar = 'add_bazaar';
  static const String manageBazaars = 'manage_bazaars';
  static const String manageLocations = 'manage_locations';
  static const String manageDepartments = 'manage_departments';

  static const String manageUsers = 'manage_users';
  static const String manageRoles = 'manage_roles';
  static const String managePermissions = 'manage_permissions';

  static const String viewReports = 'view_reports';
  static const String exportReports = 'export_reports';

  static const String manageOrganization = 'manage_organization';
  static const String manageSubscription = 'manage_subscription';
  static const String manageSettings = 'manage_settings';

  static const String createRequest = 'create_request';
  static const String viewOwnRequests = 'view_own_requests';
  static const String reviewRequests = 'review_requests';
  static const String approveRequests = 'approve_requests';
  static const String rejectRequests = 'reject_requests';

  static const String manageRepairs = 'manage_repairs';

  static const String viewNotifications = 'view_notifications';
  static const String manageNotifications = 'manage_notifications';

  static const String viewAuditLogs = 'view_audit_logs';

  static const String scanQr = 'scan_qr';
  static const String generateQr = 'generate_qr';
  static const String shareQr = 'share_qr';

  static const String importAssets = 'import_assets';
  static const String exportAssets = 'export_assets';
  static const String bulkAssign = 'bulk_assign';
  static const String bulkUpdate = 'bulk_update';
  static const String bulkStatusChange = 'bulk_status_change';

  static const String viewOwnAssignedAssets = 'view_own_assigned_assets';

  // ============================================================
  // ROLE NORMALIZATION
  // ============================================================

  /// THE canonical form of a stored role: trimmed and lower-cased, exactly as
  /// `roleOf()` in firestore.rules reads it.
  ///
  /// Deliberately NO alias mapping. 'Super Admin', 'super-admin',
  /// 'administrator' and 'employee' are unknown roles here, because every rule
  /// compares the stored role against 'super_admin', 'admin' or 'user' and
  /// denies anything else. Mapping them would make the app grant screens and
  /// actions whose data Firestore then refuses with permission-denied.
  static String normalizeRole(String? role) {
    return (role ?? '').trim().toLowerCase();
  }

  /// The canonical roles out of a stored `roles` array: unknown values are
  /// dropped instead of being carried around, so the mirror array written
  /// back to Firestore always satisfies the `validRoles()` rule.
  static List<String> normalizeRoles(Iterable<String>? roles) {
    if (roles == null) {
      return <String>[];
    }

    return roles
        .map(normalizeRole)
        .where(isMainRole)
        .toSet()
        .toList();
  }

  static String normalizeStatus(String? status) {
    return (status ?? '').trim().toLowerCase();
  }

  /// The only two statuses the Firestore rules let into the system.
  /// 'pending' (a self-registered account awaiting activation), 'inactive',
  /// 'blocked', 'disabled' and 'deleted' all mean no access.
  static bool isActiveStatus(String? status) {
    final value = normalizeStatus(status);

    return value == 'active' || value == 'approved';
  }

  /// A self-registered account that nobody has admitted yet.
  static bool isPendingStatus(String? status) {
    return normalizeStatus(status) == 'pending';
  }

  static String normalizePermission(String? permission) {
    return (permission ?? '')
        .trim()
        .toLowerCase()
        .replaceAll('-', '_')
        .replaceAll(' ', '_');
  }

  static List<String> normalizePermissions(Iterable<String>? permissions) {
    if (permissions == null) {
      return <String>[];
    }

    return permissions
        .map(normalizePermission)
        .where((permission) => permission.isNotEmpty)
        .toSet()
        .toList();
  }

  // ============================================================
  // ROLE CHECKS
  // ============================================================

  static bool isSuperAdmin(String? role) {
    return normalizeRole(role) == superAdminRole;
  }

  static bool isAdmin(String? role) {
    return normalizeRole(role) == adminRole;
  }

  static bool isUser(String? role) {
    return normalizeRole(role) == userRole;
  }

  // Compatibility helpers.
  // These old role names are no longer separate main roles.

  static bool isAssetManager(String? role) {
    return isAdmin(role);
  }

  static bool isInventoryManager(String? role) {
    return isAdmin(role);
  }

  static bool isDepartmentManager(String? role) {
    return isAdmin(role);
  }

  static bool isEmployee(String? role) {
    return isUser(role);
  }

  static bool isViewer(String? role) {
    return isUser(role);
  }

  // ============================================================
  // MULTIPLE ROLE SUPPORT
  // ============================================================

  static bool hasSuperAdminRole(Iterable<String>? roles) {
    return normalizeRoles(roles).contains(superAdminRole);
  }

  static bool hasAdminRole(Iterable<String>? roles) {
    return normalizeRoles(roles).contains(adminRole);
  }

  static bool hasRole(Iterable<String>? roles, String role) {
    final normalizedTarget = normalizeRole(role);

    return normalizeRoles(roles).contains(normalizedTarget);
  }

  static bool hasAnyRole(
    Iterable<String>? roles,
    Iterable<String> requiredRoles,
  ) {
    final userRoles = normalizeRoles(roles);
    final targets = normalizeRoles(requiredRoles);

    return targets.any(userRoles.contains);
  }

  static bool hasAllRoles(
    Iterable<String>? roles,
    Iterable<String> requiredRoles,
  ) {
    final userRoles = normalizeRoles(roles);
    final targets = normalizeRoles(requiredRoles);

    return targets.every(userRoles.contains);
  }

  // ============================================================
  // GENERAL APPLICATION ACCESS
  // ============================================================

  /// An account reaches the application only with an active status AND one of
  /// the three canonical roles. A 'pending' self-registration and an unknown
  /// role both end here, because the rules would deny every read that follows.
  static bool canAccessApplication({
    required String? role,
    required String? status,
    Iterable<String>? roles,
    Iterable<String>? permissions,
  }) {
    if (!isActiveStatus(status)) {
      return false;
    }

    return _decisionRoles(role, roles).isNotEmpty;
  }

  // ============================================================
  // PERMISSION CALCULATION
  // ============================================================

  /// The permissions one canonical role grants. An unknown role grants
  /// nothing, so a profile holding e.g. 'administrator' sees exactly what the
  /// Firestore rules allow it: nothing.
  ///
  /// Read from [builtInRolePermissions] so the Roles & Permissions page, this
  /// method and the rules can never drift apart.
  static Set<String> permissionsForRole(String? role) {
    return Set<String>.of(
      builtInRolePermissions[normalizeRole(role)] ?? const <String>{},
    );
  }

  /// Combines permissions from all assigned official roles.
  ///
  /// This is a definition-level union (what these roles grant together), not
  /// an authorization decision: a single account is always judged by its one
  /// primary role. See [hasPermission].
  static Set<String> permissionsForRoles(Iterable<String>? roles) {
    final result = <String>{};

    for (final role in normalizeRoles(roles)) {
      result.addAll(permissionsForRole(role));
    }

    return result;
  }

  /// Combines built-in permissions with explicit custom permissions.
  static Set<String> effectivePermissions({
    Iterable<String>? roles,
    Iterable<String>? customPermissions,
  }) {
    final result = permissionsForRoles(roles);

    result.addAll(normalizePermissions(customPermissions));

    return result;
  }

  /// The one authorization decision every capability getter goes through.
  ///
  /// [roles] is the account's role list as the screens build it: the primary
  /// `role` field FIRST, the `roles` mirror after it. Only that first entry
  /// decides. The mirror is data the rules require to mirror `role`
  /// (`validRoles()`), never a second source of privileges - a legacy
  /// document holding roles: ['super_admin'] next to role: 'user' stays a
  /// User here exactly as it does in Firestore.
  static bool hasPermission({
    Iterable<String>? roles,
    Iterable<String>? permissions,
    required String permission,
  }) {
    final normalizedPermission = normalizePermission(permission);

    if (normalizedPermission.isEmpty) {
      return false;
    }

    final primaryRole = _primaryRole(roles);

    if (primaryRole == superAdminRole) {
      return true;
    }

    final effective = permissionsForRole(primaryRole)
      ..addAll(normalizePermissions(permissions));

    return effective.contains(normalizedPermission);
  }

  // ============================================================
  // DASHBOARD
  // ============================================================

  static bool canAccessDashboard(
    String? role, {
    Iterable<String>? roles,
    Iterable<String>? permissions,
  }) {
    return hasPermission(
      roles: _decisionRoles(role, roles),
      permissions: permissions,
      permission: viewDashboard,
    );
  }

  static bool canViewFullDashboard(
    String? role, {
    Iterable<String>? roles,
    Iterable<String>? permissions,
  }) {
    final combinedRoles = _decisionRoles(role, roles);

    return hasSuperAdminRole(combinedRoles) ||
        hasAdminRole(combinedRoles) ||
        hasPermission(
          roles: combinedRoles,
          permissions: permissions,
          permission: viewReports,
        );
  }

  static bool canViewAdministrativeAnalytics(
    String? role, {
    Iterable<String>? roles,
    Iterable<String>? permissions,
  }) {
    return hasSuperAdminRole(_decisionRoles(role, roles));
  }

  // ============================================================
  // USER MANAGEMENT
  // ============================================================

  static bool canCreateUser(
    String? role, {
    Iterable<String>? roles,
    Iterable<String>? permissions,
  }) {
    return hasPermission(
      roles: _decisionRoles(role, roles),
      permissions: permissions,
      permission: manageUsers,
    );
  }

  static bool canEditUser(
    String? role, {
    Iterable<String>? roles,
    Iterable<String>? permissions,
  }) {
    return canCreateUser(role, roles: roles, permissions: permissions);
  }

  static bool canDeleteUser(
    String? role, {
    Iterable<String>? roles,
    Iterable<String>? permissions,
  }) {
    return canCreateUser(role, roles: roles, permissions: permissions);
  }

  static bool canChangeUserStatus(
    String? role, {
    Iterable<String>? roles,
    Iterable<String>? permissions,
  }) {
    return canCreateUser(role, roles: roles, permissions: permissions);
  }

  /// Only Super Admin can change the primary role of another user.
  static bool canChangeUserRole(
    String? role, {
    Iterable<String>? roles,
    Iterable<String>? permissions,
  }) {
    final combinedRoles = _decisionRoles(role, roles);

    return hasSuperAdminRole(combinedRoles);
  }

  /// Only Super Admin can manage granular permissions.
  static bool canManagePermissions(
    String? role, {
    Iterable<String>? roles,
    Iterable<String>? permissions,
  }) {
    final combinedRoles = _decisionRoles(role, roles);

    return hasSuperAdminRole(combinedRoles);
  }

  static bool canManageUsers(
    String? role, {
    Iterable<String>? roles,
    Iterable<String>? permissions,
  }) {
    return canCreateUser(role, roles: roles, permissions: permissions);
  }

  // ============================================================
  // ROLES
  // ============================================================

  /// Role administration is Super Admin only.
  static bool canManageRoles(
    String? role, {
    Iterable<String>? roles,
    Iterable<String>? permissions,
  }) {
    return hasSuperAdminRole(_decisionRoles(role, roles));
  }

  static bool canCreateCustomRole(
    String? role, {
    Iterable<String>? roles,
    Iterable<String>? permissions,
  }) {
    return canManageRoles(role, roles: roles, permissions: permissions);
  }

  static bool canEditCustomRole(
    String? role, {
    Iterable<String>? roles,
    Iterable<String>? permissions,
  }) {
    return canManageRoles(role, roles: roles, permissions: permissions);
  }

  static bool canDeleteCustomRole(
    String? role, {
    Iterable<String>? roles,
    Iterable<String>? permissions,
  }) {
    return canManageRoles(role, roles: roles, permissions: permissions);
  }

  // ============================================================
  // ASSETS
  // ============================================================

  static bool canManageAssets(
    String? role, {
    Iterable<String>? roles,
    Iterable<String>? permissions,
  }) {
    final combinedRoles = _decisionRoles(role, roles);

    return hasPermission(
          roles: combinedRoles,
          permissions: permissions,
          permission: addAsset,
        ) ||
        hasPermission(
          roles: combinedRoles,
          permissions: permissions,
          permission: editAsset,
        );
  }

  static bool canViewAssets(
    String? role, {
    Iterable<String>? roles,
    Iterable<String>? permissions,
  }) {
    return hasPermission(
      roles: _decisionRoles(role, roles),
      permissions: permissions,
      permission: viewAssets,
    );
  }

  /// Inventory is organisation-wide: every canonical role reads all of it,
  /// which is what the `allow read: if isActiveUser()` rule on /assets says.
  static bool canViewInventory(
    String? role, {
    Iterable<String>? roles,
    Iterable<String>? permissions,
  }) {
    return canViewAssets(role, roles: roles, permissions: permissions);
  }

  /// Adding inventory is allowed for a User too - only changing it later is
  /// reserved for managers.
  static bool canAddAsset(
    String? role, {
    Iterable<String>? roles,
    Iterable<String>? permissions,
  }) {
    return hasPermission(
      roles: _decisionRoles(role, roles),
      permissions: permissions,
      permission: addAsset,
    );
  }

  static bool canCreateAsset(
    String? role, {
    Iterable<String>? roles,
    Iterable<String>? permissions,
  }) {
    return hasPermission(
      roles: _decisionRoles(role, roles),
      permissions: permissions,
      permission: addAsset,
    );
  }

  static bool canEditAsset(
    String? role, {
    Iterable<String>? roles,
    Iterable<String>? permissions,
  }) {
    return hasPermission(
      roles: _decisionRoles(role, roles),
      permissions: permissions,
      permission: editAsset,
    );
  }

  static bool canDeleteAsset(
    String? role, {
    Iterable<String>? roles,
    Iterable<String>? permissions,
  }) {
    return hasPermission(
      roles: _decisionRoles(role, roles),
      permissions: permissions,
      permission: deleteAsset,
    );
  }

  static bool canAssignAsset(
    String? role, {
    Iterable<String>? roles,
    Iterable<String>? permissions,
  }) {
    return hasPermission(
      roles: _decisionRoles(role, roles),
      permissions: permissions,
      permission: assignAsset,
    );
  }

  static bool canReassignAsset(
    String? role, {
    Iterable<String>? roles,
    Iterable<String>? permissions,
  }) {
    return hasPermission(
      roles: _decisionRoles(role, roles),
      permissions: permissions,
      permission: reassignAsset,
    );
  }

  static bool canReturnAsset(
    String? role, {
    Iterable<String>? roles,
    Iterable<String>? permissions,
  }) {
    return hasPermission(
      roles: _decisionRoles(role, roles),
      permissions: permissions,
      permission: returnAsset,
    );
  }

  static bool canTransferAsset(
    String? role, {
    Iterable<String>? roles,
    Iterable<String>? permissions,
  }) {
    return hasPermission(
      roles: _decisionRoles(role, roles),
      permissions: permissions,
      permission: transferAsset,
    );
  }

  static bool canChangeAssetStatus(
    String? role, {
    Iterable<String>? roles,
    Iterable<String>? permissions,
  }) {
    final combinedRoles = _decisionRoles(role, roles);

    return hasPermission(
          roles: combinedRoles,
          permissions: permissions,
          permission: markDamaged,
        ) ||
        hasPermission(
          roles: combinedRoles,
          permissions: permissions,
          permission: markUnderRepair,
        ) ||
        hasPermission(
          roles: combinedRoles,
          permissions: permissions,
          permission: markLost,
        ) ||
        hasPermission(
          roles: combinedRoles,
          permissions: permissions,
          permission: retireAsset,
        );
  }

  // ============================================================
  // INVENTORY
  // ============================================================

  static bool canManageInventory(
    String? role, {
    Iterable<String>? roles,
    Iterable<String>? permissions,
  }) {
    return hasPermission(
      roles: _decisionRoles(role, roles),
      permissions: permissions,
      permission: manageInventory,
    );
  }

  /// Any active account may ADD a category (the document id is the name key,
  /// so a duplicate add is simply the same document).
  static bool canAddCategory(
    String? role, {
    Iterable<String>? roles,
    Iterable<String>? permissions,
  }) {
    return hasPermission(
      roles: _decisionRoles(role, roles),
      permissions: permissions,
      permission: addCategory,
    );
  }

  /// Renaming a category is open to every active account, like adding one:
  /// it only corrects a spelling. Categories are never deleted, and a rename
  /// cannot touch the category's identity, so existing assets keep working.
  static bool canManageCategories(
    String? role, {
    Iterable<String>? roles,
    Iterable<String>? permissions,
  }) {
    return hasPermission(
      roles: _decisionRoles(role, roles),
      permissions: permissions,
      permission: manageCategories,
    );
  }

  /// Any active account may ADD a Bazaar, always as an active one.
  static bool canAddBazaar(
    String? role, {
    Iterable<String>? roles,
    Iterable<String>? permissions,
  }) {
    return hasPermission(
      roles: _decisionRoles(role, roles),
      permissions: permissions,
      permission: addBazaar,
    );
  }

  /// Editing and disabling a Bazaar is a manager action - Bazaars are
  /// disabled, never deleted, so movement records keep their reference.
  static bool canManageBazaars(
    String? role, {
    Iterable<String>? roles,
    Iterable<String>? permissions,
  }) {
    return hasPermission(
      roles: _decisionRoles(role, roles),
      permissions: permissions,
      permission: manageBazaars,
    );
  }

  static bool canManageLocations(
    String? role, {
    Iterable<String>? roles,
    Iterable<String>? permissions,
  }) {
    return hasPermission(
      roles: _decisionRoles(role, roles),
      permissions: permissions,
      permission: manageLocations,
    );
  }

  static bool canManageDepartments(
    String? role, {
    Iterable<String>? roles,
    Iterable<String>? permissions,
  }) {
    return hasPermission(
      roles: _decisionRoles(role, roles),
      permissions: permissions,
      permission: manageDepartments,
    );
  }

  // ============================================================
  // ADMIN OWNERSHIP
  // ============================================================

  /// Super Admin can access every inventory.
  ///
  /// Admin can access only inventory belonging to that Admin.
  ///
  /// User does not receive inventory ownership write access here.
  static bool canAccessInventoryOwnedBy({
    required String? currentRole,
    required String? currentUid,
    required String? assetAdminId,
    Iterable<String>? roles,
  }) {
    final combinedRoles = _decisionRoles(currentRole, roles);

    if (hasSuperAdminRole(combinedRoles)) {
      return true;
    }

    if (!hasAdminRole(combinedRoles)) {
      return false;
    }

    final uid = currentUid?.trim() ?? '';
    final ownerId = assetAdminId?.trim() ?? '';

    if (uid.isEmpty || ownerId.isEmpty) {
      return false;
    }

    return uid == ownerId;
  }

  /// Inventory modification ownership check.
  ///
  /// Super Admin:
  /// - all inventory
  ///
  /// Admin:
  /// - own inventory only
  ///
  /// User:
  /// - no direct inventory modification
  static bool canModifyInventoryOwnedBy({
    required String? currentRole,
    required String? currentUid,
    required String? assetAdminId,
    Iterable<String>? roles,
    Iterable<String>? permissions,
  }) {
    final combinedRoles = _decisionRoles(currentRole, roles);

    if (hasSuperAdminRole(combinedRoles)) {
      return true;
    }

    if (!hasAdminRole(combinedRoles)) {
      return false;
    }

    final uid = currentUid?.trim() ?? '';
    final ownerId = assetAdminId?.trim() ?? '';

    if (uid.isEmpty || ownerId.isEmpty) {
      return false;
    }

    if (uid != ownerId) {
      return false;
    }

    return hasPermission(
      roles: combinedRoles,
      permissions: permissions,
      permission: editAsset,
    );
  }

  // ============================================================
  // REQUESTS
  // ============================================================

  static bool canCreateRequest(
    String? role, {
    Iterable<String>? roles,
    Iterable<String>? permissions,
  }) {
    return hasPermission(
      roles: _decisionRoles(role, roles),
      permissions: permissions,
      permission: createRequest,
    );
  }

  static bool canViewOwnRequests(
    String? role, {
    Iterable<String>? roles,
    Iterable<String>? permissions,
  }) {
    return hasPermission(
      roles: _decisionRoles(role, roles),
      permissions: permissions,
      permission: viewOwnRequests,
    );
  }

  static bool canReviewRequests(
    String? role, {
    Iterable<String>? roles,
    Iterable<String>? permissions,
  }) {
    return hasPermission(
      roles: _decisionRoles(role, roles),
      permissions: permissions,
      permission: reviewRequests,
    );
  }

  /// Approving or rejecting a request about ANY inventory. An Admin may
  /// already change any asset directly, so restricting it to its own
  /// inventory would buy nothing - the rules guard what matters instead
  /// (only a Pending request, and never one's own).
  static bool canApproveRequests(
    String? role, {
    Iterable<String>? roles,
    Iterable<String>? permissions,
  }) {
    return hasPermission(
      roles: _decisionRoles(role, roles),
      permissions: permissions,
      permission: approveRequests,
    );
  }

  static bool canApproveRejectRequests(
    String? role, {
    Iterable<String>? roles,
    Iterable<String>? permissions,
  }) {
    final combinedRoles = _decisionRoles(role, roles);

    return hasPermission(
          roles: combinedRoles,
          permissions: permissions,
          permission: approveRequests,
        ) ||
        hasPermission(
          roles: combinedRoles,
          permissions: permissions,
          permission: rejectRequests,
        );
  }

  /// Super Admin has global request administration.
  static bool canAdministrateRequests(
    String? role, {
    Iterable<String>? roles,
    Iterable<String>? permissions,
  }) {
    return hasSuperAdminRole(_decisionRoles(role, roles));
  }

  // ============================================================
  // NOTIFICATIONS
  // ============================================================

  static bool canViewNotifications(
    String? role, {
    Iterable<String>? roles,
    Iterable<String>? permissions,
  }) {
    return hasPermission(
      roles: _decisionRoles(role, roles),
      permissions: permissions,
      permission: viewNotifications,
    );
  }

  static bool canManageNotifications(
    String? role, {
    Iterable<String>? roles,
    Iterable<String>? permissions,
  }) {
    return hasPermission(
      roles: _decisionRoles(role, roles),
      permissions: permissions,
      permission: manageNotifications,
    );
  }

  // ============================================================
  // PROFILE
  // ============================================================

  static bool canViewProfile(
    String? role, {
    Iterable<String>? roles,
    Iterable<String>? permissions,
  }) {
    return canAccessApplication(
      role: role,
      status: 'active',
      roles: roles,
      permissions: permissions,
    );
  }

  static bool canEditOwnProfile(
    String? role, {
    Iterable<String>? roles,
    Iterable<String>? permissions,
  }) {
    return canViewProfile(role, roles: roles, permissions: permissions);
  }

  // ============================================================
  // SETTINGS / ORGANIZATION
  // ============================================================

  static bool canAccessAdminSettings(
    String? role, {
    Iterable<String>? roles,
    Iterable<String>? permissions,
  }) {
    return hasPermission(
      roles: _decisionRoles(role, roles),
      permissions: permissions,
      permission: manageSettings,
    );
  }

  static bool canAccessSecuritySettings(
    String? role, {
    Iterable<String>? roles,
    Iterable<String>? permissions,
  }) {
    return hasSuperAdminRole(_decisionRoles(role, roles));
  }

  static bool canManageOrganization(
    String? role, {
    Iterable<String>? roles,
    Iterable<String>? permissions,
  }) {
    return hasSuperAdminRole(_decisionRoles(role, roles));
  }

  static bool canManageSubscription(
    String? role, {
    Iterable<String>? roles,
    Iterable<String>? permissions,
  }) {
    return hasSuperAdminRole(_decisionRoles(role, roles));
  }

  // ============================================================
  // REPORTS
  // ============================================================

  static bool canViewReports(
    String? role, {
    Iterable<String>? roles,
    Iterable<String>? permissions,
  }) {
    return hasPermission(
      roles: _decisionRoles(role, roles),
      permissions: permissions,
      permission: viewReports,
    );
  }

  static bool canExportReports(
    String? role, {
    Iterable<String>? roles,
    Iterable<String>? permissions,
  }) {
    return hasPermission(
      roles: _decisionRoles(role, roles),
      permissions: permissions,
      permission: exportReports,
    );
  }

  // ============================================================
  // AUDIT LOGS
  // ============================================================

  static bool canViewAuditLogs(
    String? role, {
    Iterable<String>? roles,
    Iterable<String>? permissions,
  }) {
    return hasPermission(
      roles: _decisionRoles(role, roles),
      permissions: permissions,
      permission: viewAuditLogs,
    );
  }

  // ============================================================
  // REPAIRS
  // ============================================================

  static bool canManageRepairs(
    String? role, {
    Iterable<String>? roles,
    Iterable<String>? permissions,
  }) {
    return hasPermission(
      roles: _decisionRoles(role, roles),
      permissions: permissions,
      permission: manageRepairs,
    );
  }

  // ============================================================
  // QR / BARCODE
  // ============================================================

  static bool canScanQr(
    String? role, {
    Iterable<String>? roles,
    Iterable<String>? permissions,
  }) {
    return hasPermission(
      roles: _decisionRoles(role, roles),
      permissions: permissions,
      permission: scanQr,
    );
  }

  static bool canGenerateQr(
    String? role, {
    Iterable<String>? roles,
    Iterable<String>? permissions,
  }) {
    return hasPermission(
      roles: _decisionRoles(role, roles),
      permissions: permissions,
      permission: generateQr,
    );
  }

  static bool canShareQr(
    String? role, {
    Iterable<String>? roles,
    Iterable<String>? permissions,
  }) {
    return hasPermission(
      roles: _decisionRoles(role, roles),
      permissions: permissions,
      permission: shareQr,
    );
  }

  // ============================================================
  // BULK OPERATIONS
  // ============================================================

  static bool canImportAssets(
    String? role, {
    Iterable<String>? roles,
    Iterable<String>? permissions,
  }) {
    return hasPermission(
      roles: _decisionRoles(role, roles),
      permissions: permissions,
      permission: importAssets,
    );
  }

  static bool canExportAssets(
    String? role, {
    Iterable<String>? roles,
    Iterable<String>? permissions,
  }) {
    return hasPermission(
      roles: _decisionRoles(role, roles),
      permissions: permissions,
      permission: exportAssets,
    );
  }

  static bool canBulkAssign(
    String? role, {
    Iterable<String>? roles,
    Iterable<String>? permissions,
  }) {
    return hasPermission(
      roles: _decisionRoles(role, roles),
      permissions: permissions,
      permission: bulkAssign,
    );
  }

  static bool canBulkUpdate(
    String? role, {
    Iterable<String>? roles,
    Iterable<String>? permissions,
  }) {
    return hasPermission(
      roles: _decisionRoles(role, roles),
      permissions: permissions,
      permission: bulkUpdate,
    );
  }

  // ============================================================
  // SUPER ADMIN
  // ============================================================

  static bool hasFullAccess(String? role, {Iterable<String>? roles}) {
    return isSuperAdmin(role) || hasSuperAdminRole(roles);
  }

  static bool canAssignSuperAdminRole(
    String? currentRole, {
    Iterable<String>? currentRoles,
  }) {
    return hasFullAccess(currentRole, roles: currentRoles);
  }

  /// Only Super Admin can modify administrative user accounts.
  ///
  /// A Super Admin cannot modify their own account through this
  /// administrative operation.
  ///
  /// Protected Super Admin accounts cannot be modified through
  /// this operation.
  static bool canModifyTargetUser({
    required String? currentRole,
    required String? targetRole,
    required String currentUid,
    required String targetUid,
    Iterable<String>? currentRoles,
  }) {
    if (!hasFullAccess(currentRole, roles: currentRoles)) {
      return false;
    }

    final current = currentUid.trim();
    final target = targetUid.trim();

    if (current.isNotEmpty && target.isNotEmpty && current == target) {
      return false;
    }

    if (isSuperAdmin(targetRole)) {
      return false;
    }

    return true;
  }

  // ============================================================
  // ROLE LABELS
  // ============================================================

  static String roleLabel(String? role) {
    final normalized = normalizeRole(role);

    switch (normalized) {
      case superAdminRole:
        return 'Super Admin';

      case adminRole:
        return 'Admin';

      case userRole:
        return 'User';

      default:
        // Never 'User': a profile whose role is not one of the three has no
        // access at all, and calling it a User would hide a broken document
        // from whoever has to repair it.
        return 'Unknown role';
    }
  }

  // ============================================================
  // ROLE PERMISSION SUMMARY
  // ============================================================

  static Map<String, bool> permissionsFor(
    String? role, {
    Iterable<String>? roles,
    Iterable<String>? permissions,
  }) {
    final combinedRoles = _decisionRoles(role, roles);

    return {
      viewDashboard: hasPermission(
        roles: combinedRoles,
        permissions: permissions,
        permission: viewDashboard,
      ),
      viewAssets: hasPermission(
        roles: combinedRoles,
        permissions: permissions,
        permission: viewAssets,
      ),
      addAsset: hasPermission(
        roles: combinedRoles,
        permissions: permissions,
        permission: addAsset,
      ),
      editAsset: hasPermission(
        roles: combinedRoles,
        permissions: permissions,
        permission: editAsset,
      ),
      deleteAsset: hasPermission(
        roles: combinedRoles,
        permissions: permissions,
        permission: deleteAsset,
      ),
      assignAsset: hasPermission(
        roles: combinedRoles,
        permissions: permissions,
        permission: assignAsset,
      ),
      reassignAsset: hasPermission(
        roles: combinedRoles,
        permissions: permissions,
        permission: reassignAsset,
      ),
      returnAsset: hasPermission(
        roles: combinedRoles,
        permissions: permissions,
        permission: returnAsset,
      ),
      transferAsset: hasPermission(
        roles: combinedRoles,
        permissions: permissions,
        permission: transferAsset,
      ),
      manageInventory: hasPermission(
        roles: combinedRoles,
        permissions: permissions,
        permission: manageInventory,
      ),
      addBazaar: hasPermission(
        roles: combinedRoles,
        permissions: permissions,
        permission: addBazaar,
      ),
      manageBazaars: hasPermission(
        roles: combinedRoles,
        permissions: permissions,
        permission: manageBazaars,
      ),
      addCategory: hasPermission(
        roles: combinedRoles,
        permissions: permissions,
        permission: addCategory,
      ),
      manageCategories: hasPermission(
        roles: combinedRoles,
        permissions: permissions,
        permission: manageCategories,
      ),
      manageUsers: hasPermission(
        roles: combinedRoles,
        permissions: permissions,
        permission: manageUsers,
      ),
      manageRoles: hasPermission(
        roles: combinedRoles,
        permissions: permissions,
        permission: manageRoles,
      ),
      managePermissions: hasPermission(
        roles: combinedRoles,
        permissions: permissions,
        permission: managePermissions,
      ),
      viewReports: hasPermission(
        roles: combinedRoles,
        permissions: permissions,
        permission: viewReports,
      ),
      exportReports: hasPermission(
        roles: combinedRoles,
        permissions: permissions,
        permission: exportReports,
      ),
      viewAuditLogs: hasPermission(
        roles: combinedRoles,
        permissions: permissions,
        permission: viewAuditLogs,
      ),
      createRequest: hasPermission(
        roles: combinedRoles,
        permissions: permissions,
        permission: createRequest,
      ),
      reviewRequests: hasPermission(
        roles: combinedRoles,
        permissions: permissions,
        permission: reviewRequests,
      ),
      approveRequests: hasPermission(
        roles: combinedRoles,
        permissions: permissions,
        permission: approveRequests,
      ),
      rejectRequests: hasPermission(
        roles: combinedRoles,
        permissions: permissions,
        permission: rejectRequests,
      ),
      manageRepairs: hasPermission(
        roles: combinedRoles,
        permissions: permissions,
        permission: manageRepairs,
      ),
      scanQr: hasPermission(
        roles: combinedRoles,
        permissions: permissions,
        permission: scanQr,
      ),
      generateQr: hasPermission(
        roles: combinedRoles,
        permissions: permissions,
        permission: generateQr,
      ),
      importAssets: hasPermission(
        roles: combinedRoles,
        permissions: permissions,
        permission: importAssets,
      ),
      exportAssets: hasPermission(
        roles: combinedRoles,
        permissions: permissions,
        permission: exportAssets,
      ),
      manageOrganization: hasPermission(
        roles: combinedRoles,
        permissions: permissions,
        permission: manageOrganization,
      ),
      manageSubscription: hasPermission(
        roles: combinedRoles,
        permissions: permissions,
        permission: manageSubscription,
      ),
      manageSettings: hasPermission(
        roles: combinedRoles,
        permissions: permissions,
        permission: manageSettings,
      ),
      'hasFullAccess': hasSuperAdminRole(combinedRoles),
    };
  }

  // ============================================================
  // ALL PERMISSIONS
  // ============================================================

  static const Set<String> allPermissions = {
    viewDashboard,
    viewAssets,
    addAsset,
    editAsset,
    deleteAsset,
    assignAsset,
    reassignAsset,
    returnAsset,
    transferAsset,
    markDamaged,
    markUnderRepair,
    markLost,
    retireAsset,
    disposeAsset,
    reserveAsset,
    viewAssetHistory,
    manageInventory,
    addCategory,
    manageCategories,
    addBazaar,
    manageBazaars,
    manageLocations,
    manageDepartments,
    manageUsers,
    manageRoles,
    managePermissions,
    viewReports,
    exportReports,
    manageOrganization,
    manageSubscription,
    manageSettings,
    createRequest,
    viewOwnRequests,
    reviewRequests,
    approveRequests,
    rejectRequests,
    manageRepairs,
    viewNotifications,
    manageNotifications,
    viewAuditLogs,
    scanQr,
    generateQr,
    shareQr,
    importAssets,
    exportAssets,
    bulkAssign,
    bulkUpdate,
    bulkStatusChange,
    viewOwnAssignedAssets,
  };

  // ============================================================
  // BUILT-IN ROLE DEFINITIONS
  // ============================================================
  //
  // THE permission matrix. [permissionsForRole] reads it, the Roles &
  // Permissions page renders it, and every entry has a matching rule in
  // firestore.rules - a permission granted here that the rules deny would
  // only produce a button that fails with permission-denied.
  // ============================================================

  static const Map<String, Set<String>> builtInRolePermissions = {
    superAdminRole: allPermissions,

    adminRole: {
      viewDashboard,
      viewAssets,

      // All inventory: add, edit directly (no approval), delete when no
      // stock sits at a Bazaar or with a person, and move it.
      addAsset,
      editAsset,
      deleteAsset,
      manageInventory,
      importAssets,
      exportAssets,
      viewAssetHistory,
      assignAsset,
      reassignAsset,
      returnAsset,
      transferAsset,
      markDamaged,
      markUnderRepair,
      markLost,
      reserveAsset,

      // Master data: Bazaars and categories, add and maintain.
      addBazaar,
      manageBazaars,
      addCategory,
      manageCategories,
      manageLocations,
      manageDepartments,

      // Its own Users, including admitting a pending self-registration.
      manageUsers,

      // Requests about any inventory, and the trail they leave.
      createRequest,
      viewOwnRequests,
      reviewRequests,
      approveRequests,
      rejectRequests,
      viewAuditLogs,

      viewReports,
      exportReports,
      manageRepairs,
      viewNotifications,
      manageNotifications,
      scanQr,
      generateQr,
      shareQr,
      bulkAssign,
      bulkUpdate,
      bulkStatusChange,
      viewOwnAssignedAssets,
      manageSettings,
    },

    // Read-only on the whole organisation, plus the three additive actions
    // the rules allow any active account (asset, Bazaar, category create)
    // and a request for everything else. No edit, no delete, no disable, no
    // user directory, no audit trail.
    userRole: {
      viewDashboard,
      viewAssets,
      viewAssetHistory,
      addAsset,
      addBazaar,
      addCategory,
      // Renaming a category corrects a spelling; it cannot reach the
      // category's identity or any other field, and existing assets keep
      // working. See CategoryService.rename and the /categories update rule.
      manageCategories,
      createRequest,
      viewOwnRequests,
      viewNotifications,
      viewOwnAssignedAssets,
      scanQr,
    },
  };

  // ============================================================
  // SINGLE DECIDING ROLE
  // ============================================================

  /// The one role every capability getter below decides from, as a list so it
  /// can be handed straight to [hasPermission].
  ///
  /// Derived from the primary `role` field ONLY. [mirror] is the profile's
  /// `roles` array: it is accepted so existing call sites keep passing what
  /// they read from the document, but it never contributes a grant - the
  /// Firestore rules read `role` alone, and the app must not be more
  /// permissive than the rules. An unknown value yields no role at all.
  static List<String> _decisionRoles(String? role, Iterable<String>? mirror) {
    final primary = normalizeRole(role);

    if (!isMainRole(primary)) {
      return const <String>[];
    }

    return <String>[primary];
  }

  /// The primary role out of a role list whose FIRST entry is the account's
  /// `role` field. Anything after it is the mirror and is ignored.
  static String _primaryRole(Iterable<String>? roles) {
    if (roles == null || roles.isEmpty) {
      return '';
    }

    final primary = normalizeRole(roles.first);

    return isMainRole(primary) ? primary : '';
  }

  // ============================================================
  // MAIN ROLE VALIDATION
  // ============================================================

  static bool isMainRole(String? role) {
    final normalized = normalizeRole(role);

    return normalized == superAdminRole ||
        normalized == adminRole ||
        normalized == userRole;
  }

  static bool isKnownRole(String? role) {
    return isMainRole(role);
  }

  // ============================================================
  // ROLE LIST
  // ============================================================

  /// Exactly three official application roles.
  static const List<String> builtInRoles = [
    superAdminRole,
    adminRole,
    userRole,
  ];

  // ============================================================
  // PERMISSION LABEL
  // ============================================================

  static String permissionLabel(String permission) {
    final normalized = normalizePermission(permission);

    return normalized
        .split('_')
        .where((part) => part.isNotEmpty)
        .map((part) => '${part[0].toUpperCase()}${part.substring(1)}')
        .join(' ');
  }

  // ============================================================
  // ROLE DESCRIPTION
  // ============================================================

  static String roleDescription(String role) {
    switch (normalizeRole(role)) {
      case superAdminRole:
        return 'Full organization control, users, locations, bazaars, inventory and system administration.';

      case adminRole:
        return 'View all inventory, add, edit, delete and transfer assets, maintain Bazaars and categories, manage its own Users and approve or reject requests.';

      case userRole:
        return 'Read all inventory and movement history, add assets, Bazaars and categories, and request every other change.';

      default:
        return 'User access with permissions defined by the application.';
    }
  }
}
