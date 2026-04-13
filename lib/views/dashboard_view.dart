import 'package:flutter/material.dart';
import '../controllers/auth_controller.dart';
import '../models/user.dart';
import 'manage_products_view.dart';
import 'manage_supplier_view.dart';
import 'account_view.dart';
import 'send_notification_view.dart';
import 'notifications_list_view.dart';
import '../controllers/notification_controller.dart';
import '../controllers/historical_sales_controller.dart';
import '../controllers/stock_controller.dart';
import '../controllers/role_controller.dart';
import 'historical_sales_view.dart';
import 'import_data_view.dart';
import 'audit_log_view.dart';
import 'dashboard_content.dart';
import 'settings_view.dart';

class DashboardView extends StatefulWidget {
  final UserModel user;

  const DashboardView({super.key, required this.user});

  @override
  State<DashboardView> createState() => _DashboardViewState();
}

class _DashboardViewState extends State<DashboardView> {
  late UserModel _currentUser;
  final GlobalKey<ScaffoldState> _scaffoldKey = GlobalKey<ScaffoldState>();
  final AuthController authController = AuthController();
  final NotificationController notificationController =
      NotificationController();
  final HistoricalSalesController historicalSalesController =
      HistoricalSalesController();
  final StockController stockController = StockController();
  final RoleController roleController = RoleController();
  String _resolvedRole = 'User';
  bool _canManageRoles = false;
  bool _canManageStock = false;
  bool _canManageUsers = false;
  bool _canManageProducts = false;
  bool _canManageSuppliers = false;
  bool _canSendMessage = false;
  bool _canViewHistoricalData = false;
  bool _canViewAuditLog = false;
  bool _canImportData = false;
  bool _canViewForecasts = false;
  bool _canSetupBackup = false;
  bool _isSidebarLoading = true;

  @override
  void initState() {
    super.initState();
    _currentUser = widget.user;
    authController.cacheUser(_currentUser);
    _loadSidebarState();
  }

  Future<void> _loadSidebarState() async {
    final role = await authController
        .getUserRole(_currentUser.roleId)
        .catchError((_) => _currentUser.role);
    final requiredPerms = [
      'Manage Roles',
      'Manage stock',
      'Manage Users',
      'Manage Products',
      'Manage Suppliers',
      'Send message',
      'Historical data',
      'View audit log',
      'Import data',
      'View forecasts',
      'Setup backup',
    ];

    final permissionsMap = await authController
        .hasPermissionsBatch(requiredPerms)
        .catchError((_) => <String, bool>{});

    if (!mounted) {
      return;
    }

    setState(() {
      _resolvedRole = (role ?? _currentUser.role).trim().isEmpty
          ? 'User'
          : (role ?? _currentUser.role).trim();
      _canManageRoles = permissionsMap['Manage Roles'] ?? false;
      _canManageStock = permissionsMap['Manage stock'] ?? false;
      _canManageUsers = permissionsMap['Manage Users'] ?? false;
      _canManageProducts = permissionsMap['Manage Products'] ?? false;
      _canManageSuppliers = permissionsMap['Manage Suppliers'] ?? false;
      _canSendMessage = permissionsMap['Send message'] ?? false;
      _canViewHistoricalData = permissionsMap['Historical data'] ?? false;
      _canViewAuditLog = permissionsMap['View audit log'] ?? false;
      _canImportData = permissionsMap['Import data'] ?? false;
      _canViewForecasts = permissionsMap['View forecasts'] ?? false;
      _canSetupBackup = permissionsMap['Setup backup'] ?? false;
      _isSidebarLoading = false;
    });
  }

