import Foundation
import Security

/// Versioned entries keep queued captures tied to the destination chosen at capture.
public struct DirectSendSettingsStore: Sendable {
    private let service: String

    public init(service: String = "com.danfakkeldy.macromark.direct-send") { self.service = service }

    public func current() throws -> DirectSendConfiguration? { try read(account: "current") }

    public func configuration(id: UUID) throws -> DirectSendConfiguration? {
        try read(account: "configuration:\(id.uuidString)")
    }

    public func save(_ configuration: DirectSendConfiguration) throws {
        try configuration.validate()
        if let existing = try self.configuration(id: configuration.id), existing != configuration {
            throw DirectSendError.invalidConfiguration("Create a new setup version when changing a destination.")
        }
        let data = try JSONEncoder().encode(configuration)
        guard data.count <= 64 * 1024 else {
            throw DirectSendError.invalidConfiguration("Direct Send setup is too large to transfer safely to the watch.")
        }
        try write(data, account: "configuration:\(configuration.id.uuidString)")
        try write(data, account: "current")
    }

    private func query(account: String) -> [String: Any] {
        [kSecClass as String: kSecClassGenericPassword,
         kSecAttrService as String: service, kSecAttrAccount as String: account,
         kSecAttrSynchronizable as String: false]
    }

    private func read(account: String) throws -> DirectSendConfiguration? {
        var query = query(account: account)
        query[kSecReturnData as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne
        var item: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &item)
        if status == errSecItemNotFound { return nil }
        guard status == errSecSuccess, let data = item as? Data else { throw DirectSendError.credentialStorage }
        let configuration = try JSONDecoder().decode(DirectSendConfiguration.self, from: data)
        try configuration.validate()
        return configuration
    }

    private func write(_ data: Data, account: String) throws {
        let query = query(account: account)
        let attributes: [String: Any] = [kSecValueData as String: data,
            kSecAttrAccessible as String: kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly]
        let status = SecItemUpdate(query as CFDictionary, attributes as CFDictionary)
        if status == errSecItemNotFound {
            let added = SecItemAdd(query.merging(attributes) { _, new in new } as CFDictionary, nil)
            guard added == errSecSuccess else { throw DirectSendError.credentialStorage }
        } else if status != errSecSuccess {
            throw DirectSendError.credentialStorage
        }
    }
}
