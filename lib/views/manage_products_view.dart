import 'dart:async';

import 'package:flutter/material.dart';
import '../controllers/product_controller.dart';
import '../models/product.dart';
import '../models/supplier.dart';
import 'product_detail_page.dart';

class ManageProductsView extends StatefulWidget {
  final int roleId;
  final int userId;
  final bool isEmbedded;

  const ManageProductsView({
    super.key,
    required this.roleId,
    required this.userId,
    this.isEmbedded = false,
  });

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
  Timer? _filterDebounce;

  @override
  void initState() {
    super.initState();
    loadProducts();
    loadSuppliers();
  }

  @override
  void dispose() {
    _filterDebounce?.cancel();
    super.dispose();
  }

  String _safeLower(dynamic value) {
    return value?.toString().toLowerCase() ?? '';
  }

  String _safeText(dynamic value, {String fallback = 'N/A'}) {
    final text = value?.toString().trim() ?? '';
    return text.isEmpty ? fallback : text;
  }

  void _scheduleFilter() {
    _filterDebounce?.cancel();
    _filterDebounce = Timer(const Duration(milliseconds: 500), () {
      loadProducts(search: searchQuery);
    });
  }

  void loadProducts({String? search}) async {
    try {
      final data = await controller.fetchProducts(search: search);
      if (!mounted) return;
      setState(() {
        products = data;
        _filterProductsLocal();
      });
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Error loading products: $e')));
    }
  }

  void loadSuppliers() async {
    try {
      final data = await controller.fetchSuppliers();
      if (!mounted) return;
      setState(() => suppliers = data);
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Error loading suppliers: $e')));
    }
  }

  void _filterProductsLocal() {
    if (!mounted) return;
    setState(() {
      filteredProducts = products.where((p) {
        final statusFlag = _safeText(p['status_flag'], fallback: 'In Stock');
        final matchesStatus =
            selectedStatus == 'All' || statusFlag == selectedStatus;
        return matchesStatus;
      }).toList();
      _sortProducts();
    });
  }

  void _sortProducts() {
    filteredProducts.sort(
      (a, b) =>
          _safeText(a['status_flag']).compareTo(_safeText(b['status_flag'])),
    );
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
            await controller.updateProduct(
              updatedProduct,
              widget.roleId,
              actorUserId: widget.userId,
            );
            loadProducts();
          },
          onDelete: () async {
            await controller.deleteProduct(
              productData['product_id'],
              widget.roleId,
              actorUserId: widget.userId,
            );
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
            await controller.addProduct(
              newProduct,
              widget.roleId,
              actorUserId: widget.userId,
            );
            loadProducts();
          },
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: widget.isEmbedded ? null : AppBar(title: const Text("Manage Products")),
      floatingActionButton: FloatingActionButton(
        onPressed: _createProduct,
        child: const Icon(Icons.add),
      ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.all(8.0),
            child: Autocomplete<String>(
              optionsBuilder: (TextEditingValue textEditingValue) async {
                if (textEditingValue.text.isEmpty) {
                  return const Iterable<String>.empty();
                }
                return await controller.fetchSearchSuggestions(textEditingValue.text);
              },
              onSelected: (String selection) {
                setState(() {
                  searchQuery = selection;
                });
                loadProducts(search: searchQuery);
              },
              fieldViewBuilder: (context, textController, focusNode, onFieldSubmitted) {
                return TextField(
                  controller: textController,
                  focusNode: focusNode,
                  decoration: const InputDecoration(
                    labelText: 'Search (Name, Serial, Code, SKU)',
                    prefixIcon: Icon(Icons.search),
                  ),
                  onChanged: (value) {
                    searchQuery = value;
                    _scheduleFilter();
                  },
                  onSubmitted: (value) {
                    searchQuery = value;
                    loadProducts(search: value);
                  },
                );
              },
            ),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 8.0),
            child: DropdownButtonFormField<String>(
              initialValue: selectedStatus,
              decoration: const InputDecoration(labelText: 'Filter by status'),
              items:
                  ['All', 'Low Stock', 'In Stock', 'High Stock', 'Discontinued']
                      .map(
                        (status) => DropdownMenuItem(
                          value: status,
                          child: Text(status),
                        ),
                      )
                      .toList(),
              onChanged: (value) {
                setState(() {
                  selectedStatus = value!;
                });
                _scheduleFilter();
              },
            ),
          ),
          Expanded(
            child: ListView.builder(
              itemCount: filteredProducts.length,
              itemBuilder: (context, index) {
                final data = filteredProducts[index];
                final productName = _safeText(
                  data['product_name'],
                  fallback: 'Unnamed Product',
                );
                final sku = _safeText(data['sku']);
                final productCode = _safeText(data['product_code']);
                final supplierName = _safeText(
                  (data['supplier'] as Map?)?['supplier_name'],
                  fallback: 'Unknown',
                );
                final serialNo = _safeText(data['serial_no']);
                final statusFlag = _safeText(
                  data['status_flag'],
                  fallback: 'In Stock',
                );
                return ListTile(
                  title: Text(productName),
                  subtitle: Text(
                    'Code: $productCode, SKU: $sku, Supplier: $supplierName, Serial: $serialNo, Status: $statusFlag',
                  ),
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
