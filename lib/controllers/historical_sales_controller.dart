import '../services/audit_log_service.dart';
import '../services/api/inventory_api_service.dart';
import '../services/api/reports_api_service.dart';
import '../models/historical_sale.dart';

class HistoricalSalesController {
  final AuditLogService auditLogService = AuditLogService();
  final InventoryApiService _inventoryApi = InventoryApiService();
  final ReportsApiService _reportsApi = ReportsApiService();

  // Ensure "Historical data" permission exists
  Future<void> ensureHistoricalDataPermission() async {
    return;
  }

  // Get unique product names for auto-complete
  Future<List<String>> getProductNames() async {
    try {
      final response = await _inventoryApi.listProducts();
      return response
          .map<String>((e) => e['name']?.toString() ?? '')
          .where((name) => name.trim().isNotEmpty)
          .toList()
          .toSet()
          .toList();
    } catch (e) {
      print('Error fetching product names: $e');
      return [];
    }
  }

  // Get unique supplier names for auto-complete
  Future<List<String>> getSupplierNames() async {
    try {
      final response = await _inventoryApi.listSuppliers();
      return response
          .map<String>((e) => e['name']?.toString() ?? '')
          .where((name) => name.trim().isNotEmpty)
          .toList()
          .toSet()
          .toList();
    } catch (e) {
      print('Error fetching supplier names: $e');
      return [];
    }
  }

  // Fetch sales with filters
  Future<List<HistoricalSale>> fetchSales({
    DateTime? startDate,
    DateTime? endDate,
    String? productQuery,
    String? supplierQuery,
  }) async {
    try {
      return _reportsApi.getHistoricalSales(
        limit: 1000,
        startDate: startDate,
        endDate: endDate,
        productQuery: productQuery,
        supplierQuery: supplierQuery,
      );
    } catch (e) {
      print('Error fetching historical sales: $e');
      rethrow;
    }
  }

  Future<List<HistoricalSale>> fetchSalesForProduct(int productId) async {
    try {
      return _reportsApi.getHistoricalSales(limit: 1000, productId: productId);
    } catch (e) {
      print('Error fetching product sales history: $e');
      rethrow;
    }
  }

  // Log unauthorized access
  Future<void> logUnauthorizedAccess(int userId) async {
    await auditLogService.logAction(
      userId: userId,
      action: 'Unauthorized access attempt',
      entityType: 'Page',
      entityId: 0,
      details: 'Historical Sales Data page access denied',
    );
  }

  // Export to CSV and log to csv_import
  Future<String> exportToCsv(List<HistoricalSale> sales, int userId) async {
    try {
      List<List<dynamic>> rows = [];
      // Headers
      rows.add([
        'Sale ID',
        'Product Name',
        'Product Code',
        'Sale Date',
        'Quantity Sold',
        'Revenue',
        'Supplier',
      ]);

      // Data
      for (var sale in sales) {
        rows.add([
          sale.saleId,
          sale.productName,
          sale.productCode ?? '',
          sale.saleDate.toIso8601String(),
          sale.quantitySold,
          sale.revenue,
          sale.supplier ?? '',
        ]);
      }

      // Convert to CSV string natively
      String csvData = rows
          .map((row) {
            return row
                .map((item) {
                  String str = item.toString();
                  // Escape quotes and commas
                  if (str.contains(',') ||
                      str.contains('"') ||
                      str.contains('\n')) {
                    str = '"${str.replaceAll('"', '""')}"';
                  }
                  return str;
                })
                .join(',');
          })
          .join('\r\n');
      await auditLogService.logAction(
        userId: userId,
        action: 'Export historical sales',
        entityType: 'HistoricalSales',
        details: 'Exported ${sales.length} rows to CSV',
      );

      return csvData;
    } catch (e) {
      print('Error exporting to CSV: $e');
      rethrow;
    }
  }
}
