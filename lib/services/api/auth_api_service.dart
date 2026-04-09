import '../../models/user.dart';
import 'api_client.dart';
import 'api_config.dart';
import 'token_storage.dart';

class AuthApiService {
  AuthApiService({ApiClient? apiClient, TokenStorage? tokenStorage})
    : _tokenStorage = tokenStorage ?? TokenStorage(),
      _api = apiClient ?? ApiClient(baseUrl: ApiConfig.baseUrl);

  final ApiClient _api;
  final TokenStorage _tokenStorage;

  Future<Map<String, dynamic>> login({
    required String email,
    required String password,
    bool rememberMe = true,
  }) async {
    final data = await _api.post(
      '/auth/login',
      body: {'email': email, 'password': password},
    );
    if (data is Map<String, dynamic>) {
      final accessToken = data['access_token']?.toString();
      final refreshToken = data['refresh_token']?.toString();
      if (rememberMe &&
          accessToken != null &&
          accessToken.isNotEmpty &&
          refreshToken != null &&
          refreshToken.isNotEmpty) {
        await _tokenStorage.saveTokens(
          accessToken: accessToken,
          refreshToken: refreshToken,
        );
      }
      return data;
    }
    throw Exception('Invalid login response');
  }

  Future<UserModel> verify2FA({
    required String loginChallenge,
    required String code,
    bool rememberMe = true,
  }) async {
    final data =
        await _api.post(
              '/auth/verify-2fa',
              body: {'login_challenge': loginChallenge, 'code': code},
            )
            as Map<String, dynamic>;

    final accessToken = data['access_token']?.toString();
    final refreshToken = data['refresh_token']?.toString();
    if (accessToken == null || refreshToken == null) {
      throw Exception('Token response is invalid');
    }
    if (rememberMe) {
      await _tokenStorage.saveTokens(
        accessToken: accessToken,
        refreshToken: refreshToken,
      );
    }

    final userJson = data['user'] as Map<String, dynamic>?;
    if (userJson == null) {
      throw Exception('User payload missing');
    }
    return UserModel.fromJson(userJson);
  }

  Future<UserModel> getCurrentUser() async {
    final data = await _api.get('/auth/me', authorized: true);
    if (data is Map<String, dynamic>) {
      return UserModel.fromJson(data);
    }
    throw Exception('Invalid current user response');
  }

  Future<bool> hasPermission(String permissionName) async {
    final data = await _api.get(
      '/auth/permissions',
      query: {'permission': permissionName},
      authorized: true,
    );
    if (data is Map<String, dynamic>) {
      return data['allowed'] == true;
    }
    return false;
  }

  Future<Map<String, bool>> hasPermissionsBatch(
    List<String> permissions,
  ) async {
    if (permissions.isEmpty) return {};
    final data = await _api.get(
      '/auth/permissions/batch',
      query: {'permissions': permissions},
      authorized: true,
    );
    if (data is Map<String, dynamic>) {
      return data.map((key, value) => MapEntry(key, value == true));
    }
    return {};
  }

  Future<void> changePassword({
    required String currentPassword,
    required String newPassword,
    String? twoFactorCode,
  }) async {
    await _api.post(
      '/auth/change-password',
      body: {
        'current_password': currentPassword,
        'new_password': newPassword,
        'two_factor_code': ?twoFactorCode,
      },
      authorized: true,
    );
  }

  Future<void> generate2fa({int? userId, String? email}) async {
    await _api.post(
      '/auth/generate-2fa',
      body: {'user_id': ?userId, 'email': ?email},
    );
  }

  Future<void> logout() async {
    final refreshToken = await _tokenStorage.getRefreshToken();
    if (refreshToken != null && refreshToken.isNotEmpty) {
      try {
        await _api.post('/auth/logout', body: {'refresh_token': refreshToken});
      } catch (_) {
        // Continue with local token cleanup even if server logout fails.
      }
    }
    await _tokenStorage.clearTokens();
  }
}
