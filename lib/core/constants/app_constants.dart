class AppConstants {
  AppConstants._();

  // ============================================================
  // APPLICATION
  // ============================================================

  static const String appName = 'IT Management System';
  static const String appVersion = '1.0.0';

  // ============================================================
  // FIRESTORE COLLECTIONS
  // ============================================================

  static const String usersCollection = 'users';
  static const String assetsCollection = 'assets';
  static const String requestsCollection = 'requests';
  static const String notificationsCollection = 'notifications';
  static const String logsCollection = 'logs';

  // Activity logs compatibility name.
  // Used by LogService.
  static const String activityLogsCollection = logsCollection;

  // Compatibility aliases.
  static const String users = usersCollection;
  static const String assets = assetsCollection;
  static const String requests = requestsCollection;
  static const String notifications = notificationsCollection;
  static const String logs = logsCollection;

  // ============================================================
  // USER ROLES
  // ============================================================

  static const String superAdminRole = 'super_admin';
  static const String adminRole = 'admin';
  static const String userRole = 'user';

  // Uppercase compatibility constants.
  //
  // These are intentionally retained because existing screens and
  // services use AppConstants.SUPER_ADMIN / ADMIN / USER.
  // ignore: constant_identifier_names
  static const String SUPER_ADMIN = superAdminRole;

  // ignore: constant_identifier_names
  static const String ADMIN = adminRole;

  // ignore: constant_identifier_names
  static const String USER = userRole;

  // ============================================================
  // USER STATUS
  // ============================================================

  static const String activeStatus = 'active';
  static const String inactiveStatus = 'inactive';
  static const String blockedStatus = 'blocked';
  static const String pendingStatus = 'pending';

  // ============================================================
  // ASSET STATUS
  // ============================================================

  static const String availableStatus = 'Available';
  static const String assignedStatus = 'Assigned';
  static const String reservedStatus = 'Reserved';
  static const String underMaintenanceStatus = 'Under Maintenance';
  static const String inRepairStatus = 'In Repair';
  static const String damagedStatus = 'Damaged';
  static const String lostStatus = 'Lost';
  static const String disposedStatus = 'Disposed';

  // Compatibility aliases.
  static const String available = availableStatus;
  static const String assigned = assignedStatus;
  static const String reserved = reservedStatus;
  static const String underMaintenance = underMaintenanceStatus;
  static const String inRepair = inRepairStatus;
  static const String damaged = damagedStatus;
  static const String lost = lostStatus;
  static const String disposed = disposedStatus;

  // ============================================================
  // REQUEST STATUS
  // ============================================================

  static const String requestPending = 'Pending';
  static const String requestApproved = 'Approved';
  static const String requestRejected = 'Rejected';

  // ============================================================
  // REQUEST TYPES
  // ============================================================

  static const String addRequest = 'add';
  static const String editRequest = 'edit';
  static const String deleteRequest = 'delete';
  static const String assignRequest = 'assign';
  static const String returnRequest = 'return';

  // ============================================================
  // PERMISSION NAMES
  // ============================================================

  static const String viewAssetsPermission = 'view_assets';
  static const String addAssetsPermission = 'add_assets';
  static const String editAssetsPermission = 'edit_assets';
  static const String deleteAssetsPermission = 'delete_assets';

  static const String viewUsersPermission = 'view_users';
  static const String addUsersPermission = 'add_users';
  static const String editUsersPermission = 'edit_users';
  static const String deleteUsersPermission = 'delete_users';

  static const String viewRequestsPermission = 'view_requests';
  static const String approveRequestsPermission = 'approve_requests';
  static const String rejectRequestsPermission = 'reject_requests';

  static const String viewReportsPermission = 'view_reports';  

  // ============================================================
  // HELPER METHODS
  // ============================================================

  static bool isSuperAdmin(String role) {
    return role.trim().toLowerCase() == superAdminRole;
  } 

  static bool isAdmin(String role) {
    return role.trim().toLowerCase() == adminRole; 
  }

  static bool isUser(String role) {
    return role.trim().toLowerCase() == userRole;
  }

  static bool isActive(String status) {
    return status.trim().toLowerCase() == activeStatus;
  }

  static bool isBlocked(String status) {
    return status.trim().toLowerCase() == blockedStatus;
  }
}
