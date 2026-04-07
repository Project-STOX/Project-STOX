import '../models/supplier.dart';
import '../services/supabase_service.dart';
import '../services/audit_log_service.dart';
import 'auth_controller.dart';

class SupplierController {
  final supabase = SupabaseService.client;
  final AuthController authController = AuthController();
  final AuditLogService auditLogService = AuditLogService();

  Future<void> _syncSupplierLeadTimeToReorderParameters(
    int supplierId,
    int? leadTimeDays, {
    int? actorUserId,
  }) async {
    if (leadTimeDays == null) {
      return;
    }

    final products = await supabase
        .from('product')
        .select('product_id')
        .eq('supplier_id', supplierId);

    final productIds = (products as List)
        .map((row) => (row['product_id'] as num).toInt())
        .toList();

    if (productIds.isEmpty) {
      return;
    }

    await supabase
        .from('reorder_parameter')
        .update({'lead_time_days': leadTimeDays})
        .inFilter('product_id', productIds);

    if (actorUserId == null) {
      return;
    }

    final existingRows = await supabase
        .from('reorder_parameter')
        .select('product_id')
        .inFilter('product_id', productIds);

    final existingIds = (existingRows as List)
        .map((row) => (row['product_id'] as num).toInt())
        .toSet();

    final missingIds = productIds.where((id) => !existingIds.contains(id)).toList();
    if (missingIds.isEmpty) {
      return;
    }

    await supabase.from('reorder_parameter').insert(
      missingIds
          .map(
            (productId) => {
              'product_id': productId,
              'configured_by': actorUserId,
              'safety_stock': 0,
              'lead_time_days': leadTimeDays,
            },
          )
          .toList(),
    );
  }

  Future<List<Supplier>> fetchSuppliers() async {
    final response = await supabase.from('supplier').select();
    return (response as List).map((json) => Supplier.fromJson(json)).toList();
  }

  Future<void> addSupplier(Supplier supplier, int roleId, int userId) async {
    final allowed = await authController.hasPermission(roleId, "Manage suppliers");
    if (!allowed) {
      throw Exception("Permission denied: Manage suppliers");
    }

    await supabase.from('supplier').insert({
      'supplier_name': supplier.supplierName,
      'address': supplier.address,
      'contact_info': supplier.contactInfo,
      'lead_time_days': supplier.leadTimeDays,
      'created_by': userId,
    });

    await auditLogService.logAction(
      userId: userId,
      action: 'Create supplier',
      entityType: 'Supplier',
      details: 'Created supplier ${supplier.supplierName}',
    );
  }

  Future<void> updateSupplier(
    Supplier supplier,
    int roleId, {
    int? actorUserId,
  }) async {
    final allowed = await authController.hasPermission(roleId, "Manage suppliers");
    if (!allowed) {
      throw Exception("Permission denied: Manage suppliers");
    }

    await supabase.from('supplier').update({
      'supplier_name': supplier.supplierName,
      'address': supplier.address,
      'contact_info': supplier.contactInfo,
      'lead_time_days': supplier.leadTimeDays,
    }).eq('supplier_id', supplier.supplierId);

    await _syncSupplierLeadTimeToReorderParameters(
      supplier.supplierId,
      supplier.leadTimeDays,
      actorUserId: actorUserId,
    );

    await auditLogService.logAction(
      userId: actorUserId,
      action: 'Update supplier',
      entityType: 'Supplier',
      entityId: supplier.supplierId,
      details: 'Updated supplier ${supplier.supplierName}',
    );
  }

  Future<void> deleteSupplier(
    int supplierId,
    int roleId, {
    int? actorUserId,
  }) async {
    final allowed = await authController.hasPermission(roleId, "Manage suppliers");
    if (!allowed) {
      throw Exception("Permission denied: Manage suppliers");
    }

    await supabase.from('supplier').delete().eq('supplier_id', supplierId);

    await auditLogService.logAction(
      userId: actorUserId,
      action: 'Delete supplier',
      entityType: 'Supplier',
      entityId: supplierId,
    );
  }
}
