import 'dart:async';

import 'package:flutter/material.dart';

import '../main.dart'; // To access global themeController
import '../models/user.dart';
import 'new_backup_tab.dart';
import 'end_of_contract_view.dart';
import 'totp_setup_dialog.dart';
import '../controllers/auth_controller.dart';
import '../controllers/user_controller.dart';
import '../utils/theme_controller.dart';

// ─────────────────────────────────────────────────────────────────────────────
// Top-level model for a settings destination (tab entry in the sidebar)
// ─────────────────────────────────────────────────────────────────────────────
class _SettingsDestination {
  const _SettingsDestination({
    required this.title,
    required this.icon,
    required this.selectedIcon,
  });
  final String title;
  final IconData icon;
  final IconData selectedIcon;
}

// ─────────────────────────────────────────────────────────────────────────────
// Main SettingsView — Resizable Master-Detail split layout
// ─────────────────────────────────────────────────────────────────────────────
class SettingsView extends StatefulWidget {
  final UserModel user;
  final bool canManageBackup;
  final bool isEmbedded;
  final VoidCallback? onBack;

  const SettingsView({
    super.key,
    required this.user,
    required this.canManageBackup,
    this.isEmbedded = false,
    this.onBack,
  });

  @override
  State<SettingsView> createState() => _SettingsViewState();
}

class _SettingsViewState extends State<SettingsView> {
  // Sidebar width state — draggable between min/max
  double _sidebarWidth = 240.0;
  static const double _sidebarMinWidth = 180.0;
  static const double _sidebarMaxWidth = 400.0;
  static const double _dividerWidth = 6.0;

  // Selected navigation index
  int _selectedIndex = 0;

  // Build the destinations dynamically based on permissions
  List<_SettingsDestination> get _destinations {
    final list = <_SettingsDestination>[
      const _SettingsDestination(
        title: 'General',
        icon: Icons.settings_outlined,
        selectedIcon: Icons.settings_rounded,
      ),
      const _SettingsDestination(
        title: 'Security',
        icon: Icons.security_outlined,
        selectedIcon: Icons.security_rounded,
      ),
    ];
    // Manual data backup — based on permissions
    if (widget.canManageBackup) {
      list.add(
        const _SettingsDestination(
          title: 'Backup Data',
          icon: Icons.download_outlined,
          selectedIcon: Icons.download_rounded,
        ),
      );
    }
    // Advanced (Danger Zone) — SME Owner only
    if (widget.user.roleId == 1) {
      list.add(
        const _SettingsDestination(
          title: 'Advanced',
          icon: Icons.admin_panel_settings_outlined,
          selectedIcon: Icons.admin_panel_settings_rounded,
        ),
      );
    }
    return list;
  }

  Widget _buildContent() {
    if (_destinations.isEmpty) return const SizedBox.shrink();
    final title = _destinations[_selectedIndex].title;
    switch (title) {
      case 'General':
        return _GeneralSettingsTab(user: widget.user);
      case 'Security':
        return _SecuritySettingsTab(user: widget.user);
      case 'Backup Data':
        return NewBackupTab(user: widget.user);
      case 'Advanced':
        return _AdvancedSettingsTab(user: widget.user);
      default:
        return _GeneralSettingsTab(user: widget.user);
    }
  }

