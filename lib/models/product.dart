class Product {
  final int productId;
  final int supplierId;
  final String productName;
  final String productCode;
  final String sku;
  final double unitCost;
  final int currentQty;
  final int? leadTimeDays;
  final int safetyStock;
  final int reorderPoint;
  final String? serialNo;
  final String statusFlag;

  Product({
    required this.productId,
    required this.supplierId,
    required this.productName,
    required this.productCode,
    required this.sku,
    required this.unitCost,
    required this.currentQty,
    this.leadTimeDays,
    required this.safetyStock,
    required this.reorderPoint,
    this.serialNo,
    required this.statusFlag,
  });

  factory Product.fromJson(Map<String, dynamic> json) {
    Map<String, dynamic>? supplierData;
    final supplier = json['supplier'];
    if (supplier is List && supplier.isNotEmpty && supplier.first is Map) {
      supplierData = supplier.first as Map<String, dynamic>;
    } else if (supplier is Map<String, dynamic>) {
      supplierData = supplier;
    }

    Map<String, dynamic>? reorderParameter;
    final relation = json['reorder_parameter'];
    if (relation is List && relation.isNotEmpty && relation.first is Map) {
      reorderParameter = relation.first as Map<String, dynamic>;
    } else if (relation is Map<String, dynamic>) {
      reorderParameter = relation;
    }

    int? intValue(dynamic value) {
      if (value is num) {
        return value.toInt();
      }
      return int.tryParse(value?.toString() ?? '');
    }

    String statusValue = json['status_flag']?.toString() ?? 'In Stock';
    switch (statusValue.toUpperCase()) {
      case 'LOW_STOCK':
        statusValue = 'Low Stock';
        break;
      case 'OVERSTOCK':
        statusValue = 'High Stock';
        break;
      case 'DISCONTINUED':
        statusValue = 'Discontinued';
        break;
    }

    return Product(
      productId: intValue(json['product_id'] ?? json['id']) ?? 0,
      supplierId:
          intValue(json['supplier_id'] ?? supplierData?['supplier_id'] ?? supplierData?['id']) ??
          0,
      productName: (json['product_name'] ?? json['name'] ?? '').toString(),
      productCode: (json['product_code'] ?? '').toString(),
      sku: (json['sku'] ?? '').toString(),
      unitCost: double.tryParse((json['unit_cost'] ?? 0).toString()) ?? 0,
      currentQty: intValue(json['current_qty']) ?? 0,
      leadTimeDays:
          intValue(json['lead_time_days']) ??
          intValue(reorderParameter?['lead_time_days']) ??
          intValue(supplierData?['lead_time_days']),
      safetyStock:
          intValue(json['safety_stock']) ??
          intValue(json['overstock_level']) ??
          intValue(reorderParameter?['safety_stock']) ??
          0,
      reorderPoint: intValue(json['reorder_point'] ?? json['reorder_level']) ?? 0,
      serialNo: json['serial_no']?.toString(),
      statusFlag: statusValue,
    );
  }
}
