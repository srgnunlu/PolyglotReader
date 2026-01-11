import Foundation
import Security

/// Secure Keychain wrapper for storing sensitive data.
final class KeychainService {
    /// Shared singleton instance.
    static let shared = KeychainService()

    /// Access control options for Keychain items.
    enum AccessControl {
        case none
        case userPresence
        case biometryCurrentSet
    }

    /// Keychain operation errors.
    enum KeychainError: LocalizedError {
        case itemNotFound
        case accessDenied
        case invalidData
        case unexpectedStatus(OSStatus)

        var errorDescription: String? {
            switch self {
            case .itemNotFound:
                return "Keychain item not found."
            case .accessDenied:
                return "Keychain access denied."
            case .invalidData:
                return "Keychain data is invalid."
            case .unexpectedStatus(let status):
                return "Keychain error: \(status)"
            }
        }
    }

    private let service: String
    private let accessGroup: String?

    private init(
        service: String = Bundle.main.bundleIdentifier ?? "PolyglotReader",
        accessGroup: String? = nil
    ) {
        self.service = service
        self.accessGroup = accessGroup
    }

    /// Stores data in the Keychain for the given key.
    func store(_ data: Data, for key: String, accessControl: AccessControl) throws {
        if accessControl == .none {
            _ = SecItemDelete(baseQuery(for: key) as CFDictionary)
        }

        var query = baseQuery(for: key)
        query[kSecValueData as String] = data

        if let accessControl = accessControlObject(for: accessControl) {
            query[kSecAttrAccessControl as String] = accessControl
        } else {
            query[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
        }

        let status = SecItemAdd(query as CFDictionary, nil)
        if status == errSecDuplicateItem {
            let updateStatus = SecItemUpdate(
                baseQuery(for: key) as CFDictionary,
                [kSecValueData as String: data] as CFDictionary
            )

            if updateStatus != errSecSuccess {
                _ = SecItemDelete(baseQuery(for: key) as CFDictionary)
                let retryStatus = SecItemAdd(query as CFDictionary, nil)
                guard retryStatus == errSecSuccess else {
                    throw KeychainError.unexpectedStatus(retryStatus)
                }
            }
            return
        }

        guard status == errSecSuccess else {
            throw KeychainError.unexpectedStatus(status)
        }
    }

    /// Stores a UTF-8 string in the Keychain for the given key.
    func storeString(_ value: String, for key: String, accessControl: AccessControl) throws {
        guard let data = value.data(using: .utf8) else {
            throw KeychainError.invalidData
        }
        try store(data, for: key, accessControl: accessControl)
    }

    /// Reads data from the Keychain for the given key.
    func readData(for key: String, prompt: String? = nil) throws -> Data {
        var query = baseQuery(for: key)
        query[kSecReturnData as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne

        _ = prompt

        var item: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &item)

        switch status {
        case errSecSuccess:
            guard let data = item as? Data else {
                throw KeychainError.invalidData
            }
            return data
        case errSecItemNotFound:
            throw KeychainError.itemNotFound
        case errSecInteractionNotAllowed, errSecAuthFailed:
            throw KeychainError.accessDenied
        default:
            throw KeychainError.unexpectedStatus(status)
        }
    }

    /// Reads a UTF-8 string from the Keychain for the given key.
    func readString(for key: String, prompt: String? = nil) throws -> String {
        let data = try readData(for: key, prompt: prompt)
        guard let value = String(data: data, encoding: .utf8) else {
            throw KeychainError.invalidData
        }
        return value
    }

    /// Deletes a Keychain item for the given key.
    func delete(_ key: String) throws {
        let status = SecItemDelete(baseQuery(for: key) as CFDictionary)
        guard status == errSecSuccess || status == errSecItemNotFound else {
            throw KeychainError.unexpectedStatus(status)
        }
    }

    /// Clears all Keychain items for the service.
    func clearAll() throws {
        let status = SecItemDelete(baseServiceQuery() as CFDictionary)
        guard status == errSecSuccess || status == errSecItemNotFound else {
            throw KeychainError.unexpectedStatus(status)
        }
    }

    private func baseQuery(for key: String) -> [String: Any] {
        var query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: key
        ]

        if let accessGroup = accessGroup {
            query[kSecAttrAccessGroup as String] = accessGroup
        }

        return query
    }

    private func baseServiceQuery() -> [String: Any] {
        var query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service
        ]

        if let accessGroup = accessGroup {
            query[kSecAttrAccessGroup as String] = accessGroup
        }

        return query
    }

    private func accessControlObject(for accessControl: AccessControl) -> SecAccessControl? {
        let flags: SecAccessControlCreateFlags

        switch accessControl {
        case .none:
            return nil
        case .userPresence:
            flags = [.userPresence]
        case .biometryCurrentSet:
            flags = [.biometryCurrentSet]
        }

        return SecAccessControlCreateWithFlags(
            nil,
            kSecAttrAccessibleWhenUnlockedThisDeviceOnly,
            flags,
            nil
        )
    }
}
