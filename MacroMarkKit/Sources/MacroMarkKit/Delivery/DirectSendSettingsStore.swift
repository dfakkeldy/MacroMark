import Foundation
import Security
import CryptoKit

/// A setup snapshot. Credential repairs travel independently from the latest settings context.
public struct DirectSendSetupDelivery: Codable, Equatable, Sendable {
    public let current: DirectSendConfiguration
    public let repairs: [DirectSendConfiguration]

    public init(current: DirectSendConfiguration, repairs: [DirectSendConfiguration]) {
        self.current = current
        self.repairs = repairs
    }

    public static func decode(from data: Data) throws -> DirectSendSetupDelivery {
        let decoder = JSONDecoder()
        if let delivery = try? decoder.decode(DirectSendSetupDelivery.self, from: data) {
            return delivery
        }
        return DirectSendSetupDelivery(current: try decoder.decode(DirectSendConfiguration.self, from: data), repairs: [])
    }
}

/// Versioned entries keep queued captures tied to the destination chosen at capture.
public struct DirectSendSettingsStore: Sendable {
    private struct CredentialRecord: Codable {
        let configuration: DirectSendConfiguration
    }

    private struct WriterState: Codable {
        let sourceID: UUID
        let revision: UInt64
    }

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

    /// Reserve before writing setup so a failed save cannot reuse an earlier revision.
    public func makeConfiguration(mode: WatchDeliveryMode, github: GitHubDestination? = nil,
                                  webhook: WebhookDestination? = nil) throws -> DirectSendConfiguration {
        try DirectSendConfiguration(mode: mode, github: github, webhook: webhook).validate()
        let writer = try reserveRevision()
        return DirectSendConfiguration(revision: writer.revision, sourceID: writer.sourceID,
            mode: mode, github: github, webhook: webhook)
    }

    public func configuration(id: UUID) throws -> DirectSendConfiguration? {
        try read(account: "configuration:\(id.uuidString)")
    }

    public func deliveryConfiguration(id: UUID) throws -> DirectSendConfiguration? {
        guard var configuration = try configuration(id: id) else { return nil }
        for account in try credentialAccounts(configuration) {
            configuration = configuration.refreshingCredentials(from: try credentialConfiguration(account: account))
        }
        return configuration
    }

    public func pendingCredentialRepairs() throws -> [DirectSendConfiguration] {
        var pending: [DirectSendConfiguration] = []
        for account in try credentialAccountNames() {
            guard let data = try readData(account: account),
                  var configuration = try credentialConfiguration(account: account) else { continue }
            if (try? JSONDecoder().decode(CredentialRecord.self, from: data)) == nil {
                // Legacy accounts contain whole setups, sometimes with equal revisions after a failed save.
                // Their per-account value is authoritative; project it and give the repair a fresh order.
                let writer = try reserveRevision(minimum: configuration.revision)
                configuration = DirectSendConfiguration(revision: writer.revision, sourceID: writer.sourceID,
                    mode: configuration.mode, github: configuration.github, webhook: configuration.webhook)
                try write(try JSONEncoder().encode(CredentialRecord(configuration: configuration)), account: account)
            }
            let identifier = Self.credentialRepairIdentifier(configuration)
            if try readData(account: "credential-ack:\(account)") != Data(identifier.utf8) {
                pending.append(configuration)
            }
        }
        return pending
    }

    public static func credentialRepairIdentifier(_ configuration: DirectSendConfiguration) -> String {
        "\(configuration.id.uuidString):\(configuration.github != nil ? "github" : "webhook")"
    }

    public func acknowledgeCredentialRepair(_ identifier: String) throws {
        for account in try credentialAccountNames() {
            guard let configuration = try credentialConfiguration(account: account),
                  Self.credentialRepairIdentifier(configuration) == identifier else { continue }
            try write(Data(identifier.utf8), account: "credential-ack:\(account)")
        }
    }

    @discardableResult
    public func apply(_ delivery: DirectSendSetupDelivery) throws -> DirectSendConfiguration {
        let repairs = delivery.repairs.sorted { lhs, rhs in
            lhs.revision == rhs.revision ? lhs.id.uuidString < rhs.id.uuidString : lhs.revision < rhs.revision
        }
        for repair in repairs { try applyCredentialRepair(repair) }
        if let saved = try current(), saved.sourceID == delivery.current.sourceID,
           saved.revision > delivery.current.revision { return saved }
        try save(delivery.current)
        return delivery.current
    }

