import Foundation
import Security

enum KeyStore {
    static let typeSafe = "typesafe-api-key"
    static let planner = "openrouter-api-key"

    private static func query(_ account: String) -> [String: Any] {
        [kSecClass as String: kSecClassGenericPassword,
         kSecAttrService as String: "local.lyra",
         kSecAttrAccount as String: account]
    }

    static func read(_ account: String = typeSafe) throws -> String? {
        var request = query(account)
        request[kSecReturnData as String] = true
        request[kSecMatchLimit as String] = kSecMatchLimitOne
        var result: CFTypeRef?
        let status = SecItemCopyMatching(request as CFDictionary, &result)
        if status == errSecItemNotFound { return nil }
        guard status == errSecSuccess, let data = result as? Data,
              let key = String(data: data, encoding: .utf8) else { throw failure(status) }
        return key
    }

    static func save(_ key: String, account: String = typeSafe) throws {
        let key = key.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !key.isEmpty else { throw DesktopError(message: "Enter an API key.") }
        let attributes = [kSecValueData as String: Data(key.utf8)]
        let result = SecItemUpdate(query(account) as CFDictionary, attributes as CFDictionary)
        if result == errSecItemNotFound {
            var item = query(account)
            item.merge(attributes) { _, new in new }
            let added = SecItemAdd(item as CFDictionary, nil)
            guard added == errSecSuccess else { throw failure(added) }
        } else if result != errSecSuccess { throw failure(result) }
    }

    private static func failure(_ status: OSStatus) -> DesktopError {
        DesktopError(message: "Keychain: \(SecCopyErrorMessageString(status, nil) as String? ?? "error \(status)")")
    }
}
