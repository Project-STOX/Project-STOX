import 'package:flutter/material.dart';
import '../models/supplier.dart';

class SupplierDetailPage extends StatefulWidget {
  final Supplier? supplier;
  final int roleId;
  final int userId;
  final Function(Supplier) onSave;
  final Function()? onDelete;

  const SupplierDetailPage({
    super.key,
    this.supplier,
    required this.roleId,
    required this.userId,
    required this.onSave,
    this.onDelete,
  });

  @override
  _SupplierDetailPageState createState() => _SupplierDetailPageState();
}

class _SupplierDetailPageState extends State<SupplierDetailPage> {
  late TextEditingController supplierIdController;
  late TextEditingController nameController;
  late TextEditingController addressController;
  late TextEditingController contactController;
  late TextEditingController leadTimeController;

  @override
  void initState() {
    super.initState();
    final supplier = widget.supplier;
    if (supplier != null) {
      supplierIdController = TextEditingController(text: supplier.supplierId.toString());
      nameController = TextEditingController(text: supplier.supplierName);
      addressController = TextEditingController(text: supplier.address ?? '');
      contactController = TextEditingController(text: supplier.contactInfo ?? '');
      leadTimeController = TextEditingController(text: supplier.leadTimeDays?.toString() ?? '');
    } else {
      supplierIdController = TextEditingController();
      nameController = TextEditingController();
      addressController = TextEditingController();
      contactController = TextEditingController();
      leadTimeController = TextEditingController();
    }
  }

  @override
  void dispose() {
    supplierIdController.dispose();
    nameController.dispose();
    addressController.dispose();
    contactController.dispose();
    leadTimeController.dispose();
    super.dispose();
  }

  void _save() async {
    try {
      final updated = Supplier(
        supplierId: widget.supplier?.supplierId ?? 0,
        supplierName: nameController.text,
        address: addressController.text.isEmpty ? null : addressController.text,
        contactInfo: contactController.text.isEmpty ? null : contactController.text,
        leadTimeDays: leadTimeController.text.isEmpty ? null : int.parse(leadTimeController.text),
      );
      await widget.onSave(updated);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Supplier saved successfully')));
        Navigator.pop(context);
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Error saving: $e')));
      }
    }
  }

  void _delete() async {
    try {
      if (widget.onDelete != null) {
        await widget.onDelete!();
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Supplier deleted successfully')));
          Navigator.pop(context);
        }
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Error deleting: $e')));
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final isNew = widget.supplier == null;
    return Scaffold(
      appBar: AppBar(
        title: Text(isNew ? 'Create Supplier' : 'Edit Supplier'),
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
              if (!isNew)
                TextField(
                  controller: supplierIdController,
                  decoration: const InputDecoration(labelText: 'Supplier ID'),
                  readOnly: true,
                  enabled: false,
                ),
              TextField(
                controller: nameController,
                decoration: const InputDecoration(labelText: 'Supplier Name'),
              ),
              TextField(
                controller: addressController,
                decoration: const InputDecoration(labelText: 'Address'),
              ),
              TextField(
                controller: contactController,
                decoration: const InputDecoration(labelText: 'Contact Info'),
              ),
              TextField(
                controller: leadTimeController,
                decoration: const InputDecoration(labelText: 'Lead Time Days'),
                keyboardType: TextInputType.number,
              ),
            ],
          ),
        ),
      ),
    );
  }
}