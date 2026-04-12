import 'dart:convert';
import 'dart:io';

import 'package:csv/csv.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/foundation.dart' show compute, kIsWeb;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show rootBundle;

import '../utils/csv_export_stub.dart'
  if (dart.library.html) '../utils/csv_export_web.dart' as csv_export;


import '../controllers/auth_controller.dart';
import '../controllers/historical_sales_controller.dart';
import '../models/user.dart';
import '../services/audit_log_service.dart';
import '../services/api/inventory_api_service.dart';
import '../services/api/reports_api_service.dart';

class ImportDataView extends StatefulWidget {
  final UserModel user;

  const ImportDataView({super.key, required this.user});

  @override
  State<ImportDataView> createState() => _ImportDataViewState();
}

class _ImportDataViewState extends State<ImportDataView> {
  final AuthController _authController = AuthController();
  final InventoryApiService _inventoryApi = InventoryApiService();
  final ReportsApiService _reportsApi = ReportsApiService();
  final AuditLogService _auditLogService = AuditLogService();
  final HistoricalSalesController _historicalSalesController = HistoricalSalesController();

  bool _isLoading = true;
  bool _hasAccess = false;

  // Expected headers for each data type
  static const Map<String, List<String>> _expectedHeaders = {
    'Product details': ['product code', 'product name', 'supplier id', 'sku', 'unit cost', 'serial number'],
    'Supplier details': ['supplier id', 'supplier name', 'contact info', 'leadtime days', 'address'],
    'Stock receipt': ['receipt id', 'receipt date', 'supplier id', 'product code', 'quantity received', 'qa check', 'quantitiy damage', 'remarks'],
    'Sales history': ['sales id', 'product code', 'sale date', 'quanitity sold', 'revenue'],
  };

  @override
  void initState() {
    super.initState();
    _checkAccess();
  }

  Future<void> _checkAccess() async {
    final hasPermission = await _authController.hasPermission(
      widget.user.roleId,
      'Import data',
    );

    if (!mounted) {
      return;
    }

    if (!hasPermission) {
      await _auditLogService.logAction(
        userId: widget.user.userId,
        action: 'Unauthorized access attempt',
        entityType: 'Page',
        entityId: 0,
        details: 'CSV import page access denied',
      );
    }

    if (!mounted) {
      return;
    }

    setState(() {
      _hasAccess = hasPermission;
      _isLoading = false;
    });
  }

