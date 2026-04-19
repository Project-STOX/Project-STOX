import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:uuid/uuid.dart';

import '../models/user.dart';
import '../services/api/backup_api_service.dart';
import '../services/api/export_api_service.dart';
import '../utils/backup_downloader.dart';

// ─────────────────────────────────────────────────────────────────────────────
// Backup Data Tab — SME Owner only
// ─────────────────────────────────────────────────────────────────────────────
class NewBackupTab extends StatefulWidget {
  final UserModel user;
  const NewBackupTab({super.key, required this.user});

  @override
  State<NewBackupTab> createState() => _NewBackupTabState();
}

class _NewBackupTabState extends State<NewBackupTab> {
  final ExportApiService _service = ExportApiService();
  final BackupApiService _dbBackupService = BackupApiService();
  final _uuid = const Uuid();

  // Database Snapshots (Full PG Dump)
  List<BackupFileInfo> _dbSnapshots = [];
  bool _loadingSnapshots = true;
  bool _isDbBackupRunning = false;
  double _dbBackupProgress = 0;
  String _dbBackupMessage = '';

  // Categories
  List<ExportCategory> _categories = [];
  final Set<String> _selected = {};
  bool _loadingCategories = true;

  // Manual backup state
  bool _isRunning = false;
  double _progress = 0;
  String _statusMessage = '';
  bool _done = false;
  bool _error = false;
  Timer? _progressTimer;
  final Set<String> _selectedFormats = {'csv'};

  // Schedules
  List<BackupScheduleModel> _schedules = [];
  bool _loadingSchedules = true;

  static const int maxSchedules = 10;
  static const List<Map<String, String>> availableFormats = [
    {'key': 'csv', 'label': 'CSV (Excel)'},
    {'key': 'json', 'label': 'JSON (Web)'},
    {'key': 'sql', 'label': 'SQL (Database)'},
  ];

  @override
  void initState() {
    super.initState();
    _loadCategories();
    _loadSchedules();
    _loadDbSnapshots();
  }

  @override
  void dispose() {
    _progressTimer?.cancel();
    super.dispose();
  }

  // ─── Loaders ─────────────────────────────────────────────────────────────

