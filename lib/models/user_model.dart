import 'package:cloud_firestore/cloud_firestore.dart';

import '../core/services/permission_service.dart';

class UserModel {
  const UserModel({
    required this.uid,
    required this.name,
    required this.email,
    required this.role,
    required this.status,
    this.roles = const [],
    this.employeeId = '',
    this.department = '',
    this.designation = '',
    this.createdAt,
    this.createdBy = '',
    this.createdByEmail = '',
    this.organizationId = '',
  });

  final String uid;
  final String name;
  final String email;

  /// Primary role, and the ONLY field any access decision is made from.
  ///
  /// The application has exactly three main roles:
  /// super_admin, admin, user.
  final String role;

  /// Mirror of [role], kept because existing Firestore documents have it and
  /// the rules require it to match `role` (`validRoles()`).
  ///
  /// It never grants anything: a document holding roles: ['super_admin'] next
  /// to role: 'user' is a User here, exactly as it is in the rules.
  final List<String> roles;

  final String status;
  final String employeeId;
  final String department;
  final String designation;
  final DateTime? createdAt;

  /// UID of the Admin/Super Admin who created or manages this user.
  final String createdBy;

  /// Email of the Admin/Super Admin who created or manages this user.
  final String createdByEmail;

  /// Organization this user belongs to.
  final String organizationId;

  String get fullName => name;

  /// Exactly the statuses the Firestore Security Rules accept. Anything
  /// else (pending, blocked, disabled, inactive, deleted, missing) has no
  /// access, so the app never shows a UI whose data the rules would then deny.
  bool get isActive => PermissionService.isActiveStatus(status);

  /// A self-registered account nobody has admitted yet. It can do nothing
  /// until a Super Admin (or the Admin who manages it) sets status 'active'.
  bool get isPending => PermissionService.isPendingStatus(status);

  bool get isCreatedBySuperAdmin => createdBy.trim().isNotEmpty;

  // ===========================================================================
  // ROLE HELPERS
  // ===========================================================================

  /// The single canonical role of this account, or '' when the stored value is
  /// not one of the three (an unknown role has no access anywhere).
  ///
  /// The `roles` mirror is deliberately not consulted: the rules read `role`
  /// alone, so falling back to the array would grant access Firestore denies.
  String get effectiveRole {
    final normalized = PermissionService.normalizeRole(role);

    return PermissionService.isMainRole(normalized) ? normalized : '';
  }

  /// The mirror as it is written back to Firestore: the primary role and
  /// nothing else, which is what `validRoles()` requires.
  List<String> get effectiveRoles {
    final primary = effectiveRole;

    return List.unmodifiable(primary.isEmpty ? const <String>[] : [primary]);
  }

  bool hasRole(String requestedRole) {
    final target = PermissionService.normalizeRole(requestedRole);

    return target.isNotEmpty && target == effectiveRole;
  }

  bool get isSuperAdmin => hasRole('super_admin');

  bool get isAdmin => hasRole('admin');

  bool get isUser => hasRole('user');

  // ===========================================================================
  // ROLE ACCESS
  // ===========================================================================
  //
  // Every capability below is false while the account is not active, so a
  // 'pending' self-registration - like a blocked or deleted profile - can do
  // nothing at all. That is the same answer the Firestore rules give.
  //
  // The matrix itself lives in PermissionService, never duplicated here.
  // ===========================================================================

  bool _can(String permission) {
    return isActive &&
        PermissionService.hasPermission(
          roles: effectiveRoles,
          permission: permission,
        );
  }

  /// Super Admin has access to the complete system.
  bool get hasFullAccess => isActive && isSuperAdmin;

  /// Admin manages inventory directly; a Super Admin manages all of it.
  bool get canManageOwnInventory => isActive && (isSuperAdmin || isAdmin);

  /// Inventory is organisation-wide: every canonical role reads all of it.
  bool get canViewInventory => _can(PermissionService.viewAssets);

  /// Only Super Admin/Admin can import inventory.
  bool get canImportInventory => _can(PermissionService.importAssets);

  /// Only Super Admin/Admin can directly edit inventory.
  bool get canDirectlyEditInventory => _can(PermissionService.editAsset);

  /// Users must submit edit requests instead of directly editing assets.
  bool get mustRequestInventoryEdit => isActive && isUser;

  /// Only Super Admin/Admin can approve or reject user edit requests.
  bool get canManageEditRequests => _can(PermissionService.approveRequests);

  // ===========================================================================
  // FIRESTORE
  // ===========================================================================

  factory UserModel.fromFirestore(String uid, Map<String, dynamic> data) {
    return UserModel(
      uid: uid,
      name: _readString(data['name']),
      email: _readString(data['email']),
      role: _readString(data['role']),
      roles: _readRoles(data['roles']),
      status: _readString(data['status']),
      employeeId: _readString(data['employeeId']),
      department: _readString(data['department']),
      designation: _readString(data['designation']),
      createdAt: _readDateTime(data['createdAt']),
      createdBy: _readString(data['createdBy']),
      createdByEmail: _readString(data['createdByEmail']),
      organizationId: _readString(data['organizationId']),
    );
  }

