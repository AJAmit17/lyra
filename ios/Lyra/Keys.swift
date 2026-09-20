import Foundation
import Security

/// API keys, in the iPhone's Keychain. Never in UserDefaults, never in the app bundle.
enum Keys {
    static let typeSafe = "typesafe-api-key"
    static let openRouter = "openrouter-api-key"

    private static func query(_ account: String) -> [String: Any] {
        [kSecClass as String: kSecClassGenericPassword,
         kSecAttrService as String: "local.lyra",
         kSecAttrAccount as String: account]
    }

    static func read(_ account: String) -> String? {
        var request = query(account)
        request[kSecReturnData as String] = true
        request[kSecMatchLimit as String] = kSecMatchLimitOne
        var result: CFTypeRef?
        guard SecItemCopyMatching(request as CFDictionary, &result) == errSecSuccess,
              let data = result as? Data else { return nil }
        return String(data: data, encoding: .utf8)
    }

    static func save(_ value: String, account: String) {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        let attributes = [kSecValueData as String: Data(trimmed.utf8)]
        if SecItemUpdate(query(account) as CFDictionary, attributes as CFDictionary) == errSecItemNotFound {
            var item = query(account)
            item.merge(attributes) { _, new in new }
            SecItemAdd(item as CFDictionary, nil)
        }
    }
}
