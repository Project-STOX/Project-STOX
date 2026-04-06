import '../models/audit_log_entry.dart';
import 'supabase_service.dart';

class AuditLogService {
  final supabase = SupabaseService.client;

  int? _toInt(dynamic value) {
    if (value == null) return null;
    if (value is int) return value;
    if (value is num) return value.toInt();
    return int.tryParse(value.toString());
  }

  Future<void> logAction({
    int? userId,
    required String action,
    required String entityType,
    int? entityId,
    String? details,
  }) async {
    final payload = <String, dynamic>{
      'user_id': userId,
      'action': action,
      'entity_type': entityType,
      // audit_log.entity_id is NOT NULL in this schema.
      'entity_id': entityId ?? 0,
      if (details != null && details.trim().isNotEmpty) 'details': details,
    };

    try {
      await supabase.from('audit_log').insert(payload);
      return;
    } catch (_) {
      // Some deployments may not have a details column.
    }

    try {
      payload.remove('details');
      await supabase.from('audit_log').insert(payload);
    } catch (_) {
      // Audit logging must never block primary business flows (e.g. login).
      return;
    }
  }

  Future<List<AuditLogEntry>> getAuditLogs({
    int limit = 500,
  }) async {
    final normalizedLimit = limit <= 0 ? 100 : limit;
    List<dynamic> rawLogs = [];

    const orderCandidates = [
      'created_at',
      'action_time',
      'logged_at',
      'timestamp',
    ];

    for (final field in orderCandidates) {
      try {
        final response = await supabase
            .from('audit_log')
            .select()
            .order(field, ascending: false)
            .limit(normalizedLimit);

        rawLogs = response as List<dynamic>;
        break;
      } catch (_) {
        // Try next timestamp field.
      }
    }

    if (rawLogs.isEmpty) {
      try {
        final fallback = await supabase
            .from('audit_log')
            .select()
            .limit(normalizedLimit);
        rawLogs = fallback as List<dynamic>;
      } catch (_) {
        return [];
      }
    }

    final userIds = rawLogs
        .map((row) => _toInt((row as Map)['user_id']))
        .whereType<int>()
        .where((id) => id > 0)
        .toSet()
        .toList();

    final usernameById = <int, String>{};
    if (userIds.isNotEmpty) {
      try {
        final users = await supabase
            .from('user')
            .select('user_id, username')
            .inFilter('user_id', userIds);

        for (final item in users as List<dynamic>) {
          final userMap = Map<String, dynamic>.from(item as Map);
          final id = _toInt(userMap['user_id']);
          final username = userMap['username']?.toString();
          if (id != null && username != null && username.trim().isNotEmpty) {
            usernameById[id] = username;
          }
        }
      } catch (_) {
        // Keep logs even if username resolution fails.
      }
    }

    return rawLogs.map((row) {
      final logMap = Map<String, dynamic>.from(row as Map);
      final userId = _toInt(logMap['user_id']);
      if (userId != null && usernameById.containsKey(userId)) {
        logMap['username'] = usernameById[userId];
      }
      return AuditLogEntry.fromJson(logMap);
    }).toList();
  }
}