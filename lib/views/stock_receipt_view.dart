import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:mobile_scanner/mobile_scanner.dart';

import '../controllers/stock_controller.dart';
import '../models/product.dart';
import '../models/stock_receipt.dart';
import '../models/supplier.dart';
import '../models/user.dart';

class StockReceiptView extends StatefulWidget {
  final UserModel user;
  final bool isEmbedded;

  const StockReceiptView({super.key, required this.user, this.isEmbedded = false});

  @override
  State<StockReceiptView> createState() => _StockReceiptViewState();
}

class _StockReceiptViewState extends State<StockReceiptView> {
  final StockController _controller = StockController();
  final _searchController = TextEditingController();
  final _notesController = TextEditingController();
  final _quantityReceivedController = TextEditingController(text: '0');
  final _quantityDamagedController = TextEditingController(text: '0');
  final _receiptDateController = TextEditingController();
  final _productAutocompleteController = TextEditingController();
  final _supplierAutocompleteController = TextEditingController();

  List<Product> _products = [];
  List<Supplier> _suppliers = [];
  List<StockReceipt> _receipts = [];
  Product? _selectedProduct;
  Supplier? _selectedSupplier;
  StockReceipt? _editingReceipt;
  DateTime _receiptDate = DateTime.now();
  bool _isLoading = true;
  bool _isSearching = false;
  bool _isAuthorized = false;
  Timer? _searchDebounce;

  @override
  void initState() {
    super.initState();
    _receiptDateController.text = _formatDateTime(_receiptDate);
    _bootstrap();
  }

  @override
  void dispose() {
    _searchDebounce?.cancel();
    _searchController.dispose();
    _notesController.dispose();
    _quantityReceivedController.dispose();
    _quantityDamagedController.dispose();
    _receiptDateController.dispose();
    _productAutocompleteController.dispose();
    _supplierAutocompleteController.dispose();
    super.dispose();
  }

  String _formatDateTime(DateTime value) {
    return DateFormat('yyyy-MM-dd HH:mm').format(value);
  }

  Supplier? _recommendedSupplierForProduct(Product? product) {
    if (product == null) {
      return null;
    }

    try {
      return _suppliers.firstWhere(
        (supplier) => supplier.supplierId == product.supplierId,
      );
    } catch (_) {
      return null;
    }
  }

  Product? _findProductById(int productId) {
    for (final product in _products) {
      if (product.productId == productId) {
        return product;
      }
    }
    return null;
  }

  Supplier? _findSupplierById(int supplierId) {
    for (final supplier in _suppliers) {
      if (supplier.supplierId == supplierId) {
        return supplier;
      }
    }
    return null;
  }

  String _receiptTitle(StockReceipt receipt) {
    return 'Receipt ID: ${receipt.stockReceiptId}';
  }

  String _receiptSubtitle(StockReceipt receipt) {
    return 'Receipt Date: ${_formatDateTime(receipt.receiptDate)}\n'
        'Product: ${receipt.productName ?? '-'} | SKU: ${receipt.productSku ?? '-'}\n'
      'Supplier: ${receipt.supplierId} - ${receipt.supplierName ?? '-'}\n'
        'Received: ${receipt.quantityReceived} | Damaged: ${receipt.quantityDamaged} | By: ${receipt.recordedByUsername ?? 'Deleted User (ID: ${receipt.recordedBy})'}';
  }

  String _productDisplay(Product product) {
    return '${product.productName} | SKU: ${product.sku} | Supplier ID: ${product.supplierId}${product.serialNo != null ? ' | SN: ${product.serialNo}' : ''}';
  }

  String _supplierDisplay(Supplier supplier) {
    return 'ID: ${supplier.supplierId} | ${supplier.supplierName}';
  }

