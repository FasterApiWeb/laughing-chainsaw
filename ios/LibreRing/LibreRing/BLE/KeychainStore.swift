import Foundation
import Security

struct KeychainStore {
    private let servicePrefix = "com.librering.authkey"

    func saveAuthKey(_ key: Data, for ringID: String) {
        let account = "\(servicePrefix).\(ringID)"
        delete(account: account)

        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrAccount as String: account,
            kSecAttrService as String: servicePrefix,
            kSecValueData as String: key,
            kSecAttrAccessible as String: kSecAttrAccessibleAfterFirstUnlock,
        ]

        SecItemAdd(query as CFDictionary, nil)
    }

    func loadAuthKey(for ringID: String) -> Data? {
        let account = "\(servicePrefix).\(ringID)"
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrAccount as String: account,
            kSecAttrService as String: servicePrefix,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne,
        ]

        var result: AnyObject?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        guard status == errSecSuccess else { return nil }
        return result as? Data
    }

    func deleteAuthKey(for ringID: String) {
        delete(account: "\(servicePrefix).\(ringID)")
    }

    private func delete(account: String) {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrAccount as String: account,
            kSecAttrService as String: servicePrefix,
        ]
        SecItemDelete(query as CFDictionary)
    }
}
