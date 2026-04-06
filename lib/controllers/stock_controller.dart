import '../models/product.dart';
import '../models/stock_receipt.dart';
import '../models/supplier.dart';
import '../services/supabase_service.dart';
import 'auth_controller.dart';

class StockController {
  final supabase = SupabaseService.client;
  final AuthController authController = AuthController();

  Future<void> ensureStockReceiptPermission() async {
    try {
      final byId = await supabase
          .from('permission')
          .select('perm_id, perm_name')
          .eq('perm_id', 5)
          .maybeSingle();

      if (byId != null) {
        if ((byId['perm_name'] as String?) != 'Manage stock') {
          await supabase
              .from('permission')
              .update({'perm_name': 'Manage stock'})
              .eq('perm_id', 5);
        }
        return;
      }

      final byName = await supabase
          .from('permission')
          .select('perm_id')
          .ilike('perm_name', 'Manage stock')
          .maybeSingle();

      if (byName == null) {
        await supabase.from('permission').insert({
          'perm_id': 5,
          'perm_name': 'Manage stock',
        });
      }
    } catch (e) {
      print('Error ensuring Manage stock permission: $e');
    }
  }

  Future<List<Product>> fetchProducts() async {
    final response = await supabase
        .from('product')
        .select()
        .order('product_name');
    return (response as List).map((json) => Product.fromJson(json)).toList();
  }

  Future<List<Supplier>> fetchSuppliers() async {
    final response = await supabase
        .from('supplier')
        .select()
        .order('supplier_name');
    return (response as List).map((json) => Supplier.fromJson(json)).toList();
  }

  Future<List<StockReceipt>> fetchStockReceipts({String? searchQuery}) async {
    final response = await supabase
        .from('stock_receipt')
        .select(
          'receipt_id, product_id, supplier_id, recorded_by, quantity_received, quantity_damaged, receipt_date, notes, product(product_name, sku, serial_no), supplier(supplier_name), user(username)',
        )
        .order('receipt_date', ascending: false);

    var receipts = (response as List)
        .map((json) => StockReceipt.fromJson(json as Map<String, dynamic>))
        .toList();

    final query = searchQuery?.trim().toLowerCase() ?? '';
    final normalizedQuery = query.replaceAll(RegExp(r'[^a-z0-9]'), '');
    if (query.isNotEmpty) {
      receipts = receipts.where((receipt) {
        final normalizedSupplierName = (receipt.supplierName ?? '')
            .toLowerCase()
            .replaceAll(RegExp(r'[^a-z0-9]'), '');
        final supplierIdText = receipt.supplierId.toString();
        final supplierKeyText = 'supplierid$supplierIdText';

        return receipt.stockReceiptId.toString().contains(query) ||
            receipt.productId.toString().contains(query) ||
            (receipt.productName ?? '').toLowerCase().contains(query) ||
            (receipt.productSku ?? '').toLowerCase().contains(query) ||
            (receipt.productSerialNo ?? '').toLowerCase().contains(query) ||
            supplierIdText.contains(query) ||
            supplierKeyText.contains(normalizedQuery) ||
            normalizedSupplierName.contains(normalizedQuery) ||
            (receipt.supplierName ?? '').toLowerCase().contains(query) ||
            receipt.recordedBy.toString().contains(query) ||
            (receipt.recordedByUsername ?? '').toLowerCase().contains(query);
      }).toList();
    }

    return receipts;
  }

  Future<void> addStockReceipt(StockReceipt receipt, int roleId) async {
    final allowed = await authController.hasPermission(roleId, 'Manage stock');
    if (!allowed) {
      throw Exception('Permission denied: Manage stock');
    }

    await supabase
        .from('stock_receipt')
        .insert(receipt.toJson()..remove('receipt_id'));
  }

  Future<void> updateStockReceipt(StockReceipt receipt, int roleId) async {
    final allowed = await authController.hasPermission(roleId, 'Manage stock');
    if (!allowed) {
      throw Exception('Permission denied: Manage stock');
    }

    await supabase
        .from('stock_receipt')
        .update(receipt.toJson()..remove('receipt_id'))
        .eq('receipt_id', receipt.stockReceiptId);
  }

  Future<void> deleteStockReceipt(int stockReceiptId, int roleId) async {
    final allowed = await authController.hasPermission(roleId, 'Manage stock');
    if (!allowed) {
      throw Exception('Permission denied: Manage stock');
    }

    await supabase
        .from('stock_receipt')
        .delete()
        .eq('receipt_id', stockReceiptId);
  }

  Future<int> quickCreateProduct({
    required String productName,
    required String sku,
    required int supplierId,
    String? serialNo,
  }) async {
    final response = await supabase
        .from('product')
        .insert({
          'supplier_id': supplierId,
          'product_name': productName,
          'sku': sku,
          'unit_cost': 0,
          'current_qty': 0,
          'lead_time_days': 0,
          'safety_stock': 0,
          'reorder_point': 0,
          'serial_no': serialNo,
          'status_flag': 'In Stock',
        })
        .select('product_id')
        .single();

    return (response['product_id'] as num).toInt();
  }

  Future<int> quickCreateSupplier({
    required String supplierName,
    int? createdByUserId,
    String? address,
    String? contactInfo,
    int? leadTimeDays,
  }) async {
    final response = await supabase
        .from('supplier')
        .insert({
          'supplier_name': supplierName,
          'address': address,
          'contact_info': contactInfo,
          'lead_time_days': leadTimeDays,
          'created_by': createdByUserId,
        })
        .select('supplier_id')
        .single();

    return (response['supplier_id'] as num).toInt();
  }
}
