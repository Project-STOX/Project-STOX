import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import 'package:mobile_scanner/mobile_scanner.dart';
import 'package:dropdown_search/dropdown_search.dart';
import '../models/product.dart';
import '../models/supplier.dart';

class ProductDetailPage extends StatefulWidget {
  final Product? product;
  final List<Supplier> suppliers;
  final int roleId;
  final Function(Product) onSave;
  final Function()? onDelete;

  const ProductDetailPage({
    super.key,
    this.product,
    required this.suppliers,
    required this.roleId,
    required this.onSave,
    this.onDelete,
  });

  @override
  _ProductDetailPageState createState() => _ProductDetailPageState();
}

class _ProductDetailPageState extends State<ProductDetailPage> {
  late TextEditingController nameController;
  late TextEditingController skuController;
  late TextEditingController costController;
  late TextEditingController qtyController;
  late TextEditingController reorderController;
  late TextEditingController serialController;
  late String status;
  late int selectedSupplierId;

  final List<String> statusOptions = ['Low Stock', 'In Stock', 'High Stock', 'Discontinued'];

  @override
  void initState() {
    super.initState();
    final product = widget.product;
    if (product != null) {
      nameController = TextEditingController(text: product.productName);
      skuController = TextEditingController(text: product.sku);
      costController = TextEditingController(text: product.unitCost.toString());
      qtyController = TextEditingController(text: product.currentQty.toString());
      reorderController = TextEditingController(text: product.reorderPoint.toString());
      serialController = TextEditingController(text: product.serialNo ?? '');
      status = product.statusFlag;
      selectedSupplierId = product.supplierId;
    } else {
      nameController = TextEditingController();
      skuController = TextEditingController();
      costController = TextEditingController();
      qtyController = TextEditingController();
      reorderController = TextEditingController();
      serialController = TextEditingController();
      status = 'In Stock';
      selectedSupplierId = widget.suppliers.isNotEmpty ? widget.suppliers.first.supplierId : 0;
    }
  }

  void _scanSerial() async {
    final result = await Navigator.push(
      context,
      MaterialPageRoute(builder: (context) => const BarcodeScannerView()),
    );
    if (result != null) {
      setState(() => serialController.text = result);
    }
  }

  void _save() {
    try {
      final updated = Product(
        productId: widget.product?.productId ?? 0,
        supplierId: selectedSupplierId,
        productName: nameController.text,
        sku: skuController.text,
        unitCost: double.parse(costController.text),
        currentQty: int.parse(qtyController.text),
        reorderPoint: int.parse(reorderController.text),
        serialNo: serialController.text.isEmpty ? null : serialController.text,
        statusFlag: status,
      );
      widget.onSave(updated);
      Navigator.pop(context);
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Error saving: $e')));
    }
  }

  void _delete() {
    if (widget.onDelete != null) {
      widget.onDelete!();
      Navigator.pop(context);
    }
  }

  @override
  Widget build(BuildContext context) {
    final isNew = widget.product == null;
    return Scaffold(
      appBar: AppBar(
        title: Text(isNew ? 'Create Product' : 'Edit Product'),
        actions: [
          if (!isNew)
            IconButton(
              icon: const Icon(Icons.delete, color: Colors.red),
              onPressed: _delete,
            ),
          IconButton(
            icon: const Icon(Icons.save),
            onPressed: _save,
          ),
        ],
      ),
      body: Padding(
        padding: const EdgeInsets.all(16.0),
        child: SingleChildScrollView(
          child: Column(
            children: [
              TextField(
                controller: nameController,
                decoration: const InputDecoration(labelText: 'Product Name'),
              ),
              TextField(
                controller: skuController,
                decoration: const InputDecoration(labelText: 'SKU'),
              ),
              TextField(
                controller: costController,
                decoration: const InputDecoration(labelText: 'Unit Cost'),
                keyboardType: TextInputType.number,
              ),
              TextField(
                controller: qtyController,
                decoration: const InputDecoration(labelText: 'Current Qty'),
                keyboardType: TextInputType.number,
              ),
              TextField(
                controller: reorderController,
                decoration: const InputDecoration(labelText: 'Reorder Point'),
                keyboardType: TextInputType.number,
              ),
              Row(
                children: [
                  Expanded(
                    child: TextField(
                      controller: serialController,
                      decoration: const InputDecoration(labelText: 'Serial No'),
                    ),
                  ),
                  if (!kIsWeb)
                    IconButton(
                      icon: const Icon(Icons.camera),
                      onPressed: _scanSerial,
                      tooltip: 'Scan with Camera',
                    ),
                ],
              ),
              DropdownButton<String>(
                value: status,
                items: statusOptions.map((s) => DropdownMenuItem(value: s, child: Text(s))).toList(),
                onChanged: (value) => setState(() => status = value!),
                isExpanded: true,
              ),
              DropdownSearch<Supplier>(
                popupProps: PopupProps.menu(
                  showSearchBox: true,
                  searchFieldProps: TextFieldProps(
                    decoration: InputDecoration(
                      labelText: 'Search Supplier',
                    ),
                  ),
                ),
                items: widget.suppliers,
                itemAsString: (Supplier s) => s.supplierName,
                selectedItem: widget.suppliers.isNotEmpty
                    ? widget.suppliers.firstWhere(
                        (s) => s.supplierId == selectedSupplierId,
                        orElse: () => widget.suppliers.first,
                      )
                    : null,
                onChanged: (Supplier? s) {
                  if (s != null) setState(() => selectedSupplierId = s.supplierId);
                },
                dropdownDecoratorProps: DropDownDecoratorProps(
                  dropdownSearchDecoration: InputDecoration(
                    labelText: 'Supplier',
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class BarcodeScannerView extends StatefulWidget {
  const BarcodeScannerView({super.key});

  @override
  _BarcodeScannerViewState createState() => _BarcodeScannerViewState();
}

class _BarcodeScannerViewState extends State<BarcodeScannerView> {
  MobileScannerController controller = MobileScannerController(
    formats: [BarcodeFormat.qrCode, BarcodeFormat.code128, BarcodeFormat.code39, BarcodeFormat.ean13, BarcodeFormat.ean8],
  );

  @override
  void dispose() {
    controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Scan Barcode/QR'),
        actions: [
          IconButton(
            icon: const Icon(Icons.flash_on),
            onPressed: () => controller.toggleTorch(),
          ),
          IconButton(
            icon: const Icon(Icons.close),
            onPressed: () => Navigator.pop(context),
          ),
        ],
      ),
      body: Column(
        children: [
          const Padding(
            padding: EdgeInsets.all(16.0),
            child: Text(
              'Point your camera at a barcode or QR code to scan the serial number.',
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 16),
            ),
          ),
          Expanded(
            child: MobileScanner(
              controller: controller,
              onDetect: (capture) {
                final List<Barcode> barcodes = capture.barcodes;
                if (barcodes.isNotEmpty && barcodes.first.rawValue != null) {
                  Navigator.pop(context, barcodes.first.rawValue);
                }
              },
            ),
          ),
        ],
      ),
    );
  }
}