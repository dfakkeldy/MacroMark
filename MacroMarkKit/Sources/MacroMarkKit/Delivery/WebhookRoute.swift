import Foundation

public enum WebhookRoute {
    public static func confirmsDelivery(status: Int, expectedURL: URL?, responseURL: URL?, finalMethod: String?) -> Bool {
        guard (200..<300).contains(status), let expectedURL, responseURL == expectedURL else { return false }
        return finalMethod == "POST"
    }

    public struct Upload: Sendable {
        public let request: URLRequest
        public let body: Data
    }

    public static func upload(_ note: CapturedNote, to destination: WebhookDestination) throws -> Upload {
        try destination.validate()
        var request = URLRequest(url: destination.url, cachePolicy: .reloadIgnoringLocalCacheData, timeoutInterval: 30)
        request.httpMethod = "POST"
        for (name, value) in destination.headers { request.setValue(value, forHTTPHeaderField: name) }
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue(note.id.uuidString, forHTTPHeaderField: "Idempotency-Key")
        let encoder = JSONEncoder()
        encoder.outputFormatting = .sortedKeys
        let body = try encoder.encode(Payload(id: note.id.uuidString, text: note.text,
            capturedAt: note.capturedAtISO8601, source: "macromark-watch"))
        return Upload(request: request, body: body)
    }

    private struct Payload: Encodable {
        let id: String
        let text: String
        let capturedAt: String
        let source: String
    }
}
