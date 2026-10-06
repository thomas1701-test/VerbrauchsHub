import Foundation
import Security

/// A boolean kept in the keychain. Unlike UserDefaults it survives deleting
/// and reinstalling the app, so a recognised existing customer stays unlocked
/// even when StoreKit cannot be reached.
enum KeychainFlag {
    private static let service = Bundle.main.bundleIdentifier ?? "net.gmx.dillmann.VerbrauchsHub"

    static func isSet(_ key: String) -> Bool {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: key,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne,
        ]
        var result: AnyObject?
        guard SecItemCopyMatching(query as CFDictionary, &result) == errSecSuccess,
              let data = result as? Data else { return false }
        return data == Data([1])
    }

    static func set(_ key: String) {
        let match: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: key,
        ]
        let value: [String: Any] = [
            kSecValueData as String: Data([1]),
            kSecAttrAccessible as String: kSecAttrAccessibleAfterFirstUnlock,
        ]
        if SecItemUpdate(match as CFDictionary, value as CFDictionary) == errSecItemNotFound {
            SecItemAdd(match.merging(value) { $1 } as CFDictionary, nil)
        }
    }
}
