import Flutter
import UIKit

/// SmartLocalStoragePlugin — returns the app's Documents directory path.
/// Uses Foundation's own file-system API directly, no pub.dev package.
public class SmartLocalStoragePlugin: NSObject, FlutterPlugin {
  public static func register(with registrar: FlutterPluginRegistrar) {
    let channel = FlutterMethodChannel(name: "smart_local_storage", binaryMessenger: registrar.messenger())
    let instance = SmartLocalStoragePlugin()
    registrar.addMethodCallDelegate(instance, channel: channel)
  }

  public func handle(_ call: FlutterMethodCall, result: @escaping FlutterResult) {
    if call.method == "getDocumentsPath" {
      let paths = NSSearchPathForDirectoriesInDomains(.documentDirectory, .userDomainMask, true)
      result(paths.first)
    } else {
      result(FlutterMethodNotImplemented)
    }
  }
}
