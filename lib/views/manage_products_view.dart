import 'package:flutter/material.dart';
import '../controllers/product_controller.dart';
import '../models/product.dart';
import '../models/supplier.dart';
import 'product_detail_page.dart';

class ManageProductsView extends StatefulWidget {
  final int roleId;
  const ManageProductsView({super.key, required this.roleId});

  @override
  _ManageProductsViewState createState() => _ManageProductsViewState();
}

class _ManageProductsViewState extends State<ManageProductsView> {
  final ProductController controller = ProductController();
  List<Map<String, dynamic>> products = [];
  List<Map<String, dynamic>> filteredProducts = [];
  String searchQuery = '';
  List<Supplier> suppliers = [];
  String selectedStatus = 'All';

  @override
  void initState() {
    super.initState();
    loadProducts();
    loadSuppliers();
  }

  void loadProducts() async {
    try {
      final data = await controller.fetchProducts();
      setState(() {
        products = data;
        filteredProducts = data;
        _sortProducts();
      });
    } catch (e) {
      // Handle error, perhaps show snackbar
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Error loading products: $e')));
    }
  }

  void loadSuppliers() async {
    try {
      final data = await controller.fetchSuppliers();
      setState(() => suppliers = data);
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Error loading suppliers: $e')));
    }
  }

  void _filterProducts() {
    setState(() {
      filteredProducts = products.where((p) {
        final query = searchQuery.toLowerCase().trim();
        final matchesSearch = p['product_name'].toLowerCase().contains(query) ||
               p['sku'].toLowerCase().contains(query) ||
               (p['supplier'] != null && p['supplier']['supplier_name'].toLowerCase().contains(query)) ||
               (p['serial_no'] != null && p['serial_no'].toString().toLowerCase().contains(query));
        final matchesStatus = selectedStatus == 'All' || p['status_flag'] == selectedStatus;
        return matchesSearch && matchesStatus;
      }).toList();
      _sortProducts();
    });
  }

  void _sortProducts() {
    filteredProducts.sort((a, b) => a['status_flag'].compareTo(b['status_flag']));
  }

  void _showProductDetails(Map<String, dynamic> productData) {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => ProductDetailPage(
          product: Product.fromJson(productData),
          suppliers: suppliers,
          roleId: widget.roleId,
          onSave: (updatedProduct) async {
            await controller.updateProduct(updatedProduct, widget.roleId);
            loadProducts();
          },
          onDelete: () async {
            await controller.deleteProduct(productData['product_id'], widget.roleId);
            loadProducts();
          },
        ),
      ),
    );
  }

  void _createProduct() {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => ProductDetailPage(
          product: null,
          suppliers: suppliers,
          roleId: widget.roleId,
          onSave: (newProduct) async {
            await controller.addProduct(newProduct, widget.roleId);
            loadProducts();
          },
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text("Manage Products")),
      floatingActionButton: FloatingActionButton(
        onPressed: _createProduct,
        child: const Icon(Icons.add),
      ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.all(8.0),
            child: TextField(
              decoration: const InputDecoration(
                labelText: 'Search',
                prefixIcon: Icon(Icons.search),
              ),
              onChanged: (value) {
                searchQuery = value;
                _filterProducts();
              },
            ),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 8.0),
            child: DropdownButton<String>(
              value: selectedStatus,
              items: ['All', 'Low Stock', 'In Stock', 'High Stock', 'Discontinued'].map((status) => DropdownMenuItem(
                value: status,
                child: Text('Filter by: $status'),
              )).toList(),
              onChanged: (value) {
                setState(() {
                  selectedStatus = value!;
                  _filterProducts();
                });
              },
              isExpanded: true,
            ),
          ),
          Expanded(
            child: ListView.builder(
              itemCount: filteredProducts.length,
              itemBuilder: (context, index) {
                final data = filteredProducts[index];
                return ListTile(
                  title: Text(data['product_name']),
                  subtitle: Text('SKU: ${data['sku']}, Supplier: ${data['supplier']?['supplier_name'] ?? 'Unknown'}, Serial: ${data['serial_no'] ?? 'N/A'}, Status: ${data['status_flag']}'),
                  onTap: () => _showProductDetails(data),
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}