  void _syncAutocompleteFields() {
    final productText = _selectedProduct == null
        ? ''
        : _productDisplay(_selectedProduct!);
    if (_productAutocompleteController.text != productText) {
      _productAutocompleteController.text = productText;
      _productAutocompleteController.selection = TextSelection.collapsed(
        offset: productText.length,
      );
    }

    final supplierText = _selectedSupplier == null
        ? ''
        : _supplierDisplay(_selectedSupplier!);
    if (_supplierAutocompleteController.text != supplierText) {
      _supplierAutocompleteController.text = supplierText;
      _supplierAutocompleteController.selection = TextSelection.collapsed(
        offset: supplierText.length,
      );
    }
  }

  Widget _buildReceiptForm({required bool isCreating}) {
    final recommendedSupplier = _recommendedSupplierForProduct(
      _selectedProduct,
    );
    final recommendedSupplierText = _selectedProduct == null
        ? 'No product selected'
        : recommendedSupplier == null
        ? '${_selectedProduct!.supplierId} - Supplier not loaded'
        : '${recommendedSupplier.supplierId} - ${recommendedSupplier.supplierName}';

    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          isCreating ? 'Create Stock Receipt' : 'Edit Stock Receipt',
          style: Theme.of(context).textTheme.titleMedium,
        ),
        const SizedBox(height: 12),
        DropdownButtonFormField<Product>(
          initialValue: _selectedProduct,
          isExpanded: true,
          decoration: const InputDecoration(
            labelText: 'Product',
            prefixIcon: Icon(Icons.inventory_2),
          ),
          items: _products
              .map(
                (product) => DropdownMenuItem<Product>(
                  value: product,
                  child: Text(_productDisplay(product)),
                ),
              )
              .toList(),
          onChanged: (product) async {
            if (product == null) {
              return;
            }
            await _selectProduct(product);
          },
          hint: const Text('Select product'),
        ),
        const SizedBox(height: 8),
        if (_selectedProduct != null)
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: Theme.of(context).colorScheme.surfaceContainerHighest,
              borderRadius: BorderRadius.circular(12),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Recommended supplier: $recommendedSupplierText'),
                const SizedBox(height: 4),
                Text(
                  'This supplier comes from the selected product\'s supplier_id and can still be changed below.',
                ),
              ],
            ),
          ),
        Align(
          alignment: Alignment.centerLeft,
          child: TextButton.icon(
            onPressed: _quickAddProduct,
            icon: const Icon(Icons.add),
            label: const Text('Add new product'),
          ),
        ),
        const SizedBox(height: 8),
        DropdownButtonFormField<Supplier>(
          initialValue: _selectedSupplier,
          isExpanded: true,
          decoration: const InputDecoration(
            labelText: 'Supplier',
            prefixIcon: Icon(Icons.business),
          ),
          items: _suppliers
              .map(
                (supplier) => DropdownMenuItem<Supplier>(
                  value: supplier,
                  child: Text(_supplierDisplay(supplier)),
                ),
              )
              .toList(),
          onChanged: _selectSupplier,
          selectedItemBuilder: (context) {
            return _suppliers
                .map(
                  (supplier) => Align(
                    alignment: Alignment.centerLeft,
                    child: Text(_supplierDisplay(supplier)),
                  ),
                )
                .toList();
          },
          hint: const Text('Search and select a supplier from the list'),
        ),
        Align(
          alignment: Alignment.centerLeft,
          child: TextButton.icon(
            onPressed: _quickAddSupplier,
            icon: const Icon(Icons.add_business),
            label: const Text('Add new supplier'),
          ),
        ),
        const SizedBox(height: 8),
        Row(
          children: [
            Expanded(
              child: TextField(
                controller: _receiptDateController,
                readOnly: true,
                decoration: const InputDecoration(labelText: 'Receipt date'),
                onTap: _pickReceiptDate,
              ),
            ),
            IconButton(
              icon: const Icon(Icons.edit_calendar),
              onPressed: _pickReceiptDate,
            ),
          ],
        ),
        const SizedBox(height: 8),
        _buildQuantityStepper(
          label: 'Quantity received',
          controller: _quantityReceivedController,
          onPlus: _incrementQuantityReceived,
          onMinus: _decrementQuantityReceived,
        ),
        const SizedBox(height: 8),
        Row(
          children: [
            Expanded(
              child: TextField(
                controller: _quantityDamagedController,
                keyboardType: TextInputType.number,
                decoration: const InputDecoration(
                  labelText: 'Quantity damaged',
                ),
              ),
            ),
            IconButton(
              onPressed: _decrementDamaged,
              icon: const Icon(Icons.remove_circle_outline),
            ),
            IconButton(
              onPressed: _incrementDamaged,
              icon: const Icon(Icons.add_circle_outline),
            ),
          ],
        ),
        const SizedBox(height: 8),
        TextField(
          controller: _notesController,
          maxLines: 4,
          decoration: const InputDecoration(
            labelText: 'Notes',
            alignLabelWithHint: true,
            border: OutlineInputBorder(),
          ),
        ),
        const SizedBox(height: 12),
        if (!kIsWeb)
          Row(
            children: [
              Expanded(
                child: ElevatedButton.icon(
                  onPressed: _scanSerial,
                  icon: const Icon(Icons.qr_code_scanner),
                  label: const Text('Scan serial to count'),
                ),
              ),
            ],
          ),
        const SizedBox(height: 12),
        Row(
          children: [
            if (!isCreating)
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: _deleteCurrentReceipt,
                  icon: const Icon(Icons.delete_outline, color: Colors.red),
                  label: const Text('Delete'),
                ),
              ),
            if (!isCreating) const SizedBox(width: 12),
            Expanded(
              child: OutlinedButton.icon(
                onPressed: _resetForm,
                icon: const Icon(Icons.clear),
                label: const Text('Clear'),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: ElevatedButton.icon(
                onPressed: _saveReceipt,
                icon: Icon(isCreating ? Icons.add : Icons.save),
                label: Text(isCreating ? 'Create' : 'Update'),
              ),
            ),
          ],
        ),
      ],
    );
  }

  Future<void> _openReceiptEditor({StockReceipt? receipt}) async {
    if (receipt == null) {
      _resetForm();
    } else {
      _editReceipt(receipt);
    }
    _syncAutocompleteFields();

    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      builder: (context) {
        return SafeArea(
          child: FractionallySizedBox(
            heightFactor: 0.92,
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: SingleChildScrollView(
                child: _buildReceiptForm(isCreating: receipt == null),
              ),
            ),
          ),
        );
      },
    ).whenComplete(() {
      if (mounted) {
        _resetForm();
      }
    });
  }

  Future<void> _deleteCurrentReceipt() async {
    final receipt = _editingReceipt;
    if (receipt == null) {
      return;
    }
    await _deleteReceipt(receipt);
  }

  Future<void> _bootstrap() async {
    final allowed = await _controller.authController.hasPermission(
      widget.user.roleId,
      'Manage stock',
    );
    if (!mounted) {
      return;
    }

    if (!allowed) {
      setState(() {
        _isAuthorized = false;
        _isLoading = false;
      });
      return;
    }

    setState(() {
      _isAuthorized = true;
    });

    await _loadCatalog();
    await _loadReceipts(showLoading: true);
  }

  Future<void> _loadCatalog() async {
    try {
      final products = await _controller.fetchProducts();
      final suppliers = await _controller.fetchSuppliers();

      if (!mounted) {
        return;
      }

      setState(() {
        _products = products;
        _suppliers = suppliers;
      });
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Error loading catalog: $e')));
      }
    }
  }

  Future<void> _loadReceipts({bool showLoading = false}) async {
    if (showLoading) {
      setState(() => _isLoading = true);
    } else {
      setState(() => _isSearching = true);
    }

    try {
      final receipts = await _controller.fetchStockReceipts(
        searchQuery: _searchController.text,
      );
      if (!mounted) {
        return;
      }

      setState(() {
        _receipts = receipts;
        _isLoading = false;
        _isSearching = false;
      });
    } catch (e) {
      if (!mounted) {
        return;
      }
      setState(() {
        _isLoading = false;
        _isSearching = false;
      });
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Error loading stock receipts: $e')),
      );
    }
  }

  void _onSearchChanged(String value) {
    _searchDebounce?.cancel();
    _searchDebounce = Timer(const Duration(milliseconds: 350), () {
      _loadReceipts();
    });
  }

  Future<void> _selectProduct(Product? product) async {
    setState(() {
      _selectedProduct = product;
    });

    final productSupplierId = product?.supplierId;
    Supplier? recommendedSupplier = productSupplierId == null
        ? null
        : _findSupplierById(productSupplierId);

    if (product != null && recommendedSupplier == null) {
      try {
        final freshSuppliers = await _controller.fetchSuppliers();
        if (!mounted) {
          return;
        }

        setState(() {
          _suppliers = freshSuppliers;
        });

        recommendedSupplier = productSupplierId == null
            ? null
            : _findSupplierById(productSupplierId);
      } catch (_) {
        // Keep current selection if supplier refresh fails.
      }
    }

    if (!mounted) {
      return;
    }

    setState(() {
      _selectedSupplier = recommendedSupplier;
    });
    _syncAutocompleteFields();
  }

  void _selectSupplier(Supplier? supplier) {
    setState(() {
      _selectedSupplier = supplier;
    });
    _syncAutocompleteFields();
  }

  void _resetForm() {
    setState(() {
      _editingReceipt = null;
      _selectedProduct = null;
      _selectedSupplier = null;
      _receiptDate = DateTime.now();
      _receiptDateController.text = _formatDateTime(_receiptDate);
      _quantityReceivedController.text = '0';
      _quantityDamagedController.text = '0';
      _notesController.clear();
    });
    _syncAutocompleteFields();
  }

  void _editReceipt(StockReceipt receipt) {
    final product = _findProductById(receipt.productId);
    final explicitSupplier = _findSupplierById(receipt.supplierId);
    final recommendedSupplier =
        explicitSupplier ?? _recommendedSupplierForProduct(product);

    setState(() {
      _editingReceipt = receipt;
      _selectedProduct = product;
      _selectedSupplier = recommendedSupplier;
      _receiptDate = receipt.receiptDate;
      _receiptDateController.text = _formatDateTime(_receiptDate);
      _quantityReceivedController.text = receipt.quantityReceived.toString();
      _quantityDamagedController.text = receipt.quantityDamaged.toString();
      _notesController.text = receipt.notes ?? '';
    });
    _syncAutocompleteFields();
  }

  Future<void> _pickReceiptDate() async {
    final date = await showDatePicker(
      context: context,
      initialDate: _receiptDate,
      firstDate: DateTime(2020),
      lastDate: DateTime(2100),
    );

    if (date == null || !mounted) {
      return;
    }

    final time = await showTimePicker(
      context: context,
      initialTime: TimeOfDay.fromDateTime(_receiptDate),
    );

    final selected = DateTime(
      date.year,
      date.month,
      date.day,
      time?.hour ?? _receiptDate.hour,
      time?.minute ?? _receiptDate.minute,
    );

    setState(() {
      _receiptDate = selected;
      _receiptDateController.text = _formatDateTime(_receiptDate);
    });
  }

  Future<void> _incrementQuantityReceived() async {
    final current = int.tryParse(_quantityReceivedController.text) ?? 0;
    setState(() => _quantityReceivedController.text = (current + 1).toString());
  }

  Future<void> _decrementQuantityReceived() async {
    final current = int.tryParse(_quantityReceivedController.text) ?? 0;
    setState(
      () => _quantityReceivedController.text = current > 0
          ? (current - 1).toString()
          : '0',
    );
  }

  Future<void> _incrementDamaged() async {
    final current = int.tryParse(_quantityDamagedController.text) ?? 0;
    setState(() => _quantityDamagedController.text = (current + 1).toString());
  }

  Future<void> _decrementDamaged() async {
    final current = int.tryParse(_quantityDamagedController.text) ?? 0;
    setState(
      () => _quantityDamagedController.text = current > 0
          ? (current - 1).toString()
          : '0',
    );
  }

  Future<void> _scanSerial() async {
    if (_selectedProduct == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Select a product before scanning.')),
      );
      return;
    }

    final expected = (_selectedProduct!.serialNo?.trim().isNotEmpty ?? false)
        ? _selectedProduct!.serialNo!.trim()
        : _selectedProduct!.sku.trim();

    final scannedCount = await Navigator.push<int>(
      context,
      MaterialPageRoute(
        builder: (context) => StockReceiptScannerView(
          expectedValue: expected,
          productName: _selectedProduct!.productName,
        ),
      ),
    );

    if (scannedCount == null || !mounted) {
      return;
    }

    if (scannedCount > 0) {
      final current = int.tryParse(_quantityReceivedController.text) ?? 0;
      setState(() {
        _quantityReceivedController.text = (current + scannedCount).toString();
      });
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Added $scannedCount scanned item(s).')),
      );
    }
  }

  Future<void> _quickAddSupplier() async {
    final result = await showDialog<Map<String, dynamic>>(
      context: context,
      builder: (context) => const _QuickSupplierDialog(),
    );

    if (result == null) {
      return;
    }

    try {
      final supplierId = await _controller.quickCreateSupplier(
        supplierName: result['supplierName'] as String,
        createdByUserId: widget.user.userId,
        address: result['address'] as String?,
        contactInfo: result['contactInfo'] as String?,
        leadTimeDays: result['leadTimeDays'] as int?,
      );

      await _loadCatalog();
      final createdSupplier = _findSupplierById(supplierId);
      if (createdSupplier != null) {
        _selectSupplier(createdSupplier);
      }
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Supplier created successfully.')),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Error creating supplier: $e')));
      }
    }
  }

  Future<void> _quickAddProduct() async {
    if (_selectedSupplier == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Select or create a supplier first.')),
      );
      return;
    }

    final result = await showDialog<Map<String, dynamic>>(
      context: context,
      builder: (context) =>
          _QuickProductDialog(supplierName: _selectedSupplier!.supplierName),
    );

    if (result == null) {
      return;
    }

    try {
      final productId = await _controller.quickCreateProduct(
        productName: result['productName'] as String,
        sku: result['sku'] as String,
        supplierId: _selectedSupplier!.supplierId,
        serialNo: result['serialNo'] as String?,
        actorUserId: widget.user.userId,
      );

      await _loadCatalog();
      final createdProduct = _findProductById(productId);
      if (createdProduct != null) {
        _selectProduct(createdProduct);
      }
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Product created successfully.')),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Error creating product: $e')));
      }
    }
  }

  Future<void> _saveReceipt() async {
    final product = _selectedProduct;
    final supplier = _selectedSupplier;
    final isCreating = _editingReceipt == null;

    if (product == null || supplier == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Select both a product and a supplier.')),
      );
      return;
    }

    final quantityReceived =
        int.tryParse(_quantityReceivedController.text) ?? 0;
    final quantityDamaged = int.tryParse(_quantityDamagedController.text) ?? 0;

    if (quantityReceived < 0 || quantityDamaged < 0) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Quantities cannot be negative.')),
      );
      return;
    }

    if (quantityDamaged > quantityReceived) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'Quantity damaged cannot be larger than quantity received.',
          ),
        ),
      );
      return;
    }

    final receipt = StockReceipt(
      stockReceiptId: _editingReceipt?.stockReceiptId ?? 0,
      productId: product.productId,
      supplierId: supplier.supplierId,
      recordedBy: widget.user.userId,
      quantityReceived: quantityReceived,
      quantityDamaged: quantityDamaged,
      receiptDate: _receiptDate,
      notes: _notesController.text.trim().isEmpty
          ? null
          : _notesController.text.trim(),
    );

    try {
      if (isCreating) {
        await _controller.addStockReceipt(receipt, widget.user.roleId);
      } else {
        await _controller.updateStockReceipt(receipt, widget.user.roleId);
      }

      await _loadReceipts(showLoading: false);
      _resetForm();
      if (mounted) {
        Navigator.pop(context);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              isCreating
                  ? 'Stock receipt created successfully.'
                  : 'Stock receipt updated successfully.',
            ),
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Error saving receipt: $e')));
      }
    }
  }

  Future<void> _deleteReceipt(StockReceipt receipt) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Delete Stock Receipt'),
        content: const Text(
          'Are you sure you want to delete this stock receipt?',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Delete'),
          ),
        ],
      ),
    );

    if (confirm != true) {
      return;
    }

    try {
      await _controller.deleteStockReceipt(
        receipt.stockReceiptId,
        widget.user.roleId,
        actorUserId: widget.user.userId,
      );
      await _loadReceipts(showLoading: false);
      if (_editingReceipt?.stockReceiptId == receipt.stockReceiptId) {
        _resetForm();
        if (mounted) {
           // We might need to pop twice if we came from the editor modal, 
           // but the first pop happened for the confirmation dialog.
           // However, _deleteReceipt is called directly.
           // If we are in the modal, we need to close it.
           Navigator.of(context).popUntil((route) => route.isFirst || route.settings.name != null);
           // Actually, standard way is to pop once if we are in a sub-view.
           // Let's just pop once more if we are editing.
           Navigator.pop(context);
        }
      }
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Stock receipt deleted successfully.')),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Error deleting receipt: $e')));
      }
    }
  }

  Widget _buildQuantityStepper({
    required String label,
    required TextEditingController controller,
    required VoidCallback onPlus,
    required VoidCallback onMinus,
  }) {
    return Row(
      children: [
        Expanded(
          child: TextField(
            controller: controller,
            keyboardType: TextInputType.number,
            decoration: InputDecoration(labelText: label),
          ),
        ),
        IconButton(
          onPressed: onMinus,
          icon: const Icon(Icons.remove_circle_outline),
        ),
        IconButton(
          onPressed: onPlus,
          icon: const Icon(Icons.add_circle_outline),
        ),
      ],
    );
  }

  Widget _buildReceiptCard(StockReceipt receipt) {
    return Card(
      child: ListTile(
        leading: const CircleAvatar(child: Icon(Icons.receipt_long)),
        title: Text(_receiptTitle(receipt)),
        subtitle: Text(_receiptSubtitle(receipt)),
        isThreeLine: true,
        trailing: Wrap(
          spacing: 4,
          children: [
            IconButton(
              icon: const Icon(Icons.edit_outlined),
              tooltip: 'Edit receipt',
              onPressed: () => _openReceiptEditor(receipt: receipt),
            ),
            IconButton(
              icon: const Icon(Icons.delete_outline, color: Colors.red),
              tooltip: 'Delete receipt',
              onPressed: () => _deleteReceipt(receipt),
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (!_isAuthorized && !_isLoading) {
      return Scaffold(
        appBar: widget.isEmbedded ? null : AppBar(title: const Text('Access denied')),
        body: const Center(child: Text('Access denied')),
      );
    }

    return Scaffold(
      appBar: widget.isEmbedded
          ? null
          : AppBar(
              title: const Text('Stock Receipt'),
              actions: [
                IconButton(
                  icon: const Icon(Icons.refresh),
                  onPressed: () async {
                    await _loadCatalog();
                    await _loadReceipts();
                  },
                ),
              ],
            ),
      floatingActionButton: FloatingActionButton(
        onPressed: () => _openReceiptEditor(),
        child: const Icon(Icons.add),
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : RefreshIndicator(
              onRefresh: () async {
                await _loadCatalog();
                await _loadReceipts(showLoading: false);
              },
              child: ListView(
                physics: const AlwaysScrollableScrollPhysics(),
                padding: const EdgeInsets.all(16),
                children: [
                  const SizedBox(height: 16),
                  Row(
                    children: [
                      Expanded(
                        child: TextField(
                          controller: _searchController,
                          decoration: InputDecoration(
                            labelText:
                              'Search by receipt ID, product, SKU, serial, supplier, or supplier ID',
                            prefixIcon: const Icon(Icons.search),
                            suffixIcon: _isSearching
                                ? const SizedBox(
                                    width: 18,
                                    height: 18,
                                    child: Padding(
                                      padding: EdgeInsets.all(12.0),
                                      child: CircularProgressIndicator(
                                        strokeWidth: 2,
                                      ),
                                    ),
                                  )
                                : null,
                          ),
                          onChanged: _onSearchChanged,
                        ),
                      ),
                      IconButton(
                        icon: const Icon(Icons.clear),
                        onPressed: () {
                          _searchDebounce?.cancel();
                          _searchController.clear();
                          _loadReceipts(showLoading: false);
                        },
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  Text(
                    'Stock receipt records',
                    style: Theme.of(context).textTheme.titleMedium,
                  ),
                  const SizedBox(height: 8),
                  if (_receipts.isNotEmpty)
                    Text(
                      'Use the pencil icon to edit a receipt. Use the trash icon to delete.',
                      style: Theme.of(context).textTheme.bodySmall,
                    ),
                  if (_receipts.isEmpty)
                    const Padding(
                      padding: EdgeInsets.all(24),
                      child: Center(child: Text('No stock receipts found.')),
                    )
                  else
                    ..._receipts.map(_buildReceiptCard),
                ],
              ),
            ),
    );
  }
}

class StockReceiptScannerView extends StatefulWidget {
  final String expectedValue;
  final String productName;

  const StockReceiptScannerView({
    super.key,
    required this.expectedValue,
    required this.productName,
  });

  @override
  State<StockReceiptScannerView> createState() =>
      _StockReceiptScannerViewState();
}

class _StockReceiptScannerViewState extends State<StockReceiptScannerView> {
  final MobileScannerController _scannerController = MobileScannerController(
    formats: const [
      BarcodeFormat.qrCode,
      BarcodeFormat.code128,
      BarcodeFormat.code39,
      BarcodeFormat.ean13,
      BarcodeFormat.ean8,
    ],
  );
  int _validCount = 0;
  String _statusMessage = 'Point camera at the product serial QR/barcode.';
  Color _statusColor = Colors.blueGrey;
  String _lastRaw = '';
  DateTime _lastScanAt = DateTime.fromMillisecondsSinceEpoch(0);

  @override
  void dispose() {
    _scannerController.dispose();
    super.dispose();
  }

  void _handleDetect(BarcodeCapture capture) {
    for (final barcode in capture.barcodes) {
      final rawValue = barcode.rawValue?.trim();
      if (rawValue == null || rawValue.isEmpty) {
        continue;
      }

      final now = DateTime.now();
      if (_lastRaw == rawValue &&
          now.difference(_lastScanAt).inMilliseconds < 700) {
        continue;
      }
      _lastRaw = rawValue;
      _lastScanAt = now;

      if (rawValue == widget.expectedValue.trim()) {
        setState(() {
          _validCount += 1;
          _statusMessage = 'Valid scan. Count: $_validCount';
          _statusColor = Colors.green;
        });
      } else {
        setState(() {
          _statusMessage = 'Invalid code for ${widget.productName}. Try again.';
          _statusColor = Colors.red;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Scan product serial'),
        actions: [
          IconButton(
            icon: const Icon(Icons.check),
            tooltip: 'Done',
            onPressed: () => Navigator.pop(context, _validCount),
          ),
          IconButton(
            icon: const Icon(Icons.close),
            onPressed: () => Navigator.pop(context, 0),
          ),
        ],
      ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.all(16),
            child: Text(
              'Scan the QR code or barcode for ${widget.productName}.\nExpected value: ${widget.expectedValue}',
              textAlign: TextAlign.center,
            ),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Container(
              width: double.infinity,
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(10),
                color: _statusColor.withValues(alpha: 0.12),
              ),
              child: Text(
                _statusMessage,
                style: TextStyle(color: _statusColor),
                textAlign: TextAlign.center,
              ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
            child: Text(
              'Valid count: $_validCount',
              style: Theme.of(context).textTheme.titleMedium,
            ),
          ),
          Expanded(
            child: MobileScanner(
              controller: _scannerController,
              onDetect: _handleDetect,
            ),
          ),
          Padding(
            padding: const EdgeInsets.all(12),
            child: SizedBox(
              width: double.infinity,
              child: ElevatedButton.icon(
                onPressed: () => Navigator.pop(context, _validCount),
                icon: const Icon(Icons.done_all),
                label: const Text('Done scanning'),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _QuickSupplierDialog extends StatefulWidget {
  const _QuickSupplierDialog();

  @override
  State<_QuickSupplierDialog> createState() => _QuickSupplierDialogState();
}

class _QuickSupplierDialogState extends State<_QuickSupplierDialog> {
  final _nameController = TextEditingController();
  final _addressController = TextEditingController();
  final _contactController = TextEditingController();
  final _leadTimeController = TextEditingController();

  @override
  void dispose() {
    _nameController.dispose();
    _addressController.dispose();
    _contactController.dispose();
    _leadTimeController.dispose();
    super.dispose();
  }

  void _save() {
    if (_nameController.text.trim().isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Supplier name is required.')),
      );
      return;
    }

    Navigator.pop(context, {
      'supplierName': _nameController.text.trim(),
      'address': _addressController.text.trim().isEmpty
          ? null
          : _addressController.text.trim(),
      'contactInfo': _contactController.text.trim().isEmpty
          ? null
          : _contactController.text.trim(),
      'leadTimeDays': int.tryParse(_leadTimeController.text.trim()),
    });
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Create Supplier'),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: _nameController,
              decoration: const InputDecoration(labelText: 'Supplier name'),
            ),
            TextField(
              controller: _addressController,
              decoration: const InputDecoration(labelText: 'Address'),
            ),
            TextField(
              controller: _contactController,
              decoration: const InputDecoration(labelText: 'Contact info'),
            ),
            TextField(
              controller: _leadTimeController,
              decoration: const InputDecoration(labelText: 'Lead time days'),
              keyboardType: TextInputType.number,
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Cancel'),
        ),
        ElevatedButton(onPressed: _save, child: const Text('Create')),
      ],
    );
  }
}

class _QuickProductDialog extends StatefulWidget {
  final String supplierName;

  const _QuickProductDialog({required this.supplierName});

  @override
  State<_QuickProductDialog> createState() => _QuickProductDialogState();
}

class _QuickProductDialogState extends State<_QuickProductDialog> {
  final _productNameController = TextEditingController();
  final _skuController = TextEditingController();
  final _serialController = TextEditingController();

  @override
  void dispose() {
    _productNameController.dispose();
    _skuController.dispose();
    _serialController.dispose();
    super.dispose();
  }

  void _save() {
    if (_productNameController.text.trim().isEmpty ||
        _skuController.text.trim().isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Product name and SKU are required.')),
      );
      return;
    }

    Navigator.pop(context, {
      'productName': _productNameController.text.trim(),
      'sku': _skuController.text.trim(),
      'serialNo': _serialController.text.trim().isEmpty
          ? null
          : _serialController.text.trim(),
    });
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Create Product'),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text('Supplier: ${widget.supplierName}'),
            const SizedBox(height: 12),
            TextField(
              controller: _productNameController,
              decoration: const InputDecoration(labelText: 'Product name'),
            ),
            TextField(
              controller: _skuController,
              decoration: const InputDecoration(labelText: 'SKU'),
            ),
            TextField(
              controller: _serialController,
              decoration: const InputDecoration(labelText: 'Serial number'),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Cancel'),
        ),
        ElevatedButton(onPressed: _save, child: const Text('Create')),
      ],
    );
  }
}
