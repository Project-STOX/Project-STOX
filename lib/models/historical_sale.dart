class HistoricalSale {
  final int saleId;
  final int productId;
  final String productName;
  final String? productCode;
  final DateTime saleDate;
  final int quantitySold;
  final double revenue;
  final String? supplier;

  HistoricalSale({
    required this.saleId,
    required this.productId,
    required this.productName,
    this.productCode,
    required this.saleDate,
    required this.quantitySold,
    required this.revenue,
    this.supplier,
  });

  factory HistoricalSale.fromJson(Map<String, dynamic> json) {
    int parseInt(dynamic value) {
      if (value is num) {
        return value.toInt();
      }
      return int.tryParse(value?.toString() ?? '') ?? 0;
    }

    final productData = (json['product'] as Map?)?.cast<String, dynamic>() ?? const {};
    final supplierData = (productData['supplier'] as Map?)?.cast<String, dynamic>() ?? const {};

    return HistoricalSale(
      saleId: parseInt(json['sale_id'] ?? json['id']),
      productId: parseInt(json['product_id']),
      productName: productData['product_name']?.toString() ?? 'Unknown',
      productCode: productData['product_code']?.toString(),
      saleDate: DateTime.parse(json['sale_date'].toString()),
      quantitySold: parseInt(json['quantity_sold']),
      revenue: double.tryParse((json['revenue'] ?? 0).toString()) ?? 0,
      supplier: supplierData['supplier_name']?.toString(),
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'sale_id': saleId,
      'product_name': productName,
      'product_code': productCode,
      'sale_date': saleDate.toIso8601String(),
      'quantity_sold': quantitySold,
      'revenue': revenue,
      'supplier': supplier,
    };
  }
}
