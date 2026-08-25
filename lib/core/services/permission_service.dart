import '../constants/app_constants.dart';

/// Centralized role and permission service.
///
/// This service contains the application's role-based access rules.
/// UI screens should use these methods to decide what a user can see/do,
/// while service/repository layers should also enforce the same rules
/// before performing sensitive operations.
class PermissionService {
  PermissionService._();

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

  static String normalizeStatus(String? status) {
    return (status ?? '').trim().toLowerCase();
  }

  // ============================================================
  // ROLE CHECKS
  // ============================================================

  static bool isSuperAdmin(String? role) {
    final normalized = normalizeRole(role);

    return normalized == 'super_admin' ||
        normalized == 'superadmin' ||
        normalized == 'super_admin_role';
  }

  static bool isAdmin(String? role) {
    return normalizeRole(role) == 'admin';
  }

  static bool isUser(String? role) {
    return normalizeRole(role) == 'user';
  }

  // ============================================================
  // GENERAL ACCESS
  // ============================================================

  static bool canAccessApplication({
    required String? role,
    required String? status,
  }) {
    if (normalizeStatus(status) != 'active' &&
        normalizeStatus(status) != 'approved') {
      return false;
    }

    return isSuperAdmin(role) || isAdmin(role) || isUser(role);
  }

  // ============================================================
  // DASHBOARD
  // ============================================================

  static bool canAccessDashboard(String? role) {
    return isSuperAdmin(role) || isAdmin(role) || isUser(role);
  }

  static bool canViewFullDashboard(String? role) {
    return isSuperAdmin(role) || isAdmin(role);
  }

  static bool canViewAdministrativeAnalytics(String? role) {
    return isSuperAdmin(role);
  }

  // ============================================================
  // USER MANAGEMENT
  // ============================================================

  /// Only Super Admin can create system users.
  static bool canCreateUser(String? role) {
    return isSuperAdmin(role);
  }

  /// Only Super Admin can edit users.
  static bool canEditUser(String? role) {
    return isSuperAdmin(role);
  }

  /// Only Super Admin can delete users.
  static bool canDeleteUser(String? role) {
    return isSuperAdmin(role);
  }

  /// Only Super Admin can activate/deactivate users.
  static bool canChangeUserStatus(String? role) {
    return isSuperAdmin(role);
  }

  /// Only Super Admin can change roles.
  static bool canChangeUserRole(String? role) {
    return isSuperAdmin(role);
  }

  /// Only Super Admin can manage permissions.
  static bool canManagePermissions(String? role) {
    return isSuperAdmin(role);
  }

  /// Admin and normal User must never access user-management
  /// operations.
  static bool canManageUsers(String? role) {
    return isSuperAdmin(role);
  }

  // ============================================================
  // INVENTORY / ASSETS
  // ============================================================

  /// Super Admin and Admin can directly manage assets.
  ///
  /// Normal User must submit a request.
  static bool canManageAssets(String? role) {
    return isSuperAdmin(role) || isAdmin(role);
  }

  static bool canViewAssets(String? role) {
    return isSuperAdmin(role) || isAdmin(role) || isUser(role);
  }

  static bool canCreateAsset(String? role) {
    return isSuperAdmin(role) || isAdmin(role);
  }

  static bool canEditAsset(String? role) {
    return isSuperAdmin(role) || isAdmin(role);
  }

  static bool canDeleteAsset(String? role) {
    return isSuperAdmin(role) || isAdmin(role);
  }

  static bool canAssignAsset(String? role) {
    return isSuperAdmin(role) || isAdmin(role);
  }

  static bool canChangeAssetStatus(String? role) {
    return isSuperAdmin(role) || isAdmin(role);
  }

  // ============================================================
  // REQUESTS
  // ============================================================

  /// Normal users can submit requests.
  ///
  /// Admin and Super Admin can also submit requests if required by
  /// the workflow, but they are not forced to use requests for
  /// normal administrative asset operations.
  static bool canCreateRequest(String? role) {
    return isSuperAdmin(role) || isAdmin(role) || isUser(role);
  }

  /// Everyone can see their own requests.
  static bool canViewOwnRequests(String? role) {
    return isSuperAdmin(role) || isAdmin(role) || isUser(role);
  }

  /// Super Admin and Admin can review requests.
  static bool canReviewRequests(String? role) {
    return isSuperAdmin(role) || isAdmin(role);
  }

  /// Super Admin and Admin can approve/reject requests.
  static bool canApproveRejectRequests(String? role) {
    return isSuperAdmin(role) || isAdmin(role);
  }

  /// Only Super Admin can make system-wide request decisions if
  /// the application is configured for Super Admin-only approval.
  static bool canAdministrateRequests(String? role) {
    return isSuperAdmin(role);
  }