  Future<void> _loadCategories() async {
    try {
      final cats = await _service.getCategories();
      if (mounted) {
        setState(() {
          _categories = cats;
          _selected.addAll(cats.map((c) => c.key));
          _loadingCategories = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() => _loadingCategories = false);
        _showError(
          'Could not load categories: ${e.toString().replaceFirst('Exception: ', '')}',
        );
      }
    }
  }

  Future<void> _loadSchedules() async {
    try {
      final schedules = await _service.getSchedules();
      if (mounted) {
        setState(() {
          _schedules = schedules;
          _loadingSchedules = false;
        });
      }
    } catch (_) {
      if (mounted) {
        setState(() {
          _loadingSchedules = false;
        });
      }
    }
  }

  Future<void> _loadDbSnapshots() async {
    try {
      final list = await _dbBackupService.listBackups();
      if (mounted) {
        setState(() {
          _dbSnapshots = list;
          _loadingSnapshots = false;
        });
      }
    } catch (_) {
      if (mounted) {
        setState(() => _loadingSnapshots = false);
      }
    }
  }

  void _showError(String msg) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        behavior: SnackBarBehavior.floating,
        backgroundColor: Theme.of(context).colorScheme.error,
        content: Text(msg),
      ),
    );
  }

  // ─── Manual Backup ───────────────────────────────────────────────────────

  Future<void> _runBackup({
    List<String>? categoryOverride,
    bool silent = false,
  }) async {
    final cats = categoryOverride ?? _selected.toList();
    if (cats.isEmpty) return;

    final fmts = _selectedFormats.toList();
    if (fmts.isEmpty) {
      _showError('Please select at least one format.');
      return;
    }

    if (!silent) {
      setState(() {
        _isRunning = true;
        _progress = 0;
        _statusMessage = 'Preparing backup…';
        _done = false;
        _error = false;
      });
    }

    // Animate progress bar while HTTP call happens
    _progressTimer?.cancel();
    if (!silent) {
      _progressTimer = Timer.periodic(const Duration(milliseconds: 80), (t) {
        if (!mounted) {
          t.cancel();
          return;
        }
        setState(() {
          if (_progress < 0.85) _progress += 0.012;
        });
      });
    }

    try {
      if (!silent) {
        setState(() => _statusMessage = 'Fetching data from server…');
      }
      final bytes = await _service.runBackup(cats, formats: fmts);

      _progressTimer?.cancel();
      if (!silent) {
        setState(() {
          _progress = 0.92;
          _statusMessage = 'Saving ZIP file…';
        });
      }

      final timestamp = DateFormat('yyyyMMdd_HHmmss').format(DateTime.now());
      final filename = 'stox_backup_$timestamp.zip';
      await downloadZip(bytes, filename);

      if (!silent) {
        setState(() {
          _progress = 1.0;
          _isRunning = false;
          _done = true;
          _statusMessage = kIsWeb
              ? 'Backup downloaded to your browser Downloads folder.'
              : 'Saved to Downloads/STOX Backups/';
        });
      }

      if (mounted) {
        final fmtLabel = fmts.map((f) => f.toUpperCase()).join(' + ');
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            behavior: SnackBarBehavior.floating,
            backgroundColor: Colors.green.shade700,
            duration: const Duration(seconds: 5),
            content: Row(
              children: [
                const Icon(Icons.check_circle, color: Colors.white),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    kIsWeb
                        ? '$filename ($fmtLabel) downloaded successfully.'
                        : 'Saved to Downloads/STOX Backups/ ($fmtLabel)',
                  ),
                ),
              ],
            ),
          ),
        );
      }
    } catch (e) {
      _progressTimer?.cancel();
      if (!silent) {
        setState(() {
          _isRunning = false;
          _error = true;
          _progress = 0;
          _statusMessage = e.toString().replaceFirst('Exception: ', '');
        });
      } else {
        // Background schedule — show snackbar
        if (mounted) {
          _showError(
            'Scheduled backup failed: ${e.toString().replaceFirst('Exception: ', '')}',
          );
        }
      }
    }
  }

  Future<void> _runDbBackup() async {
    setState(() {
      _isDbBackupRunning = true;
      _dbBackupProgress = 0;
      _dbBackupMessage = 'Initializing snapshot…';
    });

    try {
      await for (final event in _dbBackupService.runBackup(sync: true)) {
        if (!mounted) break;
        setState(() {
          _dbBackupProgress = event.progress / 100.0;
          _dbBackupMessage = event.message;
        });
        if (event.event == 'done' || event.event == 'error') {
          if (event.event == 'error') {
            _showError('Snapshot error: ${event.message}');
          }
          break;
        }
      }
      await _loadDbSnapshots();
    } catch (e) {
      if (mounted) {
        _showError('Database backup connection failed: $e');
      }
    } finally {
      if (mounted) {
        setState(() => _isDbBackupRunning = false);
      }
    }
  }

  // ─── Schedule Dialog ─────────────────────────────────────────────────────

  Future<void> _showAddScheduleDialog() async {
    if (_schedules.length >= maxSchedules) {
      _showError('Maximum of 10 schedules reached. Delete one to add another.');
      return;
    }
    await showDialog(
      context: context,
      builder: (ctx) => _AddScheduleDialog(
        categories: _categories,
        onSave: (label, cats, freq, time, fmts, dow, dom, mon) async {
          try {
            final s = BackupScheduleModel(
              id: 0, // Server will assign int ID
              label: label,
              categories: cats,
              frequency: freq,
              scheduledTime: time,
              formats: fmts,
              dayOfWeek: dow,
              dayOfMonth: dom,
              month: mon,
            );
            await _service.addSchedule(s);
            // Refresh list from server to get the new real ID
            await _loadSchedules();
            if (mounted) {
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(
                  behavior: SnackBarBehavior.floating,
                  content: Text('Schedule created successfully.'),
                ),
              );
            }
          } catch (e) {
            if (mounted) {
              _showError(e.toString().replaceFirst('Exception: ', ''));
            }
          }
        },
      ),
    );
  }

  Future<void> _deleteSchedule(BackupScheduleModel schedule) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Delete Schedule'),
        content: Text('Delete "${schedule.label}"?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Delete'),
          ),
        ],
      ),
    );
    if (confirmed == true) {
      try {
        await _service.removeSchedule(schedule.id);
        if (mounted) {
          setState(() => _schedules.removeWhere((s) => s.id == schedule.id));
        }
      } catch (e) {
        _showError('Failed to delete schedule: ${e.toString()}');
      }
    }
  }

  // ─── Build ────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    return SingleChildScrollView(
      padding: const EdgeInsets.all(24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // ── Header Info ─────────────────────────────────────────────────
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: colorScheme.primaryContainer.withValues(alpha: 0.3),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: colorScheme.primaryContainer),
            ),
            child: Row(
              children: [
                Icon(Icons.info_outline_rounded, color: colorScheme.primary),
                const SizedBox(width: 12),
                const Expanded(
                  child: Text(
                    'Backup your data as CSV, JSON, or SQL files bundled in a ZIP archive. '
                    'On web, the ZIP downloads to your browser Downloads folder. '
                    'On Windows/Desktop, it saves to Downloads/STOX Backups/.',
                    style: TextStyle(fontSize: 13, height: 1.4),
                  ),
                ),
              ],
            ),
          ),

          const SizedBox(height: 12),

          // ── System Recovery Info ─────────────────────────────────────────
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: colorScheme.secondaryContainer.withValues(alpha: 0.3),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: colorScheme.secondaryContainer),
            ),
            child: Row(
              children: [
                Icon(Icons.security_rounded, color: colorScheme.secondary),
                const SizedBox(width: 12),
                const Expanded(
                  child: Text(
                    'System-wide encrypted snapshots are performed every 4 hours to ensure recovery from infrastructure failure or security incidents. '
                    'This is supplemented by individually isolated SME backups generated daily. '
                    'While we recommend following standard operational procedures, your data remains fully protected and recoverable in the event of accidental loss.',
                    style: TextStyle(fontSize: 13, height: 1.4),
                  ),
                ),
              ],
            ),
          ),

          const SizedBox(height: 28),

          // ── Manual Backup ────────────────────────────────────────────────
          _SectionHeader(title: 'Manual Backup', icon: Icons.download_rounded),
          const SizedBox(height: 12),

          _Card(
            children: [
              // Category checklist header
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
                child: Row(
                  children: [
                    const Text(
                      'Select data to include:',
                      style: TextStyle(fontWeight: FontWeight.w600),
                    ),
                    const Spacer(),
                    TextButton(
                      onPressed: () => setState(
                        () => _selected.addAll(_categories.map((c) => c.key)),
                      ),
                      child: const Text('All'),
                    ),
                    TextButton(
                      onPressed: () => setState(() => _selected.clear()),
                      child: const Text('None'),
                    ),
                  ],
                ),
              ),
              if (_loadingCategories)
                const Padding(
                  padding: EdgeInsets.all(20),
                  child: Center(child: CircularProgressIndicator()),
                )
              else if (_categories.isEmpty)
                Padding(
                  padding: const EdgeInsets.all(16),
                  child: Text(
                    'Could not load categories. Make sure the backend is running.',
                    style: TextStyle(color: colorScheme.error),
                  ),
                )
              else
                ..._categories.map(
                  (cat) => CheckboxListTile(
                    dense: true,
                    value: _selected.contains(cat.key),
                    onChanged: (v) => setState(() {
                      if (v == true) {
                        _selected.add(cat.key);
                      } else {
                        _selected.remove(cat.key);
                      }
                    }),
                    title: Text(
                      cat.label,
                      style: const TextStyle(fontSize: 14),
                    ),
                    subtitle: Text(
                      cat.description,
                      style: const TextStyle(fontSize: 12, color: Colors.grey),
                    ),
                    secondary: _categoryIcon(cat.key, colorScheme),
                    controlAffinity: ListTileControlAffinity.trailing,
                  ),
                ),

              const Divider(indent: 16, endIndent: 16),

              // Format selection
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'Preferred Formats:',
                      style: TextStyle(
                        fontWeight: FontWeight.w600,
                        fontSize: 13,
                      ),
                    ),
                    const SizedBox(height: 8),
                    Wrap(
                      spacing: 12,
                      children: availableFormats.map((f) {
                        final isSelected = _selectedFormats.contains(f['key']);
                        return FilterChip(
                          label: Text(f['label']!),
                          selected: isSelected,
                          onSelected: (v) {
                            setState(() {
                              if (v) {
                                _selectedFormats.add(f['key']!);
                              } else if (_selectedFormats.length > 1) {
                                _selectedFormats.remove(f['key']!);
                              }
                            });
                          },
                        );
                      }).toList(),
                    ),
                  ],
                ),
              ),

              const Divider(indent: 16, endIndent: 16),

              // Progress
              if (_isRunning || _done || _error)
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      ClipRRect(
                        borderRadius: BorderRadius.circular(4),
                        child: LinearProgressIndicator(
                          value: _isRunning && _progress < 0.05
                              ? null
                              : _progress,
                          minHeight: 8,
                          backgroundColor: colorScheme.surfaceContainerHighest,
                          valueColor: AlwaysStoppedAnimation(
                            _error
                                ? colorScheme.error
                                : _done
                                ? Colors.green
                                : colorScheme.primary,
                          ),
                        ),
                      ),
                      const SizedBox(height: 8),
                      Text(
                        _statusMessage,
                        style: TextStyle(
                          fontSize: 12,
                          color: _error
                              ? colorScheme.error
                              : _done
                              ? Colors.green
                              : colorScheme.onSurface,
                        ),
                      ),
                    ],
                  ),
                ),

              // Run button
              Padding(
                padding: const EdgeInsets.all(16),
                child: SizedBox(
                  width: double.infinity,
                  child: FilledButton.icon(
                    onPressed: _isRunning || _selected.isEmpty
                        ? null
                        : _runBackup,
                    icon: _isRunning
                        ? const SizedBox(
                            width: 18,
                            height: 18,
                            child: CircularProgressIndicator(
                              strokeWidth: 2,
                              color: Colors.white,
                            ),
                          )
                        : const Icon(Icons.download_rounded),
                    label: Text(
                      _isRunning
                          ? 'Backing up…'
                          : _selected.isEmpty
                          ? 'Select at least one category'
                          : 'Run Backup Now  (${_selected.length} selected)',
                    ),
                  ),
                ),
              ),
            ],
          ),

          const SizedBox(height: 28),

          // ── Scheduled Backups ────────────────────────────────────────────
          _SectionHeader(
            title: 'Automated Schedules',
            icon: Icons.schedule_rounded,
          ),
          const SizedBox(height: 4),
          Padding(
            padding: const EdgeInsets.only(left: 4, bottom: 12),
            child: Text(
              'Scheduled backups fire automatically while the app is open. Max $maxSchedules schedules.',
              style: TextStyle(
                fontSize: 12,
                color: colorScheme.onSurface.withValues(alpha: 0.6),
              ),
            ),
          ),

          _Card(
            children: [
              ListTile(
                leading: Icon(
                  Icons.add_alarm_rounded,
                  color: colorScheme.primary,
                ),
                title: const Text('Add Automated Schedule'),
                subtitle: Text(
                  '${_schedules.length}/$maxSchedules schedules active',
                ),
                trailing: FilledButton.tonalIcon(
                  onPressed: _schedules.length >= maxSchedules
                      ? null
                      : _showAddScheduleDialog,
                  icon: const Icon(Icons.add, size: 18),
                  label: const Text('New'),
                ),
              ),
              if (_loadingSchedules)
                const Padding(
                  padding: EdgeInsets.all(16),
                  child: Center(child: CircularProgressIndicator()),
                )
              else if (_schedules.isEmpty)
                const Padding(
                  padding: EdgeInsets.fromLTRB(16, 8, 16, 20),
                  child: Text(
                    'No schedules configured yet.',
                    style: TextStyle(color: Colors.grey),
                  ),
                )
              else ...[
                const Divider(indent: 16, endIndent: 16),
                ..._schedules.map(
                  (s) => _ScheduleTile(
                    schedule: s,
                    onDelete: () => _deleteSchedule(s),
                  ),
                ),
              ],
            ],
          ),

          const SizedBox(height: 28),

          // ── Database Snapshots ──────────────────────────────────────────
          _SectionHeader(
            title: 'Database Snapshots',
            icon: Icons.storage_rounded,
          ),
          const SizedBox(height: 4),
          Padding(
            padding: const EdgeInsets.only(left: 4, bottom: 12),
            child: Text(
              'Full PostgreSQL database dumps. These ensure infrastructure-level recovery and local failover synchronization.',
              style: TextStyle(
                fontSize: 12,
                color: colorScheme.onSurface.withValues(alpha: 0.6),
              ),
            ),
          ),

          _Card(
            children: [
              ListTile(
                leading: Icon(
                  Icons.backup_rounded,
                  color: colorScheme.primary,
                ),
                title: const Text('Create Database Snapshot'),
                subtitle: const Text('Dumps primary DB & syncs to localhost'),
                trailing: FilledButton.icon(
                  onPressed: _isDbBackupRunning ? null : _runDbBackup,
                  icon: _isDbBackupRunning
                      ? const SizedBox(
                          width: 14,
                          height: 14,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            color: Colors.white,
                          ),
                        )
                      : const Icon(Icons.play_arrow_rounded, size: 18),
                  label: Text(_isDbBackupRunning ? 'Running…' : 'Start'),
                ),
              ),
              if (_isDbBackupRunning)
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      LinearProgressIndicator(value: _dbBackupProgress),
                      const SizedBox(height: 4),
                      Text(
                        _dbBackupMessage,
                        style: const TextStyle(fontSize: 12),
                      ),
                    ],
                  ),
                ),
              const Divider(height: 1),
              if (_loadingSnapshots)
                const Padding(
                  padding: EdgeInsets.all(24),
                  child: Center(child: CircularProgressIndicator()),
                )
              else if (_dbSnapshots.isEmpty)
                const Padding(
                  padding: EdgeInsets.all(24),
                  child: Center(
                    child: Text(
                      'No snapshots found.',
                      style: TextStyle(color: Colors.grey),
                    ),
                  ),
                )
              else
                ..._dbSnapshots.take(5).map(
                  (f) => ListTile(
                    dense: true,
                    leading: const Icon(Icons.insert_drive_file_outlined),
                    title: Text(f.filename),
                    subtitle: Text(
                      DateFormat('yyyy-MM-dd HH:mm').format(f.createdAt),
                    ),
                    trailing: Text(f.displaySize),
                  ),
                ),
            ],
          ),

          const SizedBox(height: 40),
        ],
      ),
    );
  }

  Widget _categoryIcon(String key, ColorScheme cs) {
    final icon = switch (key) {
      'users' => Icons.people_rounded,
      'roles_permissions' => Icons.admin_panel_settings_rounded,
      'products' => Icons.inventory_2_rounded,
      'suppliers' => Icons.business_rounded,
      'stock_receipts' => Icons.receipt_long_rounded,
      'historical_sales' => Icons.bar_chart_rounded,
      'demand_forecasts' => Icons.trending_up_rounded,
      'audit_log' => Icons.manage_history_rounded,
      'notifications' => Icons.notifications_rounded,
      _ => Icons.folder_rounded,
    };
    return Icon(icon, size: 20, color: cs.secondary);
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Schedule tile
// ─────────────────────────────────────────────────────────────────────────────
class _ScheduleTile extends StatelessWidget {
  final BackupScheduleModel schedule;
  final VoidCallback onDelete;
  const _ScheduleTile({required this.schedule, required this.onDelete});

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return ListTile(
      dense: true,
      leading: Icon(
        Icons.event_repeat_rounded,
        size: 20,
        color: colorScheme.primary,
      ),
      title: Text(
        schedule.label,
        style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 14),
      ),
      subtitle: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(schedule.summary, style: const TextStyle(fontSize: 12)),
          Text(
            schedule.categories.join(', '),
            style: TextStyle(
              fontSize: 11,
              color: colorScheme.onSurface.withValues(alpha: 0.5),
            ),
            overflow: TextOverflow.ellipsis,
          ),
        ],
      ),
      trailing: IconButton(
        icon: Icon(
          Icons.delete_outline_rounded,
          color: colorScheme.error,
          size: 20,
        ),
        tooltip: 'Delete schedule',
        onPressed: onDelete,
      ),
      isThreeLine: true,
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Add Schedule Dialog
// ─────────────────────────────────────────────────────────────────────────────
typedef _OnSave =
    void Function(
      String label,
      List<String> categories,
      String frequency,
      String scheduledTime,
      List<String> formats,
      int? dayOfWeek,
      int? dayOfMonth,
      int? month,
    );

