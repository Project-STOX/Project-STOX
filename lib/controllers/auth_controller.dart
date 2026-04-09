import '../services/api/auth_api_service.dart';
import '../models/user.dart';

class AuthController {
  final AuthApiService _authApiService = AuthApiService();
  static UserModel? _currentUser;

  void cacheUser(UserModel user) {
    _currentUser = user;
  }

  Future<Map<String, dynamic>> signIn(String email, String password, {bool rememberMe = true}) async {
    final response = await _authApiService.login(
      email: email,
      password: password,
      rememberMe: rememberMe,
    );
    final userPayload = response['user'];
    if (userPayload is Map<String, dynamic>) {
      _currentUser = UserModel.fromJson(userPayload);
    }
    return response;
  }

  Future<UserModel> getCurrentUser() async {
    final user = await _authApiService.getCurrentUser();
    _currentUser = user;
    return user;
  }

  Future<UserModel?> tryAutoLogin() async {
    try {
      final user = await getCurrentUser();
      _currentUser = user;
      return user;
    } catch (e) {
      // Token might be missing or expired
      return null;
    }
  }

  Future<UserModel> verify2FA(String loginChallenge, String code, {bool rememberMe = true}) async {
    final user = await _authApiService.verify2FA(
      loginChallenge: loginChallenge,
      code: code,
      rememberMe: rememberMe,
    );
    _currentUser = user;
    return user;
  }

  Future<bool> verify2FALegacy(int userId, String code) async {
    return false;
  }

  Future<void> signOut() {
    _currentUser = null;
    return _authApiService.logout();
  }

  Future<bool> hasPermission(int roleId, String permissionName) async {
    return _authApiService.hasPermission(permissionName);
  }

  Future<Map<String, bool>> hasPermissionsBatch(
    List<String> permissions,
  ) async {
    return _authApiService.hasPermissionsBatch(permissions);
  }

  Future<String?> getUserRole(int roleId) async {
    final role = _currentUser?.role.trim() ?? '';
    if (role.isNotEmpty) {
      return role;
    }

    UserModel? currentUser;
    try {
      currentUser = await getCurrentUser();
    } catch (_) {
      currentUser = null;
    }

    if (currentUser != null && currentUser.role.isNotEmpty) {
      return currentUser.role;
    }

    if (roleId == 1) return 'SME Owner';
    if (roleId == 2) return 'Inventory Manager';

    return 'User';
  }

  Future<void> signOutAndInvalidateRememberedSession({int? userId}) =>
      signOut();

  Future<void> generate2FAByEmail(String email) async {
    await _authApiService.generate2fa(email: email);
  }

  Future<void> generate2FA(int userId) async {
    await _authApiService.generate2fa(userId: userId);
  }

  Future<bool> isAccountDeactivated(String identifier, String password) async =>
      false;
}
