import 'package:flutter/material.dart';
import 'services/supabase_service.dart';
import 'services/api/api_config.dart';

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

final themeController = ThemeController();

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // 1. Initialize DB and API Config
  await SupabaseService.initializeIfConfigured();
  await ApiConfig.initialize();

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
