import 'package:flutter/material.dart';
import 'package:fl_chart/fl_chart.dart';
import 'package:intl/intl.dart';
import '../models/user.dart';
import '../models/historical_sale.dart';
import '../controllers/auth_controller.dart';
import '../controllers/historical_sales_controller.dart';
import '../utils/csv_export_stub.dart' if (dart.library.js_interop) '../utils/csv_export_web.dart';

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
    if (!hasPerm) {
      await _salesController.logUnauthorizedAccess(widget.user.userId);
      setState(() {
        _hasAccess = false;
        _isLoading = false;
      });
      return;
    }

    final products = await _salesController.getProductNames();
    final suppliers = await _salesController.getSupplierNames();

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
      setState(() {
        _sales = sales;
        _isLoading = false;
      });
    } catch (e) {
      setState(() {
        _isLoading = false;
      });
      if (!mounted) return;
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
      final filename = "historical_sales_${DateTime.now().millisecondsSinceEpoch}.csv";
      final savedPath = await downloadCsvWeb(csvString, filename);

      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            savedPath != null
                ? 'Saved to: $savedPath'
                : 'File downloaded successfully!',
          ),
          duration: const Duration(seconds: 5),
        ),
      );
    } catch (e) {
      if (!mounted) return;
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

  String _getTopSellingProduct() {
    if (_sales.isEmpty) return 'N/A';
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
    if (_sales.isEmpty) return 0.0;
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
      appBar: AppBar(
        title: const Text('Historical Sales Data'),
        actions: [
          IconButton(
            icon: const Icon(Icons.download),
            tooltip: 'Export CSV',
            onPressed: _exportCsv,
          ),
        ],
      ),
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
              LayoutBuilder(
                builder: (context, constraints) {
                  if (constraints.maxWidth > 600) {
                    return SizedBox(
                      height: 380,
                      child: Row(
                        children: [
                          Expanded(child: _buildBarChart()),
                          const SizedBox(width: 16),
                          Expanded(child: _buildPieChart()),
                        ],
                      ),
                    );
                  } else {
                    return Column(
                      children: [
                        SizedBox(height: 300, child: _buildBarChart()),
                        const SizedBox(height: 16),
                        SizedBox(height: 310, child: _buildPieChart()),
                      ],
                    );
                  }
                },
              ),
              const SizedBox(height: 16),
              SizedBox(height: 300, child: _buildLineChart()),
              const SizedBox(height: 24),
              const Text(
                'Detailed Records',
                style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
              ),
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
      child: Padding(
        padding: const EdgeInsets.all(12.0),
        child: Wrap(
          spacing: 16,
          runSpacing: 16,
          crossAxisAlignment: WrapCrossAlignment.center,
          children: [
            SizedBox(
              width: 200,
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
                          if (val.isEmpty) _loadSalesData();
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
              width: 200,
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
                          if (val.isEmpty) _loadSalesData();
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
      ),
    );
  }

  Widget _buildSummaryCards() {
    final cards = [
      _buildCard(
        'Total Revenue',
        '\$${_getTotalRevenue().toStringAsFixed(2)}',
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
    ];

    return LayoutBuilder(
      builder: (context, constraints) {
        if (constraints.maxWidth > 600) {
          return Row(
            mainAxisAlignment: MainAxisAlignment.spaceAround,
            children: cards.map((c) => Expanded(child: c)).toList(),
          );
        } else {
          return GridView.count(
            crossAxisCount: 2,
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            childAspectRatio: 1.2,
            mainAxisSpacing: 8,
            crossAxisSpacing: 8,
            children: cards,
          );
        }
      },
    );
  }

  Widget _buildCard(String title, String value, IconData icon, Color color) {
    return Card(
      elevation: 3,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      color: color.withValues(alpha: 0.1),
      margin: const EdgeInsets.symmetric(horizontal: 4),
      child: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(icon, size: 36, color: color),
            const SizedBox(height: 8),
            Text(
              title,
              style: TextStyle(fontSize: 14, color: Colors.grey[700]),
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

  Widget _buildPieChart() {
    if (_sales.isEmpty) {
      return const Center(child: Text('No data for pie chart'));
    }

    Map<String, double> productRev = {};
    for (var s in _sales) {
      productRev[s.productName] =
          (productRev[s.productName] ?? 0.0) + s.revenue;
    }

    var entries = productRev.entries.toList();
    entries.sort((a, b) => b.value.compareTo(a.value));
    if (entries.length > 5) {
      double others =
          entries.sublist(5).fold(0.0, (sum, item) => sum + item.value);
      entries = entries.sublist(0, 5);
      entries.add(MapEntry('Others', others));
    }

    final List<Color> colors = [
      const Color(0xFF5C6BC0),
      const Color(0xFFFF7043),
      const Color(0xFF66BB6A),
      const Color(0xFFAB47BC),
      const Color(0xFFEF5350),
      const Color(0xFF78909C),
    ];

    List<PieChartSectionData> sections = [];
    for (int i = 0; i < entries.length; i++) {
      sections.add(
        PieChartSectionData(
          color: colors[i % colors.length],
          value: entries[i].value,
          title: '',
          radius: 55,
          badgeWidget: null,
        ),
      );
    }

    return Card(
      elevation: 2,
      child: Padding(
        padding: const EdgeInsets.all(12.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            const Center(
              child: Text(
                'Revenue Contribution',
                style: TextStyle(fontWeight: FontWeight.bold),
              ),
            ),
            const SizedBox(height: 8),
            // Fixed height for pie — legend won't be pushed out
            SizedBox(
              height: 140,
              child: PieChart(
                PieChartData(
                  sections: sections,
                  centerSpaceRadius: 24,
                  sectionsSpace: 3,
                  pieTouchData: PieTouchData(
                    touchCallback: (FlTouchEvent event, pieTouchResponse) {},
                  ),
                ),
              ),
            ),
            const SizedBox(height: 10),
            // --- Legend ---
            Wrap(
              spacing: 8,
              runSpacing: 6,
              children: List.generate(entries.length, (i) {
                final total = entries.fold(0.0, (s, e) => s + e.value);
                final pct = total > 0
                    ? (entries[i].value / total * 100).toStringAsFixed(1)
                    : '0';
                return Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Container(
                      width: 10,
                      height: 10,
                      decoration: BoxDecoration(
                        color: colors[i % colors.length],
                        shape: BoxShape.circle,
                      ),
                    ),
                    const SizedBox(width: 4),
                    Text(
                      '${entries[i].key} ($pct%)',
                      style: const TextStyle(fontSize: 10),
                      overflow: TextOverflow.ellipsis,
                    ),
                  ],
                );
              }),
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

    Map<String, double> dateRev = {};
    for (var s in _sales) {
      String dateStr = DateFormat('yyyy-MM-dd').format(s.saleDate);
      dateRev[dateStr] = (dateRev[dateStr] ?? 0.0) + s.revenue;
    }

    var sortedKeys = dateRev.keys.toList()..sort();
    List<FlSpot> spots = [];
    for (int i = 0; i < sortedKeys.length; i++) {
      spots.add(FlSpot(i.toDouble(), dateRev[sortedKeys[i]]!));
    }

    final lineColor = const Color(0xFF26A69A);
    final fillColor = lineColor.withValues(alpha: 0.15);
    final borderColor = Colors.grey.withValues(alpha: 0.4);

    final chart = LineChart(
      LineChartData(
        clipData: const FlClipData.all(),
        gridData: FlGridData(
          show: true,
          getDrawingHorizontalLine: (v) =>
              FlLine(color: borderColor, strokeWidth: 0.8),
          getDrawingVerticalLine: (v) =>
              FlLine(color: borderColor, strokeWidth: 0.8),
        ),
        titlesData: FlTitlesData(
          bottomTitles: AxisTitles(
            sideTitles: SideTitles(
              showTitles: true,
              reservedSize: 32,
              getTitlesWidget: (value, meta) {
                int index = value.toInt();
                if (index < 0 || index >= sortedKeys.length) {
                  return const Text('');
                }
                if (sortedKeys.length > 10 &&
                    index % (sortedKeys.length ~/ 5) != 0) {
                  return const Text('');
                }
                return Padding(
                  padding: const EdgeInsets.only(top: 6.0),
                  child: Text(
                    sortedKeys[index].substring(5), // MM-DD
                    style: const TextStyle(fontSize: 9),
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
                '\$${value.toInt()}',
                style: const TextStyle(fontSize: 9),
              ),
            ),
          ),
          topTitles:
              const AxisTitles(sideTitles: SideTitles(showTitles: false)),
          rightTitles:
              const AxisTitles(sideTitles: SideTitles(showTitles: false)),
        ),
        borderData: FlBorderData(
          show: true,
          border: Border.all(color: borderColor),
        ),
        lineTouchData: LineTouchData(
          enabled: true,
          touchTooltipData: LineTouchTooltipData(
            getTooltipItems: (touchedSpots) {
              return touchedSpots.map((spot) {
                final date = sortedKeys[spot.x.toInt()];
                return LineTooltipItem(
                  '$date\n\$${spot.y.toStringAsFixed(2)}',
                  const TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.bold,
                    fontSize: 12,
                  ),
                );
              }).toList();
            },
          ),
        ),
        lineBarsData: [
          LineChartBarData(
            spots: spots,
            isCurved: true,
            color: lineColor,
            barWidth: 2.5,
            isStrokeCapRound: true,
            dotData: FlDotData(
              show: true,
              getDotPainter: (spot, percent, bar, index) =>
                  FlDotCirclePainter(
                radius: 3,
                color: lineColor,
                strokeWidth: 1.5,
                strokeColor: Colors.white,
              ),
            ),
            belowBarData: BarAreaData(show: true, color: fillColor),
          ),
        ],
      ),
    );

    return Card(
      elevation: 2,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // Title + legend row
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                const Text(
                  'Revenue Trends Over Time',
                  style: TextStyle(fontWeight: FontWeight.bold),
                ),
                Row(
                  children: [
                    Container(
                      width: 16,
                      height: 4,
                      decoration: BoxDecoration(
                        color: lineColor,
                        borderRadius: BorderRadius.circular(2),
                      ),
                    ),
                    const SizedBox(width: 6),
                    const Text('Daily Revenue', style: TextStyle(fontSize: 12)),
                  ],
                ),
              ],
            ),
            const SizedBox(height: 4),
            const Text(
              'Pinch or scroll to zoom · Drag to pan',
              style: TextStyle(fontSize: 10, color: Colors.grey),
            ),
            const SizedBox(height: 12),
            Expanded(
              child: InteractiveViewer(
                boundaryMargin: const EdgeInsets.all(20),
                minScale: 0.8,
                maxScale: 6.0,
                child: chart,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildDataTable() {
    if (_sales.isEmpty) {
      return const Card(
        child: Padding(
          padding: EdgeInsets.all(32.0),
          child: Center(
            child: Text('No historical sales match your criteria.'),
          ),
        ),
      );
    }

    // Manual pagination for standard DataTable (which is more compatible with nested scrolls)
    return Padding(
      padding: const EdgeInsets.only(bottom: 24.0),
      child: _ManualSalesTable(sales: _sales),
    );
  }
}

class _ManualSalesTable extends StatefulWidget {
  final List<HistoricalSale> sales;
  const _ManualSalesTable({required this.sales});

  @override
  State<_ManualSalesTable> createState() => _ManualSalesTableState();
}

class _ManualSalesTableState extends State<_ManualSalesTable> {
  final int _rowsPerPage = 10;
  int _currentPage = 0;

  @override
  Widget build(BuildContext context) {
    final int start = _currentPage * _rowsPerPage;
    final int end =
        (start + _rowsPerPage).clamp(0, widget.sales.length);
    final pageRows = widget.sales.sublist(start, end);
    final int totalPages = (widget.sales.length / _rowsPerPage).ceil();

    return Card(
      elevation: 2,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const Padding(
            padding: EdgeInsets.all(16.0),
            child: Text(
              'Sales Records',
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
            ),
          ),
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: DataTable(
              columns: const [
                DataColumn(label: Text('Product')),
                DataColumn(label: Text('Date')),
                DataColumn(label: Text('Qty')),
                DataColumn(label: Text('Revenue')),
                DataColumn(label: Text('Supplier')),
              ],
              rows: pageRows.map((sale) {
                return DataRow(cells: [
                  DataCell(Text(sale.productName)),
                  DataCell(Text(DateFormat('yyyy-MM-dd HH:mm').format(sale.saleDate))),
                  DataCell(Text(sale.quantitySold.toString())),
                  DataCell(Text('\$${sale.revenue.toStringAsFixed(2)}')),
                  DataCell(Text(sale.supplier ?? '-')),
                ]);
              }).toList(),
            ),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 8.0, horizontal: 16.0),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                Text(
                  '${start + 1}-$end of ${widget.sales.length}',
                  style: const TextStyle(fontSize: 12),
                ),
                const SizedBox(width: 16),
                IconButton(
                  icon: const Icon(Icons.chevron_left, size: 20),
                  onPressed: _currentPage > 0
                      ? () => setState(() => _currentPage--)
                      : null,
                ),
                IconButton(
                  icon: const Icon(Icons.chevron_right, size: 20),
                  onPressed: _currentPage < totalPages - 1
                      ? () => setState(() => _currentPage++)
                      : null,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }


}