class _AddScheduleDialog extends StatefulWidget {
  final List<ExportCategory> categories;
  final _OnSave onSave;
  const _AddScheduleDialog({required this.categories, required this.onSave});

  @override
  State<_AddScheduleDialog> createState() => _AddScheduleDialogState();
}

class _AddScheduleDialogState extends State<_AddScheduleDialog> {
  final _labelCtrl = TextEditingController();
  String _frequency = 'daily';
  TimeOfDay _time = const TimeOfDay(hour: 2, minute: 0);
  int _dayOfWeek = 0;
  int _dayOfMonth = 1;
  int _month = 1;
  late Set<String> _selectedCats;
  final Set<String> _selectedFormats = {'csv'};

  static const _weekdays = [
    'Monday',
    'Tuesday',
    'Wednesday',
    'Thursday',
    'Friday',
    'Saturday',
    'Sunday',
  ];
  static const _months = [
    'January',
    'February',
    'March',
    'April',
    'May',
    'June',
    'July',
    'August',
    'September',
    'October',
    'November',
    'December',
  ];

  @override
  void initState() {
    super.initState();
    _selectedCats = Set.from(widget.categories.map((c) => c.key));
    _labelCtrl.text = 'Daily Backup';
  }

  @override
  void dispose() {
    _labelCtrl.dispose();
    super.dispose();
  }

