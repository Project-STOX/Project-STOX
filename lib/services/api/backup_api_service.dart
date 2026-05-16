import 'dart:async';
import 'dart:convert';

import 'package:http/http.dart' as http;

import 'api_config.dart';
import 'token_storage.dart';

/// Represents a single Server-Sent Event from the backup stream.
class BackupSseEvent {
  const BackupSseEvent({
    required this.event,
    required this.data,
  });

  final String event; // start | progress | done | error
  final Map<String, dynamic> data;

  int get progress => (data['progress'] as num?)?.toInt() ?? 0;
  String get message => data['message']?.toString() ?? '';
  String? get fileName => data['file']?.toString();
  double? get sizeMb => (data['size_mb'] as num?)?.toDouble();
}

/// Lightweight info about a completed backup file.
class BackupFileInfo {
  const BackupFileInfo({
    required this.filename,
    required this.sizeBytes,
    required this.createdAt,
  });

  factory BackupFileInfo.fromJson(Map<String, dynamic> json) {
    return BackupFileInfo(
      filename: json['filename'] as String,
      sizeBytes: (json['size_bytes'] as num).toInt(),
      createdAt: DateTime.parse(json['created_at'] as String),
    );
  }

  final String filename;
  final int sizeBytes;
  final DateTime createdAt;

  /// Human-readable file size.
  String get displaySize {
    if (sizeBytes >= 1024 * 1024) {
      return '${(sizeBytes / (1024 * 1024)).toStringAsFixed(2)} MB';
    } else if (sizeBytes >= 1024) {
      return '${(sizeBytes / 1024).toStringAsFixed(1)} KB';
    }
    return '$sizeBytes B';
  }
}

class BackupApiService {
  BackupApiService({TokenStorage? tokenStorage})
      : _tokenStorage = tokenStorage ?? TokenStorage();

  final TokenStorage _tokenStorage;
  final String _base = ApiConfig.baseUrl;

  Future<Map<String, String>> _headers() async {
    final token = await _tokenStorage.getAccessToken();
    return {
      'Content-Type': 'application/json',
      if (token != null && token.isNotEmpty) 'Authorization': 'Bearer $token',
    };
  }

  /// Returns the list of existing local backup files.
  Future<List<BackupFileInfo>> listBackups() async {
    final uri = Uri.parse('$_base/backup/list');
    final response = await http.get(uri, headers: await _headers());
    if (response.statusCode == 200) {
      final List<dynamic> raw = jsonDecode(response.body) as List<dynamic>;
      return raw
          .map((e) => BackupFileInfo.fromJson(e as Map<String, dynamic>))
          .toList();
    }
    if (response.statusCode == 403) {
      throw Exception('ACCESS_DENIED');
    }
    throw Exception('Failed to fetch backup list: ${response.statusCode}');
  }

  /// Returns the current backup configuration.
  Future<Map<String, dynamic>> getConfig() async {
    final uri = Uri.parse('$_base/backup/config');
    final response = await http.get(uri, headers: await _headers());
    if (response.statusCode == 200) {
      return jsonDecode(response.body) as Map<String, dynamic>;
    }
    throw Exception('Failed to fetch backup config');
  }

  /// Saves the backup configuration.
  Future<void> saveConfig(Map<String, dynamic> config) async {
    final uri = Uri.parse('$_base/backup/config');
    final response = await http.put(
      uri,
      headers: await _headers(),
      body: jsonEncode(config),
    );
    if (response.statusCode != 200) {
      throw Exception('Failed to save backup config');
    }
  }

  /// Triggers a backup and returns a stream of [BackupSseEvent]s.
  ///
  /// Uses a raw HTTP request so the caller can process chunks as they arrive
  /// without waiting for the full response body to complete.
  Stream<BackupSseEvent> runBackup({bool sync = false}) async* {
    final uri = Uri.parse('$_base/backup/run').replace(queryParameters: {
      'sync': sync.toString(),
    });
    final headers = await _headers();

    final request = http.Request('POST', uri)..headers.addAll(headers);
    final streamedResponse = await request.send();

    if (streamedResponse.statusCode == 403) {
      throw Exception('ACCESS_DENIED');
    }
    if (streamedResponse.statusCode != 200) {
      throw Exception(
          'Backup request failed: ${streamedResponse.statusCode}');
    }

    // Parse SSE text/event-stream line by line
    final buffer = StringBuffer();
    String? eventType;
    String? dataLine;

    await for (final chunk
        in streamedResponse.stream.transform(utf8.decoder)) {
      buffer.write(chunk);
      // Process complete lines
      final text = buffer.toString();
      final lines = text.split('\n');
      // Keep incomplete last line in buffer
      buffer.clear();
      buffer.write(lines.last);

      for (final line in lines.sublist(0, lines.length - 1)) {
        final trimmed = line.trim();
        if (trimmed.startsWith('event:')) {
          eventType = trimmed.substring(6).trim();
        } else if (trimmed.startsWith('data:')) {
          dataLine = trimmed.substring(5).trim();
        } else if (trimmed.isEmpty && eventType != null && dataLine != null) {
          // Emit the parsed event
          try {
            final decoded = jsonDecode(dataLine) as Map<String, dynamic>;
            yield BackupSseEvent(event: eventType, data: decoded);
          } catch (_) {
            // Malformed frame – skip
          }
          eventType = null;
          dataLine = null;
        }
      }
    }

    // Some servers may close without a trailing empty line; emit last complete frame.
    if (eventType != null && dataLine != null) {
      try {
        final decoded = jsonDecode(dataLine) as Map<String, dynamic>;
        yield BackupSseEvent(event: eventType, data: decoded);
      } catch (_) {
        // Ignore malformed trailing frame.
      }
    }
  }
}
