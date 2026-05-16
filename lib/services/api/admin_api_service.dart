import '../../models/permission.dart';
import '../../models/role.dart';
import '../../models/user.dart';
import 'api_client.dart';
import 'api_config.dart';

class AdminApiService {
  AdminApiService({ApiClient? apiClient})
    : _api = apiClient ?? ApiClient(baseUrl: ApiConfig.baseUrl);

  final ApiClient _api;

  Future<List<UserModel>> getUsers() async {
    final data = await _api.get('/admin/users', authorized: true);
    if (data is List) {
      return data
          .whereType<Map<String, dynamic>>()
          .map(UserModel.fromJson)
          .toList();
    }
    return [];
  }

  Future<UserModel?> getUserById(int userId) async {
    final users = await getUsers();
    for (final user in users) {
      if (user.userId == userId) {
        return user;
      }
    }
    return null;
  }

  Future<UserModel> createUser({
    required String username,
    required String email,
    required String password,
    required int roleId,
    bool verifyEmail = false,
  }) async {
    final data = await _api.post(
      '/admin/users',
      body: {
        'username': username,
        'email': email,
        'password': password,
        'role_id': roleId,
        'verify_email': verifyEmail,
      },
      authorized: true,
    );
    if (data is Map<String, dynamic>) {
      return UserModel.fromJson(data);
    }
    throw Exception('Invalid create user response');
  }

  Future<UserModel> updateUser(
    int userId, {
    String? username,
    String? email,
    int? roleId,
    bool? isActive,
    bool? tfaActive,
    bool? totpEnabled,
  }) async {
    final payload = <String, dynamic>{
      'username': ?username,
      'email': ?email,
      'role_id': ?roleId,
      'is_active': ?isActive,
      'tfa_active': ?tfaActive,
      'totp_enabled': ?totpEnabled,
    };
    final data = await _api.put(
      '/admin/users/$userId',
      body: payload,
      authorized: true,
    );
    if (data is Map<String, dynamic>) {
      return UserModel.fromJson(data);
    }
    throw Exception('Invalid update user response');
  }

  Future<void> deleteUser(int userId) async {
    await _api.delete('/admin/users/$userId', authorized: true);
  }

  Future<List<Role>> getRoles() async {
    final data = await _api.get('/admin/roles', authorized: true);
    if (data is List) {
      return data.whereType<Map<String, dynamic>>().map(Role.fromJson).toList();
    }
    return [];
  }

  Future<Role?> getRoleById(int roleId) async {
    final roles = await getRoles();
    for (final role in roles) {
      if (role.roleId == roleId) {
        return role;
      }
    }
    return null;
  }

  Future<Role> createRole(String roleName, String? description) async {
    final data = await _api.post(
      '/admin/roles',
      body: {'role_name': roleName, 'description': description},
      authorized: true,
    );
    if (data is Map<String, dynamic>) {
      return Role.fromJson(data);
    }
    throw Exception('Invalid create role response');
  }

  Future<Role> updateRole(
    int roleId,
    String roleName,
    String? description,
  ) async {
    final data = await _api.put(
      '/admin/roles/$roleId',
      body: {'role_name': roleName, 'description': description},
      authorized: true,
    );
    if (data is Map<String, dynamic>) {
      return Role.fromJson(data);
    }
    throw Exception('Invalid update role response');
  }

  Future<void> deleteRole(int roleId) async {
    await _api.delete('/admin/roles/$roleId', authorized: true);
  }

  Future<bool> roleHasUsers(int roleId) async {
    final users = await _api.get(
      '/admin/roles/$roleId/users',
      authorized: true,
    );
    return users is List && users.isNotEmpty;
  }

  Future<List<Permission>> getPermissions() async {
    final data = await _api.get('/admin/permissions', authorized: true);
    if (data is List) {
      return data
          .whereType<Map<String, dynamic>>()
          .map(Permission.fromJson)
          .toList();
    }
    return [];
  }

  Future<List<Permission>> getPermissionsForRole(int roleId) async {
    final data = await _api.get(
      '/admin/roles/$roleId/permissions',
      authorized: true,
    );
    if (data is List) {
      return data
          .whereType<Map<String, dynamic>>()
          .map(Permission.fromJson)
          .toList();
    }
    return [];
  }

  Future<void> assignPermissionToRole(int roleId, int permId) async {
    await _api.post(
      '/admin/roles/$roleId/permissions',
      body: {'perm_id': permId},
      authorized: true,
    );
  }

  Future<void> removePermissionFromRole(int roleId, int permId) async {
    await _api.delete(
      '/admin/roles/$roleId/permissions/$permId',
      authorized: true,
    );
  }

  Future<List<UserModel>> getUsersForRole(int roleId) async {
    final data = await _api.get('/admin/roles/$roleId/users', authorized: true);
    if (data is List) {
      return data
          .whereType<Map<String, dynamic>>()
          .map(UserModel.fromJson)
          .toList();
    }
    return [];
  }

  Future<void> assignUserToRole(int userId, int roleId) async {
    await _api.post(
      '/admin/users/$userId/role',
      body: {'role_id': roleId},
      authorized: true,
    );
  }
}