  void _updateLabel() {
    _labelCtrl.text =
        '${_frequency[0].toUpperCase()}${_frequency.substring(1)} Backup';
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('New Backup Data Schedule'),
      scrollable: true,
      content: SizedBox(
        width: 420,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: _labelCtrl,
              decoration: const InputDecoration(
                labelText: 'Schedule Name',
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 16),

            // Frequency
            DropdownButtonFormField<String>(
              initialValue: _frequency,
              decoration: const InputDecoration(
                labelText: 'Frequency',
                border: OutlineInputBorder(),
              ),
              items: ['daily', 'weekly', 'monthly', 'yearly']
                  .map(
                    (f) => DropdownMenuItem(
                      value: f,
                      child: Text(f[0].toUpperCase() + f.substring(1)),
                    ),
                  )
                  .toList(),
              onChanged: (v) => setState(() {
                _frequency = v!;
                _updateLabel();
              }),
            ),
            const SizedBox(height: 12),

            // Time
            ListTile(
              contentPadding: EdgeInsets.zero,
              title: const Text('Time', style: TextStyle(fontSize: 14)),
              subtitle: Text(
                _time.format(context),
                style: const TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.bold,
                ),
              ),
              trailing: const Icon(Icons.access_time_rounded),
              onTap: () async {
                final p = await showTimePicker(
                  context: context,
                  initialTime: _time,
                );
                if (p != null) setState(() => _time = p);
              },
            ),

            if (_frequency == 'weekly') ...[
              const SizedBox(height: 8),
              DropdownButtonFormField<int>(
                initialValue: _dayOfWeek,
                decoration: const InputDecoration(
                  labelText: 'Day of Week',
                  border: OutlineInputBorder(),
                ),
                items: List.generate(
                  7,
                  (i) => DropdownMenuItem(value: i, child: Text(_weekdays[i])),
                ),
                onChanged: (v) => setState(() => _dayOfWeek = v!),
              ),
            ],

            if (_frequency == 'monthly' || _frequency == 'yearly') ...[
              const SizedBox(height: 8),
              DropdownButtonFormField<int>(
                initialValue: _dayOfMonth,
                decoration: const InputDecoration(
                  labelText: 'Day of Month',
                  border: OutlineInputBorder(),
                ),
                items: List.generate(
                  28,
                  (i) =>
                      DropdownMenuItem(value: i + 1, child: Text('${i + 1}')),
                ),
                onChanged: (v) => setState(() => _dayOfMonth = v!),
              ),
            ],

            if (_frequency == 'yearly') ...[
              const SizedBox(height: 8),
              DropdownButtonFormField<int>(
                initialValue: _month,
                decoration: const InputDecoration(
                  labelText: 'Month',
                  border: OutlineInputBorder(),
                ),
                items: List.generate(
                  12,
                  (i) =>
                      DropdownMenuItem(value: i + 1, child: Text(_months[i])),
                ),
                onChanged: (v) => setState(() => _month = v!),
              ),
            ],

            const SizedBox(height: 16),
            const Text(
              'Formats to include:',
              style: TextStyle(fontWeight: FontWeight.w600),
            ),
            const SizedBox(height: 4),
            Row(
              children: [
                _FormatChoice(
                  label: 'CSV',
                  isSelected: _selectedFormats.contains('csv'),
                  onToggle: (v) => setState(() {
                    if (v) {
                      _selectedFormats.add('csv');
                    } else if (_selectedFormats.length > 1)
                      _selectedFormats.remove('csv');
                  }),
                ),
                const SizedBox(width: 8),
                _FormatChoice(
                  label: 'JSON',
                  isSelected: _selectedFormats.contains('json'),
                  onToggle: (v) => setState(() {
                    if (v) {
                      _selectedFormats.add('json');
                    } else if (_selectedFormats.length > 1)
                      _selectedFormats.remove('json');
                  }),
                ),
                const SizedBox(width: 8),
                _FormatChoice(
                  label: 'SQL',
                  isSelected: _selectedFormats.contains('sql'),
                  onToggle: (v) => setState(() {
                    if (v) {
                      _selectedFormats.add('sql');
                    } else if (_selectedFormats.length > 1)
                      _selectedFormats.remove('sql');
                  }),
                ),
              ],
            ),

            const SizedBox(height: 16),
            const Text(
              'Categories to include:',
              style: TextStyle(fontWeight: FontWeight.w600),
            ),
            const SizedBox(height: 4),
            ...widget.categories.map(
              (cat) => CheckboxListTile(
                dense: true,
                value: _selectedCats.contains(cat.key),
                onChanged: (v) => setState(() {
                  if (v == true) {
                    _selectedCats.add(cat.key);
                  } else {
                    _selectedCats.remove(cat.key);
                  }
                }),
                title: Text(cat.label, style: const TextStyle(fontSize: 13)),
                controlAffinity: ListTileControlAffinity.leading,
              ),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Cancel'),
        ),
        FilledButton(
          onPressed: _selectedCats.isEmpty || _selectedFormats.isEmpty
              ? null
              : () {
                  final timeStr =
                      '${_time.hour.toString().padLeft(2, '0')}:${_time.minute.toString().padLeft(2, '0')}';
                  widget.onSave(
                    _labelCtrl.text.trim().isEmpty
                        ? 'Backup'
                        : _labelCtrl.text.trim(),
                    _selectedCats.toList(),
                    _frequency,
                    timeStr,
                    _selectedFormats.toList(),
                    _frequency == 'weekly' ? _dayOfWeek : null,
                    (_frequency == 'monthly' || _frequency == 'yearly')
                        ? _dayOfMonth
                        : null,
                    _frequency == 'yearly' ? _month : null,
                  );
                  Navigator.pop(context);
                },
          child: const Text('Save Schedule'),
        ),
      ],
    );
  }
}

class _FormatChoice extends StatelessWidget {
  final String label;
  final bool isSelected;
  final ValueChanged<bool> onToggle;
  const _FormatChoice({
    required this.label,
    required this.isSelected,
    required this.onToggle,
  });

  @override
  Widget build(BuildContext context) {
    return ChoiceChip(
      label: Text(label, style: const TextStyle(fontSize: 12)),
      selected: isSelected,
      onSelected: onToggle,
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Shared widgets
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

class _Card extends StatelessWidget {
  final List<Widget> children;
  const _Card({required this.children});

  @override
  Widget build(BuildContext context) {
    return Card(
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: BorderSide(
          color: Theme.of(context).dividerColor.withValues(alpha: 0.1),
        ),
      ),
      child: Column(children: children),
    );
  }
}
