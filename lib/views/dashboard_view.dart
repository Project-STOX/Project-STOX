import 'package:flutter/material.dart';
import '../controllers/auth_controller.dart';
import '../models/user.dart';
import 'manage_products_view.dart';
import 'manage_supplier_view.dart';
import 'account_view.dart';

class DashboardView extends StatelessWidget {
  final UserModel user;
  final AuthController authController = AuthController();

  DashboardView({super.key, required this.user});

  void _logout(BuildContext context) async {
    try {
      // Sign out from Supabase Auth (in case there's an active session from 2FA)
      await authController.supabase.auth.signOut();
      
      // Navigate back to login page and clear navigation stack
      Navigator.of(context).pushNamedAndRemoveUntil('/', (Route<dynamic> route) => false);
    } catch (e) {
      // Even if sign out fails, navigate to login
      Navigator.of(context).pushNamedAndRemoveUntil('/', (Route<dynamic> route) => false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<String?>(
      future: authController.getUserRole(user.roleId),
      builder: (context, snapshot) {
        if (!snapshot.hasData) return const Center(child: CircularProgressIndicator());

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
          ),
          drawer: Drawer(
            child: ListView(
              padding: EdgeInsets.zero,
              children: [
                DrawerHeader(
                  decoration: const BoxDecoration(
                    color: Colors.blue,
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisAlignment: MainAxisAlignment.end,
                    children: [
                      Text(
                        user.username,
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
                  future: authController.hasPermission(user.roleId, "Manage Roles"),
                  builder: (context, snapshot) {
                    if (snapshot.hasData && snapshot.data == true) {
                      return ListTile(
                        leading: const Icon(Icons.admin_panel_settings),
                        title: const Text('Manage Roles & Permissions'),
                        onTap: () {
                          Navigator.pop(context); // Close drawer
                          Navigator.pushNamed(context, '/manageRoles', arguments: user);
                        },
                      );
                    }
                    return const SizedBox.shrink();
                  },
                ),
                FutureBuilder<bool>(
                  future: authController.hasPermission(user.roleId, "Manage stock"),
                  builder: (context, snapshot) {
                    if (snapshot.hasData && snapshot.data == true) {
                      return ListTile(
                        leading: const Icon(Icons.inventory),
                        title: const Text('Record Stock Receipt'),
                        onTap: () {
                          Navigator.pop(context); // Close drawer
                          Navigator.pushNamed(context, '/stockReceipt');
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
                  future: authController.hasPermission(user.roleId, "Manage Users"),
                  builder: (context, snapshot) {
                    if (snapshot.hasData && snapshot.data == true) {
                      return ListTile(
                        leading: const Icon(Icons.people),
                        title: const Text('Manage Users'),
                        onTap: () {
                          Navigator.pop(context); // Close drawer
                          Navigator.pushNamed(context, '/manageUsers', arguments: user);
                        },
                      );
                    }
                    return const SizedBox.shrink();
                  },
                ),
                FutureBuilder<bool>(
                  future: authController.hasPermission(user.roleId, "Manage Products"),
                  builder: (context, snapshot) {
                    if (snapshot.hasData && snapshot.data == true) {
                      return ListTile(
                        leading: const Icon(Icons.production_quantity_limits),
                        title: const Text('Manage Products'),
                        onTap: () {
                          Navigator.pop(context); // Close drawer
                          Navigator.push(
                            context,
                            MaterialPageRoute(builder: (context) => ManageProductsView(roleId: user.roleId)),
                          );
                        },
                      );
                    }
                    return const SizedBox.shrink();
                  },
                ),
                FutureBuilder<bool>(
                  future: authController.hasPermission(user.roleId, "Manage Suppliers"),
                  builder: (context, snapshot) {
                    if (snapshot.hasData && snapshot.data == true) {
                      return ListTile(
                        leading: const Icon(Icons.business),
                        title: const Text('Manage Suppliers'),
                        onTap: () {
                          Navigator.pop(context); // Close drawer
                          Navigator.push(
                            context,
                            MaterialPageRoute(builder: (context) => ManageSuppliersView(roleId: user.roleId, userId: user.userId)),
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
                      MaterialPageRoute(builder: (context) => AccountView(user: user)),
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
