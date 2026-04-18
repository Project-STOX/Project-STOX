import 'package:flutter/material.dart';
import 'services/supabase_service.dart';

// Import your views
import 'views/login_view.dart';
import 'views/dashboard_view.dart';
import 'views/product_list_view.dart';
import 'views/manage_users_view.dart';
import 'views/manage_roles_view.dart';
import 'views/stock_receipt_view.dart';
import 'views/audit_log_view.dart';
import 'models/user.dart';
import 'utils/theme_controller.dart';

import 'dart:async';
import 'services/api/api_config.dart';

final themeController = ThemeController();

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  
  // 1. Initialize DB
  await SupabaseService.initializeIfConfigured();

  // 2. Resilient Networking: Ping Cloud URL with a tight timeout
  // If it's sleeping, Render starts waking up, but we fail-over to local instantly.
  await ApiConfig.checkHealth(timeout: const Duration(milliseconds: 1500));

  // 3. If we failed over to local, set a 2-minute timer to switch back to cloud
  // once it has finished waking up.
  if (!ApiConfig.isUsingCloud.value) {
    Timer(const Duration(minutes: 2), () async {
      debugPrint('STOX: 2-minute mark reached. Attempting cloud wake-up switch...');
      await ApiConfig.trySwitchToCloud();
    });
  }

  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: themeController,
      builder: (context, _) {
        return MaterialApp(
          title: 'STOX Inventory',
          theme: themeController.getLightTheme(),
          darkTheme: themeController.getDarkTheme(),
          themeMode: themeController.themeMode,
          debugShowCheckedModeBanner: false,
          initialRoute: '/',
          routes: {
            '/': (context) => LoginView(),
            '/dashboard': (context) {
              final args = ModalRoute.of(context)?.settings.arguments;
              if (args == null || args is! UserModel) {
                return LoginView(); // Redirect to login if session lost
              }
              return DashboardView(user: args);
            },
            '/products': (context) => ProductListView(),
            '/manageUsers': (context) {
              final args = ModalRoute.of(context)?.settings.arguments;
              if (args == null || args is! UserModel) {
                return LoginView();
              }
              return ManageUsersView(user: args);
            },
            '/manageRoles': (context) {
              final args = ModalRoute.of(context)?.settings.arguments;
              if (args == null || args is! UserModel) {
                return LoginView();
              }
              return ManageRolesView(user: args);
            },
            '/stockReceipt': (context) {
              final args = ModalRoute.of(context)?.settings.arguments;
              if (args == null || args is! UserModel) {
                return LoginView();
              }
              return StockReceiptView(user: args);
            },
            '/auditLog': (context) {
              final args = ModalRoute.of(context)?.settings.arguments;
              if (args == null || args is! UserModel) {
                return LoginView();
              }
              return AuditLogView(user: args);
            },
          },
        );
      },
    );
  }
}
