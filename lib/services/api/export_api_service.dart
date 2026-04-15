import 'dart:convert';
import 'dart:typed_data';

import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

import 'api_config.dart';
import 'token_storage.dart';

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
    this.dayOfWeek,
    this.dayOfMonth,
    this.month,
    this.lastRunAt,
  });

  factory BackupScheduleModel.fromJson(Map<String, dynamic> json) =>
      BackupScheduleModel(
        id: json['id'] as String,
        label: json['label'] as String,
        categories: List<String>.from(json['categories'] as List),
        frequency: json['frequency'] as String,
        scheduledTime: json['scheduled_time'] as String,
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
        if (dayOfWeek != null) 'day_of_week': dayOfWeek,
        if (dayOfMonth != null) 'day_of_month': dayOfMonth,
        if (month != null) 'month': month,
        if (lastRunAt != null) 'last_run_at': lastRunAt!.toIso8601String(),
      };

  final String id;
  final String label;
  final List<String> categories;
  final String frequency;
  final String scheduledTime;
  final int? dayOfWeek;
  final int? dayOfMonth;
  final int? month;
  DateTime? lastRunAt;

  /// Human-readable summary e.g. "Daily at 02:00"
  String get summary {
    const days = ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'];
    const months = [
      'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
      'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'
    ];
    switch (frequency.toLowerCase()) {
      case 'daily':
        return 'Every day at $scheduledTime';
      case 'weekly':
        final day = dayOfWeek != null ? days[dayOfWeek!] : '?';
        return 'Every $day at $scheduledTime';
      case 'monthly':
        return 'Monthly on day ${dayOfMonth ?? '?'} at $scheduledTime';
      case 'yearly':
        final m = month != null ? months[month! - 1] : '?';
        return 'Yearly on ${dayOfMonth ?? '?'} $m at $scheduledTime';
      default:
        return frequency;
    }
  }

  /// Returns true if this schedule should fire right now.
  bool isDue() {
    final now = DateTime.now();
    final parts = scheduledTime.split(':');
    if (parts.length < 2) return false;
    final h = int.tryParse(parts[0]) ?? 0;
    final m = int.tryParse(parts[1]) ?? 0;

    // Must match current hour:minute
    if (now.hour != h || now.minute != m) return false;

    // Must not have already run in the last 60 seconds (prevents double-fire)
    if (lastRunAt != null) {
      final elapsed = now.difference(lastRunAt!).inSeconds;
      if (elapsed < 58) return false;
    }

    switch (frequency.toLowerCase()) {
      case 'daily':
        return true;
      case 'weekly':
        // now.weekday is 1=Mon…7=Sun; dayOfWeek is 0=Mon…6=Sun
        return (now.weekday - 1) == (dayOfWeek ?? 0);
      case 'monthly':
        final lastDay = DateTime(now.year, now.month + 1, 0).day;
        final target = (dayOfMonth ?? 1).clamp(1, lastDay);
        return now.day == target;
      case 'yearly':
        final cMonth = month ?? 1;
        final lastDay = DateTime(now.year, cMonth + 1, 0).day;
        final target = (dayOfMonth ?? 1).clamp(1, lastDay);
        return now.month == cMonth && now.day == target;
      default:
        return false;
    }
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Schedule Local Storage (SharedPreferences)
// ─────────────────────────────────────────────────────────────────────────────

class ScheduleStorage {
  static const _key = 'stox_backup_schedules';

  static Future<List<BackupScheduleModel>> load() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_key);
    if (raw == null || raw.isEmpty) return [];
    try {
      final list = jsonDecode(raw) as List<dynamic>;
      return list
          .map((e) => BackupScheduleModel.fromJson(e as Map<String, dynamic>))
          .toList();
    } catch (_) {
      return [];
    }
  }

  static Future<void> save(List<BackupScheduleModel> schedules) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_key, jsonEncode(schedules.map((s) => s.toJson()).toList()));
  }

  static Future<BackupScheduleModel> add(BackupScheduleModel schedule) async {
    final list = await load();
    if (list.length >= 10) {
      throw Exception('Maximum of 10 schedules reached. Delete one to add another.');
    }
    list.add(schedule);
    await save(list);
    return schedule;
  }

  static Future<void> remove(String id) async {
    final list = await load();
    list.removeWhere((s) => s.id == id);
    await save(list);
  }

  static Future<void> markRun(String id) async {
    final list = await load();
    for (final s in list) {
      if (s.id == id) s.lastRunAt = DateTime.now();
    }
    await save(list);
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Export API Service
// ─────────────────────────────────────────────────────────────────────────────

class ExportApiService {
  ExportApiService({TokenStorage? tokenStorage})
      : _tokenStorage = tokenStorage ?? TokenStorage();

  final TokenStorage _tokenStorage;
  final String _base = ApiConfig.baseUrl;

  Future<Map<String, String>> _authHeaders() async {
    final token = await _tokenStorage.getAccessToken();
    return {
      'Content-Type': 'application/json',
      if (token != null && token.isNotEmpty) 'Authorization': 'Bearer $token',
    };
  }

  /// Fetch all available export categories from the backend.
  Future<List<ExportCategory>> getCategories() async {
    final response = await http.get(
      Uri.parse('$_base/export/categories'),
      headers: await _authHeaders(),
    );
    if (response.statusCode == 200) {
      final List<dynamic> raw = jsonDecode(response.body) as List<dynamic>;
      return raw
          .map((e) => ExportCategory.fromJson(e as Map<String, dynamic>))
          .toList();
    }
    throw Exception('Failed to load export categories: ${response.statusCode} — ${response.body}');
  }

  /// Run a manual or scheduled backup for the given categories.
  /// Returns raw ZIP bytes.
  Future<Uint8List> runBackup(List<String> categories, {List<String> formats = const ['csv']}) async {
    final headers = await _authHeaders();
    final response = await http.post(
      Uri.parse('$_base/export/run'),
      headers: headers,
      body: jsonEncode({
        'categories': categories,
        'formats': formats,
      }),
    );
    if (response.statusCode == 200) {
      return response.bodyBytes;
    }
    // Try to parse an error message
    String detail = 'Unknown error';
    try {
      detail = (jsonDecode(response.body)['detail'] as String?) ?? response.body;
    } catch (_) {
      detail = response.body;
    }
    throw Exception('Backup failed (${response.statusCode}): $detail');
  }

  /// Exclusively trigger the End of Contract sequence.
  Future<Uint8List> endOfContract({
    required List<String> categories,
    required String password,
    required List<String> formats,
    String? feedback,
  }) async {
    final headers = await _authHeaders();
    final response = await http.post(
      Uri.parse('$_base/export/end-of-contract'),
      headers: headers,
      body: jsonEncode({
        'categories': categories,
        'password': password,
        'formats': formats,
        'feedback': feedback ?? '',
      }),
    );
    if (response.statusCode == 200) {
      return response.bodyBytes;
    }
    // Try to parse an error message
    String detail = 'Unknown error';
    try {
      detail = (jsonDecode(response.body)['detail'] as String?) ?? response.body;
    } catch (_) {
      detail = response.body;
    }
    throw Exception(detail); // Just throw the API message logic for the wizard
  }
}
