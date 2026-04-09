class AuditLogEntry {
  final int? logId;
  final int? userId;
  final String? username;
  final String action;
  final String entityType;
  final int? entityId;
  final String? details;
  final DateTime? occurredAt;

  AuditLogEntry({
    this.logId,
    this.userId,
    this.username,
    required this.action,
    required this.entityType,
    this.entityId,
    this.details,
    this.occurredAt,
  });

  static DateTime? _parseTimestamp(dynamic value) {
    if (value == null) return null;
    if (value is DateTime) return value;
    return DateTime.tryParse(value.toString());
  }

  static int? _parseInt(dynamic value) {
    if (value == null) return null;
    if (value is int) return value;
    if (value is num) return value.toInt();
    return int.tryParse(value.toString());
  }

  factory AuditLogEntry.fromJson(Map<String, dynamic> json) {
    final userJson = (json['user'] as Map?)?.cast<String, dynamic>();
    final logId = _parseInt(json['audit_log_id']) ?? _parseInt(json['log_id']) ?? _parseInt(json['id']);
    final entityId = _parseInt(json['entity_id']);

    return AuditLogEntry(
      logId: logId,
      userId: _parseInt(json['user_id']),
      username:
          userJson?['username']?.toString() ?? json['username']?.toString(),
      action: json['action']?.toString() ?? 'Unknown action',
      entityType: json['entity_type']?.toString() ?? 'System',
      entityId: entityId,
      details:
          json['details']?.toString() ??
          json['description']?.toString() ??
          json['metadata']?.toString(),
      occurredAt:
          _parseTimestamp(json['occurred_at']) ??
          _parseTimestamp(json['occurredAt']) ??
          _parseTimestamp(json['timestamp']) ??
          _parseTimestamp(json['created_at']) ??
          _parseTimestamp(json['createdAt']) ??
          _parseTimestamp(json['logged_at']) ??
          _parseTimestamp(json['action_time']),
    );
  }
}