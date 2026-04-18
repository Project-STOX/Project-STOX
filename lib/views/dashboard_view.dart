import 'dart:async';

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
import 'manage_roles_view.dart';
import 'stock_receipt_view.dart';
import 'manage_users_view.dart';
import 'historical_sales_view.dart';
import 'import_data_view.dart';
import 'audit_log_view.dart';
import 'dashboard_content.dart';
import 'settings_view.dart';
import '../services/api/export_api_service.dart';
import '../utils/backup_downloader.dart';
import '../utils/theme_controller.dart';
import '../services/api/api_config.dart';
import 'send_feedback_view.dart';
import '../main.dart'; // To access global themeController

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
  Widget? _shelledContent;
  String? _shelledTitle;
  final List<Widget> _navigationStack = [];
  final List<String> _titleStack = [];

  // ── Scheduled Backup Timer (SME Owner only) ────────────────────────────
  Timer? _scheduleTimer;
  final ExportApiService _exportService = ExportApiService();

  @override
  void initState() {
    super.initState();
    _currentUser = widget.user;
    authController.cacheUser(_currentUser);
    _loadSidebarState();
    // Start the schedule checker only for SME Owner (role_id == 1)
    if (_currentUser.roleId == 1) {
      _startScheduleTimer();
    }
    themeController.addListener(_onThemeChanged);
  }

  void _onThemeChanged() {
    // If navigation mode changes, clear internal shelled state to avoid UI ghosting
    if (mounted) {
      setState(() {
        _shelledContent = null;
        _shelledTitle = null;
        _navigationStack.clear();
        _titleStack.clear();
      });
    }
  }

  void _startScheduleTimer() {
    // Fire every 30 s — ensures we always catch the target minute regardless
    // of when the app launched (a 60 s interval could miss a 1-minute window).
    _scheduleTimer = Timer.periodic(const Duration(seconds: 30), (_) {
      _checkAndRunSchedules();
    });
    // Also check immediately after a short warm-up delay
    Future.delayed(const Duration(seconds: 3), _checkAndRunSchedules);
  }

  Future<void> _checkAndRunSchedules() async {
    if (!mounted) return;
    try {
      final schedules = await _exportService.getSchedules();
      final now = DateTime.now();
      for (final schedule in schedules) {
        if (schedule.isDue()) {
          // Detect if this is a catch-up (not in the exact scheduled minute)
          final parts = schedule.scheduledTime.split(':');
          final h = int.tryParse(parts[0]) ?? 0;
          final m = int.tryParse(parts[1]) ?? 0;
          final isCatchUp = now.hour != h || now.minute != m;

          // Mark as run on server
          await _exportService.markScheduleRun(schedule.id);
          _runScheduledBackup(schedule, isCatchUp: isCatchUp);
        }
      }
    } catch (_) {
      // Fail silently for background poll
    }
  }

  Future<void> _runScheduledBackup(BackupScheduleModel schedule, {bool isCatchUp = false}) async {
    try {
      if (mounted && isCatchUp) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            behavior: SnackBarBehavior.floating,
            backgroundColor: Theme.of(context).colorScheme.secondary,
            duration: const Duration(seconds: 4),
            content: Text('Catching up on missed backup: "${schedule.label}"...'),
          ),
        );
      }

      final bytes = await _exportService.runBackup(schedule.categories, formats: schedule.formats);
      final timestamp = DateTime.now();
      final filename =
          'stox_scheduled_backup_${timestamp.year}${timestamp.month.toString().padLeft(2, '0')}${timestamp.day.toString().padLeft(2, '0')}_${timestamp.hour.toString().padLeft(2, '0')}${timestamp.minute.toString().padLeft(2, '0')}.zip';
      await downloadZip(bytes, filename);
      if (mounted) {
        final fmtLabel = schedule.formats.map((f) => f.toUpperCase()).join(' + ');
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            behavior: SnackBarBehavior.floating,
            backgroundColor: Colors.green.shade700,
            duration: const Duration(seconds: 6),
            content: Row(
              children: [
                const Icon(Icons.schedule_rounded, color: Colors.white),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    isCatchUp 
                      ? 'Missed backup "${schedule.label}" completed. ($fmtLabel)'
                      : 'Scheduled backup "${schedule.label}" completed. ($fmtLabel)',
                  ),
                ),
              ],
            ),
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            behavior: SnackBarBehavior.floating,
            backgroundColor: Theme.of(context).colorScheme.error,
            content: Text(
              'Scheduled backup "${schedule.label}" failed: ${e.toString().replaceFirst('Exception: ', '')}',
            ),
          ),
        );
      }
    }
  }

  @override
  void dispose() {
    themeController.removeListener(_onThemeChanged);
    _scheduleTimer?.cancel();
    super.dispose();
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

  // ── Shelled Navigation Logic ──────────────────────────────────────────────
  void _navigateTo(_NavItem item) {
    // Current mode determines if we shell/embed or push/standalone
    final bool isHeaderMode = themeController.navigationMode == AppNavigationMode.header;
    final bool showHeader = isHeaderMode && MediaQuery.of(context).size.width >= 800;

    // isEmbedded = true only if we are in Header mode (using Dashboard's AppBar)
    final view = item.builder!(showHeader);

    if (showHeader) {
      setState(() {
        if (_shelledContent != null) {
          _navigationStack.add(_shelledContent!);
          _titleStack.add(_shelledTitle ?? 'Page');
        }
        _shelledContent = view;
        _shelledTitle = item.label;
      });
    } else {
      Navigator.push(context, MaterialPageRoute(builder: (context) => view));
    }
  }

  void _navigateBack() {
    if (_navigationStack.isNotEmpty) {
      setState(() {
        _shelledContent = _navigationStack.removeLast();
        _shelledTitle = _titleStack.isNotEmpty ? _titleStack.removeLast() : null;
      });
    } else {
      setState(() {
        _shelledContent = null; // Return to DashboardContent
        _shelledTitle = null;
      });
    }
  }

  // ── Navigation Items ──────────────────────────────────────────────────────
  List<_NavItem> _getNavItems() {
    final list = <_NavItem>[];
    if (_canManageRoles) {
      list.add(_NavItem(
        icon: Icons.admin_panel_settings,
        label: 'Manage Roles & Permissions',
        builder: (emb) => ManageRolesView(user: _currentUser, isEmbedded: emb),
      ));
    }
    if (_canManageStock) {
      list.add(_NavItem(
        icon: Icons.inventory,
        label: 'Record Stock Receipt',
        builder: (emb) => StockReceiptView(user: _currentUser, isEmbedded: emb),
      ));
    }
    if (_canManageUsers) {
      list.add(_NavItem(
        icon: Icons.people,
        label: 'Manage Users',
        builder: (emb) => ManageUsersView(user: _currentUser, isEmbedded: emb),
      ));
    }
    if (_canManageProducts) {
      list.add(_NavItem(
        icon: Icons.production_quantity_limits,
        label: 'Manage Products',
        builder: (emb) => ManageProductsView(
          roleId: _currentUser.roleId,
          userId: _currentUser.userId,
          isEmbedded: emb,
        ),
      ));
    }
    if (_canManageSuppliers) {
      list.add(_NavItem(
        icon: Icons.business,
        label: 'Manage Suppliers',
        builder: (emb) => ManageSuppliersView(
          roleId: _currentUser.roleId,
          userId: _currentUser.userId,
          isEmbedded: emb,
        ),
      ));
    }
    if (_canSendMessage) {
      list.add(_NavItem(
        icon: Icons.message,
        label: 'Send Message',
        builder: (emb) => SendNotificationView(senderId: _currentUser.userId, isEmbedded: emb),
      ));
    }
    if (_canViewHistoricalData) {
      list.add(_NavItem(
        icon: Icons.history,
        label: 'Historical Sales Data',
        builder: (emb) => HistoricalSalesView(user: _currentUser, isEmbedded: emb),
      ));
    }
    if (_canViewAuditLog) {
      list.add(_NavItem(
        icon: Icons.manage_history,
        label: 'Audit Log',
        builder: (emb) => AuditLogView(user: _currentUser, isEmbedded: emb),
      ));
    }
     if (_canViewForecasts) {
        list.add(_NavItem(
         icon: Icons.auto_graph_rounded,
         label: 'Sales Forecast',
         builder: (emb) => HistoricalSalesView(user: _currentUser, isEmbedded: emb),
       ));
     }
    if (_canImportData) {
      list.add(_NavItem(
        icon: Icons.file_upload,
        label: 'Import Data',
        builder: (emb) => ImportDataView(user: _currentUser, isEmbedded: emb),
      ));
    }
    return list;
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: themeController,
      builder: (context, _) {
        final screenWidth = MediaQuery.of(context).size.width;
        // Force Sidebar mode on mobile screens regardless of setting
        final bool showHeader =
            themeController.navigationMode == AppNavigationMode.header &&
            screenWidth >= 800;

        return Scaffold(
          key: _scaffoldKey,
          appBar: _buildAppBar(context, showHeader),
          drawer: showHeader ? null : _buildDrawer(context),
          body: Column(
            children: [
              if (showHeader) _buildTopNav(context),
              Expanded(
                child: PopScope(
                  canPop: false,
                  onPopInvokedWithResult: (didPop, result) {
                    if (didPop) return;
                    if (_navigationStack.isNotEmpty || _shelledContent != null) {
                      _navigateBack();
                    } else {
                      // Allow system to handle back if we're at home
                    }
                  },
                  child: _isSidebarLoading
                      ? const Center(child: CircularProgressIndicator())
                      : (_shelledContent ?? DashboardContent(canViewForecasts: _canViewForecasts)),
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  PreferredSizeWidget _buildAppBar(BuildContext context, bool showHeader) {
    // Determine if we should show a back button or a hamburger
    final bool isShelled = _shelledContent != null;

    return AppBar(
      title: isShelled
          ? Text(_shelledTitle ?? "Content")
          : (showHeader
              ? Image.asset(
                  'assets/images/stox_logo.png',
                  height: 32,
                  filterQuality: FilterQuality.high,
                  errorBuilder: (c, e, s) => const Icon(Icons.inventory_2_rounded),
                )
              : const Text("Dashboard")),
      centerTitle: (showHeader && !isShelled) ? false : null,
      leading: isShelled
          ? IconButton(
              icon: const Icon(Icons.arrow_back),
              onPressed: _navigateBack,
              tooltip: 'Back to Dashboard',
            )
          : (showHeader
              ? null
              : IconButton(
                  icon: const Icon(Icons.menu),
                  onPressed: () => _scaffoldKey.currentState?.openDrawer(),
                )),
      actions: [
        IconButton(
          icon: const Icon(Icons.notifications_none_rounded),
          onPressed: () {
            final isHeaderMode = themeController.navigationMode == AppNavigationMode.header;
            final bool showHeader = isHeaderMode && MediaQuery.of(context).size.width >= 800;

            _navigateTo(_NavItem(
              icon: Icons.notifications,
              label: 'Notifications',
              builder: (emb) => NotificationsListView(
                userId: _currentUser.userId,
                isEmbedded: emb,
              ),
            ));
          },
        ),
        if (showHeader) ...[
          const VerticalDivider(width: 20, indent: 12, endIndent: 12),
          _buildAccountMenu(context),
        ],
        const SizedBox(width: 8),
      ],
    );
  }

  Widget _buildAccountMenu(BuildContext context) {
    return PopupMenuButton(
      offset: const Offset(0, 48),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12),
        child: Row(
          children: [
            CircleAvatar(
              radius: 14,
              backgroundColor: Theme.of(context).colorScheme.primaryContainer,
              child: Text(_currentUser.username[0].toUpperCase(),
                  style: TextStyle(
                      fontSize: 12,
                      color: Theme.of(context).colorScheme.onPrimaryContainer)),
            ),
            const SizedBox(width: 8),
            Text(_currentUser.username, style: const TextStyle(fontSize: 14)),
            const Icon(Icons.arrow_drop_down, size: 18),
          ],
        ),
      ),
      onSelected: (val) {
        final isHeaderMode = themeController.navigationMode == AppNavigationMode.header;
        final bool showHeader = isHeaderMode && MediaQuery.of(context).size.width >= 800;

        if (val == 'settings') {
          _navigateTo(_NavItem(
            icon: Icons.settings,
            label: 'Settings',
            builder: (emb) => SettingsView(
              user: _currentUser,
              canManageBackup: _canSetupBackup,
              isEmbedded: emb,
            ),
          ));
        } else if (val == 'account') {
          _navigateTo(_NavItem(
            icon: Icons.account_circle,
            label: 'Account',
            builder: (emb) => AccountView(
              user: _currentUser,
              isEmbedded: emb,
              onUserUpdated: (updatedUser) {
                setState(() => _currentUser = updatedUser);
              },
            ),
          ));
        } else if (val == 'feedback') {
          _navigateTo(_NavItem(
            icon: Icons.feedback,
            label: 'Feedback',
            builder: (emb) => SendFeedbackView(
              user: _currentUser, 
              isEmbedded: emb,
              onSuccess: _navigateBack,
            ),
          ));
        } else if (val == 'logout') {
          _logout(context);
        }
      },
      itemBuilder: (ctx) => <PopupMenuEntry>[
        const PopupMenuItem(value: 'account', child: Text('Account Profile')),
        const PopupMenuItem(value: 'settings', child: Text('System Settings')),
        const PopupMenuItem(value: 'feedback', child: Text('Send Feedback')),
        const PopupMenuDivider(),
        const PopupMenuItem(value: 'logout', child: Text('Logout')),
      ],
    );
  }

  Widget _buildTopNav(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final navItems = _getNavItems();

    return Container(
      height: 52,
      decoration: BoxDecoration(
        color: colorScheme.surface,
        border: Border(bottom: BorderSide(color: colorScheme.outlineVariant, width: 0.5)),
      ),
      child: ListView.builder(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 16),
        itemCount: navItems.length,
        itemBuilder: (context, index) {
          final item = navItems[index];
          return Padding(
            padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 8),
            child: TextButton.icon(
              onPressed: () => _navigateTo(item),
              icon: Icon(item.icon, size: 18),
              label: Text(
                item.label, 
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w500),
              ),
              style: TextButton.styleFrom(
                foregroundColor: colorScheme.onSurface,
                padding: const EdgeInsets.symmetric(horizontal: 12),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
              ),
            ),
          );
        },
      ),
    );
  }

  Widget _buildDrawer(BuildContext context) {
    final navItems = _getNavItems();
    return Drawer(
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
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 20,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  _resolvedRole,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(color: Colors.white70, fontSize: 14),
                ),
              ],
            ),
          ),
          if (_isSidebarLoading)
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 16),
              child: Center(child: CircularProgressIndicator()),
            ),
          ...navItems.map((item) => ListTile(
                leading: Icon(item.icon),
                title: Text(item.label),
                onTap: () {
                  Navigator.pop(context);
                  _navigateTo(item);
                },
              )),
          const Divider(),
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
            leading: const Icon(Icons.feedback_outlined),
            title: const Text('Send Feedback'),
                onTap: () {
                  Navigator.pop(context);
                  Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (context) => SendFeedbackView(
                        user: _currentUser,
                        onSuccess: () => Navigator.pop(context),
                      ),
                    ),
                  );
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
    );
  }
}

class _NavItem {
  final IconData icon;
  final String label;
  final Widget Function(bool isEmbedded)? builder;

  _NavItem({
    required this.icon,
    required this.label,
    this.builder,
  });
}
