import '../models/supplier.dart';
import '../services/supabase_service.dart';
import 'auth_controller.dart';

class SupplierController {
  final supabase = SupabaseService.client;
  final AuthController authController = AuthController();

  Future<List<Supplier>> fetchSuppliers() async {
    final response = await supabase.from('supplier').select();
    return (response as List).map((json) => Supplier.fromJson(json)).toList();
  }

  Future<void> addSupplier(Supplier supplier, int roleId, int userId) async {
    final allowed = await authController.hasPermission(roleId, "manage_suppliers");
    if (!allowed) {
      throw Exception("Permission denied: manage_suppliers");
    }

    await supabase.from('supplier').insert({
      'supplier_name': supplier.supplierName,
      'address': supplier.address,
      'contact_info': supplier.contactInfo,
      'lead_time_days': supplier.leadTimeDays,
      'created_by': userId,
    });
  }

  Future<void> updateSupplier(Supplier supplier, int roleId) async {
    final allowed = await authController.hasPermission(roleId, "manage_suppliers");
    if (!allowed) {
      throw Exception("Permission denied: manage_suppliers");
    }

    await supabase.from('supplier').update({
      'supplier_name': supplier.supplierName,
      'address': supplier.address,
      'contact_info': supplier.contactInfo,
      'lead_time_days': supplier.leadTimeDays,
    }).eq('supplier_id', supplier.supplierId);
  }

  Future<void> deleteSupplier(int supplierId, int roleId) async {
    final allowed = await authController.hasPermission(roleId, "manage_suppliers");
    if (!allowed) {
      throw Exception("Permission denied: manage_suppliers");
    }

    await supabase.from('supplier').delete().eq('supplier_id', supplierId);
  }
}
