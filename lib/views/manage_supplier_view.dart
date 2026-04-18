import 'package:flutter/material.dart';
import '../controllers/supplier_controller.dart';
import '../controllers/auth_controller.dart';
import '../models/supplier.dart';
import 'supplier_detail_page.dart';

class ManageSuppliersView extends StatefulWidget {
  final int roleId;
  final int userId;
  final bool isEmbedded;
  const ManageSuppliersView({
    super.key,
    required this.roleId,
    required this.userId,
    this.isEmbedded = false,
  });

  @override
  _ManageSuppliersViewState createState() => _ManageSuppliersViewState();
}

class _ManageSuppliersViewState extends State<ManageSuppliersView> {
  final SupplierController controller = SupplierController();
  final AuthController authController = AuthController();
  List<Supplier> suppliers = [];
  List<Supplier> filteredSuppliers = [];
  String searchQuery = '';
  String? userRole;
  String selectedSort = 'Name (A-Z)';

  final List<String> sortOptions = [
    'Name (A-Z)',
    'Name (Z-A)',
    'Lead Time (Ascending)',
    'Lead Time (Descending)',
  ];

  @override
  void initState() {
    super.initState();
    _checkAccess();
  }

  Future<void> _checkAccess() async {
    userRole = await authController.getUserRole(widget.roleId);
    if (!mounted) return;

    loadSuppliers();
  }

  void loadSuppliers() async {
    try {
      final data = await controller.fetchSuppliers();
      if (!mounted) return;

      setState(() {
        suppliers = data;
        filteredSuppliers = data;
        _sortSuppliers();
      });
    } catch (e) {
      if (!mounted) return;

      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Error loading suppliers: $e')));
    }
  }

  void _filterSuppliers() {
    setState(() {
      final query = searchQuery.toLowerCase().trim();
      filteredSuppliers = suppliers.where((s) {
        if (query.isEmpty) return true;
        return s.supplierName.toLowerCase().contains(query) ||
            s.supplierId.toString().contains(query);
      }).toList();
      _applySorting();
    });
  }

  void _applySorting() {
    switch (selectedSort) {
      case 'Name (A-Z)':
        filteredSuppliers.sort(
          (a, b) => a.supplierName.compareTo(b.supplierName),
        );
        break;
      case 'Name (Z-A)':
        filteredSuppliers.sort(
          (a, b) => b.supplierName.compareTo(a.supplierName),
        );
        break;
      case 'Lead Time (Ascending)':
        filteredSuppliers.sort(
          (a, b) => (a.leadTimeDays ?? 0).compareTo(b.leadTimeDays ?? 0),
        );
        break;
      case 'Lead Time (Descending)':
        filteredSuppliers.sort(
          (a, b) => (b.leadTimeDays ?? 0).compareTo(a.leadTimeDays ?? 0),
        );
        break;
    }
  }

  void _sortSuppliers() {
    setState(() {
      _applySorting();
    });
  }

  void _showSupplierDetails(Supplier supplier) {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => SupplierDetailPage(
          supplier: supplier,
          roleId: widget.roleId,
          userId: widget.userId,
          onSave: (updatedSupplier) async {
            await controller.updateSupplier(
              updatedSupplier,
              widget.roleId,
              actorUserId: widget.userId,
            );
            loadSuppliers();
          },
          onDelete: () async {
            await controller.deleteSupplier(
              supplier.supplierId,
              widget.roleId,
              actorUserId: widget.userId,
            );
            loadSuppliers();
          },
        ),
      ),
    );
  }

  void _createSupplier() {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => SupplierDetailPage(
          supplier: null,
          roleId: widget.roleId,
          userId: widget.userId,
          onSave: (newSupplier) async {
            await controller.addSupplier(
              newSupplier,
              widget.roleId,
              widget.userId,
            );
            loadSuppliers();
          },
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (userRole == null) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }
    return Scaffold(
      appBar: widget.isEmbedded ? null : AppBar(title: const Text("Manage Suppliers")),
      floatingActionButton: FloatingActionButton(
        onPressed: _createSupplier,
        child: const Icon(Icons.add),
      ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.all(8.0),
            child: TextField(
              decoration: const InputDecoration(
                labelText: 'Search by Supplier Name or ID',
                prefixIcon: Icon(Icons.search),
              ),
              onChanged: (value) {
                searchQuery = value;
                _filterSuppliers();
              },
            ),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 8.0),
            child: DropdownButtonFormField<String>(
              initialValue: selectedSort,
              decoration: const InputDecoration(labelText: 'Sort by'),
              items: sortOptions
                  .map(
                    (sort) => DropdownMenuItem(value: sort, child: Text(sort)),
                  )
                  .toList(),
              onChanged: (value) {
                setState(() {
                  selectedSort = value!;
                  _applySorting();
                });
              },
            ),
          ),
          Expanded(
            child: ListView.builder(
              itemCount: filteredSuppliers.length,
              itemBuilder: (context, index) {
                final supplier = filteredSuppliers[index];
                return ListTile(
                  title: Text(supplier.supplierName),
                  subtitle: Text(
                    'Supplier ID: ${supplier.supplierId}, Address: ${supplier.address ?? 'N/A'}, Contact: ${supplier.contactInfo ?? 'N/A'}, Lead Time: ${supplier.leadTimeDays ?? 'N/A'} days',
                  ),
                  onTap: () => _showSupplierDetails(supplier),
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}
