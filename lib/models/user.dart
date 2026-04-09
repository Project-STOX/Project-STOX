class UserModel {
  final int id;
  final String fullName;
  final String email;
  final String role;
  final int roleIdValue;
  final bool isActive;
  final bool tfaActiveValue;

  UserModel({
    required this.id,
    required this.fullName,
    required this.email,
    required this.role,
    required this.roleIdValue,
    required this.isActive,
    required this.tfaActiveValue,
  });

  int get userId => id;
  String get username => fullName.isNotEmpty ? fullName : email;
  int get roleId => roleIdValue;
  bool get tfaActive => tfaActiveValue;

  static int _roleIdFromRoleName(String roleName) {
    final normalized = roleName.trim().toLowerCase();
    if (normalized == 'sme owner' || normalized == 'owner') {
      return 1;
    }
    if (normalized == 'inventory manager' || normalized == 'manager') {
      return 2;
    }
    if (normalized == 'staff') {
      return 3;
    }
    return 0;
  }

  static bool _asBool(dynamic value, {bool fallback = false}) {
    if (value is bool) {
      return value;
    }
    final normalized = value?.toString().trim().toLowerCase();
    if (normalized == 'true' || normalized == '1') {
      return true;
    }
    if (normalized == 'false' || normalized == '0') {
      return false;
    }
    return fallback;
  }

  factory UserModel.fromJson(Map<String, dynamic> json) {
    final rawUserId = json['id'] ?? json['user_id'];
    final parsedUserId = rawUserId is int ? rawUserId : int.tryParse(rawUserId?.toString() ?? '');

    if (parsedUserId == null) {
      throw const FormatException('Invalid user id value in user payload');
    }

    final roleName = (json['role'] ?? json['role_name'] ?? '').toString();
    final rawRoleId = json['role_id'];
    final parsedRoleId = rawRoleId is int
        ? rawRoleId
        : int.tryParse(rawRoleId?.toString() ?? '') ?? _roleIdFromRoleName(roleName);

    return UserModel(
      id: parsedUserId,
      fullName: (json['full_name'] ?? json['username'] ?? '').toString(),
      email: (json['email'] ?? '').toString(),
      role: roleName,
      roleIdValue: parsedRoleId,
      isActive: _asBool(json['is_active'], fallback: true),
      tfaActiveValue: _asBool(json['tfa_active'], fallback: false),
    );
  }
}
