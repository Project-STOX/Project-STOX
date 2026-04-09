import 'api_client.dart';
import 'api_config.dart';

class ProductApiService {
  ProductApiService({ApiClient? apiClient})
      : _api = apiClient ?? ApiClient(baseUrl: ApiConfig.baseUrl);

  final ApiClient _api;

  // Example protected API call using JWT from secure storage.
  Future<List<Map<String, dynamic>>> fetchProducts({
    int limit = 20,
    int offset = 0,
  }) async {
    final data = await _api.get(
      '/inventory/products',
      query: {'limit': '$limit', 'offset': '$offset'},
      authorized: true,
    );
    if (data is List) {
      return data.whereType<Map<String, dynamic>>().toList();
    }
    return <Map<String, dynamic>>[];
  }
}
