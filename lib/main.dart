import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

// Import your views
import 'views/login_view.dart';
import 'views/dashboard_view.dart';
import 'views/product_list_view.dart';
import 'views/manage_users_view.dart';
import 'views/manage_roles_view.dart';
import 'views/stock_receipt_view.dart';
import 'models/user.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await Supabase.initialize(
    url: 'https://odowtpnnkxgdbmtnqphr.supabase.co',
    anonKey:
        'eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6Im9kb3d0cG5ua3hnZGJtdG5xcGhyIiwicm9sZSI6ImFub24iLCJpYXQiOjE3NzQ2ODEwNjEsImV4cCI6MjA5MDI1NzA2MX0.jTGi-vgWnb6XmlaXuHK5CvsmirponTw3s0FHy-iFzig',
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
      },
    );
  }
}