  factory UserModel.fromDocument(
    DocumentSnapshot<Map<String, dynamic>> document,
  ) {
    final data = document.data();

    if (data == null) {
      return UserModel(
        uid: document.id,
        name: '',
        email: '',
        role: '',
        roles: const [],
        status: '',
      );
    }

    return UserModel.fromFirestore(document.id, data);
  }

  factory UserModel.fromMap(Map<String, dynamic> data, {String? uid}) {
    return UserModel(
      uid: uid ?? _readString(data['uid']),
      name: _readString(data['name']),
      email: _readString(data['email']),
      role: _readString(data['role']),
      roles: _readRoles(data['roles']),
      status: _readString(data['status']),
      employeeId: _readString(data['employeeId']),
      department: _readString(data['department']),
      designation: _readString(data['designation']),
      createdAt: _readDateTime(data['createdAt']),
      createdBy: _readString(data['createdBy']),
      createdByEmail: _readString(data['createdByEmail']),
      organizationId: _readString(data['organizationId']),
    );
  }

  Map<String, dynamic> toFirestore() {
    return {
      'uid': uid,
      'name': name,
      'email': email,
      'role': effectiveRole,

      // Preserve the existing roles field for compatibility.
      'roles': effectiveRoles,

      'status': status,
      'employeeId': employeeId,
      'department': department,
      'designation': designation,
      'createdBy': createdBy,
      'createdByEmail': createdByEmail,
      'organizationId': organizationId,
      'createdAt': createdAt != null
          ? Timestamp.fromDate(createdAt!)
          : FieldValue.serverTimestamp(),
    };
  }

  Map<String, dynamic> toMap() {
    return {
      'uid': uid,
      'name': name,
      'email': email,
      'role': effectiveRole,
      'roles': effectiveRoles,
      'status': status,
      'employeeId': employeeId,
      'department': department,
      'designation': designation,
      'createdBy': createdBy,
      'createdByEmail': createdByEmail,
      'organizationId': organizationId,
      'createdAt': createdAt?.toIso8601String(),
    };
  }

  // ===========================================================================
  // COPY WITH
  // ===========================================================================

  UserModel copyWith({
    String? uid,
    String? name,
    String? email,
    String? role,
    List<String>? roles,
    String? status,
    String? employeeId,
    String? department,
    String? designation,
    DateTime? createdAt,
    String? createdBy,
    String? createdByEmail,
    String? organizationId,
  }) {
    return UserModel(
      uid: uid ?? this.uid,
      name: name ?? this.name,
      email: email ?? this.email,
      role: role ?? this.role,
      roles: roles ?? this.roles,
      status: status ?? this.status,
      employeeId: employeeId ?? this.employeeId,
      department: department ?? this.department,
      designation: designation ?? this.designation,
      createdAt: createdAt ?? this.createdAt,
      createdBy: createdBy ?? this.createdBy,
      createdByEmail: createdByEmail ?? this.createdByEmail,
      organizationId: organizationId ?? this.organizationId,
    );
  }

  // ===========================================================================
  // VALUE HELPERS
  // ===========================================================================

  static String _readString(dynamic value, {String fallback = ''}) {
    if (value == null) {
      return fallback;
    }

    return value.toString().trim();
  }

  static List<String> _readRoles(dynamic value) {
    final result = <String>[];

    void addRole(dynamic item) {
      if (item == null) {
        return;
      }

      final normalized = PermissionService.normalizeRole(item.toString());

      if (PermissionService.isMainRole(normalized) &&
          !result.contains(normalized)) {
        result.add(normalized);
      }
    }

    if (value is List) {
      for (final item in value) {
        addRole(item);
      }

      return result;
    }

    // Backward compatibility:
    // old Firestore documents may store a single role as a String.
    if (value is String && value.trim().isNotEmpty) {
      addRole(value);
    }

    return result;
  }

  static DateTime? _readDateTime(dynamic value) {
    if (value == null) {
      return null;
    }

    if (value is Timestamp) {
      return value.toDate();
    }

    if (value is DateTime) {
      return value;
    }

    if (value is String) {
      return DateTime.tryParse(value);
    }

    return null;
  }

  // ===========================================================================
  // DEBUG
  // ===========================================================================

  @override
  String toString() {
    return 'UserModel('
        'uid: $uid, '
        'name: $name, '
        'email: $email, '
        'role: $role, '
        'roles: $roles, '
        'status: $status, '
        'employeeId: $employeeId, '
        'department: $department, '
        'designation: $designation, '
        'createdAt: $createdAt, '
        'createdBy: $createdBy, '
        'createdByEmail: $createdByEmail, '
        'organizationId: $organizationId'
        ')';
  }
}
