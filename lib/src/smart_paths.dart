import 'package:flutter/services.dart';

/// Talks to our own tiny native plugin (Android/iOS) to get the app's
/// private storage folder path. No pub.dev package involved — this is a
/// MethodChannel we implement and own end to end.
class SmartPaths {
  static const MethodChannel _channel = MethodChannel('smart_local_storage');
  static String? _cachedPath;

  static Future<String> getStorageRoot() async {
    if (_cachedPath != null) return _cachedPath!;
    final path = await _channel.invokeMethod<String>('getDocumentsPath');
    if (path == null) {
      throw StateError(
          'smart_local_storage: native side did not return a path.');
    }
    _cachedPath = path;
    return path;
  }
}
