class Product {
  final int productId;
  final int supplierId;
  final String productName;
  final String sku;
  final double unitCost;
  final int currentQty;
  final int reorderPoint;

  Product({
    required this.productId,
    required this.supplierId,
    required this.productName,
    required this.sku,
    required this.unitCost,
    required this.currentQty,
    required this.reorderPoint,
  });

  factory Product.fromJson(Map<String, dynamic> json) {
    return Product(
      productId: json['product_id'],
      supplierId: json['supplier_id'],
      productName: json['product_name'],
      sku: json['sku'],
      unitCost: double.parse(json['unit_cost'].toString()),
      currentQty: json['current_qty'],
      reorderPoint: json['reorder_point'],
    );
  }
}
