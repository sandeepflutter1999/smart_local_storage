import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

/// Points the plugin channel at a temp folder and fakes the native crypto
/// (XOR with a 12-byte fake nonce in front, same layout as the real thing).
Directory setUpStorage() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final dir = Directory.systemTemp.createTempSync('smart_local_cache_test');

  TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
      .setMockMethodCallHandler(const MethodChannel('smart_local_storage'),
          (call) async {
    switch (call.method) {
      case 'getDocumentsPath':
        return dir.path;
      case 'encrypt':
        final plain = call.arguments as Uint8List;
        return Uint8List.fromList([
          ...List<int>.filled(12, 7),
          ...plain.map((b) => b ^ 0x5A),
        ]);
      case 'decrypt':
        final data = call.arguments as Uint8List;
        return Uint8List.fromList(
            data.sublist(12).map((b) => b ^ 0x5A).toList());
    }
    return null;
  });

  return dir;
}
