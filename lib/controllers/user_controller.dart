import '../models/role.dart';
import '../models/user.dart';
import '../services/api/admin_api_service.dart';
import '../services/api/auth_api_service.dart';

class UserController {
  UserController({AdminApiService? adminApiService, AuthApiService? authApiService})
      : _adminApi = adminApiService ?? AdminApiService(),
        _authApi = authApiService ?? AuthApiService();

  final AdminApiService _adminApi;
  final AuthApiService _authApi;

  Future<List<UserModel>> getAllUsers() async {
    return _adminApi.getUsers();
  }

  Future<UserModel?> getUserById(int userId) async {
    return _adminApi.getUserById(userId);
  }

  Future<void> createUser(
    String username,
    String email,
    String password,
    int roleId, {
    bool verifyEmail = false,
    int? actorUserId,
  }) async {
    await _adminApi.createUser(
      username: username,
      email: email,
      password: password,
      roleId: roleId,
      verifyEmail: verifyEmail,
    );
  }

  Future<UserModel> updateUser(
    int userId, {
    String? username,
    String? email,
    int? roleId,
    bool? isActive,
    bool? tfaActive,
    bool verifyEmailChange = false,
    int? actorUserId,
  }) async {
    return await _adminApi.updateUser(
      userId,
      username: username,
      email: email,
      roleId: roleId,
      isActive: isActive,
      tfaActive: tfaActive,
    );
  }

  Future<void> updatePassword(
    int userId,
    String oldPassword,
    String newPassword, {
    String? tfaCode,
    int? actorUserId,
  }) async {
    // 2FA code is optional now as requested by user.
    // Logic: if _useTfaForPasswordChange is false, tfaCode will be null/empty.
    await _authApi.changePassword(
      currentPassword: oldPassword,
      newPassword: newPassword,
      twoFactorCode: tfaCode,
    );
  }

  Future<void> deleteUser(int userId, {int? actorUserId}) async {
    await _adminApi.deleteUser(userId);
  }

  Future<void> toggleUserActive(int userId, bool isActive, {int? actorUserId}) async {
    await _adminApi.updateUser(userId, isActive: isActive);
  }

  Future<List<Role>> getAllRoles() async {
    return _adminApi.getRoles();
  }

  Future<Role?> getRoleById(int roleId) async {
    return _adminApi.getRoleById(roleId);
  }

  Future<void> createRole(
    String roleName,
    String? description, {
    int? actorUserId,
  }) async {
    await _adminApi.createRole(roleName, description);
  }

  Future<void> updateRole(
    int roleId,
    String roleName,
    String? description, {
    int? actorUserId,
  }) async {
    await _adminApi.updateRole(roleId, roleName, description);
  }

  Future<void> deleteRole(int roleId, {int? actorUserId}) async {
    await _adminApi.deleteRole(roleId);
  }
}