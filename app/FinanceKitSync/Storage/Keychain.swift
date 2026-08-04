//
//  Keychain.swift
//  FinanceKitSync
//
//  The bearer token is the only secret this app holds. It lives here and
//  nowhere else — never in UserDefaults, never in logs.
//
import Foundation
import Security

enum Keychain {
    /// `kSecAttrService` for every item this app stores.
    private static let service = "com.asb.FinanceKitSync"

    /// Reads a value, or nil when absent or unreadable.
    static func read(_ account: String) -> String? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne
        ]
        var item: CFTypeRef?
        guard SecItemCopyMatching(query as CFDictionary, &item) == errSecSuccess,
              let data = item as? Data,
              let string = String(data: data, encoding: .utf8) else {
            return nil
        }
        return string
    }

    /// Upserts a value. Passing nil deletes the item.
    @discardableResult
    static func write(_ account: String, _ value: String?) -> Bool {
        guard let value, !value.isEmpty else {
            return delete(account)
        }
        let base: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account
        ]
        let data = Data(value.utf8)

        // Try update first; fall back to add when the item doesn't exist yet.
        let updateStatus = SecItemUpdate(
            base as CFDictionary,
            [kSecValueData as String: data] as CFDictionary
        )
        if updateStatus == errSecSuccess { return true }

        var insert = base
        insert[kSecValueData as String] = data
        // afterFirstUnlock, not whenUnlocked: a BGTask can fire while the
        // device is locked, and a token it can't read means a failed sync.
        insert[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlock
        return SecItemAdd(insert as CFDictionary, nil) == errSecSuccess
    }

    @discardableResult
    static func delete(_ account: String) -> Bool {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account
        ]
        let status = SecItemDelete(query as CFDictionary)
        return status == errSecSuccess || status == errSecItemNotFound
    }
}
