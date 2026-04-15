// Native (Windows / macOS / Linux / Android / iOS) implementation
import 'dart:io';
import 'dart:typed_data';

import 'package:path_provider/path_provider.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:flutter/foundation.dart';

Future<String> downloadZip(Uint8List bytes, String filename) async {
  return NativeDownloader.save(bytes, filename);
}

abstract class NativeDownloader {
  static Future<String> save(Uint8List bytes, String filename) async {
    Directory? baseDir;

    if (Platform.isAndroid || Platform.isIOS) {
      // Request storage permission on mobile
      final status = await Permission.manageExternalStorage.status;
      if (!status.isGranted) {
        final result = await Permission.storage.request();
        if (!result.isGranted) {
          // Fallback to app documents dir if denied
          baseDir = await getApplicationDocumentsDirectory();
        }
      }
      baseDir ??= await getExternalStorageDirectory() ??
          await getApplicationDocumentsDirectory();
    } else {
      // Windows / macOS / Linux — use Downloads directory
      baseDir = await getDownloadsDirectory() ??
          await getApplicationDocumentsDirectory();
    }

    // Create "STOX Backups" sub-folder if it doesn't exist
    final saveDir = Directory('${baseDir.path}${Platform.pathSeparator}STOX Backups');
    if (!await saveDir.exists()) {
      await saveDir.create(recursive: true);
    }

    final filePath = '${saveDir.path}${Platform.pathSeparator}$filename';
    final file = File(filePath);
    await file.writeAsBytes(bytes, flush: true);

    debugPrint('[BackupDownloader] Saved to $filePath');
    return filePath;
  }
}
