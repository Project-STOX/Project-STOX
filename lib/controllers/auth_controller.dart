import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:uuid/uuid.dart';
import '../services/supabase_service.dart';
import '../services/audit_log_service.dart';
import '../models/user.dart';
import '../utils/password_hasher.dart';

class AuthController {
  final supabase = SupabaseService.client;
  final AuditLogService auditLogService = AuditLogService();
  static const _rememberedSessionUuidKey = 'remembered_session_uuid';
  final Uuid _uuid = const Uuid();
  String? _latestSessionUuid;

  String? get latestSessionUuid => _latestSessionUuid;

  Future<Map<String, dynamic>?> _findUserByEmail(String email) async {
    final rows = await supabase
        .from('user')
        .select()
        .ilike('email', email)
        .order('user_id', ascending: false)
        .limit(1);

    if (rows.isNotEmpty) {
      return Map<String, dynamic>.from(rows.first as Map);
    }

    return null;
  }

  Future<void> _storeUserSessionToken(int userId, String token) async {
    try {
      await supabase.from('user_session').insert({
        'user_id': userId,
        'token': token,
      });
      return;
    } catch (_) {
      // Fallback path for schemas that enforce one active session row per user.
    }

    try {
      await supabase
          .from('user_session')
          .update({'token': token})
          .eq('user_id', userId);
    } catch (_) {
      // Do not block login if session persistence schema differs.
    }
  }

