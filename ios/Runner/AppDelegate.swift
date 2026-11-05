import Flutter
import UIKit
import Security

@main
@objc class AppDelegate: FlutterAppDelegate, FlutterImplicitEngineDelegate {
  private var apiKeyChannel: FlutterMethodChannel?
  override func application(
    _ application: UIApplication,
    didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
  ) -> Bool {
    return super.application(application, didFinishLaunchingWithOptions: launchOptions)
  }

  func didInitializeImplicitFlutterEngine(_ engineBridge: FlutterImplicitEngineBridge) {
    GeneratedPluginRegistrant.register(with: engineBridge.pluginRegistry)
    guard let registrar = engineBridge.pluginRegistry.registrar(forPlugin: "MarineApiKeyStore") else { return }
    let channel = FlutterMethodChannel(name: "marine_voice_translator/api_key", binaryMessenger: registrar.messenger())
    apiKeyChannel = channel
    channel.setMethodCallHandler { call, result in
      let query: [String: Any] = [
        kSecClass as String: kSecClassGenericPassword,
        kSecAttrService as String: (Bundle.main.bundleIdentifier ?? "marine_voice_translator") + ".doubao",
        kSecAttrAccount as String: call.method.hasSuffix("Ark") ? "ark-api-key" : "ast-api-key"
      ]
      switch call.method {
      case "read", "readArk":
        var request = query
        request[kSecReturnData as String] = true
        request[kSecMatchLimit as String] = kSecMatchLimitOne
        var item: CFTypeRef?
        let status = SecItemCopyMatching(request as CFDictionary, &item)
        if status == errSecItemNotFound { result(nil); return }
        guard status == errSecSuccess, let data = item as? Data,
              let value = String(data: data, encoding: .utf8) else {
          result(FlutterError(code: "KEYCHAIN_READ", message: "无法读取密钥，请解锁手机后重试。", details: nil)); return
        }
        result(value)
      case "save", "saveArk":
        guard let value = call.arguments as? String, !value.isEmpty,
              value.utf8.count <= 4096,
              value.rangeOfCharacter(from: .controlCharacters) == nil,
              let data = value.data(using: .utf8) else {
          result(FlutterError(code: "INVALID_KEY", message: "请输入有效的 API Key。", details: nil)); return
        }
        let attributes: [String: Any] = [
          kSecValueData as String: data,
          kSecAttrAccessible as String: kSecAttrAccessibleWhenUnlockedThisDeviceOnly
        ]
        var status = SecItemUpdate(query as CFDictionary, attributes as CFDictionary)
        if status == errSecItemNotFound {
          var entry = query
          attributes.forEach { entry[$0.key] = $0.value }
          status = SecItemAdd(entry as CFDictionary, nil)
        }
        guard status == errSecSuccess else {
          result(FlutterError(code: "KEYCHAIN_SAVE", message: "无法保存密钥，请解锁手机后重试。", details: nil)); return
        }
        result(nil)
      case "delete", "deleteArk":
        let status = SecItemDelete(query as CFDictionary)
        guard status == errSecSuccess || status == errSecItemNotFound else {
          result(FlutterError(code: "KEYCHAIN_DELETE", message: "无法删除密钥，请重试。", details: nil)); return
        }
        result(nil)
      default: result(FlutterMethodNotImplemented)
      }
    }
  }
}
