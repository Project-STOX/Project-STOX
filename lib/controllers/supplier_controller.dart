import '../models/supplier.dart';
import '../services/api/inventory_api_service.dart';

Map<String, dynamic> _supplierPayload(Supplier supplier) {
  return {
    'name': supplier.supplierName,
    'email': supplier.contactInfo != null && supplier.contactInfo!.contains('@')
        ? supplier.contactInfo
        : null,
    'phone': supplier.contactInfo != null && !supplier.contactInfo!.contains('@')
        ? supplier.contactInfo
        : null,
    'address': supplier.address,
    'lead_time_days': supplier.leadTimeDays,
    'is_active': true,
  };
}

class SupplierController {
  final InventoryApiService _api = InventoryApiService();

  Future<List<Supplier>> fetchSuppliers() async {
    final response = await _api.listSuppliers();
    return response.map((json) => Supplier.fromJson(json)).toList();
  }

  Future<void> addSupplier(Supplier supplier, int roleId, int userId) async {
    await _api.createSupplier(_supplierPayload(supplier));
  }

  Future<void> updateSupplier(
    Supplier supplier,
    int roleId, {
    int? actorUserId,
  }) async {
    await _api.updateSupplier(supplier.supplierId, _supplierPayload(supplier));
  }

  Future<void> deleteSupplier(
    int supplierId,
    int roleId, {
    int? actorUserId,
  }) async {
    await _api.deleteSupplier(supplierId);
  }
}