    public func applyCredentialRepair(_ configuration: DirectSendConfiguration) throws {
        try configuration.validate()
        guard configuration.destinations.count == 1,
              try JSONEncoder().encode(configuration).count <= 64 * 1024 else {
            throw DirectSendError.invalidConfiguration("Direct Send setup is too large to transfer safely to the watch.")
        }
        for account in try credentialAccounts(configuration) {
            if let saved = try credentialConfiguration(account: account), saved.sourceID == configuration.sourceID,
               saved.revision >= configuration.revision { continue }
            try write(try JSONEncoder().encode(CredentialRecord(configuration: configuration)), account: account)
        }
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
        let accounts = try credentialAccounts(configuration)
        for account in accounts {
            if let saved = try credentialConfiguration(account: account), saved.sourceID == configuration.sourceID,
               saved.revision > configuration.revision { continue }
            let projected = try project(configuration, onto: account)
            try write(try JSONEncoder().encode(CredentialRecord(configuration: projected)), account: account)
        }
        try updateCredentialIndex(accounts)
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

    private func credentialConfiguration(account: String) throws -> DirectSendConfiguration? {
        guard let data = try readData(account: account) else { return nil }
        let decoder = JSONDecoder()
        let configuration: DirectSendConfiguration
        if let record = try? decoder.decode(CredentialRecord.self, from: data) {
            configuration = record.configuration
        } else {
            configuration = try decoder.decode(DirectSendConfiguration.self, from: data)
        }
        try configuration.validate()
        return try project(configuration, onto: account)
    }

    private func project(_ configuration: DirectSendConfiguration, onto account: String) throws -> DirectSendConfiguration {
        for destination in configuration.destinations {
            let projected = DirectSendConfiguration(id: configuration.id, configuredAt: configuration.configuredAt,
                revision: configuration.revision, sourceID: configuration.sourceID, mode: configuration.mode,
                github: destination == .github ? configuration.github : nil,
                webhook: destination == .webhook ? configuration.webhook : nil)
            if try credentialAccounts(projected) == [account] { return projected }
        }
        throw DirectSendError.credentialStorage
    }

    private func reserveRevision(minimum: UInt64 = 0) throws -> WriterState {
        let current = try current()
        let stored = try readData(account: "writer-state").map { try JSONDecoder().decode(WriterState.self, from: $0) }
        let sourceID = stored?.sourceID ?? current?.sourceID ?? UUID()
        var revision = max(stored?.revision ?? 0, minimum)
        if current?.sourceID == sourceID { revision = max(revision, current?.revision ?? 0) }
        for account in try credentialAccountNames() {
            if let credential = try credentialConfiguration(account: account), credential.sourceID == sourceID {
                revision = max(revision, credential.revision)
            }
        }
        guard revision < UInt64.max else { throw DirectSendError.credentialStorage }
        let next = WriterState(sourceID: sourceID, revision: revision + 1)
        try write(try JSONEncoder().encode(next), account: "writer-state")
        return next
    }

    private func credentialAccountNames() throws -> [String] {
        var names = try readIndex()
        if readOverride == nil, let listed = try? listKeychainCredentialAccounts() {
            for name in listed where !names.contains(name) { names.append(name) }
        }
        return names
    }

    private func readIndex() throws -> [String] {
        guard let data = try readData(account: "credential-index") else { return [] }
        return try JSONDecoder().decode([String].self, from: data)
    }

    private func updateCredentialIndex(_ accounts: [String]) throws {
        var names = try readIndex()
        let count = names.count
        for account in accounts where !names.contains(account) { names.append(account) }
        guard names.count != count else { return }
        try write(try JSONEncoder().encode(names), account: "credential-index")
    }

    private func listKeychainCredentialAccounts() throws -> [String] {
        let query: [String: Any] = [kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service, kSecAttrSynchronizable as String: false,
            kSecMatchLimit as String: kSecMatchLimitAll, kSecReturnAttributes as String: true]
        var item: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &item)
        if status == errSecItemNotFound { return [] }
        guard status == errSecSuccess, let items = item as? [[String: Any]] else { throw DirectSendError.credentialStorage }
        return items.compactMap { $0[kSecAttrAccount as String] as? String }.filter { $0.hasPrefix("credentials:") }
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
