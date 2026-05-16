import '../models/product.dart';
import '../models/supplier.dart';
import '../services/api/inventory_api_service.dart';

int _toInt(dynamic value, {int defaultValue = 0}) {
  // make api value into int
  if (value is num) {
    return value.toInt();
  }
  return int.tryParse(value?.toString() ?? '') ?? defaultValue;
}

Map<String, dynamic> _supplierToMap(Supplier supplier) {
  // make supplier map for ui
  return {
    'supplier_id': supplier.supplierId,
    'supplier_name': supplier.supplierName,
    'address': supplier.address,
    'contact_info': supplier.contactInfo,
    'lead_time_days': supplier.leadTimeDays,
    'created_by': supplier.createdBy,
  };
}

String _displayStatus(String? status) {
  // show simple status text
  switch ((status ?? '').toUpperCase()) {
    case 'LOW_STOCK':
      return 'Low Stock';
    case 'OVERSTOCK':
      return 'High Stock';
    case 'DISCONTINUED':
      return 'Discontinued';
    default:
      return 'In Stock';
  }
}

class ProductController {
  final InventoryApiService _api = InventoryApiService();

  Future<List<Map<String, dynamic>>> fetchProducts({String? search}) async {
    // load products and supplier data
    final products = await _api.listProducts(search: search);
    final suppliers = await fetchSuppliers();
    final supplierById = <int, Supplier>{
      for (final supplier in suppliers) supplier.supplierId: supplier,
    };

    return products.map((product) {
      final supplierId = _toInt(product['supplier_id']);
      final supplier = supplierById[supplierId];
      return {
        'product_id': _toInt(product['id'] ?? product['product_id']),
        'supplier_id': supplierId,
        'product_name': product['name']?.toString() ?? '',
        'product_code': product['product_code']?.toString() ?? '',
        'sku': product['sku']?.toString() ?? '',
        'unit_cost': product['unit_cost'],
        'current_qty': _toInt(product['current_qty']),
        'reorder_point': _toInt(product['reorder_level']),
        'safety_stock': _toInt(product['overstock_level']),
        'serial_no': product['serial_no'],
        'lead_time_days': _toInt(product['lead_time_days']),
        'holding_cost': double.tryParse((product['holding_cost'] ?? 0).toString()) ?? 0.0,
        'ordering_cost': double.tryParse((product['ordering_cost'] ?? 0).toString()) ?? 0.0,
        'status_flag': _displayStatus(product['status_flag']?.toString()),
        'supplier': supplier == null
            ? {'supplier_id': supplierId, 'supplier_name': 'Unknown'}
            : _supplierToMap(supplier),
      };
    }).toList();
  }

  Future<List<String>> fetchSearchSuggestions(String query) async {
    // get search hints from api
    return await _api.getProductSuggestions(query);
  }

  Future<void> addProduct(
    Product product,
    int roleId, {
    int? actorUserId,
  }) async {
    // send new product to api
    await _api.createProduct({
      'product_code': product.productCode,
      'sku': product.sku,
      'name': product.productName,
      'supplier_id': product.supplierId,
      'current_qty': product.currentQty,
      'reorder_level': product.reorderPoint,
      'overstock_level': product.safetyStock < product.reorderPoint
          ? product.reorderPoint
          : product.safetyStock,
      'unit_cost': product.unitCost,
      'serial_no': product.serialNo != null ? int.tryParse(product.serialNo!) : null,
      'holding_cost': product.holdingCost,
      'ordering_cost': product.orderingCost,
      'lead_time_days': product.leadTimeDays,
    });
  }

  Future<void> updateProduct(
    Product product,
    int roleId, {
    int? actorUserId,
  }) async {
    // send edited product to api
    await _api.updateProduct(product.productId, {
      'product_code': product.productCode,
      'sku': product.sku,
      'name': product.productName,
      'supplier_id': product.supplierId,
      'current_qty': product.currentQty,
      'reorder_level': product.reorderPoint,
      'overstock_level': product.safetyStock < product.reorderPoint
          ? product.reorderPoint
          : product.safetyStock,
      'unit_cost': product.unitCost,
      'serial_no': product.serialNo != null ? int.tryParse(product.serialNo!) : null,
      'holding_cost': product.holdingCost,
      'ordering_cost': product.orderingCost,
      'lead_time_days': product.leadTimeDays,
    });
  }

  Future<void> deleteProduct(
    int productId,
    int roleId, {
    int? actorUserId,
  }) async {
    // delete product from api
    await _api.deleteProduct(productId);
  }

  Future<List<Supplier>> fetchSuppliers() async {
    // load suppliers from api
    final response = await _api.listSuppliers();
    return response.map((json) => Supplier.fromJson(json)).toList();
  }
}
