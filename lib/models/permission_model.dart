class PermissionModel {
  final String id;

  final String role;

  final List<String> permissions;

  PermissionModel({
    required this.id,

    required this.role,

    required this.permissions,
  });

  factory PermissionModel.fromMap(Map<String, dynamic> map, String documentId) {
    return PermissionModel(
      id: documentId,

      role: map['role'] ?? 'USER',

      permissions: List<String>.from(map['permissions'] ?? []),
    );
  }

  Map<String, dynamic> toMap() {
    return {'role': role, 'permissions': permissions};
  }

  bool hasPermission(String permission) {
    return permissions.contains(permission);
  }
}
