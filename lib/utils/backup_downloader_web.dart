// Web implementation — uses the `web` package (dart:js_interop safe)
import 'dart:js_interop';
import 'dart:typed_data';

import 'package:web/web.dart' as web;

Future<String> downloadZip(Uint8List bytes, String filename) async {
  // Convert Uint8List → JS ArrayBuffer via JSUint8Array, then wrap in a list
  // Blob constructor requires JSArray<JSAny?> — use toJS on the outer list.
  final jsBytes = bytes.toJS; // JSUint8Array (an ArrayBufferView = valid BlobPart)
  final blobParts = <JSAny>[jsBytes].toJS; // JSArray<JSAny>
  final options = web.BlobPropertyBag(type: 'application/zip');
  final blob = web.Blob(blobParts, options);
  final url = web.URL.createObjectURL(blob);

  final anchor = web.document.createElement('a') as web.HTMLAnchorElement;
  anchor.href = url;
  anchor.download = filename;
  web.document.body!.appendChild(anchor);
  anchor.click();
  web.document.body!.removeChild(anchor);
  web.URL.revokeObjectURL(url);
  return '';
}

abstract class NativeDownloader {
  static Future<String> save(Uint8List bytes, String filename) async => '';
}
