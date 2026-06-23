import Foundation
import Security

enum KeychainService {
    private static var service: String {
        Bundle.main.bundleIdentifier ?? "com.crypto.Mesh"
    }

    static func save(_ data: Data, account: String) -> Bool {
        let query = baseQuery(account: account).merging([
            kSecValueData as String: data,
            kSecAttrAccessible as String: kSecAttrAccessibleWhenUnlockedThisDeviceOnly
        ]) { _, new in new }
        SecItemDelete(query as CFDictionary)
        let status = SecItemAdd(query as CFDictionary, nil)
        return status == errSecSuccess
    }

    static func load(account: String) -> Data? {
        if let data = load(account: account, service: service) {
            return data
        }
        return load(account: account, service: nil)
    }

    static func delete(account: String) -> Bool {
        let withService = delete(account: account, service: service)
        let legacy = delete(account: account, service: nil)
        return withService || legacy
    }

    private static func baseQuery(account: String, service: String? = service) -> [String: Any] {
        var query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrAccount as String: account
        ]
        if let service {
            query[kSecAttrService as String] = service
        }
        return query
    }

    private static func load(account: String, service: String?) -> Data? {
        var query = baseQuery(account: account, service: service)
        query[kSecReturnData as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne
        var item: AnyObject?
        let status = SecItemCopyMatching(query as CFDictionary, &item)
        guard status == errSecSuccess else { return nil }
        return item as? Data
    }

    private static func delete(account: String, service: String?) -> Bool {
        let status = SecItemDelete(baseQuery(account: account, service: service) as CFDictionary)
        return status == errSecSuccess || status == errSecItemNotFound
    }
}
