import '../models/product.dart';
import '../models/supplier.dart';
import '../services/supabase_service.dart';
import 'auth_controller.dart';

class ProductController {
  final supabase = SupabaseService.client;
  final AuthController authController = AuthController();

  Future<List<Map<String, dynamic>>> fetchProducts() async {
    final response = await supabase.from('product').select('*, supplier(supplier_name)');
    return (response as List).map((json) => json as Map<String, dynamic>).toList();
  }
    Future<void> addProduct(Product product, int roleId) async {
    final allowed = await authController.hasPermission(roleId, "manage_products");
    if (!allowed) {
      throw Exception("Permission denied: manage_products");
    }

    await supabase.from('product').insert({
      'supplier_id': product.supplierId,
      'product_name': product.productName,
      'sku': product.sku,
      'unit_cost': product.unitCost,
      'current_qty': product.currentQty,
      'reorder_point': product.reorderPoint,
      'serial_no': product.serialNo,
      'status_flag': product.statusFlag,
    });
  }

  Future<void> updateProduct(Product product, int roleId) async {
    final allowed = await authController.hasPermission(roleId, "manage_products");
    if (!allowed) {
      throw Exception("Permission denied: manage_products");
    }

    await supabase.from('product').update({
      'supplier_id': product.supplierId,
      'product_name': product.productName,
      'sku': product.sku,
      'unit_cost': product.unitCost,
      'current_qty': product.currentQty,
      'reorder_point': product.reorderPoint,
      'serial_no': product.serialNo,
      'status_flag': product.statusFlag,
    }).eq('product_id', product.productId);
  }

  Future<void> deleteProduct(int productId, int roleId) async {
    final allowed = await authController.hasPermission(roleId, "manage_products");
    if (!allowed) {
      throw Exception("Permission denied: manage_products");
    }

    await supabase.from('product').delete().eq('product_id', productId);
  }

  Future<List<Supplier>> fetchSuppliers() async {
    final response = await supabase.from('supplier').select();
    return (response as List).map((json) => Supplier.fromJson(json)).toList();
  }
}
