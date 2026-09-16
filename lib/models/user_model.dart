import 'package:cloud_firestore/cloud_firestore.dart';

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

  /// Primary role.
  ///
  /// The application has exactly three main roles:
  /// super_admin, admin, user.
  final String role;

  /// Additional role values are retained for backward compatibility with
  /// existing Firestore documents.
  ///
  /// Access-control decisions for the new workflow should use the three
  /// supported main roles.
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
  /// else (blocked, disabled, inactive, deleted, missing) has no access, so
  /// the app never shows a UI whose data the rules would then deny.
  bool get isActive {
    final value = status.trim().toLowerCase();

    return value == 'active' || value == 'approved';
  }

  bool get isCreatedBySuperAdmin => createdBy.trim().isNotEmpty;

  // ===========================================================================
  // ROLE HELPERS
  // ===========================================================================

  /// Returns the effective main roles while preserving backward compatibility.
  ///
  /// Only the three supported application roles are considered valid main
  /// roles here. Unknown legacy/custom roles are not promoted to a main role.
  List<String> get effectiveRoles {
    final result = <String>[];

    void addRole(String value) {
      final normalized = _normalizeRole(value);

      if (!_isMainRole(normalized)) {
        return;
      }

      if (!result.contains(normalized)) {
        result.add(normalized);
      }
    }

    addRole(role);

    for (final value in roles) {
      addRole(value);
    }

    return List.unmodifiable(result);
  }

  /// Returns the primary supported role.
  ///
  /// If an old document contains a supported role in `roles` but not in the
  /// legacy `role` field, the first supported role is returned.
  String get effectiveRole {
    final normalizedPrimary = _normalizeRole(role);

    if (_isMainRole(normalizedPrimary)) {
      return normalizedPrimary;
    }

    final supportedRoles = effectiveRoles;

    if (supportedRoles.isNotEmpty) {
      return supportedRoles.first;
    }

    return '';
  }

  bool hasRole(String requestedRole) {
    final target = _normalizeRole(requestedRole);

    if (!_isMainRole(target)) {
      return false;
    }

    return effectiveRoles.contains(target);
  }

  bool get isSuperAdmin => hasRole('super_admin');

  bool get isAdmin => hasRole('admin');

  bool get isUser => hasRole('user');

  // ===========================================================================
  // ROLE ACCESS
  // ===========================================================================

  /// Super Admin has access to the complete system.
  bool get hasFullAccess => isSuperAdmin;

  /// Admin can manage inventory assigned to that Admin.
  bool get canManageOwnInventory => isSuperAdmin || isAdmin;

  /// User can view inventory but cannot directly modify it.
  bool get canViewInventory => isSuperAdmin || isAdmin || isUser;

  /// Only Super Admin/Admin can import inventory.
  bool get canImportInventory => isSuperAdmin || isAdmin;

  /// Only Super Admin/Admin can directly edit inventory.
  bool get canDirectlyEditInventory => isSuperAdmin || isAdmin;

  /// Users must submit edit requests instead of directly editing assets.
  bool get mustRequestInventoryEdit => isUser;

  /// Only Super Admin/Admin can approve or reject user edit requests.
  bool get canManageEditRequests => isSuperAdmin || isAdmin;

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
  // ROLE VALIDATION
  // ===========================================================================

  static bool _isMainRole(String value) {
    return value == 'super_admin' || value == 'admin' || value == 'user';
  }

  static String _normalizeRole(String value) {
    return value.trim().toLowerCase().replaceAll('-', '_').replaceAll(' ', '_');
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

      final normalized = _normalizeRole(item.toString());

      if (_isMainRole(normalized) && !result.contains(normalized)) {
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
