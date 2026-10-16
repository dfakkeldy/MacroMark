import Foundation

public struct GitHubDeviceFlow: Sendable {
    public struct Authorization: Sendable {
        public let userCode: String
        public let verificationURL = URL(string: "https://github.com/login/device")!
        public let expiresAt: Date
        public let interval: Int
        fileprivate let deviceCode: String
    }

    public enum PollResult: Equatable, Sendable {
        case pending(interval: Int)
        case authorized(token: String)
    }

    private let clientID: String
    private let client: DirectHTTPClient

    public init(clientID: String, client: DirectHTTPClient = .live) {
        self.clientID = clientID
        self.client = client
    }

    public func start() async throws -> Authorization {
        guard !clientID.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw DirectSendError.invalidConfiguration("GitHub sign-in is not configured in this build. Use a repository token.")
        }
        let response = try await client.send(formRequest(path: "device/code", fields: ["client_id": clientID, "scope": "repo"]))
        try response.requireSuccess()
        struct Code: Decodable {
            let device_code: String
            let user_code: String
            let expires_in: Int
            let interval: Int
        }
        let code = try JSONDecoder().decode(Code.self, from: response.data)
        guard !code.device_code.isEmpty, !code.user_code.isEmpty,
              (1...1800).contains(code.expires_in), (1...60).contains(code.interval) else {
            throw DirectSendError.invalidResponse
        }
        return Authorization(userCode: code.user_code, expiresAt: Date().addingTimeInterval(Double(code.expires_in)),
            interval: max(5, code.interval), deviceCode: code.device_code)
    }

    public func poll(_ authorization: Authorization, interval: Int) async throws -> PollResult {
        guard Date() < authorization.expiresAt else { throw DirectSendError.authorizationExpired }
        let response = try await client.send(formRequest(path: "oauth/access_token", fields: [
            "client_id": clientID, "device_code": authorization.deviceCode,
            "grant_type": "urn:ietf:params:oauth:grant-type:device_code"]))
        try response.requireSuccess()
        struct Token: Decodable {
            let access_token: String?
            let token_type: String?
            let error: String?
        }
        let result = try JSONDecoder().decode(Token.self, from: response.data)
        if let token = result.access_token, !token.isEmpty, result.token_type?.lowercased() == "bearer" {
            return .authorized(token: token)
        }
        switch result.error {
        case "authorization_pending": return .pending(interval: max(5, interval))
        case "slow_down": return .pending(interval: min(120, max(5, interval) + 5))
        case "access_denied": throw DirectSendError.authorizationDenied
        case "expired_token": throw DirectSendError.authorizationExpired
        default: throw DirectSendError.invalidResponse
        }
    }

    private func formRequest(path: String, fields: [String: String]) -> URLRequest {
        var request = URLRequest(url: URL(string: "https://github.com/login/\(path)")!, timeoutInterval: 12)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
        var components = URLComponents()
        components.queryItems = fields.sorted { $0.key < $1.key }.map { URLQueryItem(name: $0.key, value: $0.value) }
        request.httpBody = components.percentEncodedQuery?.replacingOccurrences(of: "+", with: "%2B").data(using: .utf8)
        return request
    }
}