  Future<void> persistSessionUuidLocally(String sessionUuid) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_rememberedSessionUuidKey, sessionUuid);
  }

  Future<String?> getRememberedSessionUuid() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString(_rememberedSessionUuidKey);
  }

  Future<void> clearRememberedSessionUuid() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_rememberedSessionUuidKey);
  }

  DateTime? _extractSessionTimestamp(Map<String, dynamic> row) {
    const candidates = [
      'created_at',
      'updated_at',
      'last_login',
      'last_login_at',
      'login_at',
      'session_created_at',
    ];

    for (final field in candidates) {
      final value = row[field];
      if (value == null) {
        continue;
      }

      if (value is DateTime) {
        return value.toUtc();
      }

      final parsed = DateTime.tryParse(value.toString());
      if (parsed != null) {
        return parsed.toUtc();
      }
    }

    return null;
  }

  Future<void> invalidateRememberedSession({String? sessionUuid}) async {
    final uuidToDelete = sessionUuid ?? await getRememberedSessionUuid();
    if (uuidToDelete == null || uuidToDelete.isEmpty) {
      await clearRememberedSessionUuid();
      return;
    }

    try {
      await supabase.from('user_session').delete().eq('token', uuidToDelete);
    } catch (_) {
      // Do not block logout if schema/policies reject delete.
    }

    await clearRememberedSessionUuid();
  }

  Future<UserModel?> tryAutoLoginWithRememberedSession({
    Duration maxAge = const Duration(days: 7),
  }) async {
    final rememberedUuid = await getRememberedSessionUuid();
    if (rememberedUuid == null || rememberedUuid.isEmpty) {
      return null;
    }

    final rows = await supabase
        .from('user_session')
        .select()
        .eq('token', rememberedUuid)
        .limit(1);

    if (rows.isEmpty) {
      await clearRememberedSessionUuid();
      return null;
    }

    final sessionRow = Map<String, dynamic>.from(rows.first as Map);
    final sessionCreatedAt = _extractSessionTimestamp(sessionRow);
    if (sessionCreatedAt == null || DateTime.now().toUtc().difference(sessionCreatedAt) > maxAge) {
      await invalidateRememberedSession(sessionUuid: rememberedUuid);
      return null;
    }

    final rawUserId = sessionRow['user_id'];
    final userId = rawUserId is int
        ? rawUserId
        : int.tryParse(rawUserId?.toString() ?? '');

    if (userId == null) {
      await invalidateRememberedSession(sessionUuid: rememberedUuid);
      return null;
    }

    final userRow = await supabase
        .from('user')
        .select()
        .eq('user_id', userId)
        .maybeSingle();

    if (userRow == null) {
      await invalidateRememberedSession(sessionUuid: rememberedUuid);
      return null;
    }

    final user = UserModel.fromJson(Map<String, dynamic>.from(userRow));
    if (!user.isActive) {
      await invalidateRememberedSession(sessionUuid: rememberedUuid);
      return null;
    }

    _latestSessionUuid = rememberedUuid;
    return user;
  }

  Future<void> signOutAndInvalidateRememberedSession({int? userId}) async {
    try {
      await supabase.auth.signOut();
    } catch (_) {
      // Always continue to local/session invalidation.
    }
    await invalidateRememberedSession();

    await auditLogService.logAction(
      userId: userId,
      action: 'Logout',
      entityType: 'Authentication',
      entityId: userId,
      details: 'User logged out',
    );
  }

  Future<void> logSuccessfulSystemEntry(
    UserModel user, {
    bool viaMfa = false,
  }) async {
    await auditLogService.logAction(
      userId: user.userId,
      action: 'Login success',
      entityType: 'Authentication',
      entityId: user.userId,
      details: viaMfa
          ? 'User entered the dashboard after MFA verification'
          : 'User entered the dashboard after credential verification',
    );
  }

  Future<UserModel?> _signInWithLocalPassword(String email, String password) async {
    final response = await _findUserByEmail(email);
    if (response == null) {
      return null;
    }

    final user = UserModel.fromJson(response);
    if (!user.isActive) {
      return null;
    }

    final isValid = await PasswordHasher.verifyPassword(
      password,
      user.passwordHash,
    );

    if (!isValid) {
      return null;
    }

    final sessionUuid = _uuid.v4();
    await _storeUserSessionToken(user.userId, sessionUuid);
    _latestSessionUuid = sessionUuid;

    return user;
  }

  Future<String?> _resolveLoginEmail(String identifier) async {
    final normalized = identifier.trim();
    if (normalized.isEmpty) return null;

    if (normalized.contains('@')) {
      return normalized.toLowerCase();
    }

    final exactRows = await supabase
        .from('user')
        .select('email')
        .eq('username', normalized)
        .order('user_id', ascending: false)
        .limit(1);

    if (exactRows.isNotEmpty) {
      final row = exactRows.first as Map;
      final rowEmail = row['email'];
      if (rowEmail != null) {
        return rowEmail.toString().toLowerCase();
      }
    }

    final caseInsensitiveRows = await supabase
        .from('user')
        .select('email')
        .ilike('username', normalized)
        .order('user_id', ascending: false)
        .limit(1);

    if (caseInsensitiveRows.isNotEmpty) {
      final row = caseInsensitiveRows.first as Map;
      final rowEmail = row['email'];
      if (rowEmail != null) {
        return rowEmail.toString().toLowerCase();
      }
    }

    return null;
  }

  // Sign up using Supabase Auth
  Future<void> signUp(String email, String password, String username, int roleId) async {
    final authResponse = await supabase.auth.signUp(
      email: email,
      password: password,
    );

    if (authResponse.user != null) {
      // Insert user data into custom table
      await supabase.from('user').insert({
        'email': email,
        'username': username,
        'role_id': roleId,
        'is_active': true,
      });
    }
  }

  // Sign in using Supabase Auth, then load the app user profile
  Future<UserModel?> signIn(String identifier, String password) async {
    final loginEmail = await _resolveLoginEmail(identifier);
    if (loginEmail == null) {
      return null;
    }

    AuthResponse authResponse;
    try {
      authResponse = await supabase.auth.signInWithPassword(
        email: loginEmail,
        password: password,
      );
    } on AuthApiException catch (e) {
      if (e.code == 'invalid_credentials') {
        return _signInWithLocalPassword(loginEmail, password);
      }
      rethrow;
    }

    final authUser = authResponse.user;
    if (authUser == null) {
      return null;
    }

    final response = await _findUserByEmail(loginEmail);

    if (response == null) {
      await supabase.auth.signOut();
      return null;
    }

    final user = UserModel.fromJson(response);
    if (!user.isActive) {
      await supabase.auth.signOut();
      return null; // User is deactivated, cannot login
    }

    final sessionUuid = _uuid.v4();
    await _storeUserSessionToken(user.userId, sessionUuid);
    _latestSessionUuid = sessionUuid;

    return user;
  }

  // Check if user credentials are valid but account is deactivated
  Future<bool> isAccountDeactivated(String identifier, String password) async {
    final loginEmail = await _resolveLoginEmail(identifier);
    if (loginEmail == null) {
      return false;
    }

    final localUserRow = await _findUserByEmail(loginEmail);
    if (localUserRow != null) {
      final localUser = UserModel.fromJson(localUserRow);
      if (!localUser.isActive) {
        final localPasswordMatch = await PasswordHasher.verifyPassword(
          password,
          localUser.passwordHash,
        );
        if (localPasswordMatch) {
          return true;
        }
      }
    }

    AuthResponse authResponse;
    try {
      authResponse = await supabase.auth.signInWithPassword(
        email: loginEmail,
        password: password,
      );
    } on AuthApiException catch (e) {
      if (e.code == 'invalid_credentials') {
        return false;
      }
      rethrow;
    }

    final authUser = authResponse.user;
    if (authUser == null) {
      return false; // Account doesn't exist or credentials are wrong
    }

    final response = await _findUserByEmail(loginEmail);

    final isDeactivated = response != null && !UserModel.fromJson(response).isActive;
    await supabase.auth.signOut();
    return isDeactivated; // Return true if account exists but is deactivated
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
