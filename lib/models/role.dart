class Role {
  final int roleId;
  final String roleName;
  final String? description;

  Role({
    required this.roleId,
    required this.roleName,
    this.description,
  });

  factory Role.fromJson(Map<String, dynamic> json) {
    int parseInt(dynamic value) {
      if (value is num) {
        return value.toInt();
      }
      return int.tryParse(value?.toString() ?? '') ?? 0;
    }

    return Role(
      roleId: parseInt(json['role_id'] ?? json['id']),
      roleName: (json['role_name'] ?? json['name'] ?? '').toString(),
      description: json['description']?.toString(),
    );
  }
}
