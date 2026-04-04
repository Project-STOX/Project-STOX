class UserModel {
  final int userId;
  final String username;
  final String email;
  final String passwordHash;
  final int roleId;
  final bool isActive;
  final bool tfaActive;

  UserModel({
    required this.userId,
    required this.username,
    required this.email,
    required this.passwordHash,
    required this.roleId,
    required this.isActive,
    required this.tfaActive,
  });

  factory UserModel.fromJson(Map<String, dynamic> json) {
    final rawUserId = json['user_id'];
    final parsedUserId = rawUserId is int
        ? rawUserId
        : int.tryParse(rawUserId?.toString() ?? '');

    if (parsedUserId == null) {
      throw const FormatException('Invalid user_id value in user payload');
    }

    return UserModel(
      userId: parsedUserId,
      username: json['username'],
      email: json['email'],
      passwordHash: json['password_hash'],
      roleId: json['role_id'],
      isActive: json['is_active'],
      tfaActive: json['tfa_active'] ?? false,
    );
  }
}
