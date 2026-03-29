import '../services/supabase_service.dart';
import '../models/role.dart';

class RoleController {
  final supabase = SupabaseService.client;

  // Get all roles
  Future<List<Role>> getAllRoles() async {
    final response = await supabase
        .from('role')
        .select()
        .order('role_name');

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
  Future<void> createRole(String roleName, String? description) async {
    await supabase.from('role').insert({
      'role_name': roleName,
      'description': description,
    });
  }

  // Update role
  Future<void> updateRole(int roleId, String roleName, String? description) async {
    await supabase
        .from('role')
        .update({
          'role_name': roleName,
          'description': description,
        })
        .eq('role_id', roleId);
  }

  // Delete role
  Future<void> deleteRole(int roleId) async {
    await supabase
        .from('role')
        .delete()
        .eq('role_id', roleId);
  }

  // Check if role has permission
  Future<bool> hasPermission(int roleId, String permissionName) async {
    final perm = await supabase
        .from('permission')
        .select('perm_id')
        .eq('perm_name', permissionName)
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