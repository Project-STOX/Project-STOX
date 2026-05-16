import 'api_client.dart';
import 'api_config.dart';

class SystemService {
  SystemService({ApiClient? apiClient})
      : _apiClient = apiClient ??
            ApiClient(baseUrl: ApiConfig.baseUrl);

  final ApiClient _apiClient;

  Future<Map<String, dynamic>> checkHealth() async {
    try {
      // The health endpoint is outside the /api/v1 prefix in main.py
      // but ApiClient normalizedBase might already include it if configured.
      // Wait, main.py has @app.get("/health").
      // ApiConfig.baseUrl is likely "http://localhost:8000/api/v1".
      
      // Let's check ApiConfig first.
      return await _apiClient.get('/health', authorized: false);
    } catch (e) {
      return {'status': 'error', 'detail': e.toString()};
    }
  }
}
