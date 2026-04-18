// Native (Windows / macOS / Linux / Android / iOS) implementation
import 'dart:io';

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
      if (Platform.isAndroid) {
        // For Android 11+ (API 30+), we ideally need MANAGE_EXTERNAL_STORAGE for public folders
        // or use scoped storage. Here we try to get the most accessible directory.
        final status = await Permission.manageExternalStorage.status;
        if (!status.isGranted) {
          await Permission.manageExternalStorage.request();
        }
        
        // Try to point to the public Downloads folder directly
        final downloadDir = Directory('/storage/emulated/0/Download');
        if (await downloadDir.exists()) {
          baseDir = downloadDir;
        }
      }
      
      baseDir ??=
          await getExternalStorageDirectory() ??
          await getApplicationDocumentsDirectory();
    } else {
      // Windows / macOS / Linux — use Downloads directory
      baseDir =
          await getDownloadsDirectory() ??
          await getApplicationDocumentsDirectory();
    }

    // Create "STOX Backups" sub-folder if it doesn't exist
    final saveDir = Directory(
      '${baseDir.path}${Platform.pathSeparator}STOX Backups',
    );
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
