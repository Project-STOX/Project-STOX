import '../services/api/api_client.dart';
import '../services/api/api_config.dart';

class DashboardController {
  final ApiClient _apiClient = ApiClient(baseUrl: ApiConfig.baseUrl);

  Future<Map<String, dynamic>> getSummary() async {
    try {
      final response = await _apiClient.get('/dashboard/summary', authorized: true);
      return response as Map<String, dynamic>;
    } catch (e) {
      throw Exception('Failed to fetch dashboard summary: $e');
    }
  }

  Future<Map<String, dynamic>> getForecast(int productId, int window) async {
    try {
      final response = await _apiClient.get(
        '/dashboard/forecast',
        query: {
          'product_id': productId.toString(),
          'window': window.toString(),
        },
        authorized: true,
      );
      return response as Map<String, dynamic>;
    } catch (e) {
      throw Exception('Failed to fetch forecast: $e');
    }
  }

  Future<Map<String, dynamic>> getAlerts() async {
    try {
      final response = await _apiClient.get('/dashboard/alerts', authorized: true);
      return response as Map<String, dynamic>;
    } catch (e) {
      throw Exception('Failed to fetch alerts: $e');
    }
  }

  Future<Map<String, dynamic>> generateForecast({double alpha = 0.3, List<int> windows = const [30, 60]}) async {
    try {
      final response = await _apiClient.post(
        '/forecast/generate',
        body: {
          'alpha': alpha,
          'windows': windows,
        },
        authorized: true,
      );
      return response as Map<String, dynamic>;
    } catch (e) {
      throw Exception('Failed to generate forecast: $e');
    }
  }
}
