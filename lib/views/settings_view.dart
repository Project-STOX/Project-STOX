import 'dart:async';

import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../main.dart'; // To access global themeController
import '../models/user.dart';
import '../services/api/backup_api_service.dart';
import 'new_backup_tab.dart';
import 'end_of_contract_view.dart';
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

  const SettingsView({
    super.key,
    required this.user,
    required this.canManageBackup,
    this.isEmbedded = false,
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
    ];
    if (widget.canManageBackup) {
      list.add(const _SettingsDestination(
        title: 'Database Backup',
        icon: Icons.storage_outlined,
        selectedIcon: Icons.storage_rounded,
      ));
    }
    // New consumer backup — SME Owner only (role_id == 1)
    if (widget.user.roleId == 1) {
      list.add(const _SettingsDestination(
        title: 'New Backup',
        icon: Icons.download_outlined,
        selectedIcon: Icons.download_rounded,
      ));
      list.add(const _SettingsDestination(
        title: 'Advanced',
        icon: Icons.admin_panel_settings_outlined,
        selectedIcon: Icons.admin_panel_settings_rounded,
      ));
    }
    return list;
  }

  Widget _buildContent() {
    if (_destinations.isEmpty) return const SizedBox.shrink();
    final title = _destinations[_selectedIndex].title;
    switch (title) {
      case 'General':
        return _GeneralSettingsTab(user: widget.user);
      case 'Database Backup':
        return _BackupSettingsTab();
      case 'New Backup':
        return NewBackupTab(user: widget.user);
      case 'Advanced':
        return _AdvancedSettingsTab(user: widget.user);
      default:
        return _GeneralSettingsTab(user: widget.user);
    }
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: themeController,
      builder: (context, _) {
        return Scaffold(
          appBar: AppBar(
            title: const Text('Settings'),
          ),
          body: Row(
            children: [
              // ── Left Sidebar ──────────────────────────────────────────────
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

              // ── Draggable Divider ─────────────────────────────────────────
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
                        color: Theme.of(context).dividerColor.withOpacity(0.25),
                      ),
                    ),
                  ),
                ),
              ),

              // ── Right Content Panel ───────────────────────────────────────
              Expanded(
                child: _buildContent(),
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

  const _SettingsSidebar({
    required this.destinations,
    required this.selectedIndex,
    required this.onDestinationSelected,
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
                    selectedTileColor: colorScheme.primaryContainer.withOpacity(0.7),
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
                        fontWeight:
                            isSelected ? FontWeight.w600 : FontWeight.normal,
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
              ListTile(
                leading: const Icon(Icons.brightness_medium_rounded),
                title: const Text('Appearance'),
                subtitle: Text(themeController.themeMode.name.toUpperCase()),
                trailing: SegmentedButton<ThemeMode>(
                  segments: const [
                    ButtonSegment(
                        value: ThemeMode.light, icon: Icon(Icons.light_mode)),
                    ButtonSegment(
                        value: ThemeMode.system, icon: Icon(Icons.settings)),
                    ButtonSegment(
                        value: ThemeMode.dark, icon: Icon(Icons.dark_mode)),
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
                  children: [
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
                                  color: colorScheme.onSurface, width: 2)
                              : null,
                          boxShadow: [
                            if (isSelected)
                              BoxShadow(
                                color: color.withOpacity(0.4),
                                blurRadius: 8,
                                spreadRadius: 2,
                              )
                          ],
                        ),
                        child: isSelected
                            ? const Icon(Icons.check,
                                color: Colors.white, size: 16)
                            : null,
                      ),
                    );
                  }).toList(),
                ),
              ),
            ],
          ),

          const SizedBox(height: 28),

          // ── Navigation Style ──────────────────────────────────────────────
          _SectionHeader(title: 'Navigation Style', icon: Icons.explore_rounded),
          const SizedBox(height: 12),
          _SettingsCard(
            children: [
              ListTile(
                leading: const Icon(Icons.grid_view_rounded),
                title: const Text('Layout Style'),
                subtitle: Text(themeController.navigationMode.name.toUpperCase()),
                trailing: SegmentedButton<AppNavigationMode>(
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
                  onSelectionChanged: (Set<AppNavigationMode> newSelection) {
                    themeController.setNavigationMode(newSelection.first);
                  },
                  showSelectedIcon: false,
                  style: const ButtonStyle(
                    visualDensity: VisualDensity.compact,
                  ),
                ),
              ),
            ],
          ),

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
// Tab 1 — Database Backup Settings
// ─────────────────────────────────────────────────────────────────────────────
class _BackupSettingsTab extends StatefulWidget {
  @override
  State<_BackupSettingsTab> createState() => _BackupSettingsTabState();
}

