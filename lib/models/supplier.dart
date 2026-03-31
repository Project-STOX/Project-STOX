class Supplier {
  final int supplierId;
  final String supplierName;
  final String? address;
  final String? contactInfo;
  final int? leadTimeDays;
  final int? createdBy;

  Supplier({
    required this.supplierId,
    required this.supplierName,
    this.address,
    this.contactInfo,
    this.leadTimeDays,
    this.createdBy,
  });

  factory Supplier.fromJson(Map<String, dynamic> json) {
    return Supplier(
      supplierId: json['supplier_id'],
      supplierName: json['supplier_name'],
      address: json['address'],
      contactInfo: json['contact_info'],
      leadTimeDays: json['lead_time_days'],
      createdBy: json['created_by'],
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'supplier_id': supplierId,
      'supplier_name': supplierName,
      'address': address,
      'contact_info': contactInfo,
      'lead_time_days': leadTimeDays,
      'created_by': createdBy,
    };
  }
}
