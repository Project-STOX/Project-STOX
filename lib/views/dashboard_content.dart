import 'package:flutter/material.dart';
import 'package:dropdown_search/dropdown_search.dart';
import 'package:fl_chart/fl_chart.dart';
import '../controllers/dashboard_controller.dart';
import '../controllers/product_controller.dart';

class DashboardContent extends StatefulWidget {
  final bool canViewForecasts;

  const DashboardContent({super.key, required this.canViewForecasts});

  @override
// Handles createState.
  State<DashboardContent> createState() => _DashboardContentState();
}

class _DashboardContentState extends State<DashboardContent> {
  final DashboardController _dashboardController = DashboardController();
  final ProductController _productController = ProductController();

  Map<String, dynamic>? _summaryData;
  bool _isLoadingSummary = true;
  String _summaryError = '';

  Map<String, dynamic>? _alertsData;
  bool _isLoadingAlerts = true;
  String _alertsError = '';

  List<Map<String, dynamic>> _products = [];
  Map<String, dynamic>? _selectedProduct;
  int _selectedWindow = 30;

  Map<String, dynamic>? _forecastData;
  bool _isLoadingForecast = false;
  String _forecastError = '';

  // EOQ calculator — NOT persisted to database
  final TextEditingController _holdingCostCtrl = TextEditingController(
    text: '10',
  );
  final TextEditingController _orderingCostCtrl = TextEditingController(
    text: '50',
  );
  double? _calculatedEoq;

  @override
// Handles initState.
  void initState() {
    super.initState();
    _loadSummary();
    _loadAlerts();
    if (widget.canViewForecasts) {
      _loadProducts();
    }
  }

  @override
// Handles dispose.
  void dispose() {
    _holdingCostCtrl.dispose();
    _orderingCostCtrl.dispose();
    super.dispose();
  }

// Handles _sqrt.
  double _sqrt(double x) {
    if (x <= 0) return 0;
    double r = x;
    for (int i = 0; i < 50; i++) {
      r = (r + x / r) / 2;
    }
    return r;
  }

// Handles _computeEoq.
  void _computeEoq() {
    final fd = _forecastData;
    if (fd == null) return;
    final dailyEs =
        double.tryParse(fd['daily_demand_es']?.toString() ?? '0') ?? 0;
    final annualDemand = dailyEs * 365;
    final ordering = double.tryParse(_orderingCostCtrl.text) ?? 0;
    final holding = double.tryParse(_holdingCostCtrl.text) ?? 0;
    if (holding <= 0 || ordering <= 0 || annualDemand <= 0) {
      setState(() => _calculatedEoq = null);
      return;
    }
    setState(
      () => _calculatedEoq = _sqrt(2 * annualDemand * ordering / holding),
    );
  }

  bool _isGeneratingForecast = false;

// Handles _generateAndRefresh.
  Future<void> _generateAndRefresh() async {
    if (!mounted) return;
    setState(() {
      _isGeneratingForecast = true;
    });
    try {
      if (widget.canViewForecasts) {
        try {
          await _dashboardController.generateForecast();
        } catch (e) {
          debugPrint('Forecast generation warning: $e');
        }
      }
      await Future.wait([
        _loadSummary(),
        _loadAlerts(),
        if (widget.canViewForecasts) _loadProducts(),
      ]);
      if (_selectedProduct != null) {
        await _fetchForecast();
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Failed to refresh data: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    } finally {
      if (mounted) {
        setState(() {
          _isGeneratingForecast = false;
        });
      }
    }
  }

// Handles _loadSummary.
  Future<void> _loadSummary() async {
    setState(() {
      _isLoadingSummary = true;
      _summaryError = '';
    });
    try {
      final summary = await _dashboardController.getSummary();
      if (mounted) {
        setState(() {
          _summaryData = summary;
          _isLoadingSummary = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _summaryError = e.toString();
          _isLoadingSummary = false;
        });
      }
    }
  }

// Handles _loadAlerts.
  Future<void> _loadAlerts() async {
    setState(() {
      _isLoadingAlerts = true;
      _alertsError = '';
    });
    try {
      final alerts = await _dashboardController.getAlerts();
      if (mounted) {
        setState(() {
          _alertsData = alerts;
          _isLoadingAlerts = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _alertsError = e.toString();
          _isLoadingAlerts = false;
        });
      }
    }
  }

// Handles _loadProducts.
  Future<void> _loadProducts() async {
    try {
      final products = await _productController.fetchProducts();
      if (mounted) {
        setState(() {
          _products = products;
        });
      }
    } catch (e) {
      debugPrint('Failed to fetch products for search bar: $e');
    }
  }

// Handles _fetchForecast.
  Future<void> _fetchForecast() async {
    if (_selectedProduct == null) return;
    setState(() {
      _isLoadingForecast = true;
      _forecastError = '';
    });
    try {
      final productId = _selectedProduct!['product_id'] as int;
      final forecast = await _dashboardController.getForecast(
        productId,
        _selectedWindow,
      );
      if (mounted) {
        setState(() {
          _forecastData = forecast;
          _isLoadingForecast = false;
        });
        _computeEoq(); // Auto-refresh EOQ with new forecast data
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _forecastError = e.toString();
          _isLoadingForecast = false;
        });
      }
    }
  }

