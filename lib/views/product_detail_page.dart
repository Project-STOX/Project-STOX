import 'dart:async';
import 'dart:math' as math;

import 'package:dropdown_search/dropdown_search.dart';
import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:mobile_scanner/mobile_scanner.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../controllers/historical_sales_controller.dart';
import '../models/historical_sale.dart';
import '../models/product.dart';
import '../models/supplier.dart';

class ProductDetailPage extends StatefulWidget {
  final Product? product;
  final List<Supplier> suppliers;
  final int roleId;
  final Future<void> Function(Product) onSave;
  final Future<void> Function()? onDelete;

  const ProductDetailPage({
    super.key,
    this.product,
    required this.suppliers,
    required this.roleId,
    required this.onSave,
    this.onDelete,
  });

  @override
  State<ProductDetailPage> createState() => _ProductDetailPageState();
}

class _ProductDetailPageState extends State<ProductDetailPage> {
  final HistoricalSalesController _salesController =
      HistoricalSalesController();
  final ScrollController _eoqScrollController = ScrollController();
  final ScrollController _forecastScrollController = ScrollController();

  late TextEditingController nameController;
  late TextEditingController skuController;
  late TextEditingController costController;
  late TextEditingController orderingCostController;
  late TextEditingController holdingCostController;
  late TextEditingController qtyController;
  late TextEditingController leadTimeController;
  late TextEditingController safetyStockController;
  late TextEditingController serialController;
  late String status;
  late int selectedSupplierId;

  bool _loadingHistory = false;
  bool _loadingPreferences = false;
  List<HistoricalSale> _historicalSales = [];
  double _eoqZoom = 1.0;
  double _forecastZoom = 1.0;

  static const String _orderingCostPrefKey = 'product_detail_ordering_cost';
  static const String _holdingCostPrefKey = 'product_detail_holding_cost';

  final List<String> statusOptions = [
    'Low Stock',
    'In Stock',
    'High Stock',
    'Discontinued',
  ];

  @override
  void initState() {
    super.initState();

    final product = widget.product;
    if (product != null) {
      nameController = TextEditingController(text: product.productName);
      skuController = TextEditingController(text: product.sku);
      costController = TextEditingController(text: product.unitCost.toString());
      orderingCostController = TextEditingController(text: '50');
      holdingCostController = TextEditingController(
        text: (product.unitCost * 0.25).toStringAsFixed(2),
      );
      qtyController = TextEditingController(
        text: product.currentQty.toString(),
      );
      leadTimeController = TextEditingController(
        text:
            product.leadTimeDays?.toString() ??
            _supplierLeadTime(product.supplierId)?.toString() ??
            '',
      );
      safetyStockController = TextEditingController(
        text: product.safetyStock.toString(),
      );
      serialController = TextEditingController(text: product.serialNo ?? '');
      status = product.statusFlag;
      selectedSupplierId = product.supplierId;
      _loadingHistory = true;
      _loadHistory();
    } else {
      nameController = TextEditingController();
      skuController = TextEditingController();
      costController = TextEditingController();
      orderingCostController = TextEditingController(text: '50');
      holdingCostController = TextEditingController();
      qtyController = TextEditingController();
      leadTimeController = TextEditingController(
        text: widget.suppliers.isNotEmpty
            ? widget.suppliers.first.leadTimeDays?.toString() ?? ''
            : '',
      );
      safetyStockController = TextEditingController();
      serialController = TextEditingController();
      status = 'In Stock';
      selectedSupplierId = widget.suppliers.isNotEmpty
          ? widget.suppliers.first.supplierId
          : 0;
    }

    _loadPersistedCostAssumptions();
  }

  @override
  void dispose() {
    _eoqScrollController.dispose();
    _forecastScrollController.dispose();
    nameController.dispose();
    skuController.dispose();
    costController.dispose();
    orderingCostController.dispose();
    holdingCostController.dispose();
    qtyController.dispose();
    leadTimeController.dispose();
    safetyStockController.dispose();
    serialController.dispose();
    super.dispose();
  }

  Supplier? _selectedSupplier() {
    for (final supplier in widget.suppliers) {
      if (supplier.supplierId == selectedSupplierId) {
        return supplier;
      }
    }
    return widget.suppliers.isNotEmpty ? widget.suppliers.first : null;
  }

