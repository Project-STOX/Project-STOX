import 'package:flutter/material.dart';
import 'package:fl_chart/fl_chart.dart';
import 'package:intl/intl.dart';
import '../models/user.dart';
import '../models/historical_sale.dart';
import '../controllers/auth_controller.dart';
import '../controllers/historical_sales_controller.dart';
import '../utils/csv_export_stub.dart'
    if (dart.library.html) '../utils/csv_export_web.dart'
    as csv_export;

class HistoricalSalesView extends StatefulWidget {
  final UserModel user;

  const HistoricalSalesView({super.key, required this.user});

  @override
  State<HistoricalSalesView> createState() => _HistoricalSalesViewState();
}

class _HistoricalSalesViewState extends State<HistoricalSalesView> {
  final AuthController _authController = AuthController();
  final HistoricalSalesController _salesController =
      HistoricalSalesController();

  bool _isLoading = true;
  bool _hasAccess = false;

  List<HistoricalSale> _sales = [];

  // Filters
  DateTime? _startDate;
  DateTime? _endDate;
  String _productQuery = '';
  String _supplierQuery = '';

  // Column visibility controls for the records table.
  bool _showQuantityColumn = true;
  bool _showRevenueColumn = true;
  bool _showSupplierColumn = true;

  // Line chart viewport controls.
  double _lineChartZoom = 1.0;
  double _lineChartOffset = 0.0;

  List<String> _productNames = [];
  List<String> _supplierNames = [];

  @override
  void initState() {
    super.initState();
    _checkAccessAndLoadData();
  }

  Future<void> _checkAccessAndLoadData() async {
    setState(() {
      _isLoading = true;
    });

    final hasPerm = await _authController.hasPermission(
      widget.user.roleId,
      'Historical data',
    );
    if (!mounted) {
      return;
    }
    if (!hasPerm) {
      await _salesController.logUnauthorizedAccess(widget.user.userId);
      if (!mounted) {
        return;
      }
      setState(() {
        _hasAccess = false;
        _isLoading = false;
      });
      return;
    }

    final products = await _salesController.getProductNames();
    final suppliers = await _salesController.getSupplierNames();
    if (!mounted) return;

    setState(() {
      _hasAccess = true;
      _productNames = products;
      _supplierNames = suppliers;
    });

    await _loadSalesData();
  }

  Future<void> _loadSalesData() async {
    setState(() {
      _isLoading = true;
    });

    try {
      final sales = await _salesController.fetchSales(
        startDate: _startDate,
        endDate: _endDate,
        productQuery: _productQuery,
        supplierQuery: _supplierQuery,
      );
      if (!mounted) {
        return;
      }
      setState(() {
        _sales = sales;
        _isLoading = false;
      });
    } catch (e) {
      if (!mounted) {
        return;
      }
      setState(() {
        _isLoading = false;
      });
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Error loading sales: $e')));
    }
  }

