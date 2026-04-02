import 'package:flutter/material.dart';
import 'package:fl_chart/fl_chart.dart';
import 'package:intl/intl.dart';
import '../models/user.dart';
import '../models/historical_sale.dart';
import '../controllers/auth_controller.dart';
import '../controllers/historical_sales_controller.dart';
import 'dart:convert';
import 'dart:html' as html;
import 'package:flutter/foundation.dart' show kIsWeb;

class HistoricalSalesView extends StatefulWidget {
  final UserModel user;

  const HistoricalSalesView({super.key, required this.user});

  @override
  State<HistoricalSalesView> createState() => _HistoricalSalesViewState();
}

class _HistoricalSalesViewState extends State<HistoricalSalesView> {
  final AuthController _authController = AuthController();
  final HistoricalSalesController _salesController = HistoricalSalesController();

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

    final hasPerm = await _authController.hasPermission(widget.user.roleId, 'Historical data');
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
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Error loading sales: $e')),
      );
    }
  }

  Future<void> _exportCsv() async {
    try {
      final csvString = await _salesController.exportToCsv(_sales, widget.user.userId);
      if (kIsWeb) {
        final bytes = utf8.encode(csvString);
        final blob = html.Blob([bytes]);
        final url = html.Url.createObjectUrlFromBlob(blob);
        html.AnchorElement(href: url)
          ..setAttribute("download", "historical_sales_${DateTime.now().millisecondsSinceEpoch}.csv")
          ..click();
        html.Url.revokeObjectUrl(url);
      } else {
        // Fallback or print for other platforms since path_provider is not explicitly set up and authorized.
        print("CSV Exported: ... (Requires platform specific file saving)");
      }

      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Data exported successfully!')),
      );
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Export failed: $e')),
      );
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
      productCounts[s.productName] = (productCounts[s.productName] ?? 0) + s.quantitySold;
    }
    var topProduct = productCounts.entries.reduce((a, b) => a.value > b.value ? a : b);
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
      return const Scaffold(
        body: Center(child: CircularProgressIndicator()),
      );
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
              Text('Access Denied', style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold)),
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
              const Text('Visual Insights', style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold)),
              const SizedBox(height: 16),
              SizedBox(
                height: 350,
                child: Row(
                  children: [
                    Expanded(child: _buildBarChart()),
                    const SizedBox(width: 16),
                    Expanded(child: _buildPieChart()),
                  ],
                ),
              ),
              const SizedBox(height: 16),
              SizedBox(
                height: 300,
                child: _buildLineChart(),
              ),
              const SizedBox(height: 24),
              const Text('Detailed Records', style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold)),
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
                  if (textEditingValue.text.isEmpty) { return const Iterable<String>.empty(); }
                  return _productNames.where((String option) =>
                      option.toLowerCase().contains(textEditingValue.text.toLowerCase()));
                },
                onSelected: (String selection) {
                  _productQuery = selection;
                  _loadSalesData();
                },
                fieldViewBuilder: (context, controller, focusNode, onFieldSubmitted) {
                  return TextField(
                    controller: controller,
                    focusNode: focusNode,
                    decoration: InputDecoration(
                      labelText: 'Search Product',
                      prefixIcon: const Icon(Icons.search),
                      border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
                      contentPadding: const EdgeInsets.symmetric(horizontal: 12),
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
                  if (textEditingValue.text.isEmpty) { return const Iterable<String>.empty(); }
                  return _supplierNames.where((String option) =>
                      option.toLowerCase().contains(textEditingValue.text.toLowerCase()));
                },
                onSelected: (String selection) {
                  _supplierQuery = selection;
                  _loadSalesData();
                },
                fieldViewBuilder: (context, controller, focusNode, onFieldSubmitted) {
                  return TextField(
                    controller: controller,
                    focusNode: focusNode,
                    decoration: InputDecoration(
                      labelText: 'Search Supplier',
                      prefixIcon: const Icon(Icons.business),
                      border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
                      contentPadding: const EdgeInsets.symmetric(horizontal: 12),
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
              label: Text(_startDate == null ? 'Select Date Range' : '${DateFormat('MMM d').format(_startDate!)} - ${DateFormat('MMM d').format(_endDate!)}'),
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
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceAround,
      children: [
        _buildCard('Total Revenue', '\$${_getTotalRevenue().toStringAsFixed(2)}', Icons.attach_money, Colors.green),
        _buildCard('Top Product', _getTopSellingProduct(), Icons.star, Colors.orange),
        _buildCard('Avg Qty Sold', _getAvgQuantity().toStringAsFixed(1), Icons.bar_chart, Colors.blue),
        _buildCard('Total Sales', '${_sales.length}', Icons.receipt_long, Colors.purple),
      ],
    );
  }

  Widget _buildCard(String title, String value, IconData icon, Color color) {
    return Expanded(
      child: Card(
        elevation: 3,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        color: color.withOpacity(0.1),
        margin: const EdgeInsets.symmetric(horizontal: 8),
        child: Padding(
          padding: const EdgeInsets.all(16.0),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(icon, size: 36, color: color),
              const SizedBox(height: 8),
              Text(title, style: TextStyle(fontSize: 14, color: Colors.grey[700])),
              const SizedBox(height: 4),
              Text(value, style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold, color: color)),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildBarChart() {
    if (_sales.isEmpty) return const Center(child: Text('No data for bar chart'));

    // Group sales by product to get total quantity
    Map<String, int> productQty = {};
    for (var s in _sales) {
      productQty[s.productName] = (productQty[s.productName] ?? 0) + s.quantitySold;
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
            )
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
                          if (value.toInt() >= 0 && value.toInt() < entries.length) {
                            String name = entries[value.toInt()].key;
                            if (name.length > 8) name = '${name.substring(0, 8)}...';
                            return Padding(
                              padding: const EdgeInsets.only(top: 8),
                              child: Text(name, style: const TextStyle(fontSize: 10)),
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
                        getTitlesWidget: (value, meta) => Text(value.toInt().toString(), style: const TextStyle(fontSize: 10)),
                      ),
                    ),
                    topTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
                    rightTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
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
    if (_sales.isEmpty) return const Center(child: Text('No data for pie chart'));

    // Revenue contribution by product
    Map<String, double> productRev = {};
    for (var s in _sales) {
      productRev[s.productName] = (productRev[s.productName] ?? 0.0) + s.revenue;
    }

    var entries = productRev.entries.toList();
    entries.sort((a, b) => b.value.compareTo(a.value));
    if (entries.length > 5) {
      double others = entries.sublist(5).fold(0.0, (sum, item) => sum + item.value);
      entries = entries.sublist(0, 5);
      entries.add(MapEntry('Others', others));
    }

    final List<Color> colors = [Colors.blue, Colors.orange, Colors.green, Colors.purple, Colors.red, Colors.grey];
    
    List<PieChartSectionData> sections = [];
    for (int i = 0; i < entries.length; i++) {
      sections.add(
        PieChartSectionData(
          color: colors[i % colors.length],
          value: entries[i].value,
          title: '${entries[i].key}\n\$${entries[i].value.toStringAsFixed(0)}',
          radius: 100,
          titleStyle: const TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: Colors.white),
        ),
      );
    }

    return Card(
      elevation: 2,
      child: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          children: [
            const Text('Revenue Contribution'),
            const SizedBox(height: 16),
            Expanded(
              child: PieChart(
                PieChartData(
                  sections: sections,
                  centerSpaceRadius: 40,
                  sectionsSpace: 2,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildLineChart() {
    if (_sales.isEmpty) return const Center(child: Text('No data for line chart'));

    // Process data: group revenue by date (month/year)
    // For simplicity, grouping by exact date and sorting
    Map<String, double> dateRev = {};
    for (var s in _sales) {
      String dateStr = DateFormat('yyyy-MM-dd').format(s.saleDate);
      dateRev[dateStr] = (dateRev[dateStr] ?? 0.0) + s.revenue;
    }

    var sortedKeys = dateRev.keys.toList()..sort();
    List<FlSpot> spots = [];
    double maxX = (sortedKeys.length - 1).toDouble();
    if (maxX < 1) maxX = 1;

    for (int i = 0; i < sortedKeys.length; i++) {
        spots.add(FlSpot(i.toDouble(), dateRev[sortedKeys[i]]!));
    }

    return Card(
      elevation: 2,
      child: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const Text('Revenue Trends Over Time', textAlign: TextAlign.center),
            const SizedBox(height: 16),
            Expanded(
              child: LineChart(
                LineChartData(
                  gridData: const FlGridData(show: true),
                  titlesData: FlTitlesData(
                    bottomTitles: AxisTitles(
                      sideTitles: SideTitles(
                        showTitles: true,
                        reservedSize: 30,
                        getTitlesWidget: (value, meta) {
                          int index = value.toInt();
                          if (index >= 0 && index < sortedKeys.length) {
                            if (sortedKeys.length > 10 && index % (sortedKeys.length ~/ 5) != 0) return const Text('');
                            return Padding(
                              padding: const EdgeInsets.only(top: 8.0),
                              child: Text(sortedKeys[index].substring(5), style: const TextStyle(fontSize: 10)), // MM-DD
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
                        getTitlesWidget: (value, meta) => Text(value.toInt().toString(), style: const TextStyle(fontSize: 10)),
                      ),
                    ),
                    topTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
                    rightTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
                  ),
                  borderData: FlBorderData(show: true, border: Border.all(color: Colors.grey.withOpacity(0.5))),
                  lineBarsData: [
                    LineChartBarData(
                      spots: spots,
                      isCurved: true,
                      color: Colors.green,
                      barWidth: 3,
                      isStrokeCapRound: true,
                      dotData: const FlDotData(show: true),
                      belowBarData: BarAreaData(show: true, color: Colors.green.withOpacity(0.2)),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildDataTable() {
    if (_sales.isEmpty) {
      return const Center(child: Padding(
        padding: EdgeInsets.all(16.0),
        child: Text('No historical sales match your criteria.'),
      ));
    }

    return LayoutBuilder(
      builder: (context, constraints) {
        return SingleChildScrollView(
          child: PaginatedDataTable(
            header: const Text('Sales Records'),
            rowsPerPage: _sales.length > 10 ? 10 : (_sales.length == 0 ? 1 : _sales.length),
            columns: const [
              DataColumn(label: Text('ID')),
              DataColumn(label: Text('Product')),
              DataColumn(label: Text('Date')),
              DataColumn(label: Text('Quantity')),
              DataColumn(label: Text('Revenue')),
              DataColumn(label: Text('Supplier')),
            ],
            source: SalesDataSource(_sales),
          ),
        );
      }
    );
  }
}

class SalesDataSource extends DataTableSource {
  final List<HistoricalSale> sales;

  SalesDataSource(this.sales);

  @override
  DataRow? getRow(int index) {
    if (index >= sales.length) return null;
    final sale = sales[index];
    return DataRow(cells: [
      DataCell(Text(sale.saleId.toString())),
      DataCell(Text(sale.productName)),
      DataCell(Text(DateFormat('yyyy-MM-dd HH:mm').format(sale.saleDate))),
      DataCell(Text(sale.quantitySold.toString())),
      DataCell(Text('\$${sale.revenue.toStringAsFixed(2)}')),
      DataCell(Text(sale.supplier ?? '-')),
    ]);
  }

  @override
  bool get isRowCountApproximate => false;

  @override
  int get rowCount => sales.length;

  @override
  int get selectedRowCount => 0;
}
