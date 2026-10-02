/// Registers the Dart-only desktop implementation (macOS, Linux, Windows).
///
/// Desktop needs no native code: the storage folder is found in Dart (see
/// `SmartPaths`). Encryption is only available on Android and iOS.
class SmartLocalStorageDesktop {
  SmartLocalStorageDesktop._();

  /// Called by Flutter on desktop. Nothing to register.
  static void registerWith() {}
}