// Handles _buildSummaryCard.
  Widget _buildSummaryCard(
    String title,
    String subtitle,
    IconData icon,
    Color color,
  ) {
    return Card(
      elevation: 2,
      child: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Row(
          children: [
            CircleAvatar(
              backgroundColor: color.withOpacity(0.1),
              radius: 24,
              child: Icon(icon, color: color, size: 28),
            ),
            const SizedBox(width: 16),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    title,
                    style: TextStyle(
                      fontSize: 14,
                      color: Theme.of(context).hintColor,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    subtitle,
                    style: const TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.bold,
                    ),
                    softWrap: true,
                    overflow: TextOverflow.visible,
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

// Handles _buildProductImportanceCard.
  Widget _buildProductImportanceCard(
    String label,
    Map<String, dynamic>? data,
    Color color,
  ) {
    if (data == null) {
      return Card(
        child: ListTile(
          leading: Icon(Icons.inventory, color: color),
          title: Text(label),
          subtitle: const Text('No data available'),
        ),
      );
    }
    final isMost = label.contains('Most');
    return Card(
      child: ListTile(
        leading: Icon(
          isMost ? Icons.arrow_upward : Icons.arrow_downward,
          color: color,
        ),
        title: Text('$label: ${data['name']}'),
        subtitle: Text(
          'Supplier: ${data['supplier_name']}\nReorder Pt: ${data['reorder_point']} | EOQ: ${data['eoq'] ?? 'N/A'}',
        ),
        isThreeLine: true,
      ),
    );
  }

// Handles _buildTopSummary.
  Widget _buildTopSummary() {
    if (_isLoadingSummary) {
      return const Center(child: CircularProgressIndicator());
    }
    if (_summaryError.isNotEmpty) {
      return Center(child: Text('Error: $_summaryError'));
    }
    if (_summaryData == null) return const SizedBox.shrink();

    return Padding(
      padding: const EdgeInsets.all(16.0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Expanded(
                child: Text(
                  'Dashboard Summary',
                  style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              const SizedBox(width: 8),
              ElevatedButton.icon(
                onPressed: _isGeneratingForecast ? null : _generateAndRefresh,
                icon: _isGeneratingForecast
// Handles SizedBox.
                    ? const SizedBox(
                        width: 16,
                        height: 16,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Icon(Icons.refresh),
                label: Text(
                  _isGeneratingForecast ? 'Refreshing...' : 'Refresh',
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          LayoutBuilder(
            builder: (context, constraints) {
              int crossAxisCount = constraints.maxWidth < 600
                  ? 1
                  : constraints.maxWidth < 900
                  ? 2
                  : 4;
              return GridView.count(
                crossAxisCount: crossAxisCount,
                crossAxisSpacing: 16,
                mainAxisSpacing: 16,
                shrinkWrap: true,
                physics: const NeverScrollableScrollPhysics(),
                childAspectRatio: constraints.maxWidth < 600 ? 3 : 2,
                children: [
                  _buildSummaryCard(
                    'Total Inventory Worth',
                    'Rs. ${_summaryData!['stock_value']}',
                    Icons.account_balance_wallet,
                    Colors.teal,
                  ),
                  _buildSummaryCard(
                    'Active Receipts Worth',
                    'Rs. ${_summaryData!['receipts_value']}',
                    Icons.receipt_long,
                    Colors.blue,
                  ),
                  _buildSummaryCard(
                    'Forecast Worth (30d)',
                    'Rs. ${_summaryData!['forecast_worth_30d']}',
                    Icons.auto_graph,
                    Colors.green,
                  ),
                  _buildSummaryCard(
                    'Forecast Worth (60d)',
                    'Rs. ${_summaryData!['forecast_worth_60d']}',
                    Icons.auto_graph_outlined,
                    Colors.orange,
                  ),
                ],
              );
            },
          ),
          const SizedBox(height: 16),
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: _buildProductImportanceCard(
                  'Most Important',
                  _summaryData!['most_important_product'],
                  Colors.amber,
                ),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: _buildProductImportanceCard(
                  'Least Important',
                  _summaryData!['least_important_product'],
                  Colors.blueGrey,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

// Handles _buildGlobalForecastChart.
  Widget _buildGlobalForecastChart() {
    if (_isLoadingSummary) return const SizedBox.shrink();
    if (_summaryData == null) return const SizedBox.shrink();

    // Do not show the graph if they don't have access to view forecasts
    if (!widget.canViewForecasts) return const SizedBox.shrink();

    final historicalData =
        _summaryData!['total_inventory_historical_sales'] as List<dynamic>? ??
        [];
    final futureData30 =
        _summaryData!['total_inventory_forecast_30d'] as List<dynamic>? ?? [];
    final futureData60 =
        _summaryData!['total_inventory_forecast_60d'] as List<dynamic>? ?? [];
    if (historicalData.isEmpty &&
        futureData30.isEmpty &&
        futureData60.isEmpty) {
      return const SizedBox.shrink();
    }

    final predictedMa30 =
        double.tryParse(
          _summaryData!['predicted_total_ma_30d']?.toString() ?? '0',
        ) ??
        0;
    final predictedEs30 =
        double.tryParse(
          _summaryData!['predicted_total_es_30d']?.toString() ?? '0',
        ) ??
        0;
    final predictedMa60 =
        double.tryParse(
          _summaryData!['predicted_total_ma_60d']?.toString() ?? '0',
        ) ??
        0;
    final predictedEs60 =
        double.tryParse(
          _summaryData!['predicted_total_es_60d']?.toString() ?? '0',
        ) ??
        0;

    List<FlSpot> historicalSpots = [];
    List<FlSpot> maSpots = [];
    List<FlSpot> esSpots = [];
    List<FlSpot> maSpots60 = [];
    List<FlSpot> esSpots60 = [];

    final int historicalLen = historicalData.length;
    final int maxForecastLen = futureData60.isNotEmpty
        ? futureData60.length
        : futureData30.length;
    double maxX = (historicalLen + maxForecastLen - 1).toDouble();
    if (maxX < 0) maxX = 0;
    double maxY = 0.0;

    for (int i = 0; i < historicalData.length; i++) {
      final point = historicalData[i];
      final qty = double.tryParse(point['quantity_sold'].toString()) ?? 0.0;
      historicalSpots.add(FlSpot(i.toDouble(), qty));
      if (qty > maxY) maxY = qty;
    }

    for (int i = 0; i < futureData30.length; i++) {
      final point = futureData30[i];
      final maQty =
          double.tryParse(point['moving_average_qty'].toString()) ?? 0.0;
      final esQty =
          double.tryParse(point['exponential_smoothing_qty'].toString()) ?? 0.0;

      maSpots.add(FlSpot((historicalLen + i).toDouble(), maQty));
      esSpots.add(FlSpot((historicalLen + i).toDouble(), esQty));

      if (maQty > maxY) maxY = maQty;
      if (esQty > maxY) maxY = esQty;
    }

    for (int i = 0; i < futureData60.length; i++) {
      final point = futureData60[i];
      final maQty =
          double.tryParse(point['moving_average_qty'].toString()) ?? 0.0;
      final esQty =
          double.tryParse(point['exponential_smoothing_qty'].toString()) ?? 0.0;

      maSpots60.add(FlSpot((historicalLen + i).toDouble(), maQty));
      esSpots60.add(FlSpot((historicalLen + i).toDouble(), esQty));

      if (maQty > maxY) maxY = maQty;
      if (esQty > maxY) maxY = esQty;
    }

    maxY = maxY > 0 ? maxY * 1.2 : 10.0;

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16.0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Total Inventory Demand Forecast (Historical + 30/60 Days)',
            style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 10),
          Wrap(
            spacing: 10,
            runSpacing: 10,
            children: [
              _buildStatChip(
                Icons.multiline_chart,
                'MA Next 30d',
                '${predictedMa30.toStringAsFixed(0)} units',
                Colors.blue,
              ),
              _buildStatChip(
                Icons.show_chart,
                'ES Next 30d',
                '${predictedEs30.toStringAsFixed(0)} units',
                Colors.deepOrange,
              ),
              _buildStatChip(
                Icons.timeline,
                'MA Next 60d',
                '${predictedMa60.toStringAsFixed(0)} units',
                Colors.indigo,
              ),
              _buildStatChip(
                Icons.insights,
                'ES Next 60d',
                '${predictedEs60.toStringAsFixed(0)} units',
                Colors.green,
              ),
            ],
          ),
          const SizedBox(height: 16),
          Container(
            height: 360,
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: Theme.of(context).colorScheme.surface,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: Theme.of(context).dividerColor),
            ),
            child: Column(
              children: [
                Wrap(
                  alignment: WrapAlignment.center,
                  spacing: 10,
                  runSpacing: 8,
                  children: [
                    _buildLegendItem('Historical Sales', Colors.teal),
                    _buildLegendItem('MA 30d', Colors.blue),
                    _buildLegendItem('ES 30d', Colors.deepOrange),
                    _buildLegendItem('MA 60d', Colors.indigo),
                    _buildLegendItem('ES 60d', Colors.green),
                  ],
                ),
                const SizedBox(height: 16),
                Expanded(
                  child: LineChart(
                    LineChartData(
                      minX: 0,
                      maxX: maxX,
                      minY: 0,
                      maxY: maxY,
                      gridData: FlGridData(show: true, drawVerticalLine: false),
                      titlesData: FlTitlesData(
                        bottomTitles: AxisTitles(
                          axisNameWidget: const Text(
                            'Timeline (MM/DD)',
                            style: TextStyle(fontSize: 12),
                          ),
                          sideTitles: SideTitles(
                            showTitles: true,
                            reservedSize: 30,
                            interval: 14,
                            getTitlesWidget: (value, meta) {
                              int index = value.toInt();
                              String dateStr = '';
                              if (index >= 0 && index < historicalData.length) {
                                dateStr =
                                    historicalData[index]['sale_date']
                                        ?.toString() ??
                                    '';
                              } else {
                                final forecastIndex =
                                    index - historicalData.length;
                                if (forecastIndex >= 0 &&
                                    forecastIndex < futureData60.length) {
                                  dateStr =
                                      futureData60[forecastIndex]['future_date']
                                          ?.toString() ??
                                      '';
                                } else if (forecastIndex >= 0 &&
                                    forecastIndex < futureData30.length) {
                                  dateStr =
                                      futureData30[forecastIndex]['future_date']
                                          ?.toString() ??
                                      '';
                                }
                              }
                              if (dateStr.isEmpty) {
                                return const SizedBox.shrink();
                              }
                              final date = DateTime.tryParse(dateStr);
                              if (date == null) return const SizedBox.shrink();
                              return Padding(
                                padding: const EdgeInsets.only(top: 8.0),
                                child: Text(
                                  '${date.month}/${date.day}',
                                  style: TextStyle(
                                    fontSize: 10,
                                    color: Theme.of(
                                      context,
                                    ).textTheme.bodySmall?.color,
                                  ),
                                ),
                              );
                            },
                          ),
                        ),
                        topTitles: AxisTitles(
                          sideTitles: SideTitles(showTitles: false),
                        ),
                        rightTitles: AxisTitles(
                          sideTitles: SideTitles(showTitles: false),
                        ),
                        leftTitles: AxisTitles(
                          axisNameWidget: Text(
                            'Total Qty',
                            style: TextStyle(
                              fontSize: 12,
                              color: Theme.of(
                                context,
                              ).textTheme.bodySmall?.color,
                            ),
                          ),
                          sideTitles: SideTitles(
                            showTitles: true,
                            reservedSize: 40,
                            getTitlesWidget: (val, meta) => Text(
                              val.toInt().toString(),
                              style: TextStyle(
                                fontSize: 10,
                                color: Theme.of(
                                  context,
                                ).textTheme.bodySmall?.color,
                              ),
                            ),
                          ),
                        ),
                      ),
                      borderData: FlBorderData(
                        show: true,
                        border: Border.all(
                          color: Theme.of(context).dividerColor,
                        ),
                      ),
                      lineBarsData: [
                        if (historicalSpots.isNotEmpty)
                          LineChartBarData(
                            spots: historicalSpots,
                            isCurved: true,
                            color: Colors.teal,
                            barWidth: 2.2,
                            dotData: FlDotData(
                              show: historicalSpots.length <= 35,
                            ),
                          ),
                        if (maSpots.isNotEmpty)
                          LineChartBarData(
                            spots: maSpots,
                            isCurved: false,
                            color: Colors.blue,
                            barWidth: 2,
                            isStrokeCapRound: true,
                            dashArray: [5, 5],
                            dotData: FlDotData(show: false),
                          ),
                        if (esSpots.isNotEmpty)
                          LineChartBarData(
                            spots: esSpots,
                            isCurved: false,
                            color: Colors.deepOrange,
                            barWidth: 2,
                            isStrokeCapRound: true,
                            dashArray: [5, 5],
                            dotData: FlDotData(show: false),
                          ),
                        if (maSpots60.isNotEmpty)
                          LineChartBarData(
                            spots: maSpots60,
                            isCurved: false,
                            color: Colors.indigo,
                            barWidth: 2,
                            isStrokeCapRound: true,
                            dashArray: [3, 3],
                            dotData: FlDotData(show: false),
                          ),
                        if (esSpots60.isNotEmpty)
                          LineChartBarData(
                            spots: esSpots60,
                            isCurved: false,
                            color: Colors.green,
                            barWidth: 2,
                            isStrokeCapRound: true,
                            dashArray: [3, 3],
                            dotData: FlDotData(show: false),
                          ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

// Handles _buildForecastSection.
  Widget _buildForecastSection() {
    if (!widget.canViewForecasts) {
      return Container(
        margin: const EdgeInsets.all(16.0),
        padding: const EdgeInsets.all(16.0),
        decoration: BoxDecoration(
          color: Theme.of(context).brightness == Brightness.dark
              ? Colors.red.withOpacity(0.1)
              : Colors.red.shade50,
          borderRadius: BorderRadius.circular(8),
          border: Border.all(
            color: Theme.of(context).brightness == Brightness.dark
                ? Colors.red.withOpacity(0.5)
                : Colors.red.shade200,
          ),
        ),
        child: Row(
          children: [
            Icon(Icons.lock, color: Colors.red.shade700),
            const SizedBox(width: 16),
            const Expanded(
              child: Text(
                'Forecast view is disabled to the role, please contact the administrator.',
                style: TextStyle(
                  color: Colors.red,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
          ],
        ),
      );
    }

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16.0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Demand Forecasting Analysis',
            style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 16),
          Row(
            children: [
              Expanded(
                flex: 2,
                child: DropdownSearch<Map<String, dynamic>>(
                  popupProps: const PopupProps.menu(
                    showSearchBox: true,
                    searchFieldProps: TextFieldProps(
                      decoration: InputDecoration(
                        hintText: 'Search product...',
                      ),
                    ),
                  ),
                  items: _products,
                  itemAsString: (item) {
                    final name = item['product_name'] ?? 'Unknown';
                    final code = item['product_code'] ?? 'N/A';
                    final sku = item['sku'] ?? 'N/A';
                    return '$name (Code: $code, SKU: $sku)';
                  },
                  filterFn: (item, filter) {
                    final query = filter.toLowerCase();
                    final name = (item['product_name'] ?? '')
                        .toString()
                        .toLowerCase();
                    final code = (item['product_code'] ?? '')
                        .toString()
                        .toLowerCase();
                    final sku = (item['sku'] ?? '').toString().toLowerCase();
                    return name.contains(query) ||
                        code.contains(query) ||
                        sku.contains(query);
                  },
                  dropdownDecoratorProps: const DropDownDecoratorProps(
                    dropdownSearchDecoration: InputDecoration(
                      labelText: "Select Product",
                      border: OutlineInputBorder(),
                    ),
                  ),
                  onChanged: (val) {
                    setState(() {
                      _selectedProduct = val;
                    });
                    _fetchForecast();
                  },
                ),
              ),
              const SizedBox(width: 16),
              Expanded(
                flex: 1,
                child: DropdownButtonFormField<int>(
                  initialValue: _selectedWindow,
                  decoration: const InputDecoration(
                    labelText: "Window",
                    border: OutlineInputBorder(),
                  ),
                  items: const [
                    DropdownMenuItem(value: 30, child: Text("30 Days")),
                    DropdownMenuItem(value: 60, child: Text("60 Days")),
                  ],
                  onChanged: (val) {
                    if (val != null) {
                      setState(() {
                        _selectedWindow = val;
                      });
                      _fetchForecast();
                    }
                  },
                ),
              ),
            ],
          ),
          const SizedBox(height: 24),
          _buildForecastAnalyticsPanel(),
        ],
      ),
    );
  }

// Handles _buildStockGauge.
  Widget _buildStockGauge(
    String status,
    int current,
    int reorder,
    int overstock,
  ) {
    Color gaugeColor;
    IconData gaugeIcon;
    String gaugeLabel;
    double fillFraction;

    if (status == 'Low Stock') {
      gaugeColor = Colors.red;
      gaugeIcon = Icons.arrow_downward;
      gaugeLabel = 'Low Stock';
      fillFraction = reorder > 0
          ? (current / reorder).clamp(0.0, 1.0) * 0.33
          : 0.1;
    } else if (status == 'Overstock') {
      gaugeColor = Colors.orange;
      gaugeIcon = Icons.arrow_upward;
      gaugeLabel = 'Overstock';
      fillFraction = 1.0;
    } else {
      gaugeColor = Colors.green;
      gaugeIcon = Icons.check_circle;
      gaugeLabel = 'Normal';
      fillFraction = overstock > 0
          ? (current / overstock).clamp(0.33, 0.85)
          : 0.6;
    }

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: gaugeColor.withOpacity(0.08),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: gaugeColor.withOpacity(0.4)),
      ),
      child: Column(
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(gaugeIcon, color: gaugeColor, size: 28),
              const SizedBox(width: 8),
              Text(
                gaugeLabel,
                style: TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.bold,
                  color: gaugeColor,
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          ClipRRect(
            borderRadius: BorderRadius.circular(8),
            child: LinearProgressIndicator(
              value: fillFraction,
              minHeight: 20,
              backgroundColor: Theme.of(context).brightness == Brightness.dark
                  ? Colors.white10
                  : Colors.grey.shade200,
              valueColor: AlwaysStoppedAnimation<Color>(gaugeColor),
            ),
          ),
          const SizedBox(height: 8),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                'Low Stock\n≤$reorder',
                textAlign: TextAlign.center,
                style: const TextStyle(fontSize: 10, color: Colors.red),
              ),
              Text(
                'Qty: $current',
                style: const TextStyle(fontWeight: FontWeight.bold),
              ),
              Text(
                'Overstock\n≥$overstock',
                textAlign: TextAlign.center,
                style: const TextStyle(fontSize: 10, color: Colors.orange),
              ),
            ],
          ),
        ],
      ),
    );
  }

// Handles _buildForecastAnalyticsPanel.
  Widget _buildForecastAnalyticsPanel() {
    if (_isLoadingForecast) {
      return const Center(
        child: Padding(
          padding: EdgeInsets.all(32),
          child: CircularProgressIndicator(),
        ),
      );
    }
    if (_forecastError.isNotEmpty) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Text('Error: $_forecastError'),
        ),
      );
    }
    if (_forecastData == null) {
      return const Center(
        child: Padding(
          padding: EdgeInsets.all(32),
          child: Text('Select a product to view its demand forecast.'),
        ),
      );
    }

    final fd = _forecastData!;
    final historicalData = fd['historical_sales'] as List<dynamic>? ?? [];
    final futureData = fd['future_forecasts'] as List<dynamic>? ?? [];
    final currentQty = fd['current_qty'] as int? ?? 0;
    final reorderLevel = fd['reorder_level'] as int? ?? 0;
    final overstockLevel = fd['overstock_level'] as int? ?? (reorderLevel * 2);
    final stockStatus = fd['stock_status'] as String? ?? 'Normal';
    final stdDev = double.tryParse(fd['std_dev']?.toString() ?? '0') ?? 0;
    final trend = fd['trend_direction'] as String? ?? 'stable';
    final reorderSuggestion = fd['reorder_suggestion'] as int? ?? 0;
    final suggestedOrderQty = fd['suggested_order_qty'] as int? ?? 0;
    final safetyStock = fd['safety_stock_suggestion'] as int? ?? 0;
    final histPoints = fd['historical_data_points'] as int? ?? 0;
    final predictedMa =
        double.tryParse(fd['predicted_demand_ma']?.toString() ?? '0') ?? 0;
    final predictedEs =
        double.tryParse(fd['predicted_demand_es']?.toString() ?? '0') ?? 0;
    final dailyEs =
        double.tryParse(fd['daily_demand_es']?.toString() ?? '0') ?? 0;

    // ── Build chart spots ─────────────────────────────────────────────────
    List<FlSpot> histSpots = [];
    List<FlSpot> maSpots = [];
    List<FlSpot> esSpots = [];
    double maxX =
        historicalData.length.toDouble() + futureData.length.toDouble() - 1;
    if (maxX < 0) maxX = 0;
    double maxY = currentQty.toDouble();

    for (int i = 0; i < historicalData.length; i++) {
      final qty =
          double.tryParse(historicalData[i]['quantity_sold'].toString()) ?? 0.0;
      histSpots.add(FlSpot(i.toDouble(), qty));
      if (qty > maxY) maxY = qty;
    }

    final offset = historicalData.length;
    if (histSpots.isNotEmpty && futureData.isNotEmpty) {
      maSpots.add(FlSpot(histSpots.last.x, histSpots.last.y));
      esSpots.add(FlSpot(histSpots.last.x, histSpots.last.y));
    }

    for (int i = 0; i < futureData.length; i++) {
      final maQty =
          double.tryParse(futureData[i]['moving_average_qty'].toString()) ??
          0.0;
      final esQty =
          double.tryParse(
            futureData[i]['exponential_smoothing_qty'].toString(),
          ) ??
          0.0;
      maSpots.add(FlSpot((offset + i).toDouble(), maQty));
      esSpots.add(FlSpot((offset + i).toDouble(), esQty));
      if (maQty > maxY) maxY = maQty;
      if (esQty > maxY) maxY = esQty;
    }
    maxY = maxY > 0 ? maxY * 1.2 : 10.0;

    IconData trendIcon = trend == 'upward'
        ? Icons.trending_up
        : trend == 'downward'
        ? Icons.trending_down
        : Icons.trending_flat;
    Color trendColor = trend == 'upward'
        ? Colors.green
        : trend == 'downward'
        ? Colors.red
        : Colors.blue;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        // ── Stock Status Gauge ────────────────────────────────────────────
        _buildStockGauge(stockStatus, currentQty, reorderLevel, overstockLevel),
        const SizedBox(height: 20),

        // ── Key Metrics Grid ──────────────────────────────────────────────
        Wrap(
          spacing: 12,
          runSpacing: 12,
          children: [
            _buildStatChip(
              Icons.shopify,
              'Daily Demand (ES)',
              '${dailyEs.toStringAsFixed(2)} units/day',
              Colors.deepPurple,
            ),
            _buildStatChip(
              Icons.multiline_chart,
              'MA Demand (${fd['window']}d)',
              '${predictedMa.toStringAsFixed(0)} units',
              Colors.blue,
            ),
            _buildStatChip(
              Icons.show_chart,
              'ES Demand (${fd['window']}d)',
              '${predictedEs.toStringAsFixed(0)} units',
              Colors.orange,
            ),
            _buildStatChip(
              Icons.bar_chart,
              'Std Deviation',
              '±${stdDev.toStringAsFixed(2)}',
              Colors.grey,
            ),
            _buildStatChip(
              trendIcon,
              'Demand Trend',
              trend[0].toUpperCase() + trend.substring(1),
              trendColor,
            ),
            _buildStatChip(
              Icons.data_usage,
              'History Points',
              '$histPoints records',
              Colors.teal,
            ),
          ],
        ),
        const SizedBox(height: 20),

        // ── Reorder Recommendation ────────────────────────────────────────
        Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: Theme.of(
              context,
            ).colorScheme.primaryContainer.withOpacity(0.1),
            borderRadius: BorderRadius.circular(12),
            border: Border.all(
              color: Theme.of(context).colorScheme.primaryContainer,
            ),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'Reorder Recommendations',
                style: TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.bold,
                  color: Colors.indigo,
                ),
              ),
              const SizedBox(height: 12),
              _buildRecommendationRow(
                'Reorder Now (Lead Time Cover)',
                '$reorderSuggestion units',
                reorderSuggestion > 0 ? Colors.red : Colors.green,
              ),
              _buildRecommendationRow(
                'Full Window Order Qty',
                '$suggestedOrderQty units',
                Colors.indigo,
              ),
              _buildRecommendationRow(
                'Safety Stock Buffer (95% SL)',
                '$safetyStock units',
                Colors.teal,
              ),
              _buildRecommendationRow(
                'Current Stock',
                '$currentQty units',
                currentQty <= reorderLevel ? Colors.red : Colors.green,
              ),
            ],
          ),
        ),
        const SizedBox(height: 20),

        // ── EOQ Calculator ─────────────────────────────────────────────────
        Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: Theme.of(
              context,
            ).colorScheme.secondaryContainer.withOpacity(0.1),
            borderRadius: BorderRadius.circular(12),
            border: Border.all(
              color: Theme.of(context).colorScheme.secondaryContainer,
            ),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'EOQ Calculator (Economic Order Quantity)',
                style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 4),
              const Text(
                'Formula: EOQ = √(2 × Annual Demand × Ordering Cost / Holding Cost/unit/yr)  — values not saved',
                style: TextStyle(fontSize: 11, color: Colors.grey),
              ),
              const SizedBox(height: 12),
              Row(
                children: [
                  Expanded(
                    child: TextField(
                      controller: _holdingCostCtrl,
                      keyboardType: TextInputType.number,
                      decoration: const InputDecoration(
                        labelText: 'Holding Cost (Rs./unit/yr)',
                        border: OutlineInputBorder(),
                        isDense: true,
                      ),
                      onChanged: (_) => _computeEoq(),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: TextField(
                      controller: _orderingCostCtrl,
                      keyboardType: TextInputType.number,
                      decoration: const InputDecoration(
                        labelText: 'Ordering Cost (Rs./order)',
                        border: OutlineInputBorder(),
                        isDense: true,
                      ),
                      onChanged: (_) => _computeEoq(),
                    ),
                  ),
                  const SizedBox(width: 12),
                  ElevatedButton.icon(
                    onPressed: _computeEoq,
                    icon: const Icon(Icons.calculate),
                    label: const Text('Calculate'),
                  ),
                ],
              ),
              if (_calculatedEoq != null) ...[
                const SizedBox(height: 12),
                Row(
                  children: [
                    const Icon(Icons.check_circle, color: Colors.green),
                    const SizedBox(width: 8),
                    Text(
                      'EOQ = ${_calculatedEoq!.toStringAsFixed(0)} units per order',
                      style: const TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.bold,
                        color: Colors.green,
                      ),
                    ),
                  ],
                ),
                Text(
                  'Based on annual demand of ${(dailyEs * 365).toStringAsFixed(0)} units/yr',
                  style: const TextStyle(fontSize: 12, color: Colors.grey),
                ),
              ],
              if (_calculatedEoq == null)
                const Padding(
                  padding: EdgeInsets.only(top: 8),
                  child: Text(
                    'Enter valid costs to calculate EOQ',
                    style: TextStyle(fontSize: 12, color: Colors.grey),
                  ),
                ),
            ],
          ),
        ),
        const SizedBox(height: 20),

        // ── Line Chart ────────────────────────────────────────────────────
        Container(
          height: 360,
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: Theme.of(context).colorScheme.surface,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: Theme.of(context).dividerColor),
          ),
          child: Column(
            children: [
              Wrap(
                spacing: 12,
                children: [
                  _buildLegendItem('Historical Sales', Colors.teal),
                  _buildLegendItem('MA Forecast (cumul.)', Colors.blue),
                  _buildLegendItem('ES Forecast (cumul.)', Colors.orange),
                ],
              ),
              const SizedBox(height: 12),
              Expanded(
                child: LineChart(
                  LineChartData(
                    minX: 0,
                    maxX: maxX,
                    minY: 0,
                    maxY: maxY,
                    gridData: FlGridData(show: true, drawVerticalLine: false),
                    titlesData: FlTitlesData(
                      bottomTitles: AxisTitles(
                        axisNameWidget: const Text(
                          'Date (MM/DD)',
                          style: TextStyle(fontSize: 11),
                        ),
                        sideTitles: SideTitles(
                          showTitles: true,
                          reservedSize: 36,
                          interval: 7,
                          getTitlesWidget: (value, meta) {
                            int index = value.toInt();
                            DateTime? date;
                            if (index < historicalData.length) {
                              date = DateTime.tryParse(
                                historicalData[index]['sale_date']
                                        ?.toString() ??
                                    '',
                              );
                            } else {
                              int fi = index - historicalData.length;
                              if (fi < futureData.length) {
                                date = DateTime.tryParse(
                                  futureData[fi]['future_date']?.toString() ??
                                      '',
                                );
                              }
                            }
                            if (date == null) return const SizedBox.shrink();
                            return Padding(
                              padding: const EdgeInsets.only(top: 6),
                              child: Text(
                                '${date.month}/${date.day}',
                                style: TextStyle(
                                  fontSize: 9,
                                  color: Theme.of(
                                    context,
                                  ).textTheme.bodySmall?.color,
                                ),
                              ),
                            );
                          },
                        ),
                      ),
                      topTitles: const AxisTitles(
                        sideTitles: SideTitles(showTitles: false),
                      ),
                      rightTitles: const AxisTitles(
                        sideTitles: SideTitles(showTitles: false),
                      ),
                      leftTitles: AxisTitles(
                        axisNameWidget: Text(
                          'Qty',
                          style: TextStyle(
                            fontSize: 11,
                            color: Theme.of(context).textTheme.bodySmall?.color,
                          ),
                        ),
                        sideTitles: SideTitles(
                          showTitles: true,
                          reservedSize: 40,
                          getTitlesWidget: (val, meta) => Text(
                            val.toInt().toString(),
                            style: TextStyle(
                              fontSize: 10,
                              color: Theme.of(
                                context,
                              ).textTheme.bodySmall?.color,
                            ),
                          ),
                        ),
                      ),
                    ),
                    extraLinesData: ExtraLinesData(
                      horizontalLines: [
                        HorizontalLine(
                          y: reorderLevel.toDouble(),
                          color: Colors.red.withOpacity(0.6),
                          strokeWidth: 1.5,
                          dashArray: [8, 4],
                          label: HorizontalLineLabel(
                            show: true,
                            alignment: Alignment.topRight,
                            labelResolver: (_) => 'Reorder ($reorderLevel)',
                            style: const TextStyle(
                              color: Colors.red,
                              fontSize: 9,
                            ),
                          ),
                        ),
                        HorizontalLine(
                          y: overstockLevel.toDouble(),
                          color: Colors.orange.withOpacity(0.6),
                          strokeWidth: 1.5,
                          dashArray: [8, 4],
                          label: HorizontalLineLabel(
                            show: true,
                            alignment: Alignment.topRight,
                            labelResolver: (_) => 'Overstock ($overstockLevel)',
                            style: const TextStyle(
                              color: Colors.orange,
                              fontSize: 9,
                            ),
                          ),
                        ),
                        HorizontalLine(
                          y: currentQty.toDouble(),
                          color: Colors.teal.withOpacity(0.5),
                          strokeWidth: 1.5,
                          dashArray: [4, 4],
                          label: HorizontalLineLabel(
                            show: true,
                            alignment: Alignment.topLeft,
                            labelResolver: (_) => 'Current ($currentQty)',
                            style: const TextStyle(
                              color: Colors.teal,
                              fontSize: 9,
                            ),
                          ),
                        ),
                      ],
                    ),
                    borderData: FlBorderData(
                      show: true,
                      border: Border.all(color: Theme.of(context).dividerColor),
                    ),
                    lineBarsData: [
                      if (histSpots.isNotEmpty)
                        LineChartBarData(
                          spots: histSpots,
                          isCurved: true,
                          color: Colors.teal,
                          barWidth: 2.5,
                          dotData: FlDotData(show: histSpots.length <= 15),
                        ),
                      if (maSpots.isNotEmpty)
                        LineChartBarData(
                          spots: maSpots,
                          isCurved: false,
                          color: Colors.blue,
                          barWidth: 2,
                          dashArray: [5, 5],
                          dotData: FlDotData(show: false),
                        ),
                      if (esSpots.isNotEmpty)
                        LineChartBarData(
                          spots: esSpots,
                          isCurved: false,
                          color: Colors.orange,
                          barWidth: 2,
                          dashArray: [5, 5],
                          dotData: FlDotData(show: false),
                        ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

// Handles _buildStatChip.
  Widget _buildStatChip(
    IconData icon,
    String label,
    String value,
    Color color,
  ) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: color.withOpacity(0.1),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: color.withOpacity(0.3)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, color: color, size: 18),
          const SizedBox(width: 6),
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(label, style: TextStyle(fontSize: 10, color: color)),
              Text(
                value,
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.bold,
                  color: color,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

// Handles _buildRecommendationRow.
  Widget _buildRecommendationRow(String label, String value, Color color) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(label, style: const TextStyle(fontSize: 13)),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 3),
            decoration: BoxDecoration(
              color: color.withOpacity(0.12),
              borderRadius: BorderRadius.circular(6),
              border: Border.all(color: color.withOpacity(0.4)),
            ),
            child: Text(
              value,
              style: TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.bold,
                color: color,
              ),
            ),
          ),
        ],
      ),
    );
  }