  @override
  Widget build(BuildContext context) {
    final screenWidth = MediaQuery.of(context).size.width;
    final bool isMobile = screenWidth < 700;

    return ListenableBuilder(
      listenable: themeController,
      builder: (context, _) {
        return Scaffold(
          appBar: widget.isEmbedded
              ? null
              : AppBar(
                  title: const Text('Settings'),
                  // Show hamburger on mobile if not embedded
                  leading: isMobile ? null : null,
                ),
          // Use a drawer on mobile to save space
          drawer: isMobile
              ? Drawer(
                  child: _SettingsSidebar(
                    destinations: _destinations,
                    selectedIndex: _selectedIndex,
                    onBack: () {
                      Navigator.pop(context); // Close drawer
                      if (widget.onBack != null) {
                        widget.onBack!();
                      } else {
                        Navigator.maybePop(context);
                      }
                    },
                    showMobileBack: true,
                    onDestinationSelected: (index) {
                      setState(() => _selectedIndex = index);
                      Navigator.pop(context); // Close drawer
                    },
                  ),
                )
              : null,
          body: Row(
            children: [
              // ── Left Sidebar (only on Desktop/Tablet) ─────────────────────
              if (!isMobile)
                SizedBox(
                  width: _sidebarWidth,
                  child: _SettingsSidebar(
                    destinations: _destinations,
                    selectedIndex: _selectedIndex,
                    onDestinationSelected: (index) {
                      setState(() => _selectedIndex = index);
                    },
                  ),
                ),

              // ── Draggable Divider (only on Desktop/Tablet) ────────────────
              if (!isMobile)
                MouseRegion(
                  cursor: SystemMouseCursors.resizeColumn,
                  child: GestureDetector(
                    behavior: HitTestBehavior.opaque,
                    onHorizontalDragUpdate: (details) {
                      setState(() {
                        _sidebarWidth = (_sidebarWidth + details.delta.dx)
                            .clamp(_sidebarMinWidth, _sidebarMaxWidth);
                      });
                    },
                    child: SizedBox(
                      width: _dividerWidth,
                      child: Center(
                        child: VerticalDivider(
                          width: 1,
                          thickness: 1,
                          color: Theme.of(
                            context,
                          ).dividerColor.withOpacity(0.25),
                        ),
                      ),
                    ),
                  ),
                ),

              // ── Right Content Panel ───────────────────────────────────────
              Expanded(
                child: Column(
                  children: [
                    // On mobile, show a simple title if no AppBar
                    if (isMobile && widget.isEmbedded)
                      Padding(
                        padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
                        child: Text(
                          _destinations[_selectedIndex].title,
                          style: const TextStyle(
                            fontSize: 24,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ),
                    Expanded(child: _buildContent()),
                  ],
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Sidebar Navigation Panel
// ─────────────────────────────────────────────────────────────────────────────
class _SettingsSidebar extends StatelessWidget {
  final List<_SettingsDestination> destinations;
  final int selectedIndex;
  final ValueChanged<int> onDestinationSelected;
  final VoidCallback? onBack;
  final bool showMobileBack;

  const _SettingsSidebar({
    required this.destinations,
    required this.selectedIndex,
    required this.onDestinationSelected,
    this.onBack,
    this.showMobileBack = false,
  });

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final surface = colorScheme.surfaceContainerLow;

    return Container(
      color: surface,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // ── Back Button (Mobile Drawer Only) ──────────────────────────────
          if (showMobileBack && onBack != null)
            Padding(
              padding: EdgeInsets.fromLTRB(
                12,
                MediaQuery.of(context).padding.top + 12,
                12,
                0,
              ),
              child: ListTile(
                dense: true,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(10),
                ),
                leading: Icon(
                  Icons.arrow_back_rounded,
                  size: 20,
                  color: colorScheme.onSurface.withOpacity(0.7),
                ),
                title: Text(
                  'Back to Dashboard',
                  style: TextStyle(fontSize: 14, color: colorScheme.onSurface),
                ),
                onTap: onBack,
              ),
            ),

          Padding(
            padding: const EdgeInsets.fromLTRB(16, 20, 16, 12),
            child: Text(
              'SETTINGS',
              style: TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.bold,
                letterSpacing: 1.2,
                color: colorScheme.onSurface.withOpacity(0.5),
              ),
            ),
          ),
          const Divider(height: 1, indent: 12, endIndent: 12),
          const SizedBox(height: 8),
          Expanded(
            child: ListView.builder(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
              itemCount: destinations.length,
              itemBuilder: (context, index) {
                final dest = destinations[index];
                final isSelected = index == selectedIndex;
                return Padding(
                  padding: const EdgeInsets.only(bottom: 2),
                  child: ListTile(
                    dense: true,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(10),
                    ),
                    selected: isSelected,
                    selectedTileColor: colorScheme.primaryContainer.withOpacity(
                      0.7,
                    ),
                    leading: Icon(
                      isSelected ? dest.selectedIcon : dest.icon,
                      size: 20,
                      color: isSelected
                          ? colorScheme.primary
                          : colorScheme.onSurface.withOpacity(0.7),
                    ),
                    title: Text(
                      dest.title,
                      style: TextStyle(
                        fontSize: 14,
                        fontWeight: isSelected
                            ? FontWeight.w600
                            : FontWeight.normal,
                        color: isSelected
                            ? colorScheme.primary
                            : colorScheme.onSurface,
                      ),
                    ),
                    onTap: () => onDestinationSelected(index),
                  ),
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Tab 0 — General Settings (Aesthetics + Account)
// ─────────────────────────────────────────────────────────────────────────────
class _GeneralSettingsTab extends StatelessWidget {
  final UserModel user;

  const _GeneralSettingsTab({required this.user});

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final bool isMobile = MediaQuery.of(context).size.width < 700;

    return SingleChildScrollView(
      padding: const EdgeInsets.all(24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // ── Aesthetics ────────────────────────────────────────────────────
          _SectionHeader(title: 'Aesthetics', icon: Icons.palette_rounded),
          const SizedBox(height: 12),
          _SettingsCard(
            children: [
              LayoutBuilder(
                builder: (context, constraints) {
                  final bool isNarrow = constraints.maxWidth < 450;
                  final appearanceTile = ListTile(
                    leading: const Icon(Icons.brightness_medium_rounded),
                    title: const Text('Appearance'),
                    subtitle: Text(
                      themeController.themeMode.name.toUpperCase(),
                    ),
                    trailing: isNarrow
                        ? null
                        : SegmentedButton<ThemeMode>(
                            segments: const [
                              ButtonSegment(
                                value: ThemeMode.light,
                                icon: Icon(Icons.light_mode),
                              ),
                              ButtonSegment(
                                value: ThemeMode.system,
                                icon: Icon(Icons.settings),
                              ),
                              ButtonSegment(
                                value: ThemeMode.dark,
                                icon: Icon(Icons.dark_mode),
                              ),
                            ],
                            selected: {themeController.themeMode},
                            onSelectionChanged: (Set<ThemeMode> newSelection) {
                              themeController.setThemeMode(newSelection.first);
                            },
                            showSelectedIcon: false,
                            style: const ButtonStyle(
                              visualDensity: VisualDensity.compact,
                            ),
                          ),
                  );

                  if (isNarrow) {
                    return Column(
                      children: [
                        appearanceTile,
                        Padding(
                          padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
                          child: SizedBox(
                            width: double.infinity,
                            child: SegmentedButton<ThemeMode>(
                              segments: const [
                                ButtonSegment(
                                  value: ThemeMode.light,
                                  icon: Icon(Icons.light_mode),
                                  label: Text('Light'),
                                ),
                                ButtonSegment(
                                  value: ThemeMode.system,
                                  icon: Icon(Icons.settings),
                                  label: Text('System'),
                                ),
                                ButtonSegment(
                                  value: ThemeMode.dark,
                                  icon: Icon(Icons.dark_mode),
                                  label: Text('Dark'),
                                ),
                              ],
                              selected: {themeController.themeMode},
                              onSelectionChanged:
                                  (Set<ThemeMode> newSelection) {
                                    themeController.setThemeMode(
                                      newSelection.first,
                                    );
                                  },
                              showSelectedIcon: false,
                            ),
                          ),
                        ),
                      ],
                    );
                  }
                  return appearanceTile;
                },
              ),
              const Divider(indent: 16, endIndent: 16),
              const ListTile(
                leading: Icon(Icons.color_lens_rounded),
                title: Text('Primary Color'),
                subtitle: Text('Personalize the system accent'),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
                child: Wrap(
                  spacing: 12,
                  runSpacing: 12,
                  children:
                      [
                        Colors.blue,
                        Colors.indigo,
                        Colors.deepPurple,
                        Colors.teal,
                        Colors.green,
                        Colors.orange,
                        Colors.redAccent,
                        Colors.pinkAccent,
                      ].map((color) {
                        final isSelected =
                            themeController.primaryColor.value == color.value;
                        return GestureDetector(
                          onTap: () => themeController.setPrimaryColor(color),
                          child: Container(
                            width: 32,
                            height: 32,
                            decoration: BoxDecoration(
                              color: color,
                              shape: BoxShape.circle,
                              border: isSelected
                                  ? Border.all(
                                      color: colorScheme.onSurface,
                                      width: 2,
                                    )
                                  : null,
                              boxShadow: [
                                if (isSelected)
                                  BoxShadow(
                                    color: color.withOpacity(0.4),
                                    blurRadius: 8,
                                    spreadRadius: 2,
                                  ),
                              ],
                            ),
                            child: isSelected
                                ? const Icon(
                                    Icons.check,
                                    color: Colors.white,
                                    size: 16,
                                  )
                                : null,
                          ),
                        );
                      }).toList(),
                ),
              ),
            ],
          ),

          if (!isMobile) ...[
            const SizedBox(height: 28),

            // ── Navigation Style ──────────────────────────────────────────────
            _SectionHeader(
              title: 'Navigation Style',
              icon: Icons.explore_rounded,
            ),
            const SizedBox(height: 12),
            _SettingsCard(
              children: [
                LayoutBuilder(
                  builder: (context, constraints) {
                    final bool isNarrow = constraints.maxWidth < 450;
                    final layoutTile = ListTile(
                      leading: const Icon(Icons.grid_view_rounded),
                      title: const Text('Layout Style'),
                      subtitle: Text(
                        themeController.navigationMode.name.toUpperCase(),
                      ),
                      trailing: isNarrow
                          ? null
                          : SegmentedButton<AppNavigationMode>(
                              segments: const [
                                ButtonSegment(
                                  value: AppNavigationMode.sidebar,
                                  icon: Icon(Icons.menu_open_rounded),
                                  label: Text('Sidebar'),
                                ),
                                ButtonSegment(
                                  value: AppNavigationMode.header,
                                  icon: Icon(Icons.view_headline_rounded),
                                  label: Text('Header'),
                                ),
                              ],
                              selected: {themeController.navigationMode},
                              onSelectionChanged:
                                  (Set<AppNavigationMode> newSelection) {
                                    themeController.setNavigationMode(
                                      newSelection.first,
                                    );
                                  },
                              showSelectedIcon: false,
                              style: const ButtonStyle(
                                visualDensity: VisualDensity.compact,
                              ),
                            ),
                    );

                    if (isNarrow) {
                      return Column(
                        children: [
                          layoutTile,
                          Padding(
                            padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
                            child: SizedBox(
                              width: double.infinity,
                              child: SegmentedButton<AppNavigationMode>(
                                segments: const [
                                  ButtonSegment(
                                    value: AppNavigationMode.sidebar,
                                    icon: Icon(Icons.menu_open_rounded),
                                    label: Text('Sidebar'),
                                  ),
                                  ButtonSegment(
                                    value: AppNavigationMode.header,
                                    icon: Icon(Icons.view_headline_rounded),
                                    label: Text('Header'),
                                  ),
                                ],
                                selected: {themeController.navigationMode},
                                onSelectionChanged:
                                    (Set<AppNavigationMode> newSelection) {
                                      themeController.setNavigationMode(
                                        newSelection.first,
                                      );
                                    },
                                showSelectedIcon: false,
                              ),
                            ),
                          ),
                        ],
                      );
                    }
                    return layoutTile;
                  },
                ),
              ],
            ),
          ],

          const SizedBox(height: 28),

          // ── Account ───────────────────────────────────────────────────────
          _SectionHeader(title: 'Account', icon: Icons.person_rounded),
          const SizedBox(height: 12),
          _SettingsCard(
            children: [
              _InfoRow(label: 'Username', value: user.username),
              const Divider(indent: 16, endIndent: 16),
              _InfoRow(label: 'Email', value: user.email),
              const Divider(indent: 16, endIndent: 16),
              _InfoRow(label: 'Role', value: user.role),
            ],
          ),
          const SizedBox(height: 40),
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Shared Widgets
// ─────────────────────────────────────────────────────────────────────────────

class _SectionHeader extends StatelessWidget {
  final String title;
  final IconData icon;
  const _SectionHeader({required this.title, required this.icon});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(left: 4, bottom: 8),
      child: Row(
        children: [
          Icon(icon, size: 18, color: Theme.of(context).colorScheme.primary),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              title.toUpperCase(),
              style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.bold,
                color: Theme.of(context).colorScheme.primary,
                letterSpacing: 1.2,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _SettingsCard extends StatelessWidget {
  final List<Widget> children;
  const _SettingsCard({required this.children});

  @override
  Widget build(BuildContext context) {
    return Card(
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: BorderSide(
          color: Theme.of(context).dividerColor.withOpacity(0.1),
        ),
      ),
      child: Column(children: children),
    );
  }
}

class _InfoRow extends StatelessWidget {
  final String label;
  final String value;
  const _InfoRow({required this.label, required this.value});

  @override
  Widget build(BuildContext context) {
    return ListTile(
      title: Text(
        label,
        style: const TextStyle(fontSize: 14, color: Colors.grey),
      ),
      trailing: Text(
        value,
        style: const TextStyle(fontWeight: FontWeight.w600),
      ),
    );
  }
}



// ─────────────────────────────────────────────────────────────────────────────
// Advanced Settings Tab
// ─────────────────────────────────────────────────────────────────────────────
class _AdvancedSettingsTab extends StatelessWidget {
  final UserModel user;

  const _AdvancedSettingsTab({required this.user});

  @override
  Widget build(BuildContext context) {
    if (user.roleId != 1) {
      return const Center(child: Text('Unauthorized'));
    }

    final theme = Theme.of(context);

    return Padding(
      padding: const EdgeInsets.all(32.0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Advanced',
            style: theme.textTheme.headlineMedium?.copyWith(
              fontWeight: FontWeight.bold,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            'Danger zone actions and advanced configuration.',
            style: theme.textTheme.bodyMedium?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
          const SizedBox(height: 32),
          Container(
            padding: const EdgeInsets.all(24),
            decoration: BoxDecoration(
              border: Border.all(color: theme.colorScheme.error),
              borderRadius: BorderRadius.circular(12),
              color: theme.colorScheme.error.withOpacity(0.05),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Icon(
                      Icons.warning_amber_rounded,
                      color: theme.colorScheme.error,
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        'Account Closure & Data Export',
                        style: theme.textTheme.titleLarge?.copyWith(
                          color: theme.colorScheme.error,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 16),
                Text(
                  'End your contract with STOX. This will allow you to export all your existing data in standard formats before immediately submitting a closure alert to IT. Your account will be permanently queued for deletion after your backup retention period.',
                  style: theme.textTheme.bodyMedium,
                ),
                const SizedBox(height: 24),
                ElevatedButton.icon(
                  onPressed: () {
                    Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (context) => const EndOfContractView(),
                      ),
                    );
                  },
                  style: ElevatedButton.styleFrom(
                    backgroundColor: theme.colorScheme.error,
                    foregroundColor: theme.colorScheme.onError,
                    padding: const EdgeInsets.symmetric(
                      horizontal: 24,
                      vertical: 12,
                    ),
                  ),
                  icon: const Icon(Icons.exit_to_app),
                  label: const Text('Initiate Closure Sequence'),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Tab - Security Settings (2FA / TOTP)
// ─────────────────────────────────────────────────────────────────────────────
class _SecuritySettingsTab extends StatefulWidget {
  final UserModel user;
  const _SecuritySettingsTab({required this.user});

  @override
  State<_SecuritySettingsTab> createState() => _SecuritySettingsTabState();
}

class _SecuritySettingsTabState extends State<_SecuritySettingsTab> {
  final AuthController _authController = AuthController();
  final UserController _userController = UserController();

  bool _isLoading = true;
  late UserModel _user;
  late bool _email2faEnabled;
  late bool _totpEnabled;

  // Change Password state
  final _passwordFormKey = GlobalKey<FormState>();
  final _oldPasswordController = TextEditingController();
  final _newPasswordController = TextEditingController();
  final _confirmPasswordController = TextEditingController();
  final _tfaCodeController = TextEditingController();

  bool _isOldPasswordVisible = false;
  bool _isNewPasswordVisible = false;
  bool _isConfirmPasswordVisible = false;
  final bool _useTfaForPasswordChange = false;

  @override
  void initState() {
    super.initState();
    _user = widget.user;
    _email2faEnabled = _user.tfaActive;
    _totpEnabled = _user.totpEnabled;
    _refreshUser();
  }

  Future<void> _refreshUser() async {
    try {
      final user = await _authController.getCurrentUser();
      if (mounted) {
        setState(() {
          _user = user;
          _email2faEnabled = user.tfaActive;
          _totpEnabled = user.totpEnabled;
          _isLoading = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() => _isLoading = false);
      }
    }
  }

  @override
  void dispose() {
    _oldPasswordController.dispose();
    _newPasswordController.dispose();
    _confirmPasswordController.dispose();
    _tfaCodeController.dispose();
    super.dispose();
  }

  Future<void> _changePassword() async {
    if (!(_passwordFormKey.currentState?.validate() ?? false)) return;

    setState(() => _isLoading = true);
    try {
      await _userController.updatePassword(
        _user.userId,
        _oldPasswordController.text,
        _newPasswordController.text,
        tfaCode: _useTfaForPasswordChange ? _tfaCodeController.text : null,
        actorUserId: _user.userId,
      );

      if (mounted) {
        setState(() {
          _isLoading = false;
          _oldPasswordController.clear();
          _newPasswordController.clear();
          _confirmPasswordController.clear();
          _tfaCodeController.clear();
        });
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            behavior: SnackBarBehavior.floating,
            content: Text('Password changed successfully'),
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        setState(() => _isLoading = false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            behavior: SnackBarBehavior.floating,
            backgroundColor: Theme.of(context).colorScheme.error,
            content: Text('Error: $e'),
          ),
        );
      }
    }
  }

  Future<void> _sendTfaCode() async {
    setState(() => _isLoading = true);
    try {
      await _authController.generate2FA(_user.userId);
      if (mounted) {
        setState(() => _isLoading = false);
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            behavior: SnackBarBehavior.floating,
            content: Text('2FA code sent to your email'),
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        setState(() => _isLoading = false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            behavior: SnackBarBehavior.floating,
            backgroundColor: Theme.of(context).colorScheme.error,
            content: Text('Error: $e'),
          ),
        );
      }
    }
  }

  Future<void> _toggleEmail2fa(bool enabled) async {
    setState(() => _isLoading = true);
    try {
      final updatedUser = await _userController.updateUser(
        _user.userId,
        tfaActive: enabled,
        actorUserId: _user.userId,
      );
      if (mounted) {
        setState(() {
          _user = updatedUser;
          _email2faEnabled = updatedUser.tfaActive;
          _isLoading = false;
        });
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Email 2FA ${enabled ? 'enabled' : 'disabled'}'),
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        setState(() => _isLoading = false);
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Error: $e')));
      }
    }
  }

  Future<void> _startTotpSetup() async {
    final success = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (context) => TOTPSetupDialog(user: _user),
    );

    if (success == true && mounted) {
      await _refreshUser();
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Authenticator App enabled successfully!'),
        ),
      );
    }
  }

  Future<void> _disableTotp() async {
    final passwordController = TextEditingController();
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Disable Authenticator App'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Enter your password to disable 2FA via Authenticator App.',
            ),
            const SizedBox(height: 16),
            TextField(
              controller: passwordController,
              obscureText: true,
              decoration: const InputDecoration(
                labelText: 'Password',
                border: OutlineInputBorder(),
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            style: FilledButton.styleFrom(backgroundColor: Colors.red),
            child: const Text('Disable'),
          ),
        ],
      ),
    );

    if (confirmed == true && mounted) {
      setState(() => _isLoading = true);
      try {
        await _authController.disableTOTP(passwordController.text);
        await _refreshUser();
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Authenticator App disabled.')),
          );
        }
      } catch (e) {
        if (mounted) {
          setState(() => _isLoading = false);
          ScaffoldMessenger.of(
            context,
          ).showSnackBar(SnackBar(content: Text('Error disabling TOTP: $e')));
        }
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoading) return const Center(child: CircularProgressIndicator());

    return SingleChildScrollView(
      padding: const EdgeInsets.all(24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _SectionHeader(
            title: 'Authentication',
            icon: Icons.shield_rounded,
          ),
          const SizedBox(height: 12),
          const Text(
            'Add an extra layer of security to your account by requiring a second verification step during login.',
            style: TextStyle(fontSize: 14, color: Colors.grey),
          ),
          const SizedBox(height: 24),

          // ── Email 2FA ──────────────────────────────────────────────────
          _SettingsCard(
            children: [
              SwitchListTile(
                secondary: const Icon(Icons.email_outlined),
                title: const Text('Email Verification'),
                subtitle: const Text(
                  'Receive a 6-digit code via email during login.',
                ),
                value: _email2faEnabled,
                onChanged: _toggleEmail2fa,
              ),
            ],
          ),

          const SizedBox(height: 20),

          // ── TOTP (Authenticator App) ───────────────────────────────────
          _SettingsCard(
            children: [
              ListTile(
                leading: const Icon(Icons.phonelink_lock_rounded),
                title: const Text('Authenticator App'),
                subtitle: const Text(
                  'Use an app like Google Authenticator, Authy, or Ente.',
                ),
                trailing: _totpEnabled
                    ? const Icon(Icons.check_circle, color: Colors.green)
                    : null,
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
                child: _totpEnabled
                    ? SizedBox(
                        width: double.infinity,
                        child: OutlinedButton.icon(
                          onPressed: _disableTotp,
                          style: OutlinedButton.styleFrom(
                            foregroundColor: Colors.red,
                            side: const BorderSide(color: Colors.red),
                          ),
                          icon: const Icon(Icons.delete_outline),
                          label: const Text('Disable Authenticator App'),
                        ),
                      )
                    : SizedBox(
                        width: double.infinity,
                        child: FilledButton.icon(
                          onPressed: _startTotpSetup,
                          icon: const Icon(Icons.add_moderator),
                          label: const Text('Setup Authenticator App'),
                        ),
                      ),
              ),
              if (_totpEnabled)
                const Padding(
                  padding: EdgeInsets.only(left: 16, right: 16, bottom: 16),
                  child: Text(
                    'Verification is active. Ensure you have your backup codes saved.',
                    style: TextStyle(
                      fontSize: 12,
                      fontStyle: FontStyle.italic,
                      color: Colors.green,
                    ),
                  ),
                ),
            ],
          ),
          const SizedBox(height: 28),
          _SectionHeader(
            title: 'Change Password',
            icon: Icons.password_rounded,
          ),
          const SizedBox(height: 12),
          _SettingsCard(
            children: [
              Padding(
                padding: const EdgeInsets.all(16),
                child: Form(
                  key: _passwordFormKey,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      if (!_useTfaForPasswordChange || !_user.tfaActive)
                        TextFormField(
                          controller: _oldPasswordController,
                          decoration: InputDecoration(
                            labelText: 'Current Password',
                            border: const OutlineInputBorder(),
                            suffixIcon: IconButton(
                              icon: Icon(
                                _isOldPasswordVisible
                                    ? Icons.visibility
                                    : Icons.visibility_off,
                              ),
                              onPressed: () {
                                setState(() {
                                  _isOldPasswordVisible =
                                      !_isOldPasswordVisible;
                                });
                              },
                            ),
                          ),
                          obscureText: !_isOldPasswordVisible,
                          validator: (value) {
                            if (!_useTfaForPasswordChange &&
                                (value?.isEmpty ?? true)) {
                              return 'Current password is required';
                            }
                            return null;
                          },
                        ),
                      if (_useTfaForPasswordChange && _user.tfaActive) ...[
                        Row(
                          children: [
                            Expanded(
                              child: TextFormField(
                                controller: _tfaCodeController,
                                decoration: const InputDecoration(
                                  labelText: '2FA Code',
                                  border: OutlineInputBorder(),
                                ),
                                validator: (value) {
                                  if (_useTfaForPasswordChange &&
                                      (value?.isEmpty ?? true)) {
                                    return '2FA code is required';
                                  }
                                  return null;
                                },
                              ),
                            ),
                            const SizedBox(width: 8),
                            ElevatedButton(
                              onPressed: _sendTfaCode,
                              child: const Text('Send Code'),
                            ),
                          ],
                        ),
                      ],
                      const SizedBox(height: 16),
                      TextFormField(
                        controller: _newPasswordController,
                        decoration: InputDecoration(
                          labelText: 'New Password',
                          border: const OutlineInputBorder(),
                          suffixIcon: IconButton(
                            icon: Icon(
                              _isNewPasswordVisible
                                  ? Icons.visibility
                                  : Icons.visibility_off,
                            ),
                            onPressed: () {
                              setState(() {
                                _isNewPasswordVisible = !_isNewPasswordVisible;
                              });
                            },
                          ),
                        ),
                        obscureText: !_isNewPasswordVisible,
                        validator: (value) {
                          if (value?.isEmpty ?? true) {
                            return 'New password is required';
                          }
                          if (value!.length < 6) {
                            return 'Password must be at least 6 characters';
                          }
                          return null;
                        },
                      ),
                      const SizedBox(height: 16),
                      TextFormField(
                        controller: _confirmPasswordController,
                        decoration: InputDecoration(
                          labelText: 'Confirm New Password',
                          border: const OutlineInputBorder(),
                          suffixIcon: IconButton(
                            icon: Icon(
                              _isConfirmPasswordVisible
                                  ? Icons.visibility
                                  : Icons.visibility_off,
                            ),
                            onPressed: () {
                              setState(() {
                                _isConfirmPasswordVisible =
                                    !_isConfirmPasswordVisible;
                              });
                            },
                          ),
                        ),
                        obscureText: !_isConfirmPasswordVisible,
                        validator: (value) {
                          if (value?.isEmpty ?? true) {
                            return 'Please confirm new password';
                          }
                          if (value != _newPasswordController.text) {
                            return 'Passwords do not match';
                          }
                          return null;
                        },
                      ),
                      const SizedBox(height: 16),
                      ElevatedButton(
                        onPressed: _isLoading ? null : _changePassword,
                        child: const Text('Change Password'),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 48),
        ],
      ),
    );
  }
}
