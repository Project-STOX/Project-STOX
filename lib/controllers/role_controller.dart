import '../services/api/admin_api_service.dart';
import '../models/role.dart';
import '../models/permission.dart';
import '../models/user.dart';

class RoleController {
  RoleController({AdminApiService? adminApiService}) : _adminApi = adminApiService ?? AdminApiService();

  final AdminApiService _adminApi;

  static const List<Map<String, dynamic>> permissionDictionary = [
    {'perm_id': 1, 'perm_name': 'Manage users'},
    {'perm_id': 2, 'perm_name': 'Manage products'},
    {'perm_id': 3, 'perm_name': 'Manage suppliers'},
    {'perm_id': 4, 'perm_name': 'View forecasts'},
    {'perm_id': 5, 'perm_name': 'Manage stock'},
    {'perm_id': 6, 'perm_name': 'Manage roles'},
    {'perm_id': 8, 'perm_name': 'Send message'},
    {'perm_id': 9, 'perm_name': 'Historical data'},
    {'perm_id': 10, 'perm_name': 'View audit log'},
    {'perm_id': 11, 'perm_name': 'Import data'},
  ];

  Future<void> ensurePermissionDictionary() async {
    return;
  }

  // Get all roles
  Future<List<Role>> getAllRoles() async {
    return _adminApi.getRoles();
  }

  // Get role by ID
  Future<Role?> getRoleById(int roleId) async {
    return _adminApi.getRoleById(roleId);
  }

  // Create new role
  Future<int> createRole(
    String roleName,
    String? description, {
    int? actorUserId,
  }) async {
    final createdRole = await _adminApi.createRole(roleName, description);
    return createdRole.roleId;
  }

  // Update role
  Future<void> updateRole(
    int roleId,
    String roleName,
    String? description,
    {int? actorUserId}
  ) async {
    await _adminApi.updateRole(roleId, roleName, description);
  }

  // Delete role
  Future<void> deleteRole(int roleId, {int? actorUserId}) async {
    await _adminApi.deleteRole(roleId);
  }

  // Check if role has users
  Future<bool> roleHasUsers(int roleId) async {
    return _adminApi.roleHasUsers(roleId);
  }

  // Get all permissions
  Future<List<Permission>> getAllPermissions() async {
    return _adminApi.getPermissions();
  }

  // Get permissions for a role
  Future<List<Permission>> getPermissionsForRole(int roleId) async {
    return _adminApi.getPermissionsForRole(roleId);
  }

  // Assign permission to role
  Future<void> assignPermissionToRole(
    int roleId,
    int permId, {
    int? actorUserId,
  }) async {
    await _adminApi.assignPermissionToRole(roleId, permId);
  }

  // Remove permission from role
  Future<void> removePermissionFromRole(
    int roleId,
    int permId, {
    int? actorUserId,
  }) async {
    await _adminApi.removePermissionFromRole(roleId, permId);
  }

  // Get users for a role
  Future<List<UserModel>> getUsersForRole(int roleId) async {
    return _adminApi.getUsersForRole(roleId);
  }

  // Assign user to role
  Future<void> assignUserToRole(
    int userId,
    int roleId, {
    int? actorUserId,
  }) async {
    await _adminApi.assignUserToRole(userId, roleId);
  }

  // Check if role has permission
  Future<bool> hasPermission(int roleId, String permissionName) async {
    final permissions = await _adminApi.getPermissionsForRole(roleId);
    return permissions.any(
      (permission) => permission.permName.toLowerCase() == permissionName.toLowerCase(),
    );
  }
}
