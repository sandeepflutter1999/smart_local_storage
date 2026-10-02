import 'package:flutter/services.dart';

/// AES-256-GCM encryption done by the platform itself (Android Keystore /
/// iOS Keychain + CryptoKit). No pub.dev package and no hand-written crypto:
/// the key is created and kept by the OS and never reaches Dart.
class SmartCrypto {
  SmartCrypto._();

  static const MethodChannel _channel = MethodChannel('smart_local_storage');

  /// Returns nonce + ciphertext + tag.
  static Future<Uint8List> encrypt(Uint8List plain) async {
    final out = await _call('encrypt', plain);
    if (out == null) {
      throw StateError('smart_local_storage: encryption returned nothing.');
    }
    return out;
  }

  /// Reverses [encrypt]. Throws if the data was tampered with or the key
  /// is gone (for example after an app reinstall).
  static Future<Uint8List> decrypt(Uint8List data) async {
    final out = await _call('decrypt', data);
    if (out == null) {
      throw StateError('smart_local_storage: decryption returned nothing.');
    }
    return out;
  }

  static Future<Uint8List?> _call(String method, Uint8List data) async {
    try {
      return await _channel.invokeMethod<Uint8List>(method, data);
    } on MissingPluginException {
      throw UnsupportedError(
        'smart_local_storage: encryption is only available on Android and iOS.',
      );
    }
  }
}
