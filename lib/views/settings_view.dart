import 'dart:async';

import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../main.dart'; // To access global themeController
import '../models/user.dart';
import '../services/api/backup_api_service.dart';

class SettingsView extends StatefulWidget {
  final UserModel user;
  final bool canManageBackup;

  const SettingsView({
    super.key,
    required this.user,
    required this.canManageBackup,
  });

  @override
  State<SettingsView> createState() => _SettingsViewState();
}

class _SettingsViewState extends State<SettingsView> {
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

  // ── Config state ────────────────────────────────────────────────────────
  bool _scheduleEnabled = false;
  String _selectedSchedule = 'Daily';
  TimeOfDay _scheduledTime = const TimeOfDay(hour: 2, minute: 0);
  bool _syncLocal = false;

  static const _scheduleOptions = ['Hourly', 'Daily', 'Weekly'];

  // ─────────────────────────────────────────────────────────────────────────
  @override
  void initState() {
    super.initState();
    if (widget.canManageBackup) {
      _loadBackupFiles();
      _loadConfig();
    }
  }

  @override
  void dispose() {
    _backupStream?.cancel();
    super.dispose();
  }

  // ─────────────────────────────────────────────────────────────────────────
  // Helpers
  // ─────────────────────────────────────────────────────────────────────────

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
              _statusMessage = err.toString().replaceFirst('Exception: ', '');
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

