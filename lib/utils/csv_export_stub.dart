import 'dart:io';
import 'package:path_provider/path_provider.dart';

/// Returns the saved file path on success, or null on failure.
Future<String?> downloadCsvWeb(String csvString, String filename) async {
  try {
    Directory? directory;

    if (Platform.isAndroid) {
      // Public Downloads folder — visible in the Files app on Android
      directory = Directory('/storage/emulated/0/Download');
      if (!await directory.exists()) {
        // Fallback to external storage if the path isn't accessible
        directory = await getExternalStorageDirectory();
      }
    } else if (Platform.isIOS) {
      // App's Documents folder — visible via the Files app on iOS
      directory = await getApplicationDocumentsDirectory();
    } else {
      // Desktop / other platforms: use the system downloads dir
      directory = await getDownloadsDirectory();
    }

    if (directory == null) return null;

    final file = File('${directory.path}/$filename');
    await file.writeAsString(csvString);
    return file.path;
  } catch (e) {
    print("Export failed: $e");
    return null;
  }
}

