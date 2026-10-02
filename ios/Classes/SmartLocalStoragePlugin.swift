import Flutter
import UIKit
import CryptoKit
import Security

/// SmartLocalStoragePlugin
/// - getDocumentsPath: the app's Documents directory
/// - encrypt / decrypt: AES-256-GCM (CryptoKit) with a random key kept in the
///   iOS Keychain. Output layout: 12-byte nonce + ciphertext + 16-byte tag
///   (the same layout the Android side uses).
public class SmartLocalStoragePlugin: NSObject, FlutterPlugin {
  private static let keyTag = "com.smartlocalstorage.aes_key"
  private let worker = DispatchQueue(label: "smart_local_storage.crypto")

  public static func register(with registrar: FlutterPluginRegistrar) {
    let channel = FlutterMethodChannel(name: "smart_local_storage", binaryMessenger: registrar.messenger())
    let instance = SmartLocalStoragePlugin()
    registrar.addMethodCallDelegate(instance, channel: channel)
  }

  public func handle(_ call: FlutterMethodCall, result: @escaping FlutterResult) {
    switch call.method {
    case "getDocumentsPath":
      let paths = NSSearchPathForDirectoriesInDomains(.documentDirectory, .userDomainMask, true)
      result(paths.first)
    case "encrypt", "decrypt":
      guard let typed = call.arguments as? FlutterStandardTypedData else {
        result(FlutterError(code: "bad_args", message: "Expected bytes.", details: nil))
        return
      }
      let input = typed.data
      let encrypting = call.method == "encrypt"
      // Crypto runs off the main thread so big boxes never freeze the UI.
      worker.async {
        do {
          let key = try self.symmetricKey()
          let output: Data
          if encrypting {
            let sealed = try AES.GCM.seal(input, using: key)
            guard let combined = sealed.combined else {
              throw NSError(domain: "smart_local_storage", code: 1,
                            userInfo: [NSLocalizedDescriptionKey: "Could not seal data."])
            }
            output = combined
          } else {
            let box = try AES.GCM.SealedBox(combined: input)
            output = try AES.GCM.open(box, using: key)
          }
          DispatchQueue.main.async { result(FlutterStandardTypedData(bytes: output)) }
        } catch {
          DispatchQueue.main.async {
            result(FlutterError(code: "crypto_failed", message: error.localizedDescription, details: nil))
          }
        }
      }
    default:
      result(FlutterMethodNotImplemented)
    }
  }

  // MARK: - Keychain

  private func symmetricKey() throws -> SymmetricKey {
    let query: [String: Any] = [
      kSecClass as String: kSecClassGenericPassword,
      kSecAttrAccount as String: SmartLocalStoragePlugin.keyTag,
      kSecReturnData as String: true,
      kSecMatchLimit as String: kSecMatchLimitOne,
    ]
    var item: CFTypeRef?
    let status = SecItemCopyMatching(query as CFDictionary, &item)
    if status == errSecSuccess, let data = item as? Data {
      return SymmetricKey(data: data)
    }

    let key = SymmetricKey(size: .bits256)
    let keyData = key.withUnsafeBytes { Data($0) }
    let add: [String: Any] = [
      kSecClass as String: kSecClassGenericPassword,
      kSecAttrAccount as String: SmartLocalStoragePlugin.keyTag,
      kSecValueData as String: keyData,
      kSecAttrAccessible as String: kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly,
    ]
    let addStatus = SecItemAdd(add as CFDictionary, nil)
    guard addStatus == errSecSuccess else {
      throw NSError(domain: NSOSStatusErrorDomain, code: Int(addStatus),
                    userInfo: [NSLocalizedDescriptionKey: "Keychain error \(addStatus)"])
    }
    return key
  }
}
