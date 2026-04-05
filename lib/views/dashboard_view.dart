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
import 'historical_sales_view.dart';

class DashboardView extends StatefulWidget {
  final UserModel user;

  const DashboardView({super.key, required this.user});

  @override
  State<DashboardView> createState() => _DashboardViewState();
}

class _DashboardViewState extends State<DashboardView> {
  final AuthController authController = AuthController();
  final NotificationController notificationController =
      NotificationController();
  final HistoricalSalesController historicalSalesController =
      HistoricalSalesController();
  final StockController stockController = StockController();

  @override
  void initState() {
    super.initState();
    // Ensure permissions exist in DB
    notificationController.ensureSendMessagePermission();
    historicalSalesController.ensureHistoricalDataPermission();
    stockController.ensureStockReceiptPermission();
  }

  void _logout(BuildContext context) async {
    try {
      // Sign out and remove remembered mobile session token.
      await authController.signOutAndInvalidateRememberedSession();

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
    return FutureBuilder<String?>(
      future: authController.getUserRole(widget.user.roleId),
      builder: (context, snapshot) {
        if (!snapshot.hasData) {
          return const Center(child: CircularProgressIndicator());
        }

        final role = snapshot.data;

        return Scaffold(
          appBar: AppBar(
            title: Text("Dashboard"),
            leading: Builder(
              builder: (context) => IconButton(
                icon: const Icon(Icons.menu),
                onPressed: () => Scaffold.of(context).openDrawer(),
              ),
            ),
            actions: [
              IconButton(
                icon: const Icon(Icons.notifications),
                onPressed: () {
                  Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (context) =>
                          NotificationsListView(userId: widget.user.userId),
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
                  decoration: const BoxDecoration(color: Colors.blue),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisAlignment: MainAxisAlignment.end,
                    children: [
                      Text(
                        widget.user.username,
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 20,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      const SizedBox(height: 8),
                      Text(
                        role ?? 'User',
                        style: const TextStyle(
                          color: Colors.white70,
                          fontSize: 16,
                        ),
                      ),
                    ],
                  ),
                ),
                FutureBuilder<bool>(
                  future: authController.hasPermission(
                    widget.user.roleId,
                    "Manage Roles",
                  ),
                  builder: (context, snapshot) {
                    if (snapshot.hasData && snapshot.data == true) {
                      return ListTile(
                        leading: const Icon(Icons.admin_panel_settings),
                        title: const Text('Manage Roles & Permissions'),
                        onTap: () {
                          Navigator.pop(context); // Close drawer
                          Navigator.pushNamed(
                            context,
                            '/manageRoles',
                            arguments: widget.user,
                          );
                        },
                      );
                    }
                    return const SizedBox.shrink();
                  },
                ),
                FutureBuilder<bool>(
                  future: authController.hasPermission(
                    widget.user.roleId,
                    "Manage stock",
                  ),
                  builder: (context, snapshot) {
                    if (snapshot.hasData && snapshot.data == true) {
                      return ListTile(
                        leading: const Icon(Icons.inventory),
                        title: const Text('Record Stock Receipt'),
                        onTap: () {
                          Navigator.pop(context); // Close drawer
                          Navigator.pushNamed(
                            context,
                            '/stockReceipt',
                            arguments: widget.user,
                          );
                        },
                      );
                    }
                    return const SizedBox.shrink();
                  },
                ),
                ListTile(
                  leading: const Icon(Icons.inventory_2),
                  title: const Text('View Products'),
                  onTap: () {
                    Navigator.pop(context); // Close drawer
                    Navigator.pushNamed(context, '/products');
                  },
                ),
                FutureBuilder<bool>(
                  future: authController.hasPermission(
                    widget.user.roleId,
                    "Manage Users",
                  ),
                  builder: (context, snapshot) {
                    if (snapshot.hasData && snapshot.data == true) {
                      return ListTile(
                        leading: const Icon(Icons.people),
                        title: const Text('Manage Users'),
                        onTap: () {
                          Navigator.pop(context); // Close drawer
                          Navigator.pushNamed(
                            context,
                            '/manageUsers',
                            arguments: widget.user,
                          );
                        },
                      );
                    }
                    return const SizedBox.shrink();
                  },
                ),
                FutureBuilder<bool>(
                  future: authController.hasPermission(
                    widget.user.roleId,
                    "Manage Products",
                  ),
                  builder: (context, snapshot) {
                    if (snapshot.hasData && snapshot.data == true) {
                      return ListTile(
                        leading: const Icon(Icons.production_quantity_limits),
                        title: const Text('Manage Products'),
                        onTap: () {
                          Navigator.pop(context); // Close drawer
                          Navigator.push(
                            context,
                            MaterialPageRoute(
                              builder: (context) => ManageProductsView(
                                roleId: widget.user.roleId,
                              ),
                            ),
                          );
                        },
                      );
                    }
                    return const SizedBox.shrink();
                  },
                ),
                FutureBuilder<bool>(
                  future: authController.hasPermission(
                    widget.user.roleId,
                    "Manage Suppliers",
                  ),
                  builder: (context, snapshot) {
                    if (snapshot.hasData && snapshot.data == true) {
                      return ListTile(
                        leading: const Icon(Icons.business),
                        title: const Text('Manage Suppliers'),
                        onTap: () {
                          Navigator.pop(context); // Close drawer
                          Navigator.push(
                            context,
                            MaterialPageRoute(
                              builder: (context) => ManageSuppliersView(
                                roleId: widget.user.roleId,
                                userId: widget.user.userId,
                              ),
                            ),
                          );
                        },
                      );
                    }
                    return const SizedBox.shrink();
                  },
                ),
                FutureBuilder<bool>(
                  future: authController.hasPermission(
                    widget.user.roleId,
                    "Send message",
                  ),
                  builder: (context, snapshot) {
                    if (snapshot.hasData && snapshot.data == true) {
                      return ListTile(
                        leading: const Icon(Icons.message),
                        title: const Text('Send Message'),
                        onTap: () {
                          Navigator.pop(context); // Close drawer
                          Navigator.push(
                            context,
                            MaterialPageRoute(
                              builder: (context) => SendNotificationView(
                                senderId: widget.user.userId,
                              ),
                            ),
                          );
                        },
                      );
                    }
                    return const SizedBox.shrink();
                  },
                ),
                FutureBuilder<bool>(
                  future: authController.hasPermission(
                    widget.user.roleId,
                    "Historical data",
                  ),
                  builder: (context, snapshot) {
                    if (snapshot.hasData && snapshot.data == true) {
                      return ListTile(
                        leading: const Icon(Icons.history),
                        title: const Text('Historical Sales Data'),
                        onTap: () {
                          Navigator.pop(context); // Close drawer
                          Navigator.push(
                            context,
                            MaterialPageRoute(
                              builder: (context) =>
                                  HistoricalSalesView(user: widget.user),
                            ),
                          );
                        },
                      );
                    }
                    return const SizedBox.shrink();
                  },
                ),
                const Divider(),
                ListTile(
                  leading: const Icon(Icons.account_circle),
                  title: const Text('Account'),
                  onTap: () {
                    Navigator.pop(context); // Close drawer
                    Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (context) => AccountView(user: widget.user),
                      ),
                    );
                  },
                ),
                ListTile(
                  leading: const Icon(Icons.logout),
                  title: const Text('Logout'),
                  onTap: () {
                    Navigator.pop(context); // Close drawer
                    _logout(context);
                  },
                ),
              ],
            ),
          ),
          body: const Center(
            child: Text(
              'Welcome to STOX Inventory Management\n\nUse the menu button to access features.',
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 16),
            ),
          ),
        );
      },
    );
  }
}
