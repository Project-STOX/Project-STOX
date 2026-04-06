import '../services/supabase_service.dart';
import '../models/role.dart';
import '../models/permission.dart';
import '../models/user.dart';
import '../services/audit_log_service.dart';

class RoleController {
  final supabase = SupabaseService.client;
  final AuditLogService auditLogService = AuditLogService();

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
    for (final entry in permissionDictionary) {
      final permId = entry['perm_id'] as int;
      final permName = entry['perm_name'] as String;

      final byId = await supabase
          .from('permission')
          .select('perm_id, perm_name')
          .eq('perm_id', permId)
          .maybeSingle();

      if (byId != null) {
        if ((byId['perm_name'] as String?) != permName) {
          await supabase
              .from('permission')
              .update({'perm_name': permName})
              .eq('perm_id', permId);
        }
        continue;
      }

      final byName = await supabase
          .from('permission')
          .select('perm_id')
          .ilike('perm_name', permName)
          .maybeSingle();

      if (byName == null) {
        await supabase.from('permission').insert({
          'perm_id': permId,
          'perm_name': permName,
        });
      }
    }
  }

  // Get all roles
  Future<List<Role>> getAllRoles() async {
    final response = await supabase.from('role').select().order('role_name');

    return response.map<Role>((json) => Role.fromJson(json)).toList();
  }

  // Get role by ID
  Future<Role?> getRoleById(int roleId) async {
    final response = await supabase
        .from('role')
        .select()
        .eq('role_id', roleId)
        .maybeSingle();

    if (response != null) {
      return Role.fromJson(response);
    }
    return null;
  }

  // Create new role
  Future<int> createRole(
    String roleName,
    String? description, {
    int? actorUserId,
  }) async {
    final response = await supabase
        .from('role')
        .insert({'role_name': roleName, 'description': description})
        .select('role_id')
        .single();

    await auditLogService.logAction(
      userId: actorUserId,
      action: 'Create role',
      entityType: 'Role',
      entityId: (response['role_id'] as num).toInt(),
      details: 'Created role $roleName',
    );

    return response['role_id'];
  }

  // Update role
  Future<void> updateRole(
    int roleId,
    String roleName,
    String? description,
    {int? actorUserId}
  ) async {
    await supabase
        .from('role')
        .update({'role_name': roleName, 'description': description})
        .eq('role_id', roleId);

    await auditLogService.logAction(
      userId: actorUserId,
      action: 'Update role',
      entityType: 'Role',
      entityId: roleId,
      details: 'Updated role to $roleName',
    );
  }

  // Delete role
  Future<void> deleteRole(int roleId, {int? actorUserId}) async {
    await supabase.from('role').delete().eq('role_id', roleId);

    await auditLogService.logAction(
      userId: actorUserId,
      action: 'Delete role',
      entityType: 'Role',
      entityId: roleId,
    );
  }

  // Check if role has users
  Future<bool> roleHasUsers(int roleId) async {
    final response = await supabase
        .from('user')
        .select('user_id')
        .eq('role_id', roleId)
        .limit(1);

    return response.isNotEmpty;
  }

  // Get all permissions
  Future<List<Permission>> getAllPermissions() async {
    final response = await supabase
        .from('permission')
        .select()
        .order('perm_name');

    return response
        .map<Permission>((json) => Permission.fromJson(json))
        .toList();
  }

  // Get permissions for a role
  Future<List<Permission>> getPermissionsForRole(int roleId) async {
    final response = await supabase
        .from('role_permission')
        .select('permission!inner(*)')
        .eq('role_id', roleId);

    return response
        .map<Permission>((json) => Permission.fromJson(json['permission']))
        .toList();
  }

  // Assign permission to role
  Future<void> assignPermissionToRole(
    int roleId,
    int permId, {
    int? actorUserId,
  }) async {
    await supabase.from('role_permission').insert({
      'role_id': roleId,
      'perm_id': permId,
    });

    await auditLogService.logAction(
      userId: actorUserId,
      action: 'Grant permission to role',
      entityType: 'RolePermission',
      details: 'Granted perm_id $permId to role_id $roleId',
    );
  }

  // Remove permission from role
  Future<void> removePermissionFromRole(
    int roleId,
    int permId, {
    int? actorUserId,
  }) async {
    await supabase
        .from('role_permission')
        .delete()
        .eq('role_id', roleId)
        .eq('perm_id', permId);

    await auditLogService.logAction(
      userId: actorUserId,
      action: 'Revoke permission from role',
      entityType: 'RolePermission',
      details: 'Revoked perm_id $permId from role_id $roleId',
    );
  }

  // Get users for a role
  Future<List<UserModel>> getUsersForRole(int roleId) async {
    final response = await supabase
        .from('user')
        .select()
        .eq('role_id', roleId)
        .order('username');

    return response.map<UserModel>((json) => UserModel.fromJson(json)).toList();
  }

  // Assign user to role
  Future<void> assignUserToRole(
    int userId,
    int roleId, {
    int? actorUserId,
  }) async {
    await supabase
        .from('user')
        .update({'role_id': roleId})
        .eq('user_id', userId);

    await auditLogService.logAction(
      userId: actorUserId,
      action: 'Assign user to role',
      entityType: 'UserRole',
      entityId: userId,
      details: 'Assigned user_id $userId to role_id $roleId',
    );
  }

  // Check if role has permission
  Future<bool> hasPermission(int roleId, String permissionName) async {
    final perm = await supabase
        .from('permission')
        .select('perm_id')
        .ilike('perm_name', permissionName)
        .maybeSingle();

    if (perm == null) return false;

    final mapping = await supabase
        .from('role_permission')
        .select()
        .eq('role_id', roleId)
        .eq('perm_id', perm['perm_id'])
        .maybeSingle();

    return mapping != null;
  }
}
