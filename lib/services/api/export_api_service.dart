import 'dart:typed_data';

import 'api_client.dart';
import 'api_config.dart';

// ─────────────────────────────────────────────────────────────────────────────
// Models
// ─────────────────────────────────────────────────────────────────────────────

class ExportCategory {
  const ExportCategory({
    required this.key,
    required this.label,
    required this.description,
  });

  factory ExportCategory.fromJson(Map<String, dynamic> json) => ExportCategory(
    key: json['key'] as String,
    label: json['label'] as String,
    description: json['description'] as String,
  );

  final String key;
  final String label;
  final String description;
}

class BackupScheduleModel {
  BackupScheduleModel({
    required this.id,
    required this.label,
    required this.categories,
    required this.frequency,
    required this.scheduledTime,
    this.formats = const ['csv'],
    this.dayOfWeek,
    this.dayOfMonth,
    this.month,
    this.lastRunAt,
  });

  factory BackupScheduleModel.fromJson(Map<String, dynamic> json) =>
      BackupScheduleModel(
        id: json['id'], // Can be int from server or String from legacy local
        label: json['label'] as String,
        categories: List<String>.from(json['categories'] as List),
        frequency: json['frequency'] as String,
        scheduledTime: json['scheduled_time'] as String,
        formats: json['formats'] != null
            ? List<String>.from(json['formats'] as List)
            : ['csv'],
        dayOfWeek: json['day_of_week'] as int?,
        dayOfMonth: json['day_of_month'] as int?,
        month: json['month'] as int?,
        lastRunAt: json['last_run_at'] != null
            ? DateTime.tryParse(json['last_run_at'] as String)
            : null,
      );

  Map<String, dynamic> toJson() => {
    'id': id,
    'label': label,
    'categories': categories,
    'frequency': frequency,
    'scheduled_time': scheduledTime,
    'formats': formats,
    if (dayOfWeek != null) 'day_of_week': dayOfWeek,
    if (dayOfMonth != null) 'day_of_month': dayOfMonth,
    if (month != null) 'month': month,
    if (lastRunAt != null) 'last_run_at': lastRunAt!.toIso8601String(),
  };

  final dynamic id; // Use dynamic to handle migration or native DB ints
  final String label;
  final List<String> categories;
  final String frequency;
  final String scheduledTime;
  final List<String> formats;
  final int? dayOfWeek;
  final int? dayOfMonth;
  final int? month;
  DateTime? lastRunAt;

  /// Human-readable summary e.g. "Daily at 02:00"
  String get summary {
    const days = ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'];
    const months = [
      'Jan',
      'Feb',
      'Mar',
      'Apr',
      'May',
      'Jun',
      'Jul',
      'Aug',
      'Sep',
      'Oct',
      'Nov',
      'Dec',
    ];
    String base = '';
    switch (frequency.toLowerCase()) {
      case 'daily':
        base = 'Every day at $scheduledTime';
        break;
      case 'weekly':
        final day = dayOfWeek != null ? days[dayOfWeek!] : '?';
        base = 'Every $day at $scheduledTime';
        break;
      case 'monthly':
        base = 'Monthly on day ${dayOfMonth ?? '?'} at $scheduledTime';
        break;
      case 'yearly':
        final m = month != null ? months[month! - 1] : '?';
        base = 'Yearly on ${dayOfMonth ?? '?'} $m at $scheduledTime';
        break;
      default:
        base = frequency;
    }
    final fmtStr = formats.map((f) => f.toUpperCase()).join('+');
    return '$base ($fmtStr)';
  }

