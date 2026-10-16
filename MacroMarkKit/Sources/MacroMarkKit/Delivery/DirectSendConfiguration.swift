import Foundation

public enum WatchDeliveryMode: String, Codable, CaseIterable, Sendable {
    case phone, direct
}

public enum DirectDestination: String, Codable, Hashable, CaseIterable, Sendable {
    case github, webhook
}

public enum TextDeliveryRoute: Codable, Equatable, Sendable {
    case phone
    case direct(configurationID: UUID, destinations: Set<DirectDestination>)
}

public enum DirectSendError: Error, LocalizedError, Sendable {
    case invalidConfiguration(String)
    case credentialsUnavailable
    case invalidResponse
    case tooLarge
    case conflict
    case http(Int, retryAfter: TimeInterval?)
    case authorizationDenied
    case authorizationExpired
    case credentialStorage

    public var retryAfter: TimeInterval? {
        if case let .http(_, interval) = self { return interval }
        return nil
    }

    public var errorDescription: String? {
        switch self {
        case let .invalidConfiguration(message): message
        case .credentialsUnavailable: "Reconnect this destination in Direct Send settings on your iPhone."
        case .invalidResponse: "The destination returned an invalid response. Your note is still queued."
        case .tooLarge: "The daily file is too large to update safely from the watch. Your note is still queued."
        case .conflict: "The daily file changed during delivery. Your note will retry."
        case let .http(status, _) where status == 401 || status == 403:
            "The destination refused access. Check its credentials in Direct Send settings."
        case let .http(status, _) where status == 429:
            "The destination asked MacroMark to wait. Your note will retry."
        case .http: "Delivery was not confirmed. Your note will retry."
        case .authorizationDenied: "GitHub sign-in was declined."
        case .authorizationExpired: "The GitHub sign-in code expired. Start sign-in again."
        case .credentialStorage: "Secure settings could not be saved or read. Try again after unlocking your device."
        }
    }
}

public struct GitHubDestination: Codable, Equatable, Sendable {
    public let owner: String
    public let repository: String
    public let branch: String
    public let folder: String
    public let token: String

    public init(owner: String, repository: String, branch: String = "main", folder: String = "", token: String) {
        self.owner = owner.trimmingCharacters(in: .whitespacesAndNewlines)
        self.repository = repository.trimmingCharacters(in: .whitespacesAndNewlines)
        self.branch = branch.trimmingCharacters(in: .whitespacesAndNewlines)
        self.folder = folder.trimmingCharacters(in: CharacterSet(charactersIn: "/").union(.whitespacesAndNewlines))
        self.token = token.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    public func validate() throws {
        let allowed = CharacterSet(charactersIn: "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789._-")
        for name in [owner, repository] {
            guard !name.isEmpty, name != ".", name != "..", name.unicodeScalars.allSatisfy(allowed.contains) else {
                throw DirectSendError.invalidConfiguration("Enter a GitHub owner and repository name, without a URL.")
            }
        }
        guard !branch.isEmpty, !branch.contains(where: { $0.isNewline || $0.asciiValue == 0 }) else {
            throw DirectSendError.invalidConfiguration("Enter the GitHub branch to write to.")
        }
        guard folder.split(separator: "/", omittingEmptySubsequences: false).allSatisfy({
            $0 != "." && $0 != ".." && !$0.contains(where: { $0.isNewline || $0.asciiValue == 0 })
        }) else {
            throw DirectSendError.invalidConfiguration("Use a folder inside the repository without dot or parent path components.")
        }
        guard !token.isEmpty, !token.contains(where: { $0.isNewline }) else {
            throw DirectSendError.credentialsUnavailable
        }
    }
}

public struct WebhookDestination: Codable, Equatable, Sendable {
    public let url: URL
    public let headers: [String: String]

    public init(url: URL, headers: [String: String] = [:]) {
        self.url = url
        self.headers = headers
    }

    public func validate() throws {
        guard url.scheme?.lowercased() == "https", let host = url.host, !host.isEmpty,
              url.user == nil, url.password == nil, url.fragment == nil else {
            throw DirectSendError.invalidConfiguration("Use an HTTPS webhook URL without embedded user credentials or a fragment.")
        }
        let tokenCharacters = CharacterSet(charactersIn: "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789!#$%&'*+-.^_`|~")
        let reserved: Set<String> = ["host", "content-length", "content-type", "connection", "transfer-encoding", "idempotency-key"]
        var seen: Set<String> = []
        for (name, value) in headers {
            let lower = name.lowercased()
            guard !name.isEmpty, name.unicodeScalars.allSatisfy(tokenCharacters.contains),
                  !reserved.contains(lower), seen.insert(lower).inserted,
                  !value.unicodeScalars.contains(where: { CharacterSet.controlCharacters.contains($0) }) else {
                throw DirectSendError.invalidConfiguration("Use unique HTTP headers without control characters or reserved transport headers.")
            }
        }
    }
}

/// This entire value is secret-bearing and belongs only in Keychain and the setup transfer.
public struct DirectSendConfiguration: Identifiable, Codable, Equatable, Sendable {
    public let id: UUID
    public let configuredAt: Date
    public let mode: WatchDeliveryMode
    public let github: GitHubDestination?
    public let webhook: WebhookDestination?

    public init(id: UUID = UUID(), configuredAt: Date = Date(), mode: WatchDeliveryMode,
                github: GitHubDestination? = nil, webhook: WebhookDestination? = nil) {
        self.id = id
        self.configuredAt = configuredAt
        self.mode = mode
        self.github = github
        self.webhook = webhook
    }

    public var destinations: Set<DirectDestination> {
        var result: Set<DirectDestination> = []
        if github != nil { result.insert(.github) }
        if webhook != nil { result.insert(.webhook) }
        return result
    }

    public var route: TextDeliveryRoute {
        mode == .phone ? .phone : .direct(configurationID: id, destinations: destinations)
    }

    public func validate() throws {
        try github?.validate()
        try webhook?.validate()
        guard configuredAt.timeIntervalSinceReferenceDate.isFinite,
              mode == .phone || !destinations.isEmpty else {
            throw DirectSendError.invalidConfiguration("Choose at least one Direct Send destination.")
        }
    }
}

public enum DirectSendSharedState {
    public static let appGroup = "group.com.danfakkeldy.macromark"
    public static let pendingCountKey = "directSend.pendingCount"
    public static let configurationAcknowledgedKey = "directSend.watchAcknowledgedID"
}