  int? _supplierLeadTime(int supplierId) {
    for (final supplier in widget.suppliers) {
      if (supplier.supplierId == supplierId) {
        return supplier.leadTimeDays;
      }
    }
    return null;
  }

  int _parseInt(String value, {int defaultValue = 0}) {
    return int.tryParse(value.trim()) ?? defaultValue;
  }

  double _parseDouble(String value, {double defaultValue = 0}) {
    return double.tryParse(value.trim()) ?? defaultValue;
  }

  String _formatRs(num value) {
    return 'Rs. ${value.toStringAsFixed(2)}';
  }

  String _formatRsCompact(num value) {
    return 'Rs. ${NumberFormat.compact().format(value)}';
  }

  Future<void> _loadPersistedCostAssumptions() async {
    if (kIsWeb) {
      return;
    }

    setState(() {
      _loadingPreferences = true;
    });

    try {
      final prefs = await SharedPreferences.getInstance();
      if (!mounted) return;

      final savedOrderingCost = prefs.getDouble(_orderingCostPrefKey);
      final savedHoldingCost = prefs.getDouble(_holdingCostPrefKey);

      if (savedOrderingCost != null) {
        orderingCostController.text = savedOrderingCost.toStringAsFixed(2);
      }

      if (savedHoldingCost != null) {
        holdingCostController.text = savedHoldingCost.toStringAsFixed(2);
      }
    } finally {
      if (mounted) {
        setState(() {
          _loadingPreferences = false;
        });
      }
    }
  }

  Future<void> _persistCostAssumptions() async {
    if (kIsWeb) {
      return;
    }

    final orderingCost = _parseDouble(orderingCostController.text);
    final holdingCost = _parseDouble(
      holdingCostController.text,
      defaultValue: _unitCost * 0.25,
    );

    final prefs = await SharedPreferences.getInstance();
    await prefs.setDouble(_orderingCostPrefKey, orderingCost);
    await prefs.setDouble(_holdingCostPrefKey, holdingCost);
  }

