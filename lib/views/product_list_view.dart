import 'package:flutter/material.dart';
import '../controllers/product_controller.dart';
import '../models/product.dart';

class ProductListView extends StatefulWidget {
  const ProductListView({super.key});

  @override
  _ProductListViewState createState() => _ProductListViewState();
}

class _ProductListViewState extends State<ProductListView> {
  final ProductController controller = ProductController();
  List<Product> products = [];

  // Initialize state and load products when widget is created
  @override
  void initState() {
    super.initState();
    loadProducts();
  }

  // Fetch products from controller and update the state
  void loadProducts() async {
    try {
      final data = await controller.fetchProducts();
      if (!mounted) return;
      setState(() => products = data.map((map) => Product.fromJson(map)).toList());
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Error loading products: $e')),
      );
    }
  }

  // Build the product list UI with a scaffold and list view
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text("Products")),
      body: ListView.builder(
        itemCount: products.length,
        itemBuilder: (context, index) {
          final product = products[index];
          return ListTile(
            title: Text(product.productName),
            subtitle: Text("Qty: ${product.currentQty}, Cost: ${product.unitCost}"),
          );
        },
      ),
    );
  }
}
