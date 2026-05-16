import '../models/audit_log_entry.dart';
import '../services/audit_log_service.dart';

class AuditLogController {
  final AuditLogService _service = AuditLogService();

  Future<List<AuditLogEntry>> fetchAuditLogs({int limit = 500}) {
    return _service.getAuditLogs(limit: limit);
  }

  Future<void> log({
    int? userId,
    required String action,
    required String entityType,
    int? entityId,
    String? details,
  }) {
    return _service.logAction(
      userId: userId,
      action: action,
      entityType: entityType,
      entityId: entityId,
      details: details,
    );
  }
}