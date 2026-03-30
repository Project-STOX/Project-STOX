class Supplier {
  final int supplierId;
  final String supplierName;
  final String? contactInfo;

  Supplier({
    required this.supplierId,
    required this.supplierName,
    this.contactInfo,
  });

  factory Supplier.fromJson(Map<String, dynamic> json) {
    return Supplier(
      supplierId: json['supplier_id'],
      supplierName: json['supplier_name'],
      contactInfo: json['contact_info'],
    );
  }
}
