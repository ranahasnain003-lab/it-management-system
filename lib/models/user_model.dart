import 'package:cloud_firestore/cloud_firestore.dart';

class UserModel {
  const UserModel({
    required this.uid,
    required this.name,
    required this.email,
    required this.role,
    required this.status,
    this.employeeId = '',
    this.department = '',
    this.designation = '',
    this.createdAt,
    this.createdBy = '',
    this.createdByEmail = '',
  });

  final String uid;
  final String name;
  final String email;
  final String role;
  final String status;
  final String employeeId;
  final String department;
  final String designation;
  final DateTime? createdAt;

  /// UID of the Super Admin who created this user.
  final String createdBy;

  /// Email of the Super Admin who created this user.
  final String createdByEmail;

  String get fullName => name;

  bool get isCreatedBySuperAdmin => createdBy.trim().isNotEmpty;

  factory UserModel.fromFirestore(String uid, Map<String, dynamic> data) {
    return UserModel(
      uid: uid,
      name: _readString(data['name']),
      email: _readString(data['email']),
      role: _readString(data['role']),
      status: _readString(data['status'], fallback: 'active'),
      employeeId: _readString(data['employeeId']),
      department: _readString(data['department']),
      designation: _readString(data['designation']),
      createdAt: _readDateTime(data['createdAt']),
      createdBy: _readString(data['createdBy']),
      createdByEmail: _readString(data['createdByEmail']),
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
        status: 'active',
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
      status: _readString(data['status'], fallback: 'active'),
      employeeId: _readString(data['employeeId']),
      department: _readString(data['department']),
      designation: _readString(data['designation']),
      createdAt: _readDateTime(data['createdAt']),
      createdBy: _readString(data['createdBy']),
      createdByEmail: _readString(data['createdByEmail']),
    );
  }

  Map<String, dynamic> toFirestore() {
    return {
      'uid': uid,
      'name': name,
      'email': email,
      'role': role,
      'status': status,
      'employeeId': employeeId,
      'department': department,
      'designation': designation,
      'createdBy': createdBy,
      'createdByEmail': createdByEmail,
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
      'role': role,
      'status': status,
      'employeeId': employeeId,
      'department': department,
      'designation': designation,
      'createdBy': createdBy,
      'createdByEmail': createdByEmail,
      'createdAt': createdAt?.toIso8601String(),
    };
  }

  UserModel copyWith({
    String? uid,
    String? name,
    String? email,
    String? role,
    String? status,
    String? employeeId,
    String? department,
    String? designation,
    DateTime? createdAt,
    String? createdBy,
    String? createdByEmail,
  }) {
    return UserModel(
      uid: uid ?? this.uid,
      name: name ?? this.name,
      email: email ?? this.email,
      role: role ?? this.role,
      status: status ?? this.status,
      employeeId: employeeId ?? this.employeeId,
      department: department ?? this.department,
      designation: designation ?? this.designation,
      createdAt: createdAt ?? this.createdAt,
      createdBy: createdBy ?? this.createdBy,
      createdByEmail: createdByEmail ?? this.createdByEmail,
    );
  }

  static String _readString(dynamic value, {String fallback = ''}) {
    if (value == null) {
      return fallback;
    }

    return value.toString().trim();
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

  @override
  String toString() {
    return 'UserModel('
        'uid: $uid, '
        'name: $name, '
        'email: $email, '
        'role: $role, '
        'status: $status, '
        'employeeId: $employeeId, '
        'department: $department, '
        'designation: $designation, '
        'createdAt: $createdAt, '
        'createdBy: $createdBy, '
        'createdByEmail: $createdByEmail'
        ')';
  }
}
