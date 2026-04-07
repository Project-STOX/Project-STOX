class Product {
  final int productId;
  final int supplierId;
  final String productName;
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
    Map<String, dynamic>? reorderParameter;
    final relation = json['reorder_parameter'];
    if (relation is List && relation.isNotEmpty && relation.first is Map) {
      reorderParameter = relation.first as Map<String, dynamic>;
    } else if (relation is Map<String, dynamic>) {
      reorderParameter = relation;
    }

    return Product(
      productId: json['product_id'],
      supplierId: json['supplier_id'],
      productName: json['product_name'],
      sku: json['sku'],
      unitCost: double.parse(json['unit_cost'].toString()),
      currentQty: json['current_qty'],
      leadTimeDays:
          (json['lead_time_days'] as num?)?.toInt() ??
          (reorderParameter?['lead_time_days'] as num?)?.toInt(),
      safetyStock:
          (json['safety_stock'] as num?)?.toInt() ??
          (reorderParameter?['safety_stock'] as num?)?.toInt() ??
          0,
      reorderPoint: (json['reorder_point'] as num?)?.toInt() ?? 0,
      serialNo: json['serial_no']?.toString(),
      statusFlag: json['status_flag'] ?? 'In Stock',
    );
  }
}
