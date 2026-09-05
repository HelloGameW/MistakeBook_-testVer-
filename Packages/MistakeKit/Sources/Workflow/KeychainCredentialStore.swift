import Foundation
import Contracts
#if canImport(Security)
import Security
#endif

/// Stores only API secrets. Non-secret endpoint/model settings remain in AppSettings.
/// On Apple platforms this uses Keychain and marks secrets device-only.
public actor KeychainCredentialStore: CredentialStore {
    private let service: String
#if !canImport(Security)
    private var memory: [CredentialKind: String] = [:]
#endif

    public init(service: String = "MistakeBook.API.Credentials") { self.service = service }

    public func read(kind: CredentialKind) async throws -> String? {
#if canImport(Security)
        var query = baseQuery(kind: kind)
        query[kSecReturnData as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne
        var item: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &item)
        if status == errSecItemNotFound { return nil }
        guard status == errSecSuccess, let data = item as? Data,
              let value = String(data: data, encoding: .utf8) else { throw AppError(code: .internalFailure) }
        return value
#else
        return memory[kind]
#endif
    }

    public func write(kind: CredentialKind, value: String) async throws {
        let normalized = value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !normalized.isEmpty else { try await remove(kind: kind); return }
#if canImport(Security)
        let data = Data(normalized.utf8)
        let query = baseQuery(kind: kind)
        let update: [String: Any] = [kSecValueData as String: data,
                                     kSecAttrAccessible as String: kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly]
        let updateStatus = SecItemUpdate(query as CFDictionary, update as CFDictionary)
        if updateStatus == errSecSuccess { return }
        guard updateStatus == errSecItemNotFound else { throw AppError(code: .internalFailure) }
        var add = query
        add[kSecValueData as String] = data
        add[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
        guard SecItemAdd(add as CFDictionary, nil) == errSecSuccess else { throw AppError(code: .internalFailure) }
#else
        memory[kind] = normalized
#endif
    }

    public func remove(kind: CredentialKind) async throws {
#if canImport(Security)
        let status = SecItemDelete(baseQuery(kind: kind) as CFDictionary)
        guard status == errSecSuccess || status == errSecItemNotFound else { throw AppError(code: .internalFailure) }
#else
        memory.removeValue(forKey: kind)
#endif
    }

    public func removeAll() async throws {
        for kind in CredentialKind.allCases { try await remove(kind: kind) }
    }

    public func status() async throws -> CredentialStatus {
        var configured: [CredentialKind] = []
        for kind in CredentialKind.allCases {
            if let value = try await read(kind: kind), !value.isEmpty { configured.append(kind) }
        }
        return CredentialStatus(configured: configured)
    }

#if canImport(Security)
    private func baseQuery(kind: CredentialKind) -> [String: Any] {
        [kSecClass as String: kSecClassGenericPassword,
         kSecAttrService as String: service,
         kSecAttrAccount as String: kind.rawValue]
    }
#endif
}