  void _logout(BuildContext context) async {
    try {
      // Sign out and remove remembered mobile session token.
      await authController.signOutAndInvalidateRememberedSession(
        userId: _currentUser.userId,
      );

      // Navigate back to login page and clear navigation stack
      if (mounted) {
        Navigator.of(
          context,
        ).pushNamedAndRemoveUntil('/', (Route<dynamic> route) => false);
      }
    } catch (e) {
      // Even if sign out fails, navigate to login
      if (mounted) {
        Navigator.of(
          context,
        ).pushNamedAndRemoveUntil('/', (Route<dynamic> route) => false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      key: _scaffoldKey,
      appBar: AppBar(
        title: const Text("Dashboard"),
        leading: IconButton(
          icon: const Icon(Icons.menu),
          onPressed: () => _scaffoldKey.currentState?.openDrawer(),
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.notifications),
            onPressed: () {
              Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (context) =>
                      NotificationsListView(userId: _currentUser.userId),
                ),
              );
            },
          ),
        ],
      ),
      drawer: Drawer(
        child: ListView(
          padding: EdgeInsets.zero,
          children: [
            DrawerHeader(
              decoration: BoxDecoration(color: Theme.of(context).colorScheme.primary),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  Text(
                    _currentUser.username,
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 20,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    _resolvedRole,
                    style: const TextStyle(color: Colors.white70, fontSize: 16),
                  ),
                ],
              ),
            ),
            if (_isSidebarLoading)
              const Padding(
                padding: EdgeInsets.symmetric(vertical: 16),
                child: Center(child: CircularProgressIndicator()),
              ),
            if (_canManageRoles)
              ListTile(
                leading: const Icon(Icons.admin_panel_settings),
                title: const Text('Manage Roles & Permissions'),
                onTap: () async {
                  Navigator.pop(context);
                  await Navigator.pushNamed(
                    context,
                    '/manageRoles',
                    arguments: _currentUser,
                  );
                  _loadSidebarState();
                },
              ),
            if (_canManageStock)
              ListTile(
                leading: const Icon(Icons.inventory),
                title: const Text('Record Stock Receipt'),
                onTap: () {
                  Navigator.pop(context);
                  Navigator.pushNamed(
                    context,
                    '/stockReceipt',
                    arguments: _currentUser,
                  );
                },
              ),

            if (_canManageUsers)
              ListTile(
                leading: const Icon(Icons.people),
                title: const Text('Manage Users'),
                onTap: () async {
                  Navigator.pop(context);
                  await Navigator.pushNamed(
                    context,
                    '/manageUsers',
                    arguments: _currentUser,
                  );
                  _loadSidebarState();
                },
              ),
            if (_canManageProducts)
              ListTile(
                leading: const Icon(Icons.production_quantity_limits),
                title: const Text('Manage Products'),
                onTap: () {
                  Navigator.pop(context);
                  Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (context) => ManageProductsView(
                        roleId: _currentUser.roleId,
                        userId: _currentUser.userId,
                      ),
                    ),
                  );
                },
              ),
            if (_canManageSuppliers)
              ListTile(
                leading: const Icon(Icons.business),
                title: const Text('Manage Suppliers'),
                onTap: () {
                  Navigator.pop(context);
                  Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (context) => ManageSuppliersView(
                        roleId: _currentUser.roleId,
                        userId: _currentUser.userId,
                      ),
                    ),
                  );
                },
              ),
            if (_canSendMessage)
              ListTile(
                leading: const Icon(Icons.message),
                title: const Text('Send Message'),
                onTap: () {
                  Navigator.pop(context);
                  Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (context) =>
                          SendNotificationView(senderId: _currentUser.userId),
                    ),
                  );
                },
              ),
            if (_canViewHistoricalData)
              ListTile(
                leading: const Icon(Icons.history),
                title: const Text('Historical Sales Data'),
                onTap: () {
                  Navigator.pop(context);
                  Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (context) =>
                          HistoricalSalesView(user: _currentUser),
                    ),
                  );
                },
              ),
            if (_canViewAuditLog)
              ListTile(
                leading: const Icon(Icons.manage_history),
                title: const Text('Audit Log'),
                onTap: () {
                  Navigator.pop(context);
                  Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (context) => AuditLogView(user: _currentUser),
                    ),
                  );
                },
              ),
            if (_canImportData)
              ListTile(
                leading: const Icon(Icons.file_upload),
                title: const Text('Import Data'),
                onTap: () {
                  Navigator.pop(context);
                  Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (context) => ImportDataView(user: _currentUser),
                    ),
                  );
                },
              ),
            const Divider(),
            // Settings – visible to ALL authenticated users.
            // The backup panel inside is gated by the 'Setup backup' permission.
            ListTile(
              leading: const Icon(Icons.settings_rounded),
              title: const Text('Settings'),
              onTap: () {
                Navigator.pop(context);
                Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (context) => SettingsView(
                      user: _currentUser,
                      canManageBackup: _canSetupBackup,
                    ),
                  ),
                );
              },
            ),
            ListTile(
              leading: const Icon(Icons.account_circle),
              title: const Text('Account'),
              onTap: () {
                Navigator.pop(context);
                Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (context) => AccountView(user: _currentUser),
                  ),
                ).then((updatedUser) {
                  if (updatedUser != null && updatedUser is UserModel) {
                    setState(() {
                      _currentUser = updatedUser;
                    });
                  }
                });
              },
            ),
            ListTile(
              leading: const Icon(Icons.logout),
              title: const Text('Logout'),
              onTap: () {
                Navigator.pop(context);
                _logout(context);
              },
            ),
          ],
        ),
      ),
      body: _isSidebarLoading 
          ? const Center(child: CircularProgressIndicator()) 
          : DashboardContent(canViewForecasts: _canViewForecasts),
    );
  }
}

