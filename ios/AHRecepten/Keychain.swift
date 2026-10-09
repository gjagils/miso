import Foundation
import Security

/// Kleine wrapper rond de Keychain voor één geheim per sleutel.
///
/// Gebruikt een gedeelde keychain-groep (entitlement `keychain-access-groups`), zodat de app en de
/// deel-extensie hetzelfde login-token lezen. De volledige groepsnaam (met team-prefix) staat in de
/// Info.plist onder `MisoKeychainGroup`.
enum Keychain {
    private static let service = "nl.gerdjan.ahrecepten"

    private static var accessGroup: String? {
        Bundle.main.object(forInfoDictionaryKey: "MisoKeychainGroup") as? String
    }

    private static func baseQuery(_ key: String) -> [String: Any] {
        var query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: key,
        ]
        if let accessGroup, !accessGroup.isEmpty { query[kSecAttrAccessGroup as String] = accessGroup }
        return query
    }

    static func string(for key: String) -> String? {
        var query = baseQuery(key)
        query[kSecReturnData as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne
        var result: AnyObject?
        guard SecItemCopyMatching(query as CFDictionary, &result) == errSecSuccess,
              let data = result as? Data else { return nil }
        return String(decoding: data, as: UTF8.self)
    }

    /// Slaat de waarde op (lege string = verwijderen). Geeft `true` terug als het gelukt is.
    @discardableResult
    static func set(_ value: String, for key: String) -> Bool {
        let query = baseQuery(key)
        guard !value.isEmpty else {
            let status = SecItemDelete(query as CFDictionary)
            return status == errSecSuccess || status == errSecItemNotFound
        }
        let data = Data(value.utf8)
        let update: [String: Any] = [kSecValueData as String: data]
        let status = SecItemUpdate(query as CFDictionary, update as CFDictionary)
        if status == errSecSuccess { return true }
        guard status == errSecItemNotFound else { return false }
        var add = query
        add[kSecValueData as String] = data
        // Leesbaar voor app en extensie zodra het toestel na een herstart één keer ontgrendeld is.
        add[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlock
        return SecItemAdd(add as CFDictionary, nil) == errSecSuccess
    }
}
