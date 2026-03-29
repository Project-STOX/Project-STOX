import '../models/product.dart';
import '../services/supabase_service.dart';
import 'auth_controller.dart';

class ProductController {
  final supabase = SupabaseService.client;
  final AuthController authController = AuthController();

  Future<List<Product>> fetchProducts() async {
    final response = await supabase.from('product').select();
    return (response as List).map((json) => Product.fromJson(json)).toList();
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
    });
  }
}