  Future<void> _exportCsv() async {
    try {
      final csvString = await _salesController.exportToCsv(
        _sales,
        widget.user.userId,
      );
      final fileName =
          'historical_sales_${DateTime.now().millisecondsSinceEpoch}.csv';
      final savedPath = await csv_export.downloadCsvWeb(csvString, fileName);

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            savedPath == null
                ? 'Data exported successfully!'
                : 'Data exported successfully to $savedPath',
          ),
        ),
      );
    } catch (e) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Export failed: $e')));
    }
  }

  Future<void> _selectDateRange(BuildContext context) async {
    final DateTimeRange? picked = await showDateRangePicker(
      context: context,
      firstDate: DateTime(2000),
      lastDate: DateTime.now(),
      initialDateRange: _startDate != null && _endDate != null
          ? DateTimeRange(start: _startDate!, end: _endDate!)
          : null,
    );
    if (picked != null) {
      setState(() {
        _startDate = picked.start;
        _endDate = picked.end;
      });
      _loadSalesData();
    }
  }

  void _clearFilters() {
    setState(() {
      _startDate = null;
      _endDate = null;
      _productQuery = '';
      _supplierQuery = '';
    });
    // This will fetch all data naturally. Note: Autocomplete TextFields won't clear automatically
    // unless their controllers are cleared, but their internal state handles it okay if user deletes text.
    _loadSalesData();
  }

  double _getTotalRevenue() {
    return _sales.fold(0.0, (sum, item) => sum + item.revenue);
  }

  String _formatRs(double value) {
    return 'Rs. ${value.toStringAsFixed(2)}';
  }

  String _formatRsCompact(double value) {
    return 'Rs. ${NumberFormat.compact().format(value)}';
  }

  String _getTopSellingProduct() {
    if (_sales.isEmpty) {
      return 'N/A';
    }
    Map<String, int> productCounts = {};
    for (var s in _sales) {
      productCounts[s.productName] =
          (productCounts[s.productName] ?? 0) + s.quantitySold;
    }
    var topProduct = productCounts.entries.reduce(
      (a, b) => a.value > b.value ? a : b,
    );
    return topProduct.key;
  }

  double _getAvgQuantity() {
    if (_sales.isEmpty) {
      return 0.0;
    }
    int totalQty = _sales.fold(0, (sum, item) => sum + item.quantitySold);
    return totalQty / _sales.length;
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoading) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }

    if (!_hasAccess) {
      return Scaffold(
        appBar: AppBar(title: const Text('Historical Sales Data')),
        body: const Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(Icons.error_outline, color: Colors.red, size: 60),
              SizedBox(height: 16),
              Text(
                'Access Denied',
                style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold),
              ),
              SizedBox(height: 8),
              Text('You do not have permission to view historical data.'),
            ],
          ),
        ),
      );
    }

    return Scaffold(
      appBar: AppBar(title: const Text('Historical Sales Data')),
      body: SingleChildScrollView(
        child: Padding(
          padding: const EdgeInsets.all(16.0),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _buildFilters(),
              const SizedBox(height: 16),
              _buildSummaryCards(),
              const SizedBox(height: 24),
              const Text(
                'Visual Insights',
                style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 16),
              SizedBox(height: 320, child: _buildBarChart()),
              const SizedBox(height: 16),
              SizedBox(height: 360, child: _buildRevenueBarChart()),
              const SizedBox(height: 16),
              SizedBox(height: 380, child: _buildLineChart()),
              const SizedBox(height: 24),
              Row(
                children: [
                  const Expanded(
                    child: Text(
                      'Detailed Records',
                      style: TextStyle(
                        fontSize: 20,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                  IconButton(
                    icon: const Icon(Icons.download),
                    tooltip: 'Export CSV',
                    onPressed: _exportCsv,
                  ),
                ],
              ),
              const SizedBox(height: 8),
              _buildRecordColumnFilters(),
              const SizedBox(height: 16),
              _buildDataTable(),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildFilters() {
    return Card(
      elevation: 2,
      child: LayoutBuilder(
        builder: (context, constraints) {
          final isNarrow = constraints.maxWidth < 760;
          final inputWidth = isNarrow ? constraints.maxWidth : 240.0;

          return Padding(
            padding: const EdgeInsets.all(12.0),
            child: Wrap(
              spacing: 10,
              runSpacing: 10,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: [
                SizedBox(
                  width: inputWidth,
                  child: Autocomplete<String>(
                    optionsBuilder: (TextEditingValue textEditingValue) {
                      _productQuery = textEditingValue.text;
                      if (textEditingValue.text.isEmpty) {
                        return const Iterable<String>.empty();
                      }
                      return _productNames.where(
                        (String option) => option.toLowerCase().contains(
                          textEditingValue.text.toLowerCase(),
                        ),
                      );
                    },
                    onSelected: (String selection) {
                      _productQuery = selection;
                      _loadSalesData();
                    },
                    fieldViewBuilder:
                        (context, controller, focusNode, onFieldSubmitted) {
                          return TextField(
                            controller: controller,
                            focusNode: focusNode,
                            decoration: InputDecoration(
                              labelText: 'Search Product',
                              prefixIcon: const Icon(Icons.search),
                              border: OutlineInputBorder(
                                borderRadius: BorderRadius.circular(8),
                              ),
                              contentPadding: const EdgeInsets.symmetric(
                                horizontal: 12,
                              ),
                            ),
                            onChanged: (val) {
                              _productQuery = val;
                              if (val.isEmpty) {
                                _loadSalesData();
                              }
                            },
                            onSubmitted: (_) {
                              onFieldSubmitted();
                              _loadSalesData();
                            },
                          );
                        },
                  ),
                ),
                SizedBox(
                  width: inputWidth,
                  child: Autocomplete<String>(
                    optionsBuilder: (TextEditingValue textEditingValue) {
                      _supplierQuery = textEditingValue.text;
                      if (textEditingValue.text.isEmpty) {
                        return const Iterable<String>.empty();
                      }
                      return _supplierNames.where(
                        (String option) => option.toLowerCase().contains(
                          textEditingValue.text.toLowerCase(),
                        ),
                      );
                    },
                    onSelected: (String selection) {
                      _supplierQuery = selection;
                      _loadSalesData();
                    },
                    fieldViewBuilder:
                        (context, controller, focusNode, onFieldSubmitted) {
                          return TextField(
                            controller: controller,
                            focusNode: focusNode,
                            decoration: InputDecoration(
                              labelText: 'Search Supplier',
                              prefixIcon: const Icon(Icons.business),
                              border: OutlineInputBorder(
                                borderRadius: BorderRadius.circular(8),
                              ),
                              contentPadding: const EdgeInsets.symmetric(
                                horizontal: 12,
                              ),
                            ),
                            onChanged: (val) {
                              _supplierQuery = val;
                              if (val.isEmpty) {
                                _loadSalesData();
                              }
                            },
                            onSubmitted: (_) {
                              onFieldSubmitted();
                              _loadSalesData();
                            },
                          );
                        },
                  ),
                ),
                ElevatedButton.icon(
                  icon: const Icon(Icons.date_range),
                  label: Text(
                    _startDate == null
                        ? 'Select Date Range'
                        : '${DateFormat('MMM d').format(_startDate!)} - ${DateFormat('MMM d').format(_endDate!)}',
                  ),
                  onPressed: () => _selectDateRange(context),
                ),
                ElevatedButton(
                  onPressed: _loadSalesData,
                  child: const Text('Apply Filter'),
                ),
                TextButton(
                  onPressed: _clearFilters,
                  child: const Text('Clear Filters'),
                ),
              ],
            ),
          );
        },
      ),
    );
  }

  Widget _buildSummaryCards() {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceAround,
      children: [
        _buildCard(
          'Total Revenue',
          _formatRs(_getTotalRevenue()),
          Icons.attach_money,
          Colors.green,
        ),
        _buildCard(
          'Top Product',
          _getTopSellingProduct(),
          Icons.star,
          Colors.orange,
        ),
        _buildCard(
          'Avg Qty Sold',
          _getAvgQuantity().toStringAsFixed(1),
          Icons.bar_chart,
          Colors.blue,
        ),
        _buildCard(
          'Total Sales',
          '${_sales.length}',
          Icons.receipt_long,
          Colors.purple,
        ),
      ],
    );
  }

  Widget _buildCard(String title, String value, IconData icon, Color color) {
    return Expanded(
      child: Card(
        elevation: 3,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        color: color.withValues(alpha: 0.1),
        margin: const EdgeInsets.symmetric(horizontal: 8),
        child: Padding(
          padding: const EdgeInsets.all(16.0),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(icon, size: 36, color: color),
              const SizedBox(height: 8),
              Text(
                title,
                style: TextStyle(fontSize: 14, color: Theme.of(context).hintColor),
              ),
              const SizedBox(height: 4),
              Text(
                value,
                style: TextStyle(
                  fontSize: 20,
                  fontWeight: FontWeight.bold,
                  color: color,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildBarChart() {
    if (_sales.isEmpty) {
      return const Center(child: Text('No data for bar chart'));
    }

    // Group sales by product to get total quantity
    Map<String, int> productQty = {};
    for (var s in _sales) {
      productQty[s.productName] =
          (productQty[s.productName] ?? 0) + s.quantitySold;
    }

    var entries = productQty.entries.toList();
    // Sort and take top 5
    entries.sort((a, b) => b.value.compareTo(a.value));
    if (entries.length > 5) entries = entries.sublist(0, 5);

    List<BarChartGroupData> barGroups = [];
    for (int i = 0; i < entries.length; i++) {
      barGroups.add(
        BarChartGroupData(
          x: i,
          barRods: [
            BarChartRodData(
              toY: entries[i].value.toDouble(),
              color: Colors.blueAccent,
              width: 20,
              borderRadius: BorderRadius.circular(4),
            ),
          ],
        ),
      );
    }

    return Card(
      elevation: 2,
      child: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          children: [
            const Text('Quantity Sold (Top 5 Products)'),
            const SizedBox(height: 16),
            Expanded(
              child: BarChart(
                BarChartData(
                  alignment: BarChartAlignment.spaceAround,
                  barGroups: barGroups,
                  titlesData: FlTitlesData(
                    bottomTitles: AxisTitles(
                      sideTitles: SideTitles(
                        showTitles: true,
                        getTitlesWidget: (value, meta) {
                          if (value.toInt() >= 0 &&
                              value.toInt() < entries.length) {
                            String name = entries[value.toInt()].key;
                            if (name.length > 8) {
                              name = '${name.substring(0, 8)}...';
                            }
                            return Padding(
                              padding: const EdgeInsets.only(top: 8),
                              child: Text(
                                name,
                                style: TextStyle(fontSize: 10, color: Theme.of(context).textTheme.bodySmall?.color),
                              ),
                            );
                          }
                          return const Text('');
                        },
                      ),
                    ),
                    leftTitles: AxisTitles(
                      sideTitles: SideTitles(
                        showTitles: true,
                        reservedSize: 40,
                        getTitlesWidget: (value, meta) => Text(
                          value.toInt().toString(),
                          style: TextStyle(fontSize: 10, color: Theme.of(context).textTheme.bodySmall?.color),
                        ),
                      ),
                    ),
                    topTitles: const AxisTitles(
                      sideTitles: SideTitles(showTitles: false),
                    ),
                    rightTitles: const AxisTitles(
                      sideTitles: SideTitles(showTitles: false),
                    ),
                  ),
                  borderData: FlBorderData(show: false),
                  gridData: const FlGridData(show: false),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildRevenueBarChart() {
    if (_sales.isEmpty) {
      return const Center(child: Text('No data for revenue chart'));
    }

    // Revenue contribution by product, shown as vertical columns for readability.
    Map<String, double> productRev = {};
    for (var s in _sales) {
      productRev[s.productName] =
          (productRev[s.productName] ?? 0.0) + s.revenue;
    }

    var entries = productRev.entries.toList();
    entries.sort((a, b) => b.value.compareTo(a.value));
    if (entries.length > 6) {
      entries = entries.sublist(0, 6);
    }

    final barGroups = <BarChartGroupData>[];
    for (int i = 0; i < entries.length; i++) {
      barGroups.add(
        BarChartGroupData(
          x: i,
          barRods: [
            BarChartRodData(
              toY: entries[i].value,
              color: Colors.deepPurple,
              width: 18,
              borderRadius: BorderRadius.circular(4),
            ),
          ],
        ),
      );
    }

    return Card(
      elevation: 2,
      child: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          children: [
            const Text('Revenue Distribution (Top Products)'),
            const SizedBox(height: 16),
            Expanded(
              child: BarChart(
                BarChartData(
                  alignment: BarChartAlignment.spaceAround,
                  barGroups: barGroups,
                  gridData: const FlGridData(show: true),
                  borderData: FlBorderData(show: false),
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
                        getTitlesWidget: (value, meta) {
                          final index = value.toInt();
                          if (index < 0 || index >= entries.length) {
                            return const SizedBox.shrink();
                          }
                          final raw = entries[index].key;
                          final label = raw.length > 10
                              ? '${raw.substring(0, 10)}...'
                              : raw;
                          return Padding(
                            padding: const EdgeInsets.only(top: 8.0),
                            child: Text(
                              label,
                              style: TextStyle(fontSize: 10, color: Theme.of(context).textTheme.bodySmall?.color),
                            ),
                          );
                        },
                      ),
                    ),
                    leftTitles: AxisTitles(
                      sideTitles: SideTitles(
                        showTitles: true,
                        reservedSize: 48,
                        getTitlesWidget: (value, meta) => Text(
                          _formatRsCompact(value),
                          style: TextStyle(fontSize: 10, color: Theme.of(context).textTheme.bodySmall?.color),
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  void _resetRecordColumns() {
    setState(() {
      _showQuantityColumn = true;
      _showRevenueColumn = true;
      _showSupplierColumn = true;
    });
  }

  Widget _buildRecordColumnFilters() {
    return Card(
      elevation: 1,
      child: Padding(
        padding: const EdgeInsets.all(12.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Choose visible columns',
              style: TextStyle(fontWeight: FontWeight.w600),
            ),
            const SizedBox(height: 10),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                FilterChip(
                  label: const Text('ID'),
                  selected: true,
                  onSelected: null,
                ),
                FilterChip(
                  label: const Text('Product'),
                  selected: true,
                  onSelected: null,
                ),
                FilterChip(
                  label: const Text('Date'),
                  selected: true,
                  onSelected: null,
                ),
                FilterChip(
                  label: const Text('Quantity'),
                  selected: _showQuantityColumn,
                  onSelected: (value) =>
                      setState(() => _showQuantityColumn = value),
                ),
                FilterChip(
                  label: const Text('Revenue'),
                  selected: _showRevenueColumn,
                  onSelected: (value) =>
                      setState(() => _showRevenueColumn = value),
                ),
                FilterChip(
                  label: const Text('Supplier'),
                  selected: _showSupplierColumn,
                  onSelected: (value) =>
                      setState(() => _showSupplierColumn = value),
                ),
              ],
            ),
            const SizedBox(height: 6),
            TextButton(
              onPressed: _resetRecordColumns,
              child: const Text('Reset Columns'),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildLineChart() {
    if (_sales.isEmpty) {
      return const Center(child: Text('No data for line chart'));
    }

    // Process data: group revenue by date (month/year)
    // For simplicity, grouping by exact date and sorting
    Map<String, double> dateRev = {};
    for (var s in _sales) {
      String dateStr = DateFormat('yyyy-MM-dd').format(s.saleDate);
      dateRev[dateStr] = (dateRev[dateStr] ?? 0.0) + s.revenue;
    }

    var sortedKeys = dateRev.keys.toList()..sort();
    List<FlSpot> spots = [];
    List<FlSpot> movingAvgSpots = [];
    double maxX = (sortedKeys.length - 1).toDouble();
    if (maxX < 1) maxX = 1;
    List<FlSpot> smoothingSpots = [];

    for (int i = 0; i < sortedKeys.length; i++) {
      final revenue = dateRev[sortedKeys[i]]!;
      spots.add(FlSpot(i.toDouble(), revenue));

      // 3-point moving average keeps trends readable when the dataset is dense.
      final start = i < 2 ? 0 : i - 2;
      double sum = 0;
      for (int j = start; j <= i; j++) {
        sum += dateRev[sortedKeys[j]]!;
      }
      final avg = sum / (i - start + 1);
      movingAvgSpots.add(FlSpot(i.toDouble(), avg));
    }

    // Exponential smoothing highlights trend while damping short-term noise.
    const alpha = 0.35;
    double? previousSmoothed;
    for (int i = 0; i < sortedKeys.length; i++) {
      final actual = dateRev[sortedKeys[i]]!;
      final smoothed = previousSmoothed == null
          ? actual
          : (alpha * actual) + ((1 - alpha) * previousSmoothed);
      previousSmoothed = smoothed;
      smoothingSpots.add(FlSpot(i.toDouble(), smoothed));
    }

    double maxY = 0;
    for (final spot in spots) {
      if (spot.y > maxY) maxY = spot.y;
    }
    if (maxY <= 0) maxY = 1;

    final totalPoints = sortedKeys.length;
    final visiblePoints = (totalPoints / _lineChartZoom).ceil().clamp(
      2,
      totalPoints,
    );
    final maxStart = (totalPoints - visiblePoints).toDouble();
    final currentOffset = _lineChartOffset.clamp(0.0, maxStart);
    final startIndex = currentOffset.floor();
    final endIndex = (startIndex + visiblePoints - 1).clamp(0, totalPoints - 1);

    return Card(
      elevation: 2,
      child: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const Text('Revenue Trends Over Time', textAlign: TextAlign.center),
            const SizedBox(height: 4),
            Text(
              'Use the zoom slider, drag chart to pan, tap points for values',
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 12, color: Colors.grey[700]),
            ),
            const SizedBox(height: 16),
            Row(
              children: [
                const Text(
                  'Zoom',
                  style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600),
                ),
                Expanded(
                  child: Slider(
                    value: _lineChartZoom,
                    min: 1,
                    max: 4,
                    divisions: 6,
                    label: '${_lineChartZoom.toStringAsFixed(1)}x',
                    onChanged: (value) {
                      setState(() {
                        _lineChartZoom = value;
                        final newVisiblePoints = (totalPoints / _lineChartZoom)
                            .ceil()
                            .clamp(2, totalPoints);
                        final newMaxStart = (totalPoints - newVisiblePoints)
                            .toDouble();
                        _lineChartOffset = _lineChartOffset.clamp(
                          0.0,
                          newMaxStart,
                        );
                      });
                    },
                  ),
                ),
                TextButton(
                  onPressed: () {
                    setState(() {
                      _lineChartZoom = 1.0;
                      _lineChartOffset = 0.0;
                    });
                  },
                  child: const Text('Reset'),
                ),
              ],
            ),
            Wrap(
              alignment: WrapAlignment.center,
              spacing: 16,
              runSpacing: 8,
              children: [
                _buildLegendItem(Colors.green, 'Revenue'),
                _buildLegendItem(Colors.orange, '3-Point Moving Avg'),
                _buildLegendItem(Colors.blue, 'Exponential Smoothing'),
              ],
            ),
            const SizedBox(height: 10),
            Expanded(
              child: GestureDetector(
                onHorizontalDragUpdate: (details) {
                  if (maxStart <= 0) {
                    return;
                  }
                  setState(() {
                    _lineChartOffset =
                        (_lineChartOffset - (details.primaryDelta ?? 0) / 24)
                            .clamp(0.0, maxStart);
                  });
                },
                child: LineChart(
                  LineChartData(
                    minX: startIndex.toDouble(),
                    maxX: endIndex.toDouble(),
                    minY: 0,
                    maxY: maxY * 1.15,
                    lineTouchData: LineTouchData(
                      enabled: true,
                      handleBuiltInTouches: true,
                      touchTooltipData: LineTouchTooltipData(
                        getTooltipItems: (touchedSpots) {
                          return touchedSpots.map((spot) {
                            final index = spot.x.toInt();
                            final date = index >= 0 && index < sortedKeys.length
                                ? sortedKeys[index]
                                : 'Unknown';
                            final seriesName = spot.barIndex == 0
                                ? 'Revenue'
                                : spot.barIndex == 1
                                ? '3-Point Moving Avg'
                                : 'Exponential Smoothing';
                            return LineTooltipItem(
                              '$seriesName\n$date\n${_formatRs(spot.y)}',
                              const TextStyle(
                                color: Colors.white,
                                fontWeight: FontWeight.bold,
                                fontSize: 11,
                              ),
                            );
                          }).toList();
                        },
                      ),
                    ),
                    gridData: const FlGridData(show: true),
                    titlesData: FlTitlesData(
                      bottomTitles: AxisTitles(
                        sideTitles: SideTitles(
                          showTitles: true,
                          reservedSize: 30,
                          getTitlesWidget: (value, meta) {
                            int index = value.toInt();
                            if (index >= 0 && index < sortedKeys.length) {
                              final visibleSpan = endIndex - startIndex + 1;
                              final step = visibleSpan > 12
                                  ? (visibleSpan / 6).ceil()
                                  : 1;
                              if ((index - startIndex) % step != 0 &&
                                  index != endIndex) {
                                return const Text('');
                              }
                              return Padding(
                                padding: const EdgeInsets.only(top: 8.0),
                                child: Text(
                                  sortedKeys[index].substring(5),
                                  style: const TextStyle(fontSize: 10),
                                ),
                              );
                            }
                            return const Text('');
                          },
                        ),
                      ),
                      leftTitles: AxisTitles(
                        sideTitles: SideTitles(
                          showTitles: true,
                          reservedSize: 40,
                          getTitlesWidget: (value, meta) => Text(
                            value.toInt().toString(),
                            style: const TextStyle(fontSize: 10),
                          ),
                        ),
                      ),
                      topTitles: const AxisTitles(
                        sideTitles: SideTitles(showTitles: false),
                      ),
                      rightTitles: const AxisTitles(
                        sideTitles: SideTitles(showTitles: false),
                      ),
                    ),
                    borderData: FlBorderData(
                      show: true,
                      border: Border.all(
                        color: Colors.grey.withValues(alpha: 0.5),
                      ),
                    ),
                    lineBarsData: [
                      LineChartBarData(
                        spots: spots,
                        isCurved: true,
                        color: Colors.green,
                        barWidth: 3,
                        isStrokeCapRound: true,
                        dotData: const FlDotData(show: true),
                        belowBarData: BarAreaData(
                          show: true,
                          color: Colors.green.withValues(alpha: 0.2),
                        ),
                      ),
                      LineChartBarData(
                        spots: movingAvgSpots,
                        isCurved: true,
                        color: Colors.orange,
                        barWidth: 2,
                        isStrokeCapRound: true,
                        dotData: const FlDotData(show: false),
                        belowBarData: BarAreaData(show: false),
                      ),
                      LineChartBarData(
                        spots: smoothingSpots,
                        isCurved: true,
                        color: Colors.blue,
                        barWidth: 2,
                        isStrokeCapRound: true,
                        dotData: const FlDotData(show: false),
                        belowBarData: BarAreaData(show: false),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildLegendItem(Color color, String label) {
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

  Widget _buildDataTable() {
    if (_sales.isEmpty) {
      return const Center(
        child: Padding(
          padding: EdgeInsets.all(16.0),
          child: Text('No historical sales match your criteria.'),
        ),
      );
    }

    final columns = <DataColumn>[];
    columns.add(const DataColumn(label: Text('ID')));
    columns.add(const DataColumn(label: Text('Product')));
    columns.add(const DataColumn(label: Text('Date')));
    if (_showQuantityColumn) {
      columns.add(const DataColumn(label: Text('Quantity')));
    }
    if (_showRevenueColumn) {
      columns.add(const DataColumn(label: Text('Revenue')));
    }
    if (_showSupplierColumn) {
      columns.add(const DataColumn(label: Text('Supplier')));
    }

    if (columns.isEmpty) {
      return const Center(
        child: Padding(
          padding: EdgeInsets.all(16.0),
          child: Text('Select at least one column to display records.'),
        ),
      );
    }

    return LayoutBuilder(
      builder: (context, constraints) {
        return SingleChildScrollView(
          child: PaginatedDataTable(
            header: const Text('Sales Records'),
            columnSpacing: 24,
            rowsPerPage: _sales.length > 10 ? 10 : _sales.length,
            columns: columns,
            source: SalesDataSource(
              sales: _sales,
              showIdColumn: true,
              showProductColumn: true,
              showDateColumn: true,
              showQuantityColumn: _showQuantityColumn,
              showRevenueColumn: _showRevenueColumn,
              showSupplierColumn: _showSupplierColumn,
            ),
          ),
        );
      },
    );
  }
}

class SalesDataSource extends DataTableSource {
  final List<HistoricalSale> sales;
  final bool showIdColumn;
  final bool showProductColumn;
  final bool showDateColumn;
  final bool showQuantityColumn;
  final bool showRevenueColumn;
  final bool showSupplierColumn;

  SalesDataSource({
    required this.sales,
    required this.showIdColumn,
    required this.showProductColumn,
    required this.showDateColumn,
    required this.showQuantityColumn,
    required this.showRevenueColumn,
    required this.showSupplierColumn,
  });

  @override
  DataRow? getRow(int index) {
    if (index >= sales.length) {
      return null;
    }
    final sale = sales[index];

    final cells = <DataCell>[];
    if (showIdColumn) {
      cells.add(DataCell(Text(sale.saleId.toString())));
    }
    if (showProductColumn) {
      cells.add(DataCell(Text(sale.productCode != null && sale.productCode!.isNotEmpty ? '${sale.productName} (${sale.productCode})' : sale.productName)));
    }
    if (showDateColumn) {
      cells.add(DataCell(Text(DateFormat('yyyy-MM-dd').format(sale.saleDate))));
    }
    if (showQuantityColumn) {
      cells.add(DataCell(Text(sale.quantitySold.toString())));
    }
    if (showRevenueColumn) {
      cells.add(DataCell(Text('Rs. ${sale.revenue.toStringAsFixed(2)}')));
    }
    if (showSupplierColumn) {
      cells.add(DataCell(Text(sale.supplier ?? '-')));
    }

    return DataRow(cells: cells);
  }

  @override
  bool get isRowCountApproximate => false;

  @override
  int get rowCount => sales.length;

  @override
  int get selectedRowCount => 0;
}
