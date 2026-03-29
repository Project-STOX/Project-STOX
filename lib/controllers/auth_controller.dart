import 'package:supabase_flutter/supabase_flutter.dart';
import '../services/supabase_service.dart';
import '../models/user.dart';

class AuthController {
  final supabase = SupabaseService.client;

  // Sign up using Supabase Auth
  Future<void> signUp(String email, String password, String username, int roleId) async {
    final authResponse = await supabase.auth.signUp(
      email: email,
      password: password,
    );

    if (authResponse.user != null) {
      // Insert user data into custom table
      await supabase.from('user').insert({
        'user_id': authResponse.user!.id, // Use auth user id
        'email': email,
        'username': username,
        'role_id': roleId,
        'is_active': true,
      });
    }
  }

  // Sign in using database (for existing users)
  Future<UserModel?> signIn(String email, String password) async {
    final response = await supabase
        .from('user')
        .select()
        .eq('email', email)
        .eq('password_hash', password)
        .maybeSingle();

    if (response != null) {
      final user = UserModel.fromJson(response);
      // Check if user is active
      if (!user.isActive) {
        return null; // User is deactivated, cannot login
      }
      return user;
    }
    return null;
  }

  // Check if user credentials are valid but account is deactivated
  Future<bool> isAccountDeactivated(String email, String password) async {
    final response = await supabase
        .from('user')
        .select()
        .eq('email', email)
        .eq('password_hash', password)
        .maybeSingle();

    if (response != null) {
      final user = UserModel.fromJson(response);
      return !user.isActive; // Return true if account exists but is deactivated
    }
    return false; // Account doesn't exist or credentials are wrong
  }

  // Enroll in MFA (TOTP)
  Future<Map<String, dynamic>?> enrollMFA() async {
    final enrollResponse = await supabase.auth.mfa.enroll(
      factorType: FactorType.totp,
    );
    final challengeResponse = await supabase.auth.mfa.challenge(factorId: enrollResponse.id);
    return {
      'factorId': enrollResponse.id,
      'challengeId': challengeResponse.id,
      'uri': enrollResponse.totp?.uri,
    };
  }

  // Verify MFA enrollment
  Future<void> verifyMFAEnrollment(String factorId, String challengeId, String code) async {
    await supabase.auth.mfa.verify(
      factorId: factorId,
      challengeId: challengeId,
      code: code,
    );
  }

  // Unenroll MFA
  Future<void> unenrollMFA(String factorId) async {
    await supabase.auth.mfa.unenroll(factorId);
  }

  // Get MFA factors
  Future<List<dynamic>> getMFAFactors() async {
    final response = await supabase.auth.mfa.listFactors();
    return response.all;
  }

  // Challenge MFA (for login) - returns challenge id
  Future<String?> challengeMFA(String factorId) async {
    final response = await supabase.auth.mfa.challenge(factorId: factorId);
    return response.id;
  }

  // Verify MFA challenge
  Future<void> verifyMFAChallenge(String factorId, String challengeId, String code) async {
    await supabase.auth.mfa.verify(
      factorId: factorId,
      challengeId: challengeId,
      code: code,
    );
  }

  Future<String?> getUserRole(int roleId) async {
    final response = await supabase.from('role').select().eq('role_id', roleId).maybeSingle();
    return response?['role_name'];
  }

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

  // Get roleId directly
  Future<int?> getUserRoleId(int userId) async {
    final response = await supabase
        .from('user')
        .select('role_id')
        .eq('user_id', userId)
        .maybeSingle();
    return response?['role_id'];
  }

  // Check if user has MFA enabled (from user table tfa_active column)
  Future<bool> hasMFAEnabled(int userId) async {
    try {
      final response = await supabase
          .from('user')
          .select('tfa_active')
          .eq('user_id', userId)
          .single();
      final enabled = response['tfa_active'] == true;
      print('User $userId has 2FA enabled: $enabled');
      return enabled;
    } catch (e) {
      print('Error checking 2FA for user $userId: $e');
      return false;
    }
  }

  // Generate and send 2FA code via email
  Future<void> generate2FA(int userId) async {
    try {
      // Get user email
      final userResponse = await supabase
          .from('user')
          .select('email')
          .eq('user_id', userId)
          .single();
      final email = userResponse['email'];

      // Send OTP code via email using Supabase
      await supabase.auth.signInWithOtp(email: email);
      print('2FA OTP sent to email: $email for user $userId');
    } catch (e) {
      print('Error sending 2FA OTP: $e');
      rethrow;
    }
  }

  // Verify 2FA code
  Future<bool> verify2FA(int userId, String enteredCode) async {
    try {
      // Get user email
      final userResponse = await supabase
          .from('user')
          .select('email')
          .eq('user_id', userId)
          .single();
      final email = userResponse['email'];

      // Verify OTP
      final response = await supabase.auth.verifyOTP(
        email: email,
        token: enteredCode,
        type: OtpType.email,
      );

      print('2FA verification result: ${response.user != null}');
      return response.user != null;
    } catch (e) {
      print('Error verifying 2FA: $e');
      return false;
    }
  }
}