  // ============================================================
  // NOTIFICATIONS
  // ============================================================

  static bool canViewNotifications(String? role) {
    return isSuperAdmin(role) || isAdmin(role) || isUser(role);
  }

  // ============================================================
  // PROFILE
  // ============================================================

  static bool canViewProfile(String? role) {
    return isSuperAdmin(role) || isAdmin(role) || isUser(role);
  }

  /// A user can update their own basic profile information.
  ///
  /// Role, status and administrative fields must remain protected.
  static bool canEditOwnProfile(String? role) {
    return isSuperAdmin(role) || isAdmin(role) || isUser(role);
  }

  // ============================================================
  // ADMINISTRATIVE SETTINGS
  // ============================================================

  static bool canAccessAdminSettings(String? role) {
    return isSuperAdmin(role);
  }

  static bool canAccessSecuritySettings(String? role) {
    return isSuperAdmin(role);
  }

  // ============================================================
  // REPORTS
  // ============================================================

  static bool canViewReports(String? role) {
    return isSuperAdmin(role) || isAdmin(role);
  }

  static bool canExportReports(String? role) {
    return isSuperAdmin(role) || isAdmin(role);
  }

  // ============================================================
  // AUDIT LOGS
  // ============================================================

  static bool canViewAuditLogs(String? role) {
    return isSuperAdmin(role);
  }

  // ============================================================
  // SUPER ADMIN
  // ============================================================

  /// Super Admin is the highest application role.
  static bool hasFullAccess(String? role) {
    return isSuperAdmin(role);
  }

  /// Normal users must never be able to assign themselves or anyone
  /// else the Super Admin role.
  static bool canAssignSuperAdminRole(String? currentRole) {
    return isSuperAdmin(currentRole);
  }

  /// Protect the Super Admin account from normal user-management
  /// operations.
  static bool canModifyTargetUser({
    required String? currentRole,
    required String? targetRole,
    required String currentUid,
    required String targetUid,
  }) {
    if (!isSuperAdmin(currentRole)) {
      return false;
    }

    final normalizedTargetRole = normalizeRole(targetRole);

    // The Super Admin cannot accidentally modify their own account
    // through normal user-management actions.
    if (currentUid.trim().isNotEmpty &&
        targetUid.trim().isNotEmpty &&
        currentUid.trim() == targetUid.trim()) {
      return false;
    }

    // A Super Admin should not be modified through the normal
    // user-management workflow.
    if (normalizedTargetRole == 'super_admin' ||
        normalizedTargetRole == 'superadmin') {
      return false;
    }

    return true;
  }

  // ============================================================
  // ROLE LABELS
  // ============================================================

  static String roleLabel(String? role) {
    if (isSuperAdmin(role)) {
      return 'Super Admin';
    }

    if (isAdmin(role)) {
      return 'Admin';
    }

    if (isUser(role)) {
      return 'User';
    }

    return 'Unknown';
  }

  // ============================================================
  // ROLE PERMISSION SUMMARY
  // ============================================================

  static Map<String, bool> permissionsFor(String? role) {
    return {
      'viewDashboard': canAccessDashboard(role),
      'viewFullDashboard': canViewFullDashboard(role),
      'viewAssets': canViewAssets(role),
      'createAsset': canCreateAsset(role),
      'editAsset': canEditAsset(role),
      'deleteAsset': canDeleteAsset(role),
      'assignAsset': canAssignAsset(role),
      'createUser': canCreateUser(role),
      'editUser': canEditUser(role),
      'deleteUser': canDeleteUser(role),
      'changeUserStatus': canChangeUserStatus(role),
      'changeUserRole': canChangeUserRole(role),
      'managePermissions': canManagePermissions(role),
      'createRequest': canCreateRequest(role),
      'viewOwnRequests': canViewOwnRequests(role),
      'reviewRequests': canReviewRequests(role),
      'approveRejectRequests': canApproveRejectRequests(role),
      'viewNotifications': canViewNotifications(role),
      'viewProfile': canViewProfile(role),
      'editOwnProfile': canEditOwnProfile(role),
      'viewReports': canViewReports(role),
      'exportReports': canExportReports(role),
      'viewAuditLogs': canViewAuditLogs(role),
      'adminSettings': canAccessAdminSettings(role),
      'securitySettings': canAccessSecuritySettings(role),
      'fullAccess': hasFullAccess(role),
    };
  }

  // ============================================================
  // CONSTANT-BASED HELPERS
  // ============================================================

  /// Useful when callers already have AppConstants role values.
  static bool isKnownRole(String? role) {
    return role == AppConstants.SUPER_ADMIN ||
        role == AppConstants.ADMIN ||
        role == AppConstants.USER;
  }
}
