import '../../models/audit_log_entry.dart';
import '../../models/historical_sale.dart';
import 'api_client.dart';
import 'api_config.dart';

class ReportsApiService {
  ReportsApiService({ApiClient? apiClient})
      : _api = apiClient ?? ApiClient(baseUrl: ApiConfig.baseUrl);

  final ApiClient _api;

  Future<List<HistoricalSale>> getHistoricalSales({
    int limit = 500,
    DateTime? startDate,
    DateTime? endDate,
    int? productId,
    String? productQuery,
    String? supplierQuery,
  }) async {
    final query = <String, String>{
      'limit': '$limit',
      if (startDate != null) 'start_date': startDate.toIso8601String().split('T').first,
      if (endDate != null) 'end_date': endDate.toIso8601String().split('T').first,
      if (productId != null) 'product_id': '$productId',
      if (productQuery != null && productQuery.trim().isNotEmpty) 'product_query': productQuery.trim(),
      if (supplierQuery != null && supplierQuery.trim().isNotEmpty) 'supplier_query': supplierQuery.trim(),
    };

    final response = await _api.get('/reports/historical-sales', query: query, authorized: true);
    if (response is List) {
      return response
          .whereType<Map<String, dynamic>>()
          .map(HistoricalSale.fromJson)
          .toList();
    }
    return [];
  }

  Future<List<AuditLogEntry>> getAuditLogs({int limit = 500}) async {
    final response = await _api.get('/reports/audit-logs', query: {'limit': '$limit'}, authorized: true);
    if (response is List) {
      return response
          .whereType<Map<String, dynamic>>()
          .map(AuditLogEntry.fromJson)
          .toList();
    }
    return [];
  }

  Future<void> importHistoricalSales(List<Map<String, dynamic>> rows) async {
    await _api.post('/reports/historical-sales/import', body: {'items': rows}, authorized: true);
  }

  Future<void> logAction({
    int? userId,
    required String action,
    required String entityType,
    int? entityId,
    String? details,
  }) async {
    try {
      await _api.post(
        '/reports/audit-logs',
        body: {
          'action': action,
          'entity_type': entityType,
          'entity_id': entityId ?? 0,
          if (details != null && details.trim().isNotEmpty) 'details': details,
        },
        authorized: true,
      );
    } catch (_) {
      return;
    }
  }
}