class _BackupSettingsTabState extends State<_BackupSettingsTab> {
  final BackupApiService _backupService = BackupApiService();

  // ── Backup state ──────────────────────────────────────────────────────────
  List<BackupFileInfo> _backupFiles = [];
  bool _loadingFiles = false;
  bool _isBackingUp = false;
  int _progress = 0;
  String _statusMessage = '';
  bool _backupSuccess = false;
  bool _backupError = false;
  StreamSubscription<BackupSseEvent>? _backupStream;

  // ── Config state ──────────────────────────────────────────────────────────
  bool _scheduleEnabled = false;
  String _selectedSchedule = 'Daily';
  TimeOfDay _scheduledTime = const TimeOfDay(hour: 2, minute: 0);
  bool _syncLocal = false;

  static const _scheduleOptions = ['Hourly', 'Daily', 'Weekly'];

  @override
  void initState() {
    super.initState();
    _loadBackupFiles();
    _loadConfig();
  }

  @override
  void dispose() {
    _backupStream?.cancel();
    super.dispose();
  }

  Future<void> _loadConfig() async {
    try {
      final config = await _backupService.getConfig();
      if (mounted) {
        setState(() {
          _scheduleEnabled = config['schedule_enabled'] ?? false;
          _selectedSchedule = config['frequency'] ?? 'Daily';
          _syncLocal = config['sync_local'] ?? false;
          final timeStr = config['time'] ?? '02:00';
          final parts = timeStr.split(':');
          if (parts.length == 2) {
            _scheduledTime = TimeOfDay(
              hour: int.tryParse(parts[0]) ?? 2,
              minute: int.tryParse(parts[1]) ?? 0,
            );
          }
        });
      }
    } catch (_) {}
  }

