import Foundation
import Security

enum Credentials {
    private static let service = "com.lanceroberts.LGClimate"
    private static let account = "lg-thinq-pat"
    private static var query: [String: Any] {
        [kSecClass as String: kSecClassGenericPassword,
         kSecAttrService as String: service,
         kSecAttrAccount as String: account]
    }

    static func load() throws -> ThinQConfiguration? {
        var request = query
        request[kSecReturnData as String] = true
        request[kSecMatchLimit as String] = kSecMatchLimitOne
        var item: CFTypeRef?
        let status = SecItemCopyMatching(request as CFDictionary, &item)
        if status == errSecItemNotFound { return nil }
        guard status == errSecSuccess, let data = item as? Data else { throw KeychainError(status) }
        return try JSONDecoder().decode(ThinQConfiguration.self, from: data)
    }

    static func save(_ value: ThinQConfiguration) throws {
        let data = try JSONEncoder().encode(value)
        let status = SecItemUpdate(query as CFDictionary, [kSecValueData as String: data] as CFDictionary)
        if status == errSecItemNotFound {
            var request = query
            request[kSecValueData as String] = data
            request[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
            let result = SecItemAdd(request as CFDictionary, nil)
            guard result == errSecSuccess else { throw KeychainError(result) }
        } else if status != errSecSuccess { throw KeychainError(status) }
    }

    static func delete() throws { SecItemDelete(query as CFDictionary) }
    private struct KeychainError: LocalizedError {
        let status: OSStatus
        init(_ status: OSStatus) { self.status = status }
        var errorDescription: String? { SecCopyErrorMessageString(status, nil) as String? ?? "Could not access Keychain." }
    }
}
