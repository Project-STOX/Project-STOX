import 'package:flutter/material.dart';

import '../controllers/audit_log_controller.dart';
import '../controllers/auth_controller.dart';
import '../models/audit_log_entry.dart';
import '../models/user.dart';

class AuditLogView extends StatefulWidget {
  final UserModel user;

  const AuditLogView({super.key, required this.user});

  @override
  State<AuditLogView> createState() => _AuditLogViewState();
}

class _AuditLogViewState extends State<AuditLogView> {
  final AuditLogController _auditLogController = AuditLogController();
  final AuthController _authController = AuthController();

  bool _hasPermission = false;
  bool _isLoading = true;
  String _query = '';
  int _selectedTab = 0; // 0 = Login sessions, 1 = System logs
  DateTime? _fromDateTime;
  DateTime? _toDateTime;
  List<AuditLogEntry> _logs = [];

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _isLoading = true);
    try {
      final allowed = await _authController.hasPermission(
        widget.user.roleId,
        'View audit log',
      );

      if (!allowed) {
        if (!mounted) return;
        setState(() {
          _hasPermission = false;
          _logs = [];
          _isLoading = false;
        });
        return;
      }

      final logs = await _auditLogController.fetchAuditLogs(limit: 1000);
      if (!mounted) return;
      setState(() {
        _hasPermission = true;
        _logs = logs;
        _isLoading = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _hasPermission = true;
        _logs = [];
        _isLoading = false;
      });
    }
  }

  bool _isLoginSessionLog(AuditLogEntry log) {
    final action = log.action.toLowerCase();
    final entityType = log.entityType.toLowerCase();

    return entityType.contains('authentication') ||
        entityType.contains('session') ||
        action.contains('login') ||
        action.contains('logout') ||
        action.contains('session');
  }

  bool _matchesDateTimeFilter(AuditLogEntry log) {
    final time = log.occurredAt?.toLocal();
    if (time == null) return false;
    if (_fromDateTime != null && time.isBefore(_fromDateTime!)) return false;
    if (_toDateTime != null && time.isAfter(_toDateTime!)) return false;
    return true;
  }

  List<AuditLogEntry> get _filteredLogs {
    final q = _query.trim().toLowerCase();
    return _logs.where((log) {
      final action = log.action.toLowerCase();
      final entityType = log.entityType.toLowerCase();

      final categoryMatch = _selectedTab == 0
          ? _isLoginSessionLog(log)
          : !_isLoginSessionLog(log);

      final username = (log.username ?? 'deleted user').toLowerCase();
      final details = (log.details ?? '').toLowerCase();

      final searchMatch =
          q.isEmpty ||
          action.contains(q) ||
          entityType.contains(q) ||
          username.contains(q) ||
          details.contains(q);

      final dateMatch =
          (_fromDateTime == null && _toDateTime == null) ||
          _matchesDateTimeFilter(log);

      return categoryMatch && searchMatch && dateMatch;
    }).toList();
  }

  Future<void> _pickDateTimePeriod() async {
    final now = DateTime.now();
    final initialStart = _fromDateTime ?? now;
    final initialEnd = _toDateTime ?? now;

    final dateRange = await showDateRangePicker(
      context: context,
      initialDateRange: DateTimeRange(
        start: initialStart,
        end: initialEnd.isBefore(initialStart) ? initialStart : initialEnd,
      ),
      firstDate: DateTime(2000),
      lastDate: DateTime(now.year + 5),
    );
    if (dateRange == null || !mounted) return;

    final startTime = await showTimePicker(
      context: context,
      initialTime: TimeOfDay.fromDateTime(initialStart),
    );
    if (!mounted) return;

    final endTime = await showTimePicker(
      context: context,
      initialTime: TimeOfDay.fromDateTime(initialEnd),
    );
    if (!mounted) return;

    final startDateTime = DateTime(
      dateRange.start.year,
      dateRange.start.month,
      dateRange.start.day,
      startTime?.hour ?? 0,
      startTime?.minute ?? 0,
    );

    final endDateTime = DateTime(
      dateRange.end.year,
      dateRange.end.month,
      dateRange.end.day,
      endTime?.hour ?? 23,
      endTime?.minute ?? 59,
      59,
    );

    setState(() {
      if (endDateTime.isBefore(startDateTime)) {
        _fromDateTime = endDateTime;
        _toDateTime = startDateTime;
      } else {
        _fromDateTime = startDateTime;
        _toDateTime = endDateTime;
      }
    });
  }

  void _clearDateTimeFilters() {
    setState(() {
      _fromDateTime = null;
      _toDateTime = null;
    });
  }

  String _formatTimestamp(DateTime? time) {
    if (time == null) return 'N/A';
    final local = time.toLocal();
    final mm = local.month.toString().padLeft(2, '0');
    final dd = local.day.toString().padLeft(2, '0');
    final hh = local.hour.toString().padLeft(2, '0');
    final min = local.minute.toString().padLeft(2, '0');
    final ss = local.second.toString().padLeft(2, '0');
    return '${local.year}-$mm-$dd $hh:$min:$ss';
  }

  @override
  Widget build(BuildContext context) {
    final logs = _filteredLogs;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Audit Log'),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: _load,
            tooltip: 'Refresh',
          ),
        ],
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : !_hasPermission
          ? const Center(
              child: Text(
                'Access denied: you do not have permission to view audit logs.',
              ),
            )
          : Column(
              children: [
                Padding(
                  padding: const EdgeInsets.all(12.0),
                  child: TextField(
                    decoration: const InputDecoration(
                      labelText: 'Search by action, entity type or by user',
                      prefixIcon: Icon(Icons.search),
                    ),
                    onChanged: (value) => setState(() => _query = value),
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 12.0),
                  child: Row(
                    children: [
                      Expanded(
                        child: SegmentedButton<int>(
                          segments: const [
                            ButtonSegment<int>(
                              value: 0,
                              label: Text('Login Sessions'),
                              icon: Icon(Icons.login),
                            ),
                            ButtonSegment<int>(
                              value: 1,
                              label: Text('System Logs'),
                              icon: Icon(Icons.settings_suggest),
                            ),
                          ],
                          selected: {_selectedTab},
                          onSelectionChanged: (value) {
                            setState(() => _selectedTab = value.first);
                          },
                        ),
                      ),
                    ],
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
                  child: Row(
                    children: [
                      Expanded(
                        child: OutlinedButton.icon(
                          onPressed: _pickDateTimePeriod,
                          icon: const Icon(Icons.date_range),
                          label: Text(
                            (_fromDateTime == null || _toDateTime == null)
                                ? 'Set date/time period'
                                : '${_formatTimestamp(_fromDateTime)} -> ${_formatTimestamp(_toDateTime)}',
                          ),
                        ),
                      ),
                      const SizedBox(width: 8),
                      TextButton(
                        onPressed: _clearDateTimeFilters,
                        child: const Text('Clear'),
                      ),
                    ],
                  ),
                ),
                Expanded(
                  child: logs.isEmpty
                      ? const Center(
                          child: Text(
                            'No audit records found for this filter.',
                          ),
                        )
                      : ListView.builder(
                          itemCount: logs.length,
                          itemBuilder: (context, index) {
                            final log = logs[index];
                            final userText =
                                log.username?.trim().isNotEmpty == true
                                ? log.username!
                                : (log.userId != null
                                      ? 'Deleted User (#${log.userId})'
                                      : 'Deleted User');

                            final bool hasDetails =
                                log.details != null &&
                                log.details!.trim().isNotEmpty;

                            Color actionColor = Colors.blueGrey;
                            if (log.action.contains('INSERT')) {
                              actionColor = Colors.green;
                            }
                            if (log.action.contains('UPDATE')) {
                              actionColor = Colors.orange;
                            }
                            if (log.action.contains('DELETE')) {
                              actionColor = Colors.red;
                            }

                            return Card(
                              margin: const EdgeInsets.symmetric(
                                horizontal: 12,
                                vertical: 6,
                              ),
                              elevation: 2,
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(12),
                              ),
                              child: Padding(
                                padding: const EdgeInsets.symmetric(
                                  vertical: 8.0,
                                ),
                                child: ListTile(
                                  leading: Container(
                                    width: 42,
                                    height: 42,
                                    decoration: BoxDecoration(
                                      color: actionColor.withOpacity(0.1),
                                      shape: BoxShape.circle,
                                    ),
                                    child: Icon(
                                      Icons.history_edu,
                                      color: actionColor,
                                    ),
                                  ),
                                  title: Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      Text(
                                        log.action,
                                        style: TextStyle(
                                          fontWeight: FontWeight.bold,
                                          color: actionColor,
                                          fontSize: 15,
                                        ),
                                      ),
                                      Text(
                                        _formatTimestamp(log.occurredAt),
                                        style: TextStyle(
                                          fontSize: 11,
                                          color: Theme.of(context).hintColor,
                                        ),
                                      ),
                                    ],
                                  ),
                                  subtitle: Padding(
                                    padding: const EdgeInsets.only(top: 4.0),
                                    child: Column(
                                      crossAxisAlignment:
                                          CrossAxisAlignment.start,
                                      children: [
                                        Wrap(
                                          spacing: 12,
                                          runSpacing: 4,
                                          crossAxisAlignment:
                                              WrapCrossAlignment.center,
                                          children: [
                                            Row(
                                              mainAxisSize: MainAxisSize.min,
                                              children: [
                                                const Icon(
                                                  Icons.person_outline,
                                                  size: 14,
                                                  color: Colors.grey,
                                                ),
                                                const SizedBox(width: 4),
                                                Text(
                                                  userText,
                                                  style: const TextStyle(
                                                    fontWeight: FontWeight.w500,
                                                  ),
                                                ),
                                              ],
                                            ),
                                            Row(
                                              mainAxisSize: MainAxisSize.min,
                                              children: [
                                                const Icon(
                                                  Icons.category_outlined,
                                                  size: 14,
                                                  color: Colors.grey,
                                                ),
                                                const SizedBox(width: 4),
                                                Text(
                                                  '${log.entityType}${log.entityId != null ? " #${log.entityId}" : ""}',
                                                ),
                                              ],
                                            ),
                                          ],
                                        ),
                                        if (hasDetails) ...[
                                          const SizedBox(height: 6),
                                          Container(
                                            padding: const EdgeInsets.all(8),
                                            decoration: BoxDecoration(
                                              color: Theme.of(context).colorScheme.surfaceContainerHighest.withOpacity(0.5),
                                              borderRadius:
                                                  BorderRadius.circular(8),
                                            ),
                                            child: Text(
                                              log.details!,
                                              style: TextStyle(
                                                fontSize: 13,
                                                color: Theme.of(context).colorScheme.onSurfaceVariant,
                                              ),
                                            ),
                                          ),
                                        ],
                                      ],
                                    ),
                                  ),
                                ),
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