  Future<void> _pickFile(String dataType) async {
    FilePickerResult? result = await FilePicker.platform.pickFiles(
      type: FileType.custom,
      allowedExtensions: ['csv'],
      withData: true,
    );

    if (result == null) {
      return; // User canceled the picker
    }

    try {
      final pickedFile = result.files.single;
      String csvContent;

      if (kIsWeb || pickedFile.path == null) {
        if (pickedFile.bytes == null) {
          throw Exception('Unable to read CSV file data.');
        }
        csvContent = utf8.decode(pickedFile.bytes!);
      } else {
        final file = File(pickedFile.path!);
        csvContent = await file.readAsString();
      }

      final rows = await compute(_parseCsv, csvContent);

      if (!mounted) return;

      // Validate headers
      final headers = rows[0].map((h) => h.toString()).toList();
      final headerValidationError = _validateHeaders(headers, dataType);
      if (headerValidationError != null) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(headerValidationError)),
        );
        return;
      }

      // Check for duplicates
      final duplicateWarning = await _checkForDuplicates(dataType, rows);
      if (duplicateWarning != null) {
        if (!mounted) return;
        final proceed = await showDialog<bool>(
          context: context,
          builder: (context) => AlertDialog(
            title: const Text('Duplicate Warning'),
            content: Text('$duplicateWarning\n\nDo you want to proceed with the import anyway?'),
            actions: [
              TextButton(
                onPressed: () => Navigator.of(context).pop(false),
                child: const Text('Cancel'),
              ),
              ElevatedButton(
                onPressed: () => Navigator.of(context).pop(true),
                child: const Text('Proceed'),
              ),
            ],
          ),
        );

        if (proceed != true) return;
      }

      // Show preview dialog
      await _showPreviewDialog(dataType, rows);

      // TODO: Process `rows` and upload to your database here.
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Error reading CSV file: $e')),
      );
    }
  }

  static List<List<dynamic>> _parseCsv(String content) {
    return Csv().decode(content);
  }

  // Validate CSV headers against expected headers for the data type
  String? _validateHeaders(List<String> actualHeaders, String dataType) {
    final expected = _expectedHeaders[dataType];
    if (expected == null) return 'Unknown data type: $dataType';

    // Normalize headers for comparison (lowercase, trim spaces)
    final normalizedActual = actualHeaders.map((h) => h.toLowerCase().trim()).toList();
    final normalizedExpected = expected.map((h) => h.toLowerCase().trim()).toList();

    // Check if all expected headers are present
    final missingHeaders = normalizedExpected.where((header) =>
      !normalizedActual.contains(header)).toList();

    if (missingHeaders.isNotEmpty) {
      return 'Invalid template! Missing required headers: ${missingHeaders.join(', ')}\n\nExpected headers for $dataType: ${expected.join(', ')}';
    }

    return null; // Valid
  }

  // Check for potential duplicates in the database
  Future<String?> _checkForDuplicates(String dataType, List<List<dynamic>> rows) async {
    if (rows.length < 2) return null; // No data rows

    final headers = rows[0].map((h) => h.toString().toLowerCase().trim()).toList();
    final dataRows = rows.sublist(1);

    try {
      switch (dataType) {
        case 'Product details':
          return await _checkProductDuplicates(headers, dataRows);
        case 'Supplier details':
          return await _checkSupplierDuplicates(headers, dataRows);
        case 'Stock receipt':
          return await _checkStockReceiptDuplicates(headers, dataRows);
        case 'Sales history':
          return await _checkSalesDuplicates(headers, dataRows);
      }
    } catch (e) {
      // If duplicate checking fails, don't block the import
      return null;
    }
    return null;
  }

  Future<String?> _checkProductDuplicates(List<String> headers, List<List<dynamic>> rows) async {
    final skuIndex = headers.indexOf('sku');
    if (skuIndex == -1) return null;

    final skus = rows.map((row) => row[skuIndex].toString()).where((sku) => sku.isNotEmpty).toList();
    if (skus.isEmpty) return null;

    final response = await _inventoryApi.listProducts();
    final existingSkus = response.map((p) => p['sku']?.toString() ?? '').where((sku) => skus.contains(sku)).toList();
    if (existingSkus.isNotEmpty) {
      return 'Warning: ${existingSkus.length} product(s) with these SKUs already exist: ${existingSkus.take(3).join(', ')}${existingSkus.length > 3 ? '...' : ''}';
    }
    return null;
  }

  Future<String?> _checkSupplierDuplicates(List<String> headers, List<List<dynamic>> rows) async {
    final nameIndex = headers.indexOf('supplier name');
    if (nameIndex == -1) return null;

    final names = rows.map((row) => row[nameIndex].toString()).where((name) => name.isNotEmpty).toList();
    if (names.isEmpty) return null;

    final response = await _inventoryApi.listSuppliers();
    final existingNames = response.map((s) => s['name']?.toString() ?? '').where((name) => names.contains(name)).toList();
    if (existingNames.isNotEmpty) {
      return 'Warning: ${existingNames.length} supplier(s) with these names already exist: ${existingNames.take(3).join(', ')}${existingNames.length > 3 ? '...' : ''}';
    }
    return null;
  }

  Future<String?> _checkStockReceiptDuplicates(List<String> headers, List<List<dynamic>> rows) async {
    // For stock receipts, check if receipt_id already exists
    final idIndex = headers.indexOf('receipt id');
    if (idIndex == -1) return null;

    final ids = rows.map((row) => row[idIndex].toString()).where((id) => id.isNotEmpty).toList();
    if (ids.isEmpty) return null;

    final response = await _inventoryApi.listStockReceipts();
    final existingIds = response.map((r) => (r['id'] ?? r['receipt_id']).toString()).where(ids.contains).toList();
    if (existingIds.isNotEmpty) {
      return 'Warning: ${existingIds.length} stock receipt(s) with these IDs already exist: ${existingIds.take(3).join(', ')}${existingIds.length > 3 ? '...' : ''}';
    }
    return null;
  }

  Future<String?> _checkSalesDuplicates(List<String> headers, List<List<dynamic>> rows) async {
    // For sales, check combination of product_code and sale_date
    final productCodeIndex = headers.indexOf('product code');
    final dateIndex = headers.indexOf('sale date');
    if (productCodeIndex == -1 || dateIndex == -1) return null;

    List<Map<String, dynamic>> salesToCheck = [];
    for (final row in rows) {
      final productCode = row[productCodeIndex].toString();
      final saleDate = row[dateIndex].toString();
      if (productCode.isNotEmpty && saleDate.isNotEmpty) {
        salesToCheck.add({
          'product_code': _normalizeProductCode(productCode),
          'sale_date': saleDate,
        });
      }
    }

    if (salesToCheck.isEmpty) return null;

    final existingSales = await _historicalSalesController.fetchSales();
    final existingKeys = existingSales
        .map((sale) => '${_normalizeProductCode(sale.productCode ?? '')}|${sale.saleDate.toIso8601String().split('T').first}')
        .toSet();
    final duplicateCount = salesToCheck.where((sale) {
      final saleDateText = sale['sale_date'].toString().split('T').first;
      final key = '${sale['product_code']}|$saleDateText';
      return existingKeys.contains(key);
    }).length;

    if (duplicateCount > 0) {
      return 'Warning: $duplicateCount sale record(s) with same product and date combinations already exist.';
    }
    return null;
  }

  Future<void> _showPreviewDialog(String dataType, List<List<dynamic>> rows) async {
    if (rows.isEmpty || rows.length < 2) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('CSV file appears to be empty or invalid.')),
      );
      return;
    }

    final headers = rows[0].map((h) => h.toString()).toList();
    final dataRows = rows.sublist(1);
    final media = MediaQuery.of(context);
    final maxHeight = media.size.height * 0.75;
    final maxWidth = media.size.width * 0.95;
    final showAsBottomSheet = media.size.width < 600;
    final previewRows = dataRows.take(5).toList();

    final previewContent = SizedBox(
      width: maxWidth,
      height: maxHeight,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('${dataRows.length} rows to import'),
          const SizedBox(height: 16),
          Expanded(
            child: SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: ConstrainedBox(
                constraints: BoxConstraints(minWidth: maxWidth),
                child: DataTable(
                  columnSpacing: 12,
                  headingRowHeight: 48,
                  dataRowMinHeight: 48,
                  dataRowMaxHeight: 48,
                  columns: headers.map((header) => DataColumn(label: Text(header))).toList(),
                  rows: previewRows.map((row) {
                    return DataRow(
                      cells: row.map((cell) => DataCell(Text(cell.toString()))).toList(),
                    );
                  }).toList(),
                ),
              ),
            ),
          ),
          if (dataRows.length > previewRows.length)
            Padding(
              padding: const EdgeInsets.only(top: 12.0),
              child: Text('... and ${dataRows.length - previewRows.length} more rows'),
            ),
        ],
      ),
    );

    if (showAsBottomSheet) {
      await showModalBottomSheet<void>(
        context: context,
        isScrollControlled: true,
        builder: (context) => Padding(
          padding: EdgeInsets.only(
            bottom: media.viewInsets.bottom,
            left: 16,
            right: 16,
            top: 16,
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text('Preview $dataType Import', style: Theme.of(context).textTheme.titleLarge),
              const SizedBox(height: 12),
              previewContent,
              const SizedBox(height: 12),
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton(
                      onPressed: () => Navigator.of(context).pop(),
                      child: const Text('Cancel'),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: ElevatedButton(
                      onPressed: () {
                        Navigator.of(context).pop();
                        _importData(dataType, rows);
                      },
                      child: const Text('Import'),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 16),
            ],
          ),
        ),
      );
    } else {
      await showDialog<void>(
        context: context,
        builder: (context) => AlertDialog(
          title: Text('Preview $dataType Import'),
          content: previewContent,
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: const Text('Cancel'),
            ),
            ElevatedButton(
              onPressed: () {
                Navigator.of(context).pop();
                _importData(dataType, rows);
              },
              child: const Text('Import'),
            ),
          ],
        ),
      );
    }
  }

  Future<void> _importData(String dataType, List<List<dynamic>> rows) async {
    if (rows.length < 2) return; // No data rows

    try {
      final headers = rows[0].map((h) => h.toString().toLowerCase()).toList();
      final dataRows = rows.sublist(1);

      switch (dataType) {
        case 'Product details':
          await _importProducts(headers, dataRows);
          break;
        case 'Supplier details':
          await _importSuppliers(headers, dataRows);
          break;
        case 'Stock receipt':
          await _importStockReceipts(headers, dataRows);
          break;
        case 'Sales history':
          await _importSalesHistory(headers, dataRows);
          break;
      }

      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('$dataType imported successfully!')),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Import failed: $e')),
      );
    }
  }

  Future<void> _importProducts(List<String> headers, List<List<dynamic>> rows) async {
    for (final row in rows) {
      final productData = _mapRowToProduct(headers, row);
      await _inventoryApi.createProduct({
        'product_code': productData['product_code'],
        'sku': productData['sku'],
        'name': productData['product_name'],
        'supplier_id': productData['supplier_id'],
        'current_qty': productData['current_qty'] ?? 0,
        'reorder_level': productData['reorder_point'] ?? 0,
        'overstock_level': productData['reorder_point'] ?? 0,
        'unit_cost': productData['unit_cost'] ?? 0,
      });
    }

    await _auditLogService.logAction(
      userId: widget.user.userId,
      action: 'Import CSV products',
      entityType: 'Product',
      details: 'Imported ${rows.length} product row(s) via CSV',
    );
  }

  Future<void> _importSuppliers(List<String> headers, List<List<dynamic>> rows) async {
    for (final row in rows) {
      final supplierData = _mapRowToSupplier(headers, row);
      await _inventoryApi.createSupplier({
        'name': supplierData['supplier_name'],
        'email': supplierData['contact_info'] != null && supplierData['contact_info'].toString().contains('@') ? supplierData['contact_info'] : null,
        'phone': supplierData['contact_info'] != null && !supplierData['contact_info'].toString().contains('@') ? supplierData['contact_info'] : null,
        'is_active': true,
      });
    }

    await _auditLogService.logAction(
      userId: widget.user.userId,
      action: 'Import CSV suppliers',
      entityType: 'Supplier',
      details: 'Imported ${rows.length} supplier row(s) via CSV',
    );
  }

  Future<void> _importStockReceipts(List<String> headers, List<List<dynamic>> rows) async {
    final productCodeToId = await _fetchProductCodeToIdMap();

    for (final row in rows) {
      final receiptData = _mapRowToStockReceipt(headers, row, widget.user.userId, productCodeToId);
      if ((receiptData['product_id'] ?? 0) <= 0) {
        throw Exception('Unknown product code: ${receiptData['product_code'] ?? ''}');
      }

      await _inventoryApi.createStockReceipt({
        'product_id': receiptData['product_id'],
        'supplier_id': receiptData['supplier_id'],
        'quantity': receiptData['quantity_received'],
        'unit_cost': 0,
        'reference_no': receiptData['notes'],
        'received_at': receiptData['receipt_date'],
      });
    }

    await _auditLogService.logAction(
      userId: widget.user.userId,
      action: 'Import CSV stock receipts',
      entityType: 'StockReceipt',
      details: 'Imported ${rows.length} stock receipt row(s) via CSV',
    );
  }

  Future<void> _importSalesHistory(List<String> headers, List<List<dynamic>> rows) async {
    final payload = rows.map((row) => _mapRowToSale(headers, row)).toList();
    await _reportsApi.importHistoricalSales(payload);

    await _auditLogService.logAction(
      userId: widget.user.userId,
      action: 'Import CSV sales history',
      entityType: 'Sales',
      details: 'Imported ${rows.length} sales row(s) via CSV',
    );
  }

  // Helper methods to map CSV rows to database objects
  Map<String, dynamic> _mapRowToProduct(List<String> headers, List<dynamic> row) {
    final Map<String, dynamic> data = {};
    for (int i = 0; i < headers.length && i < row.length; i++) {
      final header = headers[i].toLowerCase().replaceAll(' ', '_');
      final value = row[i];

      switch (header) {
        case 'product_code':
          data['product_code'] = value.toString();
          break;
        case 'supplier_id':
          data['supplier_id'] = int.tryParse(value.toString()) ?? 0;
          break;
        case 'product_name':
          data['product_name'] = value.toString();
          break;
        case 'sku':
          data['sku'] = value.toString();
          break;
        case 'unit_cost':
          data['unit_cost'] = double.tryParse(value.toString()) ?? 0.0;
          break;
        case 'current_qty':
          data['current_qty'] = int.tryParse(value.toString()) ?? 0;
          break;
        case 'reorder_point':
          data['reorder_point'] = int.tryParse(value.toString()) ?? 0;
          break;
        case 'serial_no':
        case 'serial_number':
          data['serial_no'] = value.toString().isEmpty ? null : value.toString();
          break;
        case 'status_flag':
          data['status_flag'] = value.toString().isEmpty ? 'In Stock' : value.toString();
          break;
      }
    }
    return data;
  }

  Map<String, dynamic> _mapRowToSupplier(List<String> headers, List<dynamic> row) {
    final Map<String, dynamic> data = {};
    for (int i = 0; i < headers.length && i < row.length; i++) {
      final header = headers[i].toLowerCase().replaceAll(' ', '_');
      final value = row[i];

      switch (header) {
        case 'supplier_name':
          data['supplier_name'] = value.toString();
          break;
        case 'contact_info':
          data['contact_info'] = value.toString().isEmpty ? null : value.toString();
          break;
        case 'leadtime_days':
        case 'lead_time_days':
          data['lead_time_days'] = int.tryParse(value.toString());
          break;
        case 'address':
          data['address'] = value.toString().isEmpty ? null : value.toString();
          break;
      }
    }
    return data;
  }

  Map<String, dynamic> _mapRowToStockReceipt(
    List<String> headers,
    List<dynamic> row,
    int userId,
    Map<String, int> productCodeToId,
  ) {
    final Map<String, dynamic> data = {};
    for (int i = 0; i < headers.length && i < row.length; i++) {
      final header = headers[i].toLowerCase().replaceAll(' ', '_');
      final value = row[i];

      switch (header) {
        case 'receipt_date':
          data['receipt_date'] = value.toString();
          break;
        case 'supplier_id':
          data['supplier_id'] = int.tryParse(value.toString()) ?? 0;
          break;
        case 'product_code':
          final normalizedCode = _normalizeProductCode(value.toString());
          data['product_code'] = value.toString();
          data['product_id'] = productCodeToId[normalizedCode] ?? 0;
          break;
        case 'quantity_received':
          data['quantity_received'] = int.tryParse(value.toString()) ?? 0;
          break;
        case 'qa_check':
          // Skip QA check for now
          break;
        case 'quantitiy_damage':
        case 'quantity_damaged':
          data['quantity_damaged'] = int.tryParse(value.toString()) ?? 0;
          break;
        case 'remarks':
        case 'notes':
          data['notes'] = value.toString().isEmpty ? null : value.toString();
          break;
      }
    }
    data['recorded_by'] = userId;
    return data;
  }

  Map<String, dynamic> _mapRowToSale(List<String> headers, List<dynamic> row) {
    final Map<String, dynamic> data = {};
    for (int i = 0; i < headers.length && i < row.length; i++) {
      final header = headers[i].toLowerCase().replaceAll(' ', '_');
      final value = row[i];

      switch (header) {
        case 'product_code':
          data['product_code'] = value.toString();
          break;
        case 'sale_date':
          data['sale_date'] = value.toString();
          break;
        case 'quanitity_sold':
        case 'quantity_sold':
          data['quantity_sold'] = int.tryParse(value.toString()) ?? 0;
          break;
        case 'revenue':
          data['revenue'] = double.tryParse(value.toString()) ?? 0.0;
          break;
      }
    }
    return data;
  }

  String _normalizeProductCode(String value) {
    return value.trim().toUpperCase();
  }

  Future<Map<String, int>> _fetchProductCodeToIdMap() async {
    final response = await _inventoryApi.listProducts();
    final productCodeToId = <String, int>{};

    for (final product in response) {
      final productCode = (product['product_code'] ?? '').toString();
      final rawId = product['id'];
      final productId = rawId is num
          ? rawId.toInt()
          : int.tryParse(rawId?.toString() ?? '') ?? 0;

      if (productCode.trim().isNotEmpty && productId > 0) {
        productCodeToId[_normalizeProductCode(productCode)] = productId;
      }
    }

    return productCodeToId;
  }

  Future<void> _downloadTemplate(String templateName) async {
    try {
      final csvString = await rootBundle.loadString('lib/csv_templates/$templateName');
      final savedPath = await csv_export.downloadCsvWeb(csvString, templateName);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            kIsWeb
                ? 'Template downloaded: $templateName'
                : 'Template saved: ${savedPath ?? 'Unknown location'}',
          ),
        ),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Error downloading template: $e')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoading) {
      return const Scaffold(
        body: Center(child: CircularProgressIndicator()),
      );
    }

    if (!_hasAccess) {
      return Scaffold(
        appBar: AppBar(title: const Text('Import CSV Data')),
        body: const Center(
          child: Padding(
            padding: EdgeInsets.all(24.0),
            child: Text(
              'Access denied: you do not have permission to use CSV import.',
              textAlign: TextAlign.center,
            ),
          ),
        ),
      );
    }

    return Scaffold(
      appBar: AppBar(title: const Text('Import CSV Data')),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(16.0),
          child: LayoutBuilder(
            builder: (context, constraints) {
              final crossAxisCount = constraints.maxWidth < 600 ? 1 : 2;
              final childAspectRatio = constraints.maxWidth < 600 ? 2.0 : 1.2;
              return GridView.count(
                crossAxisCount: crossAxisCount,
                crossAxisSpacing: 16,
                mainAxisSpacing: 16,
                childAspectRatio: childAspectRatio,
                children: [
                  _ImportSection(
                    title: 'Product details',
                    templateName: 'product_template.csv',
                    onUpload: () => _pickFile('Product details'),
                    onDownload: () => _downloadTemplate('product_template.csv'),
                  ),
                  _ImportSection(
                    title: 'Supplier details',
                    templateName: 'supplier_template.csv',
                    onUpload: () => _pickFile('Supplier details'),
                    onDownload: () => _downloadTemplate('supplier_template.csv'),
                  ),
                  _ImportSection(
                    title: 'Stock receipt',
                    templateName: 'good_receive_template.csv',
                    onUpload: () => _pickFile('Stock receipt'),
                    onDownload: () => _downloadTemplate('good_receive_template.csv'),
                  ),
                  _ImportSection(
                    title: 'Sales history',
                    templateName: 'product_order_template.csv',
                    onUpload: () => _pickFile('Sales history'),
                    onDownload: () => _downloadTemplate('product_order_template.csv'),
                  ),
                ],
              );
            },
          ),
        ),
      ),
    );
  }
}

class _ImportSection extends StatelessWidget {
  final String title;
  final String templateName;
  final VoidCallback onUpload;
  final VoidCallback onDownload;

  const _ImportSection({
    required this.title,
    required this.templateName,
    required this.onUpload,
    required this.onDownload,
  });

  @override
  Widget build(BuildContext context) {
    return Card(
      elevation: 2,
      child: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Text(title, style: const TextStyle(fontWeight: FontWeight.bold)),
            const SizedBox(height: 16),
            ElevatedButton.icon(
              icon: const Icon(Icons.upload_file),
              label: const Text('Upload .csv file'),
              onPressed: onUpload,
            ),
            const SizedBox(height: 16),
            OutlinedButton.icon(
              icon: const Icon(Icons.download),
              label: const Text('Download Template'),
              onPressed: onDownload,
            ),
          ],
        ),
      ),
    );
  }
}