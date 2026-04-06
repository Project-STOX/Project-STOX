import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

// Import your views
import 'views/login_view.dart';
import 'views/dashboard_view.dart';
import 'views/product_list_view.dart';
import 'views/manage_users_view.dart';
import 'views/manage_roles_view.dart';
import 'views/stock_receipt_view.dart';
import 'views/audit_log_view.dart';
import 'models/user.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  const supabaseUrl = String.fromEnvironment(
    'SUPABASE_URL',
    defaultValue: 'https://odowtpnnkxgdbmtnqphr.supabase.co',
  );
  const supabaseAnonKey = String.fromEnvironment(
    'SUPABASE_ANON_KEY',
    defaultValue: 'sb_publishable_vmL-vLqnAcwbDMrmOew7Ww_-KGRa6Hk',
  );

  await Supabase.initialize(
    url: supabaseUrl,
    anonKey: supabaseAnonKey,
  );
  runApp(MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'STOX Inventory',
      theme: ThemeData(primarySwatch: Colors.blue),
      debugShowCheckedModeBanner: false,
      initialRoute: '/',
      routes: {
        '/': (context) => LoginView(),
        '/dashboard': (context) {
          final user = ModalRoute.of(context)!.settings.arguments as UserModel;
          return DashboardView(user: user);
        },
        '/products': (context) => ProductListView(),
        '/manageUsers': (context) {
          final user = ModalRoute.of(context)!.settings.arguments as UserModel;
          return ManageUsersView(user: user);
        },
        '/manageRoles': (context) {
          final user = ModalRoute.of(context)!.settings.arguments as UserModel;
          return ManageRolesView(user: user);
        },
        '/stockReceipt': (context) {
          final user = ModalRoute.of(context)!.settings.arguments as UserModel;
          return StockReceiptView(user: user);
        },
        '/auditLog': (context) {
          final user = ModalRoute.of(context)!.settings.arguments as UserModel;
          return AuditLogView(user: user);
        },
      },
    );
  }
}
