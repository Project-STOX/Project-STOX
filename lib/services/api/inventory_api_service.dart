import 'api_client.dart';
import 'api_config.dart';

class InventoryApiService {
  InventoryApiService({ApiClient? apiClient})
      : _api = apiClient ?? ApiClient(baseUrl: ApiConfig.baseUrl);

  final ApiClient _api;

  Future<List<Map<String, dynamic>>> _fetchAll(
    String path, {
    Map<String, String>? query,
  }) async {
    const pageSize = 100;
    var offset = 0;
    final results = <Map<String, dynamic>>[];

    while (true) {
      final pageQuery = <String, String>{
        ...?query,
        'limit': '$pageSize',
        'offset': '$offset',
      };
      final data = await _api.get(path, query: pageQuery, authorized: true);
      if (data is! List) {
        break;
      }

      final page = data.whereType<Map<String, dynamic>>().toList();
      results.addAll(page);
      if (page.length < pageSize) {
        break;
      }
      offset += pageSize;
    }

    return results;
  }

  Future<List<Map<String, dynamic>>> listProducts({String? search}) {
    return _fetchAll(
      '/inventory/products',
      query: search != null ? {'search': search} : null,
    );
  }

  Future<List<String>> getProductSuggestions(String query) async {
    final data = await _api.get(
      '/inventory/products/suggestions',
      query: {'query': query},
      authorized: true,
    );
    if (data is List) {
      return data.map((e) => e.toString()).toList();
    }
    return [];
  }

  Future<List<Map<String, dynamic>>> listSuppliers() {
    return _fetchAll('/inventory/suppliers');
  }

  Future<List<Map<String, dynamic>>> listStockReceipts() {
    return _fetchAll('/inventory/stock-receipts');
  }

  Future<Map<String, dynamic>> createProduct(Map<String, dynamic> payload) async {
    final data = await _api.post('/inventory/products', body: payload, authorized: true);
    return data is Map<String, dynamic> ? data : <String, dynamic>{};
  }

  Future<Map<String, dynamic>> updateProduct(int productId, Map<String, dynamic> payload) async {
    final data = await _api.put('/inventory/products/$productId', body: payload, authorized: true);
    return data is Map<String, dynamic> ? data : <String, dynamic>{};
  }

  Future<void> deleteProduct(int productId) async {
    await _api.delete('/inventory/products/$productId', authorized: true);
  }

  Future<Map<String, dynamic>> createSupplier(Map<String, dynamic> payload) async {
    final data = await _api.post('/inventory/suppliers', body: payload, authorized: true);
    return data is Map<String, dynamic> ? data : <String, dynamic>{};
  }

  Future<Map<String, dynamic>> updateSupplier(int supplierId, Map<String, dynamic> payload) async {
    final data = await _api.put('/inventory/suppliers/$supplierId', body: payload, authorized: true);
    return data is Map<String, dynamic> ? data : <String, dynamic>{};
  }

  Future<void> deleteSupplier(int supplierId) async {
    await _api.delete('/inventory/suppliers/$supplierId', authorized: true);
  }

  Future<Map<String, dynamic>> createStockReceipt(Map<String, dynamic> payload) async {
    final data = await _api.post('/inventory/stock-receipts', body: payload, authorized: true);
    return data is Map<String, dynamic> ? data : <String, dynamic>{};
  }

  Future<Map<String, dynamic>> updateStockReceipt(int receiptId, Map<String, dynamic> payload) async {
    final data = await _api.put('/inventory/stock-receipts/$receiptId', body: payload, authorized: true);
    return data is Map<String, dynamic> ? data : <String, dynamic>{};
  }

  Future<void> deleteStockReceipt(int receiptId) async {
    await _api.delete('/inventory/stock-receipts/$receiptId', authorized: true);
  }
}