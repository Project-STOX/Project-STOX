class HistoricalSale {
  final int saleId;
  final int productId;
  final String productName;
  final DateTime saleDate;
  final int quantitySold;
  final double revenue;
  final String? supplier;

  HistoricalSale({
    required this.saleId,
    required this.productId,
    required this.productName,
    required this.saleDate,
    required this.quantitySold,
    required this.revenue,
    this.supplier,
  });

  factory HistoricalSale.fromJson(Map<String, dynamic> json) {
    final productData = json['product'] ?? {};
    final supplierData = productData['supplier'] ?? {};

    return HistoricalSale(
      saleId: json['sale_id'] as int,
      productId: json['product_id'] as int,
      productName: productData['product_name'] as String? ?? 'Unknown',
      saleDate: DateTime.parse(json['sale_date'].toString()),
      quantitySold: json['quantity_sold'] as int,
      // Handle numeric variations safely
      revenue: (json['revenue'] ?? 0).toDouble(),
      supplier: supplierData['supplier_name'] as String?,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'sale_id': saleId,
      'product_name': productName,
      'sale_date': saleDate.toIso8601String(),
      'quantity_sold': quantitySold,
      'revenue': revenue,
      'supplier': supplier,
    };
  }
}
