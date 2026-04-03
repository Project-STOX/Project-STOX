class StockReceipt {
  final int stockReceiptId;
  final int productId;
  final int supplierId;
  final int recordedBy;
  final int quantityReceived;
  final int quantityDamaged;
  final DateTime receiptDate;
  final String? notes;
  final String? productName;
  final String? productSku;
  final String? productSerialNo;
  final String? supplierName;
  final String? recordedByUsername;

  StockReceipt({
    required this.stockReceiptId,
    required this.productId,
    required this.supplierId,
    required this.recordedBy,
    required this.quantityReceived,
    required this.quantityDamaged,
    required this.receiptDate,
    this.notes,
    this.productName,
    this.productSku,
    this.productSerialNo,
    this.supplierName,
    this.recordedByUsername,
  });

  factory StockReceipt.fromJson(Map<String, dynamic> json) {
    final productData =
        (json['product'] as Map?)?.cast<String, dynamic>() ?? const {};
    final supplierData =
        (json['supplier'] as Map?)?.cast<String, dynamic>() ?? const {};
    final userData =
        (json['user'] as Map?)?.cast<String, dynamic>() ?? const {};

    return StockReceipt(
      stockReceiptId:
          ((json['receipt_id'] ?? json['stock_receipt_id']) as num?)?.toInt() ??
          0,
      productId: (json['product_id'] as num?)?.toInt() ?? 0,
      supplierId: (json['supplier_id'] as num?)?.toInt() ?? 0,
      recordedBy: (json['recorded_by'] as num?)?.toInt() ?? 0,
      quantityReceived: (json['quantity_received'] as num?)?.toInt() ?? 0,
      quantityDamaged: (json['quantity_damaged'] as num?)?.toInt() ?? 0,
      receiptDate: DateTime.parse(json['receipt_date'].toString()),
      notes: json['notes']?.toString(),
      productName: productData['product_name'] as String?,
      productSku: productData['sku'] as String?,
      productSerialNo: productData['serial_no']?.toString(),
      supplierName:
          supplierData['supplier_name'] as String? ??
          json['supplier_name'] as String?,
      recordedByUsername:
          userData['username'] as String? ??
          json['recorded_by_username'] as String?,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'receipt_id': stockReceiptId,
      'product_id': productId,
      'supplier_id': supplierId,
      'recorded_by': recordedBy,
      'quantity_received': quantityReceived,
      'quantity_damaged': quantityDamaged,
      'receipt_date': receiptDate.toIso8601String(),
      'notes': notes,
    };
  }
}
