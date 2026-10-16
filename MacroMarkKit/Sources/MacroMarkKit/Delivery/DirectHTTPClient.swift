import Foundation

public struct DirectHTTPResponse: Sendable {
    public let status: Int
    public let data: Data
    public let headers: [String: String]

    public init(status: Int, data: Data, headers: [String: String] = [:]) {
        self.status = status
        self.data = data
        self.headers = Dictionary(headers.map { ($0.key.lowercased(), $0.value) }, uniquingKeysWith: { _, value in value })
    }

    public func requireSuccess() throws {
        guard (200..<300).contains(status) else {
            var delay = headers["retry-after"].flatMap(TimeInterval.init)
            if delay == nil, let reset = headers["x-ratelimit-reset"].flatMap(TimeInterval.init),
               headers["x-ratelimit-remaining"] == "0" {
                delay = max(0, reset - Date().timeIntervalSince1970)
            }
            throw DirectSendError.http(status, retryAfter: delay)
        }
    }
}

private final class DirectRedirectDelegate: NSObject, URLSessionTaskDelegate, Sendable {
    func urlSession(_ session: URLSession, task: URLSessionTask,
                    willPerformHTTPRedirection response: HTTPURLResponse, newRequest request: URLRequest,
                    completionHandler: @escaping @Sendable (URLRequest?) -> Void) {
        completionHandler(nil)
    }
}

public struct DirectHTTPClient: Sendable {
    public let send: @Sendable (URLRequest) async throws -> DirectHTTPResponse

    public init(send: @escaping @Sendable (URLRequest) async throws -> DirectHTTPResponse) { self.send = send }

    public static let live: DirectHTTPClient = {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.requestCachePolicy = .reloadIgnoringLocalCacheData
        configuration.urlCache = nil
        configuration.timeoutIntervalForRequest = 12
        configuration.timeoutIntervalForResource = 30
        let session = URLSession(configuration: configuration, delegate: DirectRedirectDelegate(), delegateQueue: nil)
        return DirectHTTPClient { request in
            let (data, response) = try await session.data(for: request)
            guard let response = response as? HTTPURLResponse else { throw DirectSendError.invalidResponse }
            let headers = response.allHeaderFields.reduce(into: [String: String]()) {
                if let name = $1.key as? String { $0[name] = String(describing: $1.value) }
            }
            return DirectHTTPResponse(status: response.statusCode, data: data, headers: headers)
        }
    }()
}
