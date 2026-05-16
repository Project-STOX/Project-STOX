import '../models/audit_log_entry.dart';
import 'api/reports_api_service.dart';

class AuditLogService {
  final ReportsApiService _api = ReportsApiService();

  Future<void> logAction({
    int? userId,
    required String action,
    required String entityType,
    int? entityId,
    String? details,
  }) async {
    await _api.logAction(
      userId: userId,
      action: action,
      entityType: entityType,
      entityId: entityId,
      details: details,
    );
  }

  Future<List<AuditLogEntry>> getAuditLogs({
    int limit = 500,
  }) async {
    return _api.getAuditLogs(limit: limit);
  }
}