  Future<void> _saveConfig() async {
    final timeStr =
        '${_scheduledTime.hour.toString().padLeft(2, '0')}:${_scheduledTime.minute.toString().padLeft(2, '0')}';
    final config = {
      'schedule_enabled': _scheduleEnabled,
      'frequency': _selectedSchedule,
      'time': timeStr,
      'sync_local': _syncLocal,
    };
    try {
      await _backupService.saveConfig(config);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            behavior: SnackBarBehavior.floating,
            content: Text('Backup settings saved successfully'),
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            behavior: SnackBarBehavior.floating,
            backgroundColor: Theme.of(context).colorScheme.error,
            content: Text('Failed to save settings: $e'),
          ),
        );
      }
    }
  }

  Future<void> _loadBackupFiles() async {
    if (!mounted) return;
    setState(() => _loadingFiles = true);
    try {
      final files = await _backupService.listBackups();
      if (mounted) setState(() => _backupFiles = files);
    } catch (_) {
    } finally {
      if (mounted) setState(() => _loadingFiles = false);
    }
  }

  Future<void> _startBackup() async {
    if (_isBackingUp) return;
    setState(() {
      _isBackingUp = true;
      _progress = 0;
      _statusMessage = 'Initializing…';
      _backupSuccess = false;
      _backupError = false;
    });

    try {
      final stream = _backupService.runBackup(sync: _syncLocal);
      _backupStream = stream.listen(
        _onSseEvent,
        onError: (Object err) {
          if (mounted) {
            setState(() {
              _isBackingUp = false;
              _backupError = true;
              _statusMessage =
                  err.toString().replaceFirst('Exception: ', '');
            });
          }
        },
        cancelOnError: true,
      );
    } catch (e) {
      if (mounted) {
        setState(() {
          _isBackingUp = false;
          _backupError = true;
          _statusMessage = e.toString().replaceFirst('Exception: ', '');
        });
      }
    }
  }

  void _onSseEvent(BackupSseEvent event) {
    if (!mounted) return;
    setState(() {
      _progress = event.progress;
      _statusMessage = event.message;

      if (event.event == 'done') {
        _isBackingUp = false;
        _backupSuccess = true;
        _backupError = false;
        _loadBackupFiles();
      } else if (event.event == 'error') {
        _isBackingUp = false;
        _backupSuccess = false;
        _backupError = true;
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    return SingleChildScrollView(
      padding: const EdgeInsets.all(24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // ── Manual Snapshot ───────────────────────────────────────────────
          _SectionHeader(
              title: 'Manual Snapshot', icon: Icons.backup_rounded),
          const SizedBox(height: 12),
          _SettingsCard(
            children: [
              Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Icon(Icons.backup_rounded,
                            color: colorScheme.primary, size: 20),
                        const SizedBox(width: 8),
                        const Text(
                          'Run Now',
                          style: TextStyle(
                              fontWeight: FontWeight.w600, fontSize: 16),
                        ),
                        const Spacer(),
                        _StatusBadge(
                          success: _backupSuccess,
                          error: _backupError,
                          running: _isBackingUp,
                        ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    const Text(
                      'Creates a full export of current data. If sync is enabled, it also updates the local failover database.',
                      style: TextStyle(fontSize: 13, color: Colors.grey),
                    ),
                    const SizedBox(height: 16),
                    SwitchListTile(
                      contentPadding: EdgeInsets.zero,
                      title: const Text('Sync to local failover DB',
                          style: TextStyle(fontSize: 14)),
                      subtitle: const Text(
                          'Ensures local database is ready for read-only mode.',
                          style: TextStyle(fontSize: 12)),
                      value: _syncLocal,
                      onChanged: (v) => setState(() => _syncLocal = v),
                    ),
                    if (_isBackingUp ||
                        _progress > 0 ||
                        _backupError ||
                        _backupSuccess) ...[
                      const SizedBox(height: 12),
                      LinearProgressIndicator(
                        value: _progress / 100,
                        borderRadius: BorderRadius.circular(4),
                      ),
                      const SizedBox(height: 8),
                      Text(_statusMessage,
                          style: const TextStyle(fontSize: 12)),
                    ],
                    const SizedBox(height: 16),
                    SizedBox(
                      width: double.infinity,
                      child: FilledButton.icon(
                        onPressed: _isBackingUp ? null : _startBackup,
                        icon: _isBackingUp
                            ? const SizedBox(
                                width: 16,
                                height: 16,
                                child: CircularProgressIndicator(
                                    strokeWidth: 2, color: Colors.white))
                            : const Icon(Icons.play_arrow_rounded),
                        label: Text(_isBackingUp
                            ? 'In Progress...'
                            : 'Run Backup Now'),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),

          const SizedBox(height: 20),

          // ── Automated Schedule ────────────────────────────────────────────
          _SectionHeader(
              title: 'Automated Schedule',
              icon: Icons.event_repeat_rounded),
          const SizedBox(height: 12),
          _SettingsCard(
            children: [
              SwitchListTile(
                secondary: Icon(Icons.event_repeat_rounded,
                    color: colorScheme.secondary),
                title: const Text('Enable Automated Schedule'),
                value: _scheduleEnabled,
                onChanged: (v) => setState(() => _scheduleEnabled = v),
              ),
              if (_scheduleEnabled) ...[
                const Divider(indent: 16, endIndent: 16),
                Padding(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                  child: DropdownButtonFormField<String>(
                    initialValue: _selectedSchedule,
                    decoration:
                        const InputDecoration(labelText: 'Frequency'),
                    items: _scheduleOptions
                        .map((o) =>
                            DropdownMenuItem(value: o, child: Text(o)))
                        .toList(),
                    onChanged: (v) =>
                        setState(() => _selectedSchedule = v!),
                  ),
                ),
                ListTile(
                  title: const Text('Start Time'),
                  subtitle: Text(_scheduledTime.format(context)),
                  trailing: const Icon(Icons.access_time_rounded),
                  onTap: () async {
                    final p = await showTimePicker(
                        context: context, initialTime: _scheduledTime);
                    if (p != null) setState(() => _scheduledTime = p);
                  },
                ),
                Padding(
                  padding: const EdgeInsets.all(16),
                  child: OutlinedButton(
                    onPressed: _saveConfig,
                    child: const Text('Save Schedule Preferences'),
                  ),
                ),
              ]
            ],
          ),

          const SizedBox(height: 20),

          // ── Backup History ────────────────────────────────────────────────
          _SectionHeader(
              title: 'Backup History', icon: Icons.history_rounded),
          const SizedBox(height: 12),
          _SettingsCard(
            children: [
              ListTile(
                leading: const Icon(Icons.history_rounded),
                title: const Text('Snapshots'),
                trailing: IconButton(
                    icon: const Icon(Icons.refresh),
                    onPressed: _loadBackupFiles),
              ),
              if (_loadingFiles)
                const Padding(
                    padding: EdgeInsets.all(20),
                    child: Center(child: CircularProgressIndicator()))
              else if (_backupFiles.isEmpty)
                const Padding(
                    padding: EdgeInsets.all(20),
                    child: Text('No snapshots found.',
                        style: TextStyle(color: Colors.grey)))
              else
                ..._backupFiles.take(10).map((f) => ListTile(
                      dense: true,
                      leading: const Icon(Icons.insert_drive_file_outlined),
                      title: Text(f.filename),
                      subtitle: Text(DateFormat('yyyy-MM-dd HH:mm')
                          .format(f.createdAt)),
                      trailing: Text(f.displaySize),
                    )),
            ],
          ),

          const SizedBox(height: 20),

          // ── Failover Notice ───────────────────────────────────────────────
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: colorScheme.secondaryContainer.withOpacity(0.3),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: colorScheme.secondaryContainer),
            ),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Icon(Icons.info_outline, color: colorScheme.secondary),
                const SizedBox(width: 12),
                const Expanded(
                  child: Text(
                    'Local Failover Policy: If Supabase becomes unreachable, the app automatically switches to the local PostgreSQL instance (localhost:5432). '
                    'The local DB operates in READ-ONLY mode to prevent data diverge until the primary server is restored.',
                    style: TextStyle(fontSize: 13, height: 1.4),
                  ),
                ),
              ],
            ),
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
          Text(
            title.toUpperCase(),
            style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.bold,
              color: Theme.of(context).colorScheme.primary,
              letterSpacing: 1.2,
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
            color: Theme.of(context).dividerColor.withOpacity(0.1)),
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
      title:
          Text(label, style: const TextStyle(fontSize: 14, color: Colors.grey)),
      trailing:
          Text(value, style: const TextStyle(fontWeight: FontWeight.w600)),
    );
  }
}

class _StatusBadge extends StatelessWidget {
  final bool success;
  final bool error;
  final bool running;
  const _StatusBadge(
      {required this.success, required this.error, required this.running});

  @override
  Widget build(BuildContext context) {
    if (!running && !success && !error) return const SizedBox.shrink();
    final Color color;
    final String label;
    if (running) {
      color = Colors.blue;
      label = 'Running';
    } else if (success) {
      color = Colors.green;
      label = 'Done';
    } else {
      color = Colors.red;
      label = 'Failed';
    }

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
      decoration: BoxDecoration(
        color: color.withOpacity(0.1),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: color.withOpacity(0.5)),
      ),
      child: Text(label,
          style: TextStyle(
              color: color, fontSize: 11, fontWeight: FontWeight.bold)),
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
            style: theme.textTheme.headlineMedium?.copyWith(fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 8),
          Text(
            'Danger zone actions and advanced configuration.',
            style: theme.textTheme.bodyMedium?.copyWith(color: theme.colorScheme.onSurfaceVariant),
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
                    Icon(Icons.warning_amber_rounded, color: theme.colorScheme.error),
                    const SizedBox(width: 8),
                    Text(
                      'Account Closure & Data Export',
                      style: theme.textTheme.titleLarge?.copyWith(
                        color: theme.colorScheme.error,
                        fontWeight: FontWeight.bold,
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
                    padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
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
