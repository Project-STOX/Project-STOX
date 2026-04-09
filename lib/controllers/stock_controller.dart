import '../models/product.dart';
import '../models/stock_receipt.dart';
import '../models/supplier.dart';
import '../services/api/inventory_api_service.dart';
import 'auth_controller.dart';

int _toInt(dynamic value, {int defaultValue = 0}) {
  if (value is num) {
    return value.toInt();
  }
  return int.tryParse(value?.toString() ?? '') ?? defaultValue;
}

String _displayStatus(String? status) {
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

Map<String, dynamic> _supplierMap(Supplier supplier) {
  return {
    'supplier_id': supplier.supplierId,
    'supplier_name': supplier.supplierName,
    'address': supplier.address,
    'contact_info': supplier.contactInfo,
    'lead_time_days': supplier.leadTimeDays,
    'created_by': supplier.createdBy,
  };
}

class StockController {
  final InventoryApiService _api = InventoryApiService();
  final AuthController authController = AuthController();

  Future<void> ensureStockReceiptPermission() async {
    return;
  }

  Future<List<Product>> fetchProducts() async {
    final response = await _api.listProducts();
    return response
        .map(
          (json) => Product.fromJson({
            'product_id': _toInt(json['id'] ?? json['product_id']),
            'supplier_id': _toInt(json['supplier_id']),
            'product_name': json['name']?.toString() ?? '',
            'sku': json['sku']?.toString() ?? '',
            'unit_cost': json['unit_cost'],
            'current_qty': _toInt(json['current_qty']),
            'reorder_point': _toInt(json['reorder_level']),
            'safety_stock': _toInt(json['overstock_level']),
            'serial_no': json['serial_no'],
            'status_flag': _displayStatus(json['status_flag']?.toString()),
          }),
        )
        .toList();
  }

  Future<List<Supplier>> fetchSuppliers() async {
    final response = await _api.listSuppliers();
    return response.map((json) => Supplier.fromJson(json)).toList();
  }

  Future<List<StockReceipt>> fetchStockReceipts({String? searchQuery}) async {
    final response = await _api.listStockReceipts();
    final products = await fetchProducts();
    final suppliers = await fetchSuppliers();
    final productById = <int, Product>{
      for (final product in products) product.productId: product,
    };
    final supplierById = <int, Supplier>{
      for (final supplier in suppliers) supplier.supplierId: supplier,
    };

    var receipts = response.map((json) {
      final productId = _toInt(json['product_id']);
      final supplierId = _toInt(json['supplier_id']);
      final product = productById[productId];
      final supplier = supplierById[supplierId];
      return StockReceipt.fromJson({
        'receipt_id': _toInt(json['id'] ?? json['receipt_id']),
        'product_id': productId,
        'supplier_id': supplierId,
        'recorded_by': _toInt(json['recorded_by']),
        'recorded_by_username': json['recorded_by_username']?.toString(),
        'quantity_received': _toInt(json['quantity']),
        'quantity_damaged': _toInt(json['quantity_damaged']),
        'receipt_date': json['received_at']?.toString() ?? json['receipt_date']?.toString(),
        'notes': json['reference_no']?.toString(),
        'product': product == null
            ? {
                'product_name': '',
                'sku': '',
                'serial_no': null,
              }
            : {
                'product_name': product.productName,
                'sku': product.sku,
                'serial_no': product.serialNo,
              },
        'supplier': supplier == null ? {'supplier_name': ''} : _supplierMap(supplier),
        'user': const <String, dynamic>{},
      });
    }).toList();

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
    await _api.createStockReceipt({
      'product_id': receipt.productId,
      'supplier_id': receipt.supplierId,
      'quantity': receipt.quantityReceived,
      'quantity_damaged': receipt.quantityDamaged,
      'unit_cost': 0,
      'reference_no': receipt.notes,
      'received_at': receipt.receiptDate.toIso8601String(),
    });
  }

  Future<void> updateStockReceipt(StockReceipt receipt, int roleId) async {
    await _api.updateStockReceipt(receipt.stockReceiptId, {
      'product_id': receipt.productId,
      'supplier_id': receipt.supplierId,
      'quantity': receipt.quantityReceived,
      'quantity_damaged': receipt.quantityDamaged,
      'unit_cost': 0,
      'reference_no': receipt.notes,
      'received_at': receipt.receiptDate.toIso8601String(),
    });
  }

  Future<void> deleteStockReceipt(
    int stockReceiptId,
    int roleId, {
    int? actorUserId,
  }) async {
    await _api.deleteStockReceipt(stockReceiptId);
  }

  Future<int> quickCreateProduct({
    required String productName,
    required String sku,
    required int supplierId,
    String? serialNo,
    int? actorUserId,
  }) async {
    final response = await _api.createProduct({
      'sku': sku,
      'name': productName,
      'supplier_id': supplierId,
      'current_qty': 0,
      'reorder_level': 0,
      'overstock_level': 0,
      'unit_cost': 0,
      'serial_no': serialNo != null ? int.tryParse(serialNo) : null,
    });

    return _toInt(response['id'] ?? response['product_id']);
  }

  Future<int> quickCreateSupplier({
    required String supplierName,
    int? createdByUserId,
    String? address,
    String? contactInfo,
    int? leadTimeDays,
  }) async {
    final response = await _api.createSupplier({
      'name': supplierName,
      'email': contactInfo != null && contactInfo.contains('@') ? contactInfo : null,
      'phone': contactInfo != null && !contactInfo.contains('@') ? contactInfo : null,
      'is_active': true,
    });

    return _toInt(response['id'] ?? response['supplier_id']);
  }
}