  // ─────────────────────────────────────────────────────────────────────────
  // Build
  // ─────────────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    return ListenableBuilder(
      listenable: themeController,
      builder: (context, _) {
        return Scaffold(
          appBar: AppBar(
            title: const Text('Settings'),
          ),
          body: SingleChildScrollView(
            padding: const EdgeInsets.all(20),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // ── Theme Customization ─────────────────────────────────────
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
                    ListTile(
                      leading: const Icon(Icons.color_lens_rounded),
                      title: const Text('Primary Color'),
                      subtitle: const Text('Personalize the system accent'),
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
                          final isSelected = themeController.primaryColor.value == color.value;
                          return GestureDetector(
                            onTap: () => themeController.setPrimaryColor(color),
                            child: Container(
                              width: 32,
                              height: 32,
                              decoration: BoxDecoration(
                                color: color,
                                shape: BoxShape.circle,
                                border: isSelected
                                    ? Border.all(color: colorScheme.onSurface, width: 2)
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
                                  ? const Icon(Icons.check, color: Colors.white, size: 16)
                                  : null,
                            ),
                          );
                        }).toList(),
                      ),
                    ),
                  ],
                ),

                const SizedBox(height: 28),

                // ── Account section ─────────────────────────────────────────────
                _SectionHeader(title: 'Account', icon: Icons.person_rounded),
                const SizedBox(height: 12),
                _SettingsCard(
                  children: [
                    _InfoRow(label: 'Username', value: widget.user.username),
                    const Divider(indent: 16, endIndent: 16),
                    _InfoRow(label: 'Email', value: widget.user.email),
                    const Divider(indent: 16, endIndent: 16),
                    _InfoRow(label: 'Role', value: widget.user.role),
                  ],
                ),

                const SizedBox(height: 28),

                // ── Database Backup section (permission-gated) ─────────────────
                if (widget.canManageBackup) ...[
                  _SectionHeader(
                    title: 'Database Backup',
                    icon: Icons.storage_rounded,
                  ),
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
                                Icon(Icons.backup_rounded, color: colorScheme.primary, size: 20),
                                const SizedBox(width: 8),
                                const Text(
                                  'Manual Snapshot',
                                  style: TextStyle(fontWeight: FontWeight.w600, fontSize: 16),
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
                            
                            // Sync toggle
                            SwitchListTile(
                              contentPadding: EdgeInsets.zero,
                              title: const Text('Sync to local failover DB', style: TextStyle(fontSize: 14)),
                              subtitle: const Text('Ensures local database is ready for read-only mode.', style: TextStyle(fontSize: 12)),
                              value: _syncLocal,
                              onChanged: (v) => setState(() => _syncLocal = v),
                            ),
                            
                            if (_isBackingUp || _progress > 0 || _backupError || _backupSuccess) ...[
                              const SizedBox(height: 12),
                              LinearProgressIndicator(
                                value: _progress / 100,
                                borderRadius: BorderRadius.circular(4),
                              ),
                              const SizedBox(height: 8),
                              Text(_statusMessage, style: const TextStyle(fontSize: 12)),
                            ],
                            
                            const SizedBox(height: 16),
                            SizedBox(
                              width: double.infinity,
                              child: FilledButton.icon(
                                onPressed: _isBackingUp ? null : _startBackup,
                                icon: _isBackingUp 
                                  ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                                  : const Icon(Icons.play_arrow_rounded),
                                label: Text(_isBackingUp ? 'In Progress...' : 'Run Backup Now'),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),

                  const SizedBox(height: 16),
                  
                  // Schedule Card
                  _SettingsCard(
                    children: [
                      SwitchListTile(
                        secondary: Icon(Icons.event_repeat_rounded, color: colorScheme.secondary),
                        title: const Text('Automated Schedule'),
                        value: _scheduleEnabled,
                        onChanged: (v) => setState(() => _scheduleEnabled = v),
                      ),
                      if (_scheduleEnabled) ...[
                        const Divider(indent: 16, endIndent: 16),
                        Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                          child: DropdownButtonFormField<String>(
                            initialValue: _selectedSchedule,
                            decoration: const InputDecoration(labelText: 'Frequency'),
                            items: _scheduleOptions.map((o) => DropdownMenuItem(value: o, child: Text(o))).toList(),
                            onChanged: (v) => setState(() => _selectedSchedule = v!),
                          ),
                        ),
                        ListTile(
                          title: const Text('Start Time'),
                          subtitle: Text(_scheduledTime.format(context)),
                          trailing: const Icon(Icons.access_time_rounded),
                          onTap: () async {
                            final p = await showTimePicker(context: context, initialTime: _scheduledTime);
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

                  const SizedBox(height: 16),

                  // Files Card
                  _SettingsCard(
                    children: [
                      ListTile(
                        leading: const Icon(Icons.history_rounded),
                        title: const Text('History'),
                        trailing: IconButton(icon: const Icon(Icons.refresh), onPressed: _loadBackupFiles),
                      ),
                      if (_loadingFiles)
                        const Padding(padding: EdgeInsets.all(20), child: Center(child: CircularProgressIndicator()))
                      else if (_backupFiles.isEmpty)
                        const Padding(padding: EdgeInsets.all(20), child: Text('No snapshots found.', style: TextStyle(color: Colors.grey)))
                      else
                        ..._backupFiles.take(5).map((f) => ListTile(
                          dense: true,
                          leading: const Icon(Icons.insert_drive_file_outlined),
                          title: Text(f.filename),
                          subtitle: Text(DateFormat('yyyy-MM-dd HH:mm').format(f.createdAt)),
                          trailing: Text(f.displaySize),
                        )),
                    ],
                  ),
                  
                  const SizedBox(height: 16),
                  
                  // Notice
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
                ],
                const SizedBox(height: 40),
              ],
            ),
          ),
        );
      },
    );
  }
}

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
        side: BorderSide(color: Theme.of(context).dividerColor.withOpacity(0.1)),
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
      title: Text(label, style: const TextStyle(fontSize: 14, color: Colors.grey)),
      trailing: Text(value, style: const TextStyle(fontWeight: FontWeight.w600)),
    );
  }
}

class _StatusBadge extends StatelessWidget {
  final bool success;
  final bool error;
  final bool running;
  const _StatusBadge({required this.success, required this.error, required this.running});

  @override
  Widget build(BuildContext context) {
    if (!running && !success && !error) return const SizedBox.shrink();
    final Color color;
    final String label;
    if (running) { color = Colors.blue; label = 'Running'; }
    else if (success) { color = Colors.green; label = 'Done'; }
    else { color = Colors.red; label = 'Failed'; }

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
      decoration: BoxDecoration(
        color: color.withOpacity(0.1),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: color.withOpacity(0.5)),
      ),
      child: Text(label, style: TextStyle(color: color, fontSize: 11, fontWeight: FontWeight.bold)),
    );
  }
}