  Future<void> _loadHistory() async {
    final product = widget.product;
    if (product == null || product.productId == 0) {
      if (!mounted) return;
      setState(() {
        _historicalSales = [];
        _loadingHistory = false;
      });
      return;
    }

    try {
      final sales = await _salesController.fetchSalesForProduct(
        product.productId,
      );
      if (!mounted) return;
      setState(() {
        _historicalSales = sales;
        _loadingHistory = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _historicalSales = [];
        _loadingHistory = false;
      });
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Unable to load product history: $e')),
      );
    }
  }

  List<_DailyDemandPoint> get _dailyDemandSeries {
    if (_historicalSales.isEmpty) {
      return [];
    }

    final byDay = <DateTime, int>{};
    for (final sale in _historicalSales) {
      final day = DateTime(
        sale.saleDate.year,
        sale.saleDate.month,
        sale.saleDate.day,
      );
      byDay[day] = (byDay[day] ?? 0) + sale.quantitySold;
    }

    final entries = byDay.entries.toList()
      ..sort((a, b) => a.key.compareTo(b.key));
    return entries
        .map(
          (entry) => _DailyDemandPoint(
            date: entry.key,
            quantity: entry.value.toDouble(),
          ),
        )
        .toList();
  }

  double get _dailyDemand {
    final demandSeries = _dailyDemandSeries;
    if (demandSeries.isEmpty) {
      return 0;
    }

    final totalQuantity = demandSeries.fold<double>(
      0,
      (sum, point) => sum + point.quantity,
    );
    final firstDate = demandSeries.first.date;
    final lastDate = demandSeries.last.date;
    final daySpan = math.max(1, lastDate.difference(firstDate).inDays + 1);
    return totalQuantity / daySpan;
  }

  double get _annualDemand => _dailyDemand * 365;

  double get _unitCost => _parseDouble(costController.text);

  double get _orderingCostPerOrder =>
      _parseDouble(orderingCostController.text, defaultValue: 50.0);

  double get _holdingCostPerUnitPerYear => math.max(
    1.0,
    _parseDouble(holdingCostController.text, defaultValue: _unitCost * 0.25),
  );

  int get _leadTimeDays {
    final parsed = _parseInt(leadTimeController.text);
    if (parsed > 0) {
      return parsed;
    }
    return _selectedSupplier()?.leadTimeDays ?? 0;
  }

  int get _safetyStock => _parseInt(safetyStockController.text);

  int get _reorderPoint {
    final value = (_dailyDemand * _leadTimeDays) + _safetyStock;
    return value.ceil();
  }

  double get _eoq {
    final annualDemand = _annualDemand;
    if (annualDemand <= 0) {
      return 0;
    }

    final holdingCost = _holdingCostPerUnitPerYear;
    if (holdingCost <= 0) {
      return 0;
    }

    return math.sqrt((2 * annualDemand * _orderingCostPerOrder) / holdingCost);
  }

  List<FlSpot> _buildDemandSpots(List<_DailyDemandPoint> points) {
    return List<FlSpot>.generate(
      points.length,
      (index) => FlSpot(index.toDouble(), points[index].quantity),
    );
  }

  List<FlSpot> _buildMovingAverageSpots(
    List<_DailyDemandPoint> points,
    int window,
  ) {
    if (points.isEmpty) {
      return [];
    }

    final spots = <FlSpot>[];
    for (var index = 0; index < points.length; index++) {
      final start = math.max(0, index - window + 1);
      final range = points.sublist(start, index + 1);
      final average =
          range.fold<double>(0, (sum, point) => sum + point.quantity) /
          range.length;
      spots.add(FlSpot(index.toDouble(), average));
    }
    return spots;
  }

  List<FlSpot> _buildExponentialSmoothingSpots(
    List<_DailyDemandPoint> points,
    double alpha,
  ) {
    if (points.isEmpty) {
      return [];
    }

    final spots = <FlSpot>[];
    double? previous;
    for (var index = 0; index < points.length; index++) {
      final current = points[index].quantity;
      final smoothed = previous == null
          ? current
          : (alpha * current) + ((1 - alpha) * previous);
      previous = smoothed;
      spots.add(FlSpot(index.toDouble(), smoothed));
    }
    return spots;
  }

  List<FlSpot> _buildEoqSpots(double maxQuantity, double step) {
    final spots = <FlSpot>[];
    for (double quantity = step; quantity <= maxQuantity; quantity += step) {
      final orderingCost = (_annualDemand / quantity) * _orderingCostPerOrder;
      final holdingCost = (quantity / 2) * _holdingCostPerUnitPerYear;
      spots.add(FlSpot(quantity, orderingCost + holdingCost));
    }
    return spots;
  }

  void _resetEoqChart() {
    setState(() {
      _eoqZoom = 1.0;
    });
    if (_eoqScrollController.hasClients) {
      _eoqScrollController.jumpTo(0);
    }
  }

  void _resetForecastChart() {
    setState(() {
      _forecastZoom = 1.0;
    });
    if (_forecastScrollController.hasClients) {
      _forecastScrollController.jumpTo(0);
    }
  }

  Widget _buildMetricCard(
    String label,
    String value,
    IconData icon,
    Color color,
  ) {
    return SizedBox(
      width: 170,
      child: Card(
        elevation: 0,
        color: color.withValues(alpha: 0.08),
        child: Padding(
          padding: const EdgeInsets.all(12.0),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(icon, color: color),
              const SizedBox(height: 8),
              Text(
                value,
                style: const TextStyle(
                  fontSize: 20,
                  fontWeight: FontWeight.bold,
                ),
              ),
              const SizedBox(height: 4),
              Text(label, style: TextStyle(color: Colors.grey.shade700)),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildChartCard({
    required String title,
    required String subtitle,
    required String xAxisLabel,
    required String yAxisLabel,
    required List<_ChartLegendItem> legendItems,
    required double zoom,
    required ValueChanged<double> onZoomChanged,
    required ScrollController scrollController,
    required VoidCallback onReset,
    required Widget chart,
  }) {
    return Card(
      elevation: 2,
      child: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        title,
                        style: const TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        subtitle,
                        style: TextStyle(color: Colors.grey.shade700),
                      ),
                    ],
                  ),
                ),
                TextButton.icon(
                  onPressed: onReset,
                  icon: const Icon(Icons.restart_alt),
                  label: const Text('Reset'),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Row(
              children: [
                const Icon(Icons.zoom_out, size: 18),
                Expanded(
                  child: Slider(
                    min: 1.0,
                    max: 2.5,
                    divisions: 30,
                    value: zoom,
                    label: '${zoom.toStringAsFixed(1)}x',
                    onChanged: onZoomChanged,
                  ),
                ),
                const Icon(Icons.zoom_in, size: 18),
              ],
            ),
            Scrollbar(
              controller: scrollController,
              thumbVisibility: true,
              child: SingleChildScrollView(
                controller: scrollController,
                scrollDirection: Axis.horizontal,
                child: chart,
              ),
            ),
            const SizedBox(height: 10),
            Wrap(
              spacing: 12,
              runSpacing: 8,
              children: legendItems
                  .map(
                    (item) =>
                        _buildLegendItem(color: item.color, label: item.label),
                  )
                  .toList(),
            ),
            const SizedBox(height: 8),
            Text(
              'X-axis: $xAxisLabel',
              style: TextStyle(color: Colors.grey.shade700, fontSize: 12),
            ),
            Text(
              'Y-axis: $yAxisLabel',
              style: TextStyle(color: Colors.grey.shade700, fontSize: 12),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildLegendItem({required Color color, required String label}) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 12,
          height: 12,
          decoration: BoxDecoration(color: color, shape: BoxShape.circle),
        ),
        const SizedBox(width: 6),
        Text(label, style: const TextStyle(fontSize: 12)),
      ],
    );
  }

  Widget _buildEoqChart() {
    final eoq = _eoq;
    if (_annualDemand <= 0) {
      return const SizedBox(
        width: 760,
        height: 320,
        child: Center(
          child: Text(
            'EOQ chart will appear after historical sales are available.',
          ),
        ),
      );
    }

    final maxQuantity = math.max((eoq * 2.5).ceil().toDouble(), 30.0);
    final step = math.max(1.0, (maxQuantity / 40).ceilToDouble());
    final totalCostSpots = _buildEoqSpots(maxQuantity, step);
    final orderingCostSpots = <FlSpot>[];
    final holdingCostSpots = <FlSpot>[];

    for (final spot in totalCostSpots) {
      final orderingCost = (_annualDemand / spot.x) * _orderingCostPerOrder;
      final holdingCost = (spot.x / 2) * _holdingCostPerUnitPerYear;
      orderingCostSpots.add(FlSpot(spot.x, orderingCost));
      holdingCostSpots.add(FlSpot(spot.x, holdingCost));
    }

    final optimalCost =
        (_annualDemand / eoq) * _orderingCostPerOrder +
        (eoq / 2) * _holdingCostPerUnitPerYear;
    final chartWidth = math.max(760.0, maxQuantity * 12 * _eoqZoom);

    return SizedBox(
      width: chartWidth,
      height: 320,
      child: LineChart(
        LineChartData(
          minX: 0,
          maxX: maxQuantity,
          minY: 0,
          gridData: const FlGridData(show: true),
          borderData: FlBorderData(show: true),
          titlesData: FlTitlesData(
            topTitles: const AxisTitles(
              sideTitles: SideTitles(showTitles: false),
            ),
            rightTitles: const AxisTitles(
              sideTitles: SideTitles(showTitles: false),
            ),
            bottomTitles: AxisTitles(
              sideTitles: SideTitles(
                showTitles: true,
                reservedSize: 32,
                interval: maxQuantity / 4,
                getTitlesWidget: (value, meta) {
                  return Padding(
                    padding: const EdgeInsets.only(top: 8.0),
                    child: Text(
                      value.toInt().toString(),
                      style: const TextStyle(fontSize: 10),
                    ),
                  );
                },
              ),
            ),
            leftTitles: AxisTitles(
              sideTitles: SideTitles(
                showTitles: true,
                reservedSize: 52,
                interval: math.max(1, optimalCost / 4),
                getTitlesWidget: (value, meta) {
                  return Text(
                    _formatRsCompact(value),
                    style: const TextStyle(fontSize: 10),
                  );
                },
              ),
            ),
          ),
          lineBarsData: [
            LineChartBarData(
              spots: totalCostSpots,
              isCurved: true,
              color: Colors.blue,
              barWidth: 3,
              dotData: const FlDotData(show: false),
              belowBarData: BarAreaData(
                show: true,
                color: Colors.blue.withValues(alpha: 0.08),
              ),
            ),
            LineChartBarData(
              spots: orderingCostSpots,
              isCurved: true,
              color: Colors.orange,
              barWidth: 2,
              dotData: const FlDotData(show: false),
            ),
            LineChartBarData(
              spots: holdingCostSpots,
              isCurved: true,
              color: Colors.green,
              barWidth: 2,
              dotData: const FlDotData(show: false),
            ),
            LineChartBarData(
              spots: [FlSpot(eoq, optimalCost)],
              isCurved: false,
              color: Colors.red,
              barWidth: 0,
              dotData: const FlDotData(show: true),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildForecastChart() {
    final demandSeries = _dailyDemandSeries;
    if (demandSeries.isEmpty) {
      return const SizedBox(
        width: 760,
        height: 320,
        child: Center(
          child: Text(
            'Historical sales are required for moving average and exponential smoothing forecasts.',
          ),
        ),
      );
    }

    final demandSpots = _buildDemandSpots(demandSeries);
    final movingAverageSpots = _buildMovingAverageSpots(demandSeries, 7);
    final smoothingSpots = _buildExponentialSmoothingSpots(demandSeries, 0.35);
    final maxY = math.max(
      demandSpots.map((spot) => spot.y).fold<double>(0, math.max),
      math.max(
        movingAverageSpots.map((spot) => spot.y).fold<double>(0, math.max),
        smoothingSpots.map((spot) => spot.y).fold<double>(0, math.max),
      ),
    );
    final chartWidth = math.max(
      760.0,
      demandSeries.length * 56 * _forecastZoom,
    );

    return SizedBox(
      width: chartWidth,
      height: 320,
      child: LineChart(
        LineChartData(
          minX: 0,
          maxX: math.max(0, demandSeries.length - 1).toDouble(),
          minY: 0,
          maxY: maxY * 1.3,
          gridData: const FlGridData(show: true),
          borderData: FlBorderData(show: true),
          titlesData: FlTitlesData(
            topTitles: const AxisTitles(
              sideTitles: SideTitles(showTitles: false),
            ),
            rightTitles: const AxisTitles(
              sideTitles: SideTitles(showTitles: false),
            ),
            bottomTitles: AxisTitles(
              sideTitles: SideTitles(
                showTitles: true,
                reservedSize: 32,
                interval: math
                    .max(1, (demandSeries.length / 4).floor())
                    .toDouble(),
                getTitlesWidget: (value, meta) {
                  final index = value.round();
                  if (index < 0 || index >= demandSeries.length) {
                    return const SizedBox.shrink();
                  }
                  return Padding(
                    padding: const EdgeInsets.only(top: 8.0),
                    child: Text(
                      DateFormat.Md().format(demandSeries[index].date),
                      style: const TextStyle(fontSize: 10),
                    ),
                  );
                },
              ),
            ),
            leftTitles: AxisTitles(
              sideTitles: SideTitles(
                showTitles: true,
                reservedSize: 44,
                interval: math.max(1, maxY / 4),
                getTitlesWidget: (value, meta) {
                  return Text(
                    value.toStringAsFixed(0),
                    style: const TextStyle(fontSize: 10),
                  );
                },
              ),
            ),
          ),
          lineBarsData: [
            LineChartBarData(
              spots: demandSpots,
              isCurved: false,
              color: Colors.indigo,
              barWidth: 2,
              dotData: const FlDotData(show: false),
            ),
            LineChartBarData(
              spots: movingAverageSpots,
              isCurved: true,
              color: Colors.deepOrange,
              barWidth: 2.5,
              dotData: const FlDotData(show: false),
            ),
            LineChartBarData(
              spots: smoothingSpots,
              isCurved: true,
              color: Colors.teal,
              barWidth: 2.5,
              dotData: const FlDotData(show: false),
            ),
          ],
        ),
      ),
    );
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

  Future<void> _save() async {
    try {
      await _persistCostAssumptions();
      final leadTimeDays = _leadTimeDays;
      final safetyStock = _safetyStock;
      final reorderPoint = (_dailyDemand * leadTimeDays + safetyStock).ceil();
      final updated = Product(
        productId: widget.product?.productId ?? 0,
        supplierId: selectedSupplierId,
        productName: nameController.text,
        sku: skuController.text,
        unitCost: double.parse(costController.text),
        currentQty: int.parse(qtyController.text),
        leadTimeDays: leadTimeDays,
        safetyStock: safetyStock,
        reorderPoint: reorderPoint,
        serialNo: serialController.text.isEmpty ? null : serialController.text,
        statusFlag: status,
      );

      await widget.onSave(updated);
      if (!mounted) return;
      Navigator.pop(context);
    } catch (e) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Error saving: $e')));
    }
  }

  Future<void> _delete() async {
    if (widget.onDelete == null) return;

    try {
      await widget.onDelete!();
      if (!mounted) return;
      Navigator.pop(context);
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Product deleted successfully')),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Delete cancelled: $e')));
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
          IconButton(icon: const Icon(Icons.save), onPressed: _save),
        ],
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
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
              decoration: const InputDecoration(labelText: 'Unit Cost (Rs.)'),
              keyboardType: TextInputType.number,
              onChanged: (_) => setState(() {}),
            ),
            TextField(
              controller: orderingCostController,
              decoration: const InputDecoration(
                labelText: 'Ordering Cost per Order (Rs.)',
              ),
              keyboardType: TextInputType.number,
              onChanged: (_) {
                setState(() {});
                unawaited(_persistCostAssumptions());
              },
            ),
            TextField(
              controller: holdingCostController,
              decoration: const InputDecoration(
                labelText: 'Holding Cost per Unit per Year (Rs.)',
                helperText: 'Blank defaults to 25% of unit cost (Rs.)',
              ),
              keyboardType: TextInputType.number,
              onChanged: (_) {
                setState(() {});
                unawaited(_persistCostAssumptions());
              },
            ),
            TextField(
              controller: qtyController,
              decoration: const InputDecoration(labelText: 'Current Qty'),
              keyboardType: TextInputType.number,
            ),
            TextField(
              controller: leadTimeController,
              decoration: const InputDecoration(labelText: 'Lead Time Days'),
              keyboardType: TextInputType.number,
              onChanged: (_) => setState(() {}),
            ),
            TextField(
              controller: safetyStockController,
              decoration: const InputDecoration(labelText: 'Safety Stock'),
              keyboardType: TextInputType.number,
              onChanged: (_) => setState(() {}),
            ),
            const SizedBox(height: 12),
            Card(
              elevation: 1,
              child: Padding(
                padding: const EdgeInsets.all(12.0),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'System Predictions',
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const SizedBox(height: 12),
                    Wrap(
                      spacing: 12,
                      runSpacing: 12,
                      children: [
                        _buildMetricCard(
                          'Ordering cost',
                          _formatRs(_orderingCostPerOrder),
                          Icons.shopping_cart_checkout,
                          Colors.amber,
                        ),
                        _buildMetricCard(
                          'Holding cost',
                          _formatRs(_holdingCostPerUnitPerYear),
                          Icons.account_balance_wallet,
                          Colors.green,
                        ),
                        _buildMetricCard(
                          'Daily demand',
                          _dailyDemand.toStringAsFixed(2),
                          Icons.show_chart,
                          Colors.blue,
                        ),
                        _buildMetricCard(
                          'EOQ',
                          _eoq.toStringAsFixed(1),
                          Icons.stacked_line_chart,
                          Colors.teal,
                        ),
                        _buildMetricCard(
                          'Reorder point',
                          _reorderPoint.toString(),
                          Icons.inventory_2,
                          Colors.deepOrange,
                        ),
                        _buildMetricCard(
                          'Annual demand',
                          _annualDemand.toStringAsFixed(1),
                          Icons.timeline,
                          Colors.indigo,
                        ),
                      ],
                    ),
                    const SizedBox(height: 12),
                    Text(
                      'Reorder point = (daily demand × lead time days) + safety stock',
                      style: TextStyle(color: Colors.grey.shade700),
                    ),
                    Text(
                      'EOQ uses your ordering and holding cost inputs, with the holding cost defaulting to 25% of unit cost when blank.',
                      style: TextStyle(color: Colors.grey.shade700),
                    ),
                    if (_loadingHistory) ...[
                      const SizedBox(height: 12),
                      const LinearProgressIndicator(),
                    ],
                    if (_loadingPreferences) ...[
                      const SizedBox(height: 12),
                      const LinearProgressIndicator(),
                    ],
                  ],
                ),
              ),
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
              items: statusOptions
                  .map((s) => DropdownMenuItem(value: s, child: Text(s)))
                  .toList(),
              onChanged: (value) => setState(() => status = value!),
              isExpanded: true,
            ),
            DropdownSearch<Supplier>(
              popupProps: PopupProps.menu(
                showSearchBox: true,
                searchFieldProps: TextFieldProps(
                  decoration: const InputDecoration(
                    labelText: 'Search Supplier Name or ID',
                  ),
                ),
              ),
              items: widget.suppliers,
              itemAsString: (Supplier s) =>
                  'ID: ${s.supplierId} - ${s.supplierName}',
              filterFn: (Supplier s, String filter) {
                final query = filter.toLowerCase().trim();
                if (query.isEmpty) return true;
                return s.supplierName.toLowerCase().contains(query) ||
                    s.supplierId.toString().contains(query);
              },
              selectedItem: widget.suppliers.isNotEmpty
                  ? widget.suppliers.firstWhere(
                      (s) => s.supplierId == selectedSupplierId,
                      orElse: () => widget.suppliers.first,
                    )
                  : null,
              onChanged: (Supplier? s) {
                if (s != null) {
                  setState(() {
                    selectedSupplierId = s.supplierId;
                    if (leadTimeController.text.trim().isEmpty &&
                        s.leadTimeDays != null) {
                      leadTimeController.text = s.leadTimeDays.toString();
                    }
                  });
                }
              },
              dropdownDecoratorProps: const DropDownDecoratorProps(
                dropdownSearchDecoration: InputDecoration(
                  labelText: 'Supplier',
                ),
              ),
            ),
            const SizedBox(height: 16),
            _buildChartCard(
              title: 'EOQ projection',
              subtitle:
                  'Annual total cost against order quantity, with the EOQ marked in red.',
              xAxisLabel: 'Order quantity (units per order)',
              yAxisLabel: 'Annual cost (Rs.)',
              legendItems: const [
                _ChartLegendItem(color: Colors.blue, label: 'Total cost'),
                _ChartLegendItem(color: Colors.orange, label: 'Ordering cost'),
                _ChartLegendItem(color: Colors.green, label: 'Holding cost'),
                _ChartLegendItem(color: Colors.red, label: 'EOQ point'),
              ],
              zoom: _eoqZoom,
              onZoomChanged: (value) => setState(() => _eoqZoom = value),
              scrollController: _eoqScrollController,
              onReset: _resetEoqChart,
              chart: _buildEoqChart(),
            ),
            const SizedBox(height: 16),
            _buildChartCard(
              title: 'Demand forecast',
              subtitle:
                  'Daily demand, moving average, and exponential smoothing on a horizontal timeline.',
              xAxisLabel: 'Time (day)',
              yAxisLabel: 'Demand quantity sold',
              legendItems: const [
                _ChartLegendItem(color: Colors.indigo, label: 'Actual demand'),
                _ChartLegendItem(
                  color: Colors.deepOrange,
                  label: 'Moving average (7-day)',
                ),
                _ChartLegendItem(
                  color: Colors.teal,
                  label: 'Exponential smoothing',
                ),
              ],
              zoom: _forecastZoom,
              onZoomChanged: (value) => setState(() => _forecastZoom = value),
              scrollController: _forecastScrollController,
              onReset: _resetForecastChart,
              chart: _buildForecastChart(),
            ),
          ],
        ),
      ),
    );
  }
}

class BarcodeScannerView extends StatefulWidget {
  const BarcodeScannerView({super.key});

  @override
  State<BarcodeScannerView> createState() => _BarcodeScannerViewState();
}

class _BarcodeScannerViewState extends State<BarcodeScannerView> {
  final MobileScannerController controller = MobileScannerController(
    formats: [
      BarcodeFormat.qrCode,
      BarcodeFormat.code128,
      BarcodeFormat.code39,
      BarcodeFormat.ean13,
      BarcodeFormat.ean8,
    ],
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

class _DailyDemandPoint {
  final DateTime date;
  final double quantity;

  _DailyDemandPoint({required this.date, required this.quantity});
}

class _ChartLegendItem {
  final Color color;
  final String label;

  const _ChartLegendItem({required this.color, required this.label});
}
