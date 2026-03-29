import '../services/supabase_service.dart';
import '../models/user.dart';
import '../models/role.dart';

class UserController {
  final supabase = SupabaseService.client;

  // Get all users
  Future<List<UserModel>> getAllUsers() async {
    final response = await supabase
        .from('user')
        .select()
        .order('username');

    return response.map<UserModel>((json) => UserModel.fromJson(json)).toList();
  }

  // Get user by ID
  Future<UserModel?> getUserById(int userId) async {
    final response = await supabase
        .from('user')
        .select()
        .eq('user_id', userId)
        .maybeSingle();

    if (response != null) {
      return UserModel.fromJson(response);
    }
    return null;
  }

  // Create new user
  Future<void> createUser(String username, String email, String password, int roleId) async {
    // First create auth user
    final authResponse = await supabase.auth.signUp(
      email: email,
      password: password,
    );

    if (authResponse.user != null) {
      // Insert user data into custom table
      await supabase.from('user').insert({
        'user_id': authResponse.user!.id,
        'username': username,
        'email': email,
        'password_hash': password, // Note: In production, hash the password
        'role_id': roleId,
        'is_active': true,
        'tfa_active': false,
      });
    }
  }

  // Update user
  Future<void> updateUser(int userId, {
    String? username,
    String? email,
    int? roleId,
    bool? isActive,
    bool? tfaActive,
  }) async {
    final updates = <String, dynamic>{};
    if (username != null) updates['username'] = username;
    if (email != null) updates['email'] = email;
    if (roleId != null) updates['role_id'] = roleId;
    if (isActive != null) updates['is_active'] = isActive;
    if (tfaActive != null) updates['tfa_active'] = tfaActive;

    await supabase
        .from('user')
        .update(updates)
        .eq('user_id', userId);
  }

  // Delete user
  Future<void> deleteUser(int userId) async {
    await supabase
        .from('user')
        .delete()
        .eq('user_id', userId);
  }

  // Toggle user active status
  Future<void> toggleUserActive(int userId, bool isActive) async {
    await supabase
        .from('user')
        .update({'is_active': isActive})
        .eq('user_id', userId);
  }

  // Get all roles
  Future<List<Role>> getAllRoles() async {
    final response = await supabase
        .from('role')
        .select()
        .order('role_name');

    return response.map<Role>((json) => Role.fromJson(json)).toList();
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
}