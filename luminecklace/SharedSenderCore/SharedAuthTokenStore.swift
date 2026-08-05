import Foundation
import Security

nonisolated protocol KeychainOperating: Sendable {
    func copyMatching(_ query: CFDictionary) -> (status: OSStatus, data: Data?)
    func add(_ attributes: CFDictionary) -> OSStatus
    func update(_ query: CFDictionary, attributes: CFDictionary) -> OSStatus
    func delete(_ query: CFDictionary) -> OSStatus
}

nonisolated struct SystemKeychain: KeychainOperating {
    func copyMatching(_ query: CFDictionary) -> (status: OSStatus, data: Data?) {
        var result: CFTypeRef?
        let status = SecItemCopyMatching(query, &result)
        return (status, result as? Data)
    }

    func add(_ attributes: CFDictionary) -> OSStatus {
        SecItemAdd(attributes, nil)
    }

    func update(_ query: CFDictionary, attributes: CFDictionary) -> OSStatus {
        SecItemUpdate(query, attributes)
    }

    func delete(_ query: CFDictionary) -> OSStatus {
        SecItemDelete(query)
    }
}

nonisolated enum SharedAuthTokenStoreError: LocalizedError, Equatable {
    case invalidTokenData
    case unexpectedStatus(OSStatus)

    var errorDescription: String? {
        switch self {
        case .invalidTokenData:
            "The saved Lumi session could not be read."
        case let .unexpectedStatus(status):
            "Lumi could not access the shared session (Keychain status \(status))."
        }
    }
}

/// Stores sender credentials in the Keychain access group shared by the full app
/// and Share Extension. The App Clip does not compile or entitle this module.
nonisolated final class SharedAuthTokenStore: @unchecked Sendable {
    static let shared = SharedAuthTokenStore()

    static var accessGroup: String {
        if let configured = Bundle.main.object(forInfoDictionaryKey: "LUMIKeychainAccessGroup") as? String,
           !configured.isEmpty,
           !configured.contains("$(") {
            return configured
        }
        // Development-team fallback for tests and command-line builds where the
        // generated Info.plist is not available.
        return "7HTV4A5W6Y.luminecklace.shared"
    }
    static let service = "com.luminecklace.sender-auth"
    static let account = "supabase-access-token"

    private let keychain: any KeychainOperating
    private let accessGroup: String

    init(
        keychain: any KeychainOperating = SystemKeychain(),
        accessGroup: String = SharedAuthTokenStore.accessGroup
    ) {
        self.keychain = keychain
        self.accessGroup = accessGroup
    }

    func read() throws -> String? {
        var query = baseQuery
        query[kSecReturnData as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne

        let result = keychain.copyMatching(query as CFDictionary)
        let status = result.status
        switch status {
        case errSecSuccess:
            guard let data = result.data,
                  let token = String(data: data, encoding: .utf8),
                  !token.isEmpty else {
                throw SharedAuthTokenStoreError.invalidTokenData
            }
            return token
        case errSecItemNotFound:
            return nil
        default:
            throw SharedAuthTokenStoreError.unexpectedStatus(status)
        }
    }

    func write(_ token: String) throws {
        guard !token.isEmpty, let data = token.data(using: .utf8) else {
            try delete()
            return
        }

        var attributes = baseQuery
        attributes[kSecValueData as String] = data
        attributes[kSecAttrAccessible as String] = kSecAttrAccessibleWhenUnlockedThisDeviceOnly
        attributes[kSecAttrSynchronizable as String] = kCFBooleanFalse

        let status = keychain.add(attributes as CFDictionary)
        if status == errSecDuplicateItem {
            let update: [String: Any] = [
                kSecValueData as String: data,
                kSecAttrAccessible as String: kSecAttrAccessibleWhenUnlockedThisDeviceOnly
            ]
            let updateStatus = keychain.update(baseQuery as CFDictionary, attributes: update as CFDictionary)
            guard updateStatus == errSecSuccess else {
                throw SharedAuthTokenStoreError.unexpectedStatus(updateStatus)
            }
            return
        }
        guard status == errSecSuccess else {
            throw SharedAuthTokenStoreError.unexpectedStatus(status)
        }
    }

    func delete() throws {
        let status = keychain.delete(baseQuery as CFDictionary)
        guard status == errSecSuccess || status == errSecItemNotFound else {
            throw SharedAuthTokenStoreError.unexpectedStatus(status)
        }
    }

    private var baseQuery: [String: Any] {
        [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: Self.service,
            kSecAttrAccount as String: Self.account,
            kSecAttrAccessGroup as String: accessGroup,
            kSecAttrSynchronizable as String: kCFBooleanFalse as Any
        ]
    }
}
