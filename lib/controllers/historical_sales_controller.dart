
import '../services/supabase_service.dart';
import '../models/historical_sale.dart';


class HistoricalSalesController {
  final supabase = SupabaseService.client;

  // Ensure "Historical data" permission exists
  Future<void> ensureHistoricalDataPermission() async {
    try {
      final response = await supabase
          .from('permission')
          .select()
          .ilike('perm_name', 'Historical data')
          .maybeSingle();

      if (response == null) {
        await supabase.from('permission').insert({
          'perm_name': 'Historical data',
          'description': 'Access and view historical sales data',
        });
      }
    } catch (e) {
      print('Error ensuring Historical data permission: $e');
    }
  }

  // Get unique product names for auto-complete
  Future<List<String>> getProductNames() async {
    try {
      final response = await supabase.from('product').select('product_name');
      return response.map<String>((e) => e['product_name'] as String).toList().toSet().toList();
    } catch (e) {
      print('Error fetching product names: $e');
      return [];
    }
  }

  // Get unique supplier names for auto-complete
  Future<List<String>> getSupplierNames() async {
    try {
      final response = await supabase.from('supplier').select('supplier_name');
      return response.map<String>((e) => e['supplier_name'] as String).toList().toSet().toList();
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
      var query = supabase.from('historical_sales').select('*, product!inner(product_name, supplier!inner(supplier_name))');

      if (startDate != null) {
        query = query.gte('sale_date', startDate.toIso8601String());
      }
      if (endDate != null) {
        query = query.lte('sale_date', endDate.toIso8601String());
      }
      if (productQuery != null && productQuery.isNotEmpty) {
        query = query.ilike('product.product_name', '%$productQuery%');
      }
      if (supplierQuery != null && supplierQuery.isNotEmpty) {
        query = query.ilike('product.supplier.supplier_name', '%$supplierQuery%');
      }

      final response = await query.order('sale_date', ascending: false);
      return response.map<HistoricalSale>((json) => HistoricalSale.fromJson(json)).toList();
    } catch (e) {
      print('Error fetching historical sales: $e');
      throw e;
    }
  }

  // Log unauthorized access
  Future<void> logUnauthorizedAccess(int userId) async {
    try {
      await supabase.from('audit_log').insert({
        'user_id': userId,
        'action': 'Unauthorized access attempt to Historical Sales Data',
        'entity_type': 'Page',
        'entity_id': 0,
      });
    } catch (e) {
      print('Error logging unauthorized access: $e');
    }
  }

  // Export to CSV and log to csv_import
  Future<String> exportToCsv(List<HistoricalSale> sales, int userId) async {
    try {
      List<List<dynamic>> rows = [];
      // Headers
      rows.add([
        'Sale ID',
        'Product Name',
        'Sale Date',
        'Quantity Sold',
        'Revenue',
        'Supplier'
      ]);

      // Data
      for (var sale in sales) {
        rows.add([
          sale.saleId,
          sale.productName,
          sale.saleDate.toIso8601String(),
          sale.quantitySold,
          sale.revenue,
          sale.supplier ?? '',
        ]);
      }

      // Convert to CSV string natively
      String csvData = rows.map((row) {
        return row.map((item) {
          String str = item.toString();
          // Escape quotes and commas
          if (str.contains(',') || str.contains('"') || str.contains('\n')) {
            str = '"${str.replaceAll('"', '""')}"';
          }
          return str;
        }).join(',');
      }).join('\r\n');
      // Log export activity to csv_import
      final fileName = 'historical_sales_export_${DateTime.now().millisecondsSinceEpoch}.csv';
      await supabase.from('csv_import').insert({
        'filename': fileName,
        'imported_by': userId,
        'status': 'Completed',
        'row_count': sales.length,
      });

      return csvData;
    } catch (e) {
      print('Error exporting to CSV: $e');
      throw e;
    }
  }
}
