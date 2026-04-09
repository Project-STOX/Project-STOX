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

    int? intValue(dynamic value) {
      if (value is num) {
      return value.toInt();
      }
      return int.tryParse(value?.toString() ?? '');
    }

    final receiptDateValue = json['receipt_date'] ?? json['received_at'];

    return StockReceipt(
      stockReceiptId:
        intValue(json['receipt_id'] ?? json['stock_receipt_id'] ?? json['id']) ??
        0,
      productId: intValue(json['product_id']) ?? 0,
      supplierId: intValue(json['supplier_id']) ?? 0,
      recordedBy: intValue(json['recorded_by']) ?? 0,
      quantityReceived: intValue(json['quantity_received'] ?? json['quantity']) ?? 0,
      quantityDamaged: intValue(json['quantity_damaged']) ?? 0,
      receiptDate: DateTime.parse(receiptDateValue.toString()),
      notes: json['notes']?.toString() ?? json['reference_no']?.toString(),
      productName:
        (productData['product_name'] ?? productData['name'] ?? json['product_name'])
          ?.toString(),
      productSku: (productData['sku'] ?? json['sku'])?.toString(),
      productSerialNo: productData['serial_no']?.toString(),
      supplierName:
          supplierData['supplier_name'] as String? ??
        supplierData['name'] as String? ??
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
