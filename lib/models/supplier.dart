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
    int? intValue(dynamic value) {
      if (value is num) {
        return value.toInt();
      }
      return int.tryParse(value?.toString() ?? '');
    }

    final contactInfo = (json['contact_info']?.toString().isNotEmpty ?? false)
        ? json['contact_info']?.toString()
        : (json['phone']?.toString().isNotEmpty ?? false)
            ? json['phone']?.toString()
            : json['email']?.toString();

    return Supplier(
      supplierId: intValue(json['supplier_id'] ?? json['id']) ?? 0,
      supplierName: (json['supplier_name'] ?? json['name'] ?? '').toString(),
      address: json['address']?.toString(),
      contactInfo: contactInfo,
      leadTimeDays: intValue(json['lead_time_days']),
      createdBy: intValue(json['created_by']),
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
