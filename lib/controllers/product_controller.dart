import '../models/product.dart';
import '../models/supplier.dart';
import '../services/supabase_service.dart';
import '../services/audit_log_service.dart';
import 'auth_controller.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class ProductController {
  final supabase = SupabaseService.client;
  final AuthController authController = AuthController();
  final AuditLogService auditLogService = AuditLogService();

  Future<List<Map<String, dynamic>>> fetchProducts() async {
    final response = await supabase
        .from('product')
        .select('*, supplier(supplier_name)');
    return (response as List)
        .map((json) => json as Map<String, dynamic>)
        .toList();
  }

  Future<void> addProduct(
    Product product,
    int roleId, {
    int? actorUserId,
  }) async {
    final allowed = await authController.hasPermission(
      roleId,
      "Manage Products",
    );
    if (!allowed) {
      throw Exception("Permission denied: Manage Products");
    }

    await supabase.from('product').insert({
      'supplier_id': product.supplierId,
      'product_name': product.productName,
      'sku': product.sku,
      'unit_cost': product.unitCost,
      'current_qty': product.currentQty,
      'lead_time_days': product.leadTimeDays,
      'safety_stock': product.safetyStock,
      'reorder_point': product.reorderPoint,
      'serial_no': product.serialNo,
      'status_flag': product.statusFlag,
    });

    await auditLogService.logAction(
      userId: actorUserId,
      action: 'Create product',
      entityType: 'Product',
      details: 'Created product ${product.productName} (SKU: ${product.sku})',
    );
  }

  Future<void> updateProduct(
    Product product,
    int roleId, {
    int? actorUserId,
  }) async {
    final allowed = await authController.hasPermission(
      roleId,
      "Manage Products",
    );
    if (!allowed) {
      throw Exception("Permission denied: Manage Products");
    }

    await supabase
        .from('product')
        .update({
          'supplier_id': product.supplierId,
          'product_name': product.productName,
          'sku': product.sku,
          'unit_cost': product.unitCost,
          'current_qty': product.currentQty,
          'lead_time_days': product.leadTimeDays,
          'safety_stock': product.safetyStock,
          'reorder_point': product.reorderPoint,
          'serial_no': product.serialNo,
          'status_flag': product.statusFlag,
        })
        .eq('product_id', product.productId);

    await auditLogService.logAction(
      userId: actorUserId,
      action: 'Update product',
      entityType: 'Product',
      entityId: product.productId,
      details: 'Updated product ${product.productName} (SKU: ${product.sku})',
    );
  }

  Future<void> deleteProduct(
    int productId,
    int roleId, {
    int? actorUserId,
  }) async {
    final allowed = await authController.hasPermission(
      roleId,
      "Manage Products",
    );
    if (!allowed) {
      throw Exception("Permission denied: Manage Products");
    }

    try {
      await supabase.from('product').delete().eq('product_id', productId);

      await auditLogService.logAction(
        userId: actorUserId,
        action: 'Delete product',
        entityType: 'Product',
        entityId: productId,
      );
    } on PostgrestException catch (e) {
      final msg = e.message.toLowerCase();
      if (e.code == '23503' &&
          (msg.contains('stock_receipt') || msg.contains('foreign key'))) {
        throw Exception(
          'Cannot delete product because stock receipt records exist. Delete related stock receipts first.',
        );
      }
      rethrow;
    }
  }

  Future<List<Supplier>> fetchSuppliers() async {
    final response = await supabase.from('supplier').select();
    return (response as List).map((json) => Supplier.fromJson(json)).toList();
  }
}