// Handles _buildLegendItem.
  Widget _buildLegendItem(String name, Color color) {
    return Row(
      children: [
        Container(width: 16, height: 4, color: color),
        const SizedBox(width: 8),
        Text(name, style: const TextStyle(fontSize: 12)),
      ],
    );
  }

// Handles _buildAlertsSection.
  Widget _buildAlertsSection() {
    if (_isLoadingAlerts) {
      return const Center(child: CircularProgressIndicator());
    }
    if (_alertsError.isNotEmpty) {
      return Center(child: Text('Error loading alerts: $_alertsError'));
    }
    if (_alertsData == null) return const SizedBox.shrink();

    final stockouts = _alertsData!['stockout_risks'] as List<dynamic>? ?? [];
    final overstocks = _alertsData!['overstock_risks'] as List<dynamic>? ?? [];

    if (stockouts.isEmpty && overstocks.isEmpty) {
      return const Padding(
        padding: EdgeInsets.all(16.0),
        child: Text(
          'No critical inventory alerts at this time.',
          textAlign: TextAlign.center,
        ),
      );
    }

    return Padding(
      padding: const EdgeInsets.all(16.0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Inventory Alerts',
            style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 16),
          if (stockouts.isNotEmpty) ...[
            const Text(
              'Low Stock Risks',
              style: TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.bold,
                color: Colors.red,
              ),
            ),
            const SizedBox(height: 8),
            ...stockouts
                .take(5)
                .map(
                  (p) => Card(
                    color: Theme.of(context).brightness == Brightness.dark
                        ? Colors.red.shade200
                        : Colors.red.shade50,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(8),
                      side: BorderSide(
                        color: Theme.of(context).brightness == Brightness.dark
                            ? Colors.red.withOpacity(0.5)
                            : Colors.red.shade100,
                      ),
                    ),
                    child: ListTile(
                      leading: const Icon(Icons.warning, color: Colors.red),
                      title: Text(
                        '${p['name']} (${p['product_code']})',
                        style: const TextStyle(color: Colors.black),
                      ),
                      subtitle: Text(
                        'Qty: ${p['current_qty']} (Target: ${p['reorder_level']})',
                        style: const TextStyle(color: Colors.black87),
                      ),
                      trailing: Text(
                        p['sku'],
                        style: const TextStyle(color: Colors.black54),
                      ),
                    ),
                  ),
                ),
          ],
          if (overstocks.isNotEmpty) ...[
            const SizedBox(height: 24),
            const Text(
              'Overstock Alerts',
              style: TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.bold,
                color: Colors.orange,
              ),
            ),
            const SizedBox(height: 8),
            ...overstocks
                .take(5)
                .map(
                  (p) => Card(
                    color: Theme.of(context).brightness == Brightness.dark
                        ? Colors.orange.shade200
                        : Colors.orange.shade50,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(8),
                      side: BorderSide(
                        color: Theme.of(context).brightness == Brightness.dark
                            ? Colors.orange.withOpacity(0.5)
                            : Colors.orange.shade100,
                      ),
                    ),
                    child: ListTile(
                      leading: const Icon(
                        Icons.inventory_2,
                        color: Colors.orange,
                      ),
                      title: Text(
                        '${p['name']} (${p['product_code']})',
                        style: const TextStyle(color: Colors.black),
                      ),
                      subtitle: Text(
                        'Qty: ${p['current_qty']} (Limit: ${p['overstock_level']})',
                        style: const TextStyle(color: Colors.black87),
                      ),
                      trailing: Text(
                        p['sku'],
                        style: const TextStyle(color: Colors.black54),
                      ),
                    ),
                  ),
                ),
          ],
        ],
      ),
    );
  }

  @override
// Handles build.
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _buildTopSummary(),
          const SizedBox(height: 16),
          _buildAlertsSection(),
          const SizedBox(height: 16),
          _buildGlobalForecastChart(),
          const Divider(height: 48),
          _buildForecastSection(),
          const SizedBox(height: 32),
        ],
      ),
    );
  }
}
