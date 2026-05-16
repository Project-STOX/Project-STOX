import 'dart:typed_data';

/// Platform-aware ZIP download.
/// Returns the file path where the ZIP was saved (empty string on web).
Future<String> downloadZip(Uint8List bytes, String filename) {
  throw UnsupportedError('Use backup_downloader_web.dart or backup_downloader_io.dart');
}

/// Stub — implemented in platform files
abstract class NativeDownloader {
  static Future<String> save(Uint8List bytes, String filename) {
    throw UnsupportedError('Platform not supported');
  }
}
