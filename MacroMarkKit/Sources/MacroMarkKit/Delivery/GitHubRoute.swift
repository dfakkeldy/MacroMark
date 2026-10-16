import Foundation

public struct GitHubRoute: Sendable {
    public static let maximumFileByteCount = 256 * 1024
    private let client: DirectHTTPClient
    private let pause: @Sendable (Duration) async throws -> Void

    public init(client: DirectHTTPClient = .live,
                pause: @escaping @Sendable (Duration) async throws -> Void = { try await Task.sleep(for: $0) }) {
        self.client = client
        self.pause = pause
    }

    public func send(_ note: CapturedNote, to destination: GitHubDestination) async throws {
        try destination.validate()
        let filename = "\(note.captureDay).md"
        for attempt in 0..<3 {
            try Task.checkCancellation()
            let file = try await read(filename: filename, destination: destination)
            // Check a standalone marker, not a substring embedded inside another note.
            if file?.text.components(separatedBy: .newlines).contains(note.deliveryMarker) == true { return }
            var text = file?.text ?? ""
            if !text.isEmpty && !text.hasSuffix("\n") { text += "\n" }
            text += "\(note.text)\n\(note.deliveryMarker)\n"
            guard text.utf8.count <= Self.maximumFileByteCount else { throw DirectSendError.tooLarge }
            var request = try request(filename: filename, destination: destination, reading: false)
            request.httpMethod = "PUT"
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
            request.httpBody = try JSONEncoder().encode(WriteBody(
                message: "MacroMark: append \(filename) \(note.id.uuidString)",
                content: Data(text.utf8).base64EncodedString(), branch: destination.branch, sha: file?.sha))
            let response = try await client.send(request)
            if response.status == 409 {
                if attempt == 2 { throw DirectSendError.conflict }
                try await pause(.milliseconds(250 * (1 << attempt)))
                continue
            }
            try response.requireSuccess()
            return
        }
    }

    public func reply(for captureDay: String, at destination: GitHubDestination) async throws -> String? {
        try destination.validate()
        guard captureDay.count == 10,
              captureDay.enumerated().allSatisfy({ index, character in
                  index == 4 || index == 7 ? character == "-" : character.isASCII && character.isNumber
              }) else { throw DirectSendError.invalidResponse }
        return try await read(filename: "\(captureDay).reply.md", destination: destination)?.text
    }

    private struct FileContent: Decodable {
        let encoding: String
        let size: Int
        let content: String
        let sha: String
    }
    private struct WriteBody: Encodable {
        let message: String
        let content: String
        let branch: String
        let sha: String?
    }

    private func read(filename: String, destination: GitHubDestination) async throws -> (text: String, sha: String)? {
        let response = try await client.send(request(filename: filename, destination: destination, reading: true))
        if response.status == 404 { return nil }
        try response.requireSuccess()
        guard response.data.count <= Self.maximumFileByteCount * 2 else { throw DirectSendError.tooLarge }
        let file = try JSONDecoder().decode(FileContent.self, from: response.data)
        guard file.size <= Self.maximumFileByteCount else { throw DirectSendError.tooLarge }
        guard file.encoding == "base64", !file.sha.isEmpty,
              let bytes = Data(base64Encoded: file.content.filter { !$0.isWhitespace }),
              bytes.count == file.size, let text = String(data: bytes, encoding: .utf8) else {
            throw DirectSendError.invalidResponse
        }
        return (text, file.sha)
    }

    private func request(filename: String, destination: GitHubDestination, reading: Bool) throws -> URLRequest {
        var url = URL(string: "https://api.github.com/repos")!
        for component in [destination.owner, destination.repository, "contents"]
            + destination.folder.split(separator: "/").map(String.init) + [filename] {
            url.appendPathComponent(component)
        }
        if reading {
            var components = URLComponents(url: url, resolvingAgainstBaseURL: false)
            components?.queryItems = [URLQueryItem(name: "ref", value: destination.branch)]
            guard let withBranch = components?.url else { throw DirectSendError.invalidResponse }
            url = withBranch
        }
        var request = URLRequest(url: url, cachePolicy: .reloadIgnoringLocalCacheData, timeoutInterval: 12)
        request.setValue("Bearer \(destination.token)", forHTTPHeaderField: "Authorization")
        request.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
        request.setValue("2022-11-28", forHTTPHeaderField: "X-GitHub-Api-Version")
        request.setValue("no-cache", forHTTPHeaderField: "Cache-Control")
        request.setValue("MacroMark", forHTTPHeaderField: "User-Agent")
        return request
    }
}
