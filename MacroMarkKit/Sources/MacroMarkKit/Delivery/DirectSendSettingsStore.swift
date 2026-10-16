import Foundation
import Security
import CryptoKit

/// Versioned entries keep queued captures tied to the destination chosen at capture.
public struct DirectSendSettingsStore: Sendable {
    private let service: String
    private let readOverride: (@Sendable (String) throws -> Data?)?
    private let writeOverride: (@Sendable (Data, String) throws -> Void)?

    public init(service: String = "com.danfakkeldy.macromark.direct-send") {
        self.service = service
        readOverride = nil
        writeOverride = nil
    }

    init(read: @escaping @Sendable (String) throws -> Data?, write: @escaping @Sendable (Data, String) throws -> Void) {
        service = "fixture"
        readOverride = read
        writeOverride = write
    }

    public func current() throws -> DirectSendConfiguration? { try read(account: "current") }

    public func configuration(id: UUID) throws -> DirectSendConfiguration? {
        try read(account: "configuration:\(id.uuidString)")
    }

    public func deliveryConfiguration(id: UUID) throws -> DirectSendConfiguration? {
        guard var configuration = try configuration(id: id) else { return nil }
        for account in try credentialAccounts(configuration) {
            configuration = configuration.refreshingCredentials(from: try read(account: account))
        }
        return configuration
    }

    public func save(_ configuration: DirectSendConfiguration) throws {
        try configuration.validate()
        if let current = try current(), current.sourceID == configuration.sourceID,
           current.revision > configuration.revision {
            throw DirectSendError.invalidConfiguration("A newer Direct Send setup is already saved.")
        }
        if let existing = try self.configuration(id: configuration.id), existing != configuration {
            throw DirectSendError.invalidConfiguration("Create a new setup version when changing a destination.")
        }
        let data = try JSONEncoder().encode(configuration)
        guard data.count <= 64 * 1024 else {
            throw DirectSendError.invalidConfiguration("Direct Send setup is too large to transfer safely to the watch.")
        }
        try write(data, account: "configuration:\(configuration.id.uuidString)")
        for account in try credentialAccounts(configuration) {
            if let saved = try read(account: account), saved.sourceID == configuration.sourceID,
               saved.revision > configuration.revision { continue }
            try write(data, account: account)
        }
        try write(data, account: "current")
    }

    private func credentialAccounts(_ configuration: DirectSendConfiguration) throws -> [String] {
        let encoder = JSONEncoder()
        encoder.outputFormatting = .sortedKeys
        var keys: [String] = []
        if let github = configuration.github {
            let identity = try encoder.encode(["github", github.owner, github.repository, github.branch, github.folder])
            keys.append("credentials:" + SHA256.hash(data: identity).map { String(format: "%02x", $0) }.joined())
        }
        if let webhook = configuration.webhook {
            let authNames: Set<String> = ["authorization", "x-api-key", "api-key", "x-webhook-key"]
            let nonAuth = Dictionary(webhook.headers.filter { !authNames.contains($0.key.lowercased()) }
                .map { ($0.key.lowercased(), $0.value) }, uniquingKeysWith: { _, new in new })
            struct Identity: Encodable { let type = "webhook"; let url: URL; let headers: [String: String] }
            let identity = try encoder.encode(Identity(url: webhook.url, headers: nonAuth))
            keys.append("credentials:" + SHA256.hash(data: identity).map { String(format: "%02x", $0) }.joined())
        }
        return keys
    }

    private func query(account: String) -> [String: Any] {
        [kSecClass as String: kSecClassGenericPassword,
         kSecAttrService as String: service, kSecAttrAccount as String: account,
         kSecAttrSynchronizable as String: false]
    }

    private func read(account: String) throws -> DirectSendConfiguration? {
        guard let data = try readData(account: account) else { return nil }
        let configuration = try JSONDecoder().decode(DirectSendConfiguration.self, from: data)
        try configuration.validate()
        return configuration
    }

    private func readData(account: String) throws -> Data? {
        if let readOverride { return try readOverride(account) }
        var query = query(account: account)
        query[kSecReturnData as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne
        var item: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &item)
        if status == errSecItemNotFound { return nil }
        guard status == errSecSuccess, let data = item as? Data else { throw DirectSendError.credentialStorage }
        return data
    }

    private func write(_ data: Data, account: String) throws {
        if let writeOverride { try writeOverride(data, account); return }
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
