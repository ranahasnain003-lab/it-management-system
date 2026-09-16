/// Centralized RBAC (Role-Based Access Control) service.
///
/// Main application roles:
/// - Super Admin
/// - Admin
/// - User
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
  static const String manageCategories = 'manage_categories';
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

  static String normalizeRole(String? role) {
    return (role ?? '')
        .trim()
        .toLowerCase()
        .replaceAll('-', '_')
        .replaceAll(' ', '_');
  }

  static String normalizeRoleWithoutLegacy(String? role) {
    return (role ?? '')
        .trim()
        .toLowerCase()
        .replaceAll('-', '_')
        .replaceAll(' ', '_');
  }

  static List<String> normalizeRoles(Iterable<String>? roles) {
    if (roles == null) {
      return <String>[];
    }

    return roles
        .map(normalizeRole)
        .where((role) => role.isNotEmpty)
        .map(_normalizeLegacyRole)
        .where((role) => role.isNotEmpty)
        .toSet()
        .toList();
  }

  /// Converts supported legacy role names into the three official
  /// application roles.
  ///
  /// Official roles remain:
  /// - super_admin
  /// - admin
  /// - user
  static String _normalizeLegacyRole(String role) {
    final normalized = normalizeRoleWithoutLegacy(role);

    switch (normalized) {
      case superAdminRole:
      case 'superadmin':
      case 'super_admin_role':
        return superAdminRole;

      case adminRole:
        return adminRole;

      case userRole:
        return userRole;

      default:
        return normalized;
    }
  }

  static String normalizeStatus(String? status) {
    return (status ?? '').trim().toLowerCase();
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
    return _normalizeLegacyRole(normalizeRoleWithoutLegacy(role)) ==
        superAdminRole;
  }

  static bool isAdmin(String? role) {
    return _normalizeLegacyRole(normalizeRoleWithoutLegacy(role)) == adminRole;
  }

  static bool isUser(String? role) {
    return _normalizeLegacyRole(normalizeRoleWithoutLegacy(role)) == userRole;
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
    final normalizedTarget = _normalizeLegacyRole(
      normalizeRoleWithoutLegacy(role),
    );

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

  static bool canAccessApplication({
    required String? role,
    required String? status,
    Iterable<String>? roles,
    Iterable<String>? permissions,
  }) {
    final normalizedStatus = normalizeStatus(status);

    if (normalizedStatus != 'active' && normalizedStatus != 'approved') {
      return false;
    }

    final combinedRoles = _rolesWithLegacyRole(role, roles);

    if (hasSuperAdminRole(combinedRoles)) {
      return true;
    }

    if (hasAdminRole(combinedRoles)) {
      return true;
    }

    if (combinedRoles.contains(userRole)) {
      return true;
    }

    return normalizePermissions(permissions).isNotEmpty;
  }

  // ============================================================
  // PERMISSION CALCULATION
  // ============================================================

  static Set<String> permissionsForRole(String? role) {
    final normalized = _normalizeLegacyRole(normalizeRoleWithoutLegacy(role));

    switch (normalized) {
      case superAdminRole:
        return Set<String>.from(allPermissions);

      case adminRole:
        return {
          viewDashboard,
          viewAssets,

          // Own inventory.
          addAsset,
          editAsset,
          manageInventory,
          importAssets,
          exportAssets,
          viewAssetHistory,

          // Operational asset actions.
          assignAsset,
          reassignAsset,
          returnAsset,
          transferAsset,
          markDamaged,
          markUnderRepair,
          markLost,
          reserveAsset,

          // Inventory configuration.
          manageCategories,
          manageLocations,
          manageDepartments,

          // User edit-request workflow.
          createRequest,
          viewOwnRequests,
          reviewRequests,
          approveRequests,
          rejectRequests,

          // Reports.
          viewReports,
          exportReports,

          // Notifications.
          viewNotifications,
          manageNotifications,

          // Repairs / QR.
          manageRepairs,
          scanQr,
          generateQr,
          shareQr,

          // Bulk operations within owned inventory.
          bulkAssign,
          bulkUpdate,
          bulkStatusChange,

          viewOwnAssignedAssets,
          manageSettings,
        };

      case userRole:
        return {
          viewDashboard,
          viewAssets,

          // User cannot directly edit inventory.
          createRequest,
          viewOwnRequests,

          viewNotifications,
          viewOwnAssignedAssets,
          scanQr,
        };

      default:
        return <String>{};
    }
  }

  /// Combines permissions from all assigned official roles.
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

  static bool hasPermission({
    Iterable<String>? roles,
    Iterable<String>? permissions,
    required String permission,
  }) {
    final normalizedPermission = normalizePermission(permission);

    if (normalizedPermission.isEmpty) {
      return false;
    }

    if (hasSuperAdminRole(roles)) {
      return true;
    }

    final effective = effectivePermissions(
      roles: roles,
      customPermissions: permissions,
    );

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
      roles: _rolesWithLegacyRole(role, roles),
      permissions: permissions,
      permission: viewDashboard,
    );
  }

  static bool canViewFullDashboard(
    String? role, {
    Iterable<String>? roles,
    Iterable<String>? permissions,
  }) {
    final combinedRoles = _rolesWithLegacyRole(role, roles);

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
    return hasSuperAdminRole(_rolesWithLegacyRole(role, roles));
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
      roles: _rolesWithLegacyRole(role, roles),
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
    final combinedRoles = _rolesWithLegacyRole(role, roles);

    return hasSuperAdminRole(combinedRoles);
  }

  /// Only Super Admin can manage granular permissions.
  static bool canManagePermissions(
    String? role, {
    Iterable<String>? roles,
    Iterable<String>? permissions,
  }) {
    final combinedRoles = _rolesWithLegacyRole(role, roles);

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
    return hasSuperAdminRole(_rolesWithLegacyRole(role, roles));
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
    final combinedRoles = _rolesWithLegacyRole(role, roles);

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
      roles: _rolesWithLegacyRole(role, roles),
      permissions: permissions,
      permission: viewAssets,
    );
  }

  static bool canCreateAsset(
    String? role, {
    Iterable<String>? roles,
    Iterable<String>? permissions,
  }) {
    return hasPermission(
      roles: _rolesWithLegacyRole(role, roles),
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
      roles: _rolesWithLegacyRole(role, roles),
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
      roles: _rolesWithLegacyRole(role, roles),
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
      roles: _rolesWithLegacyRole(role, roles),
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
      roles: _rolesWithLegacyRole(role, roles),
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
      roles: _rolesWithLegacyRole(role, roles),
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
      roles: _rolesWithLegacyRole(role, roles),
      permissions: permissions,
      permission: transferAsset,
    );
  }

  static bool canChangeAssetStatus(
    String? role, {
    Iterable<String>? roles,
    Iterable<String>? permissions,
  }) {
    final combinedRoles = _rolesWithLegacyRole(role, roles);

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
      roles: _rolesWithLegacyRole(role, roles),
      permissions: permissions,
      permission: manageInventory,
    );
  }

  static bool canManageCategories(
    String? role, {
    Iterable<String>? roles,
    Iterable<String>? permissions,
  }) {
    return hasPermission(
      roles: _rolesWithLegacyRole(role, roles),
      permissions: permissions,
      permission: manageCategories,
    );
  }

  static bool canManageLocations(
    String? role, {
    Iterable<String>? roles,
    Iterable<String>? permissions,
  }) {
    return hasPermission(
      roles: _rolesWithLegacyRole(role, roles),
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
      roles: _rolesWithLegacyRole(role, roles),
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
    final combinedRoles = _rolesWithLegacyRole(currentRole, roles);

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
    final combinedRoles = _rolesWithLegacyRole(currentRole, roles);

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
      roles: _rolesWithLegacyRole(role, roles),
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
      roles: _rolesWithLegacyRole(role, roles),
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
      roles: _rolesWithLegacyRole(role, roles),
      permissions: permissions,
      permission: reviewRequests,
    );
  }

  static bool canApproveRejectRequests(
    String? role, {
    Iterable<String>? roles,
    Iterable<String>? permissions,
  }) {
    final combinedRoles = _rolesWithLegacyRole(role, roles);

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
    return hasSuperAdminRole(_rolesWithLegacyRole(role, roles));
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
      roles: _rolesWithLegacyRole(role, roles),
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
      roles: _rolesWithLegacyRole(role, roles),
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
      roles: _rolesWithLegacyRole(role, roles),
      permissions: permissions,
      permission: manageSettings,
    );
  }

  static bool canAccessSecuritySettings(
    String? role, {
    Iterable<String>? roles,
    Iterable<String>? permissions,
  }) {
    return hasSuperAdminRole(_rolesWithLegacyRole(role, roles));
  }

  static bool canManageOrganization(
    String? role, {
    Iterable<String>? roles,
    Iterable<String>? permissions,
  }) {
    return hasSuperAdminRole(_rolesWithLegacyRole(role, roles));
  }

  static bool canManageSubscription(
    String? role, {
    Iterable<String>? roles,
    Iterable<String>? permissions,
  }) {
    return hasSuperAdminRole(_rolesWithLegacyRole(role, roles));
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
      roles: _rolesWithLegacyRole(role, roles),
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
      roles: _rolesWithLegacyRole(role, roles),
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
      roles: _rolesWithLegacyRole(role, roles),
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
      roles: _rolesWithLegacyRole(role, roles),
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
      roles: _rolesWithLegacyRole(role, roles),
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
      roles: _rolesWithLegacyRole(role, roles),
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
      roles: _rolesWithLegacyRole(role, roles),
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
      roles: _rolesWithLegacyRole(role, roles),
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
      roles: _rolesWithLegacyRole(role, roles),
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
      roles: _rolesWithLegacyRole(role, roles),
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
      roles: _rolesWithLegacyRole(role, roles),
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
    final normalized = _normalizeLegacyRole(normalizeRoleWithoutLegacy(role));

    switch (normalized) {
      case superAdminRole:
        return 'Super Admin';

      case adminRole:
        return 'Admin';

      case userRole:
        return 'User';

      default:
        return 'User';
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
    final combinedRoles = _rolesWithLegacyRole(role, roles);

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
    manageCategories,
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

  static const Map<String, Set<String>> builtInRolePermissions = {
    superAdminRole: allPermissions,

    adminRole: {
      viewDashboard,
      viewAssets,
      addAsset,
      editAsset,
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
      manageCategories,
      manageLocations,
      manageDepartments,
      createRequest,
      viewOwnRequests,
      reviewRequests,
      approveRequests,
      rejectRequests,
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

    userRole: {
      viewDashboard,
      viewAssets,
      createRequest,
      viewOwnRequests,
      viewNotifications,
      viewOwnAssignedAssets,
      scanQr,
    },
  };

  // ============================================================
  // LEGACY COMPATIBILITY
  // ============================================================

  static List<String> _rolesWithLegacyRole(
    String? legacyRole,
    Iterable<String>? roles,
  ) {
    final result = <String>[];

    for (final role in normalizeRoles(roles)) {
      if (isMainRole(role)) {
        result.add(role);
      }
    }

    final normalizedLegacy = _normalizeLegacyRole(
      normalizeRoleWithoutLegacy(legacyRole),
    );

    if (normalizedLegacy.isNotEmpty &&
        isMainRole(normalizedLegacy) &&
        !result.contains(normalizedLegacy)) {
      result.add(normalizedLegacy);
    }

    return result;
  }

  // ============================================================
  // MAIN ROLE VALIDATION
  // ============================================================

  static bool isMainRole(String? role) {
    final normalized = _normalizeLegacyRole(normalizeRoleWithoutLegacy(role));

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
    switch (_normalizeLegacyRole(normalizeRoleWithoutLegacy(role))) {
      case superAdminRole:
        return 'Full organization control, users, locations, bazaars, inventory and system administration.';

      case adminRole:
        return 'Manage assigned inventory, import assets, edit owned assets and approve or reject User edit requests.';

      case userRole:
        return 'View permitted inventory and submit requests for inventory changes.';

      default:
        return 'User access with permissions defined by the application.';
    }
  }
}
