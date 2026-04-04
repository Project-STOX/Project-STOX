import '../services/supabase_service.dart';
import '../models/user.dart';
import '../models/role.dart';
import '../utils/password_hasher.dart';
import 'auth_controller.dart';

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
  Future<void> createUser(String username, String email, String password, int roleId, {bool verifyEmail = true}) async {
    final normalizedEmail = email.trim().toLowerCase();
    final normalizedUsername = username.trim();

    if (verifyEmail) {
      // Create auth user (sends confirmation email by default in Supabase)
      await supabase.auth.signUp(
        email: normalizedEmail,
        password: password,
      );
    }

    final passwordHash = await PasswordHasher.hashPassword(password);

    // Always create the app profile row. When verifyEmail is false,
    // account creation is local-only and skips auth email verification.
    final data = {
      'username': normalizedUsername,
      'email': normalizedEmail,
      'role_id': roleId,
      'is_active': true,
      'tfa_active': false,
      'password_hash': passwordHash,
    };

    await supabase.from('user').insert(data);
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

  // Update password with verification
  Future<void> updatePassword(int userId, String oldPassword, String newPassword, {String? tfaCode}) async {
    // First, verify old password or 2FA
    final userResponse = await supabase
        .from('user')
        .select('password_hash, tfa_active')
        .eq('user_id', userId)
        .single();

    final currentPasswordHash = userResponse['password_hash'];
    final tfaActive = userResponse['tfa_active'];

    bool verified = false;

    if (tfaActive && tfaCode != null) {
      // Verify 2FA code
      final authController = AuthController();
      verified = await authController.verify2FA(userId, tfaCode);
    } else if (await PasswordHasher.verifyPassword(oldPassword, currentPasswordHash.toString())) {
      verified = true;
    }

    if (!verified) {
      throw Exception('Invalid old password or 2FA code');
    }

    final newPasswordHash = await PasswordHasher.hashPassword(newPassword);

    // Update password
    await supabase
        .from('user')
      .update({'password_hash': newPasswordHash})
        .eq('user_id', userId);
  }

  // Delete user
  Future<void> deleteUser(int userId) async {
    // Remove dependent notification records first to satisfy FK constraints.
    await supabase
      .from('notification')
      .delete()
      .eq('recipient_id', userId);

    await supabase
      .from('notification')
      .delete()
      .eq('sender_id', userId);

    // Remove dependent session records first to satisfy FK constraints.
    await supabase
      .from('user_session')
      .delete()
      .eq('user_id', userId);

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