  /// Returns true if this schedule should fire right now.
  /// Returns true if this schedule should fire right now or if a run was missed.
  bool isDue() {
    final now = DateTime.now();
    final parts = scheduledTime.split(':');
    if (parts.length < 2) return false;
    final h = int.tryParse(parts[0]) ?? 0;
    final m = int.tryParse(parts[1]) ?? 0;

    // Calculate the most recent valid occurrence of this schedule in the past.
    DateTime lastExpected;

    switch (frequency.toLowerCase()) {
      case 'daily':
        lastExpected = DateTime(now.year, now.month, now.day, h, m);
        if (lastExpected.isAfter(now)) {
          lastExpected = lastExpected.subtract(const Duration(days: 1));
        }
        break;
      case 'weekly':
        final targetDow = (dayOfWeek ?? 0) + 1; // 1=Mon...7=Sun
        lastExpected = DateTime(now.year, now.month, now.day, h, m);
        while (lastExpected.weekday != targetDow || lastExpected.isAfter(now)) {
          lastExpected = lastExpected.subtract(const Duration(days: 1));
        }
        break;
      case 'monthly':
        final targetDom = (dayOfMonth ?? 1);
        lastExpected = DateTime(now.year, now.month, targetDom, h, m);
        if (lastExpected.isAfter(now)) {
          lastExpected = DateTime(now.year, now.month - 1, targetDom, h, m);
        }
        break;
      case 'yearly':
        final targetM = (month ?? 1);
        final targetD = (dayOfMonth ?? 1);
        lastExpected = DateTime(now.year, targetM, targetD, h, m);
        if (lastExpected.isAfter(now)) {
          lastExpected = DateTime(now.year - 1, targetM, targetD, h, m);
        }
        break;
      default:
        return false;
    }

    // If we have never run it, or if our last run was BEFORE the most recent expectation,
    // then we are due for a run (either a normal trigger or a catch-up).
    if (lastRunAt == null) return true;

    // Safety: ignore if we already started running in the last 60 seconds (prevents double-fire)
    final secondsSinceLastRun = now.difference(lastRunAt!).inSeconds;
    if (secondsSinceLastRun < 60) return false;

    return lastRunAt!.isBefore(lastExpected);
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Export API Service
// ─────────────────────────────────────────────────────────────────────────────

class ExportApiService {
  ExportApiService({ApiClient? apiClient})
    : _apiClient = apiClient ?? ApiClient(baseUrl: ApiConfig.baseUrl);

  final ApiClient _apiClient;

  /// Fetch all available export categories from the backend.
  Future<List<ExportCategory>> getCategories() async {
    final List<dynamic> raw = await _apiClient.get(
      '/export/categories',
      authorized: true,
    );
    return raw
        .map((e) => ExportCategory.fromJson(e as Map<String, dynamic>))
        .toList();
  }

  /// RESTful Schedule CRUD

  Future<List<BackupScheduleModel>> getSchedules() async {
    final List<dynamic> raw = await _apiClient.get(
      '/export/schedules',
      authorized: true,
    );
    return raw
        .map((e) => BackupScheduleModel.fromJson(e as Map<String, dynamic>))
        .toList();
  }

  Future<void> addSchedule(BackupScheduleModel schedule) async {
    await _apiClient.post(
      '/export/schedules',
      authorized: true,
      body: {
        'label': schedule.label,
        'categories': schedule.categories,
        'frequency': schedule.frequency,
        'scheduled_time': schedule.scheduledTime,
        'day_of_week': schedule.dayOfWeek,
        'day_of_month': schedule.dayOfMonth,
        'month': schedule.month,
      },
    );
  }

  Future<void> removeSchedule(dynamic id) async {
    await _apiClient.delete('/export/schedules/$id', authorized: true);
  }

  Future<void> markScheduleRun(dynamic id) async {
    await _apiClient.patch('/export/schedules/$id/mark-run', authorized: true);
  }

  /// Run a manual or scheduled backup for the given categories.
  /// Returns raw ZIP bytes.
  Future<Uint8List> runBackup(
    List<String> categories, {
    List<String> formats = const ['csv'],
  }) async {
    final bytes = await _apiClient.postBinary(
      '/export/run',
      authorized: true,
      body: {'categories': categories, 'formats': formats},
    );
    if (bytes is Uint8List) {
      return bytes;
    }
    throw Exception('Failed to receive binary data from server');
  }

  /// Exclusively trigger the End of Contract sequence.
  Future<Uint8List> endOfContract({
    required List<String> categories,
    required String password,
    required List<String> formats,
    String? feedback,
  }) async {
    final bytes = await _apiClient.postBinary(
      '/export/end-of-contract',
      authorized: true,
      body: {
        'categories': categories,
        'password': password,
        'formats': formats,
        'feedback': feedback ?? '',
      },
    );
    if (bytes is Uint8List) {
      return bytes;
    }
    throw Exception('Failed to receive binary data from server');
  }
}
