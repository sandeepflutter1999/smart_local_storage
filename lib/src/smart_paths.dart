import 'dart:io';

import 'package:flutter/services.dart';

/// Finds the folder where boxes are stored.
///
/// * Android / iOS: asked from our own tiny native plugin (a MethodChannel
///   we implement ourselves - no pub.dev package involved).
/// * macOS / Linux / Windows: worked out in Dart from the user's data folder.
class SmartPaths {
  static const MethodChannel _channel = MethodChannel('smart_local_storage');
  static String? _cachedPath;

  static Future<String> getStorageRoot() async {
    if (_cachedPath != null) return _cachedPath!;
    String? path;
    try {
      path = await _channel.invokeMethod<String>('getDocumentsPath');
    } on MissingPluginException {
      // No native plugin on this platform (desktop): use the Dart fallback.
      path = _desktopPath();
    }
    if (path == null) {
      throw StateError(
          'smart_local_storage: native side did not return a path.');
    }
    _cachedPath = path;
    return path;
  }

  static String _desktopPath() {
    final env = Platform.environment;
    final home = env['HOME'] ?? env['USERPROFILE'] ?? Directory.systemTemp.path;
    final String base;
    if (Platform.isWindows) {
      base = env['APPDATA'] ?? home;
    } else if (Platform.isMacOS) {
      base = '$home/Library/Application Support';
    } else {
      base = env['XDG_DATA_HOME'] ?? '$home/.local/share';
    }
    // One folder per app, so two apps using this package never share data.
    final exe = Platform.resolvedExecutable
        .split(RegExp(r'[\\/]'))
        .last
        .replaceAll(RegExp(r'\.exe$'), '');
    return '$base/smart_local_cache/$exe';
  }
}
