import Foundation
import Testing
import os
@testable import MacroMarkKit

@Suite("Direct Send durability")
@MainActor
struct DirectSendQueueTests {
    private func file() throws -> URL {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        return directory.appendingPathComponent("queue.json")
    }

    @Test("Capture day and offset survive midnight, travel and restart")
    func captureDay() throws {
        let url = try file()
        defer { try? FileManager.default.removeItem(at: url.deletingLastPathComponent()) }
        let timestamp = try #require(ISO8601DateFormatter().date(from: "2026-10-17T02:58:00Z"))
        let note = CapturedNote(text: "before midnight", timestamp: timestamp,
            timeZone: try #require(TimeZone(secondsFromGMT: -3 * 3600)),
            route: .direct(configurationID: UUID(), destinations: [.github, .webhook]))
        let queue = try TextDeliveryQueue(fileURL: url)
        try queue.enqueue(note)
        let restored = try TextDeliveryQueue(fileURL: url)
        #expect(restored.notes == [note])
        #expect(note.captureDay == "2026-10-16")
        #expect(note.capturedAtISO8601 == "2026-10-16T23:58:00-03:00")
    }

    @Test("Legacy notes migrate to Phone with the same identity and timestamp")
    func migration() throws {
        let url = try file()
        defer { try? FileManager.default.removeItem(at: url.deletingLastPathComponent()) }
        let id = UUID()
        let data = Data("[{\"id\":\"\(id)\",\"text\":\"legacy\",\"timestamp\":42}]".utf8)
        let queue = try TextDeliveryQueue(fileURL: url, legacyNotesData: data)
        #expect(queue.notes.first?.id == id)
        #expect(queue.notes.first?.timestamp == Date(timeIntervalSinceReferenceDate: 42))
        #expect(queue.notes.first?.route == .phone)
        #expect(try TextDeliveryQueue(fileURL: url).notes == queue.notes)
    }

    @Test("Partial fan-out stays queued after relaunch and ignores a phone ACK")
    func partialDelivery() throws {
        let url = try file()
        defer { try? FileManager.default.removeItem(at: url.deletingLastPathComponent()) }
        let configurationID = UUID()
        let note = CapturedNote(text: "both", route: .direct(configurationID: configurationID,
            destinations: [.github, .webhook]))
        let queue = try TextDeliveryQueue(fileURL: url)
        try queue.enqueue(note)
        try queue.complete(note.id, destination: .webhook)
        try queue.acknowledgePhone(note.id)
        let restored = try TextDeliveryQueue(fileURL: url)
        #expect(restored.notes.count == 1)
        #expect(restored.notes[0].route == note.route)
        #expect(restored.notes[0].pendingDestinations == [.github])
        try restored.complete(note.id, destination: .github)
        #expect(restored.notes.isEmpty)
        #expect(try TextDeliveryQueue(fileURL: url).notes.isEmpty)
    }

    @Test("An unsuccessful atomic save never acknowledges a capture or a delivery")
    func failedSave() throws {
        let url = try file()
        defer { try? FileManager.default.removeItem(at: url.deletingLastPathComponent()) }
        var fail = false
        let queue = try TextDeliveryQueue(fileURL: url, persist: { data, destination in
            if fail { throw CocoaError(.fileWriteNoPermission) }
            try data.write(to: destination, options: .atomic)
        })
        let note = CapturedNote(text: "keep me", route: .direct(configurationID: UUID(), destinations: [.github]))
        fail = true
        #expect(throws: (any Error).self) { try queue.enqueue(note) }
        #expect(queue.notes.isEmpty)
        fail = false
        try queue.enqueue(note)
        fail = true
        #expect(throws: (any Error).self) { try queue.complete(note.id, destination: .github) }
        #expect(queue.notes.first?.pendingDestinations == [.github])
        #expect(queue.isConfirmed(note.id, destination: .github))
        #expect(try TextDeliveryQueue(fileURL: url).notes == queue.notes)
        #expect(queue.flushConfirmations().isEmpty)
        fail = false
        #expect(queue.flushConfirmations().count == 1)
        #expect(queue.notes.isEmpty)
        #expect(!queue.hasUnpersistedConfirmations)
    }

    @Test("Corrupt queue and invalid Direct routes fail closed")
    func invalidQueue() throws {
        let url = try file()
        defer { try? FileManager.default.removeItem(at: url.deletingLastPathComponent()) }
        let queue = try TextDeliveryQueue(fileURL: url)
        #expect(throws: (any Error).self) {
            try queue.enqueue(CapturedNote(text: "unroutable", route: .direct(configurationID: UUID(), destinations: [])))
        }
        let corrupt = Data("not JSON".utf8)
        try corrupt.write(to: url)
        #expect(throws: (any Error).self) { try TextDeliveryQueue(fileURL: url) }
        #expect(try Data(contentsOf: url) == corrupt)
    }

    @Test("Retry state survives restart and a successful destination is never retried")
    func retryBackoff() throws {
        let url = try file()
        defer { try? FileManager.default.removeItem(at: url.deletingLastPathComponent()) }
        let queue = try TextDeliveryQueue(fileURL: url)
        let note = CapturedNote(text: "retry", route: .direct(configurationID: UUID(), destinations: [.github, .webhook]))
        let now = Date(timeIntervalSinceReferenceDate: 100)
        try queue.enqueue(note)
        try queue.complete(note.id, destination: .webhook)
        try queue.recordFailure(note.id, destination: .github, now: now)
        #expect(queue.notes[0].eligibleDestinations(at: now).isEmpty)
        #expect(queue.notes[0].eligibleDestinations(at: now.addingTimeInterval(5)) == [.github])
        try queue.recordFailure(note.id, destination: .github, now: now.addingTimeInterval(5), retryAfter: 120)
        let restored = try TextDeliveryQueue(fileURL: url)
        #expect(restored.notes[0].eligibleDestinations(at: now.addingTimeInterval(124)).isEmpty)
        #expect(restored.notes[0].eligibleDestinations(at: now.addingTimeInterval(125)) == [.github])
    }
}

private actor HTTPFixture {
    enum Step: Sendable {
        case response(Int, Data, [String: String] = [:])
        case timeout
    }
    var steps: [Step]
    var requests: [URLRequest] = []
    init(_ steps: [Step]) { self.steps = steps }
    func send(_ request: URLRequest) throws -> DirectHTTPResponse {
        requests.append(request)
        guard !steps.isEmpty else { throw URLError(.badServerResponse) }
        switch steps.removeFirst() {
        case let .response(status, data, headers): return DirectHTTPResponse(status: status, data: data, headers: headers)
        case .timeout: throw URLError(.timedOut)
        }
    }
}

struct DirectSendHTTPTests {
    @Test("A redirected landing-page 200 never confirms a webhook POST")
    func webhookRedirects() throws {
        let endpoint = try #require(URL(string: "https://example.com/receive"))
        let login = try #require(URL(string: "https://example.com/login"))
        #expect(WebhookRoute.confirmsDelivery(status: 204, expectedURL: endpoint, responseURL: endpoint, finalMethod: "POST"))
        #expect(!WebhookRoute.confirmsDelivery(status: 200, expectedURL: endpoint, responseURL: login, finalMethod: "GET"))
        #expect(!WebhookRoute.confirmsDelivery(status: 200, expectedURL: endpoint, responseURL: login, finalMethod: "POST"))
        #expect(!WebhookRoute.confirmsDelivery(status: 302, expectedURL: endpoint, responseURL: endpoint, finalMethod: "POST"))
    }

    @Test("Credential repairs survive switching away and stale setup replay")
    func persistentCredentialRotation() throws {
        let data = OSAllocatedUnfairLock(initialState: [String: Data]())
        let settings = DirectSendSettingsStore(read: { key in data.withLock { $0[key] } },
            write: { value, key in data.withLock { $0[key] = value } })
        let sourceID = UUID()
        let old = DirectSendConfiguration(revision: 1, sourceID: sourceID, mode: .direct,
            github: GitHubDestination(owner: "me", repository: "notes", token: "old"))
        let rotated = DirectSendConfiguration(revision: 2, sourceID: sourceID, mode: .direct,
            github: GitHubDestination(owner: "me", repository: "notes", token: "new"))
        let elsewhere = DirectSendConfiguration(revision: 3, sourceID: sourceID, mode: .direct,
            github: GitHubDestination(owner: "me", repository: "elsewhere", token: "other"))
        try settings.save(old)
        try settings.save(rotated)
        try settings.save(elsewhere)
        #expect(try settings.deliveryConfiguration(id: old.id)?.github?.token == "new")
        #expect(try settings.deliveryConfiguration(id: old.id)?.route == old.route)
        #expect(try settings.configuration(id: old.id)?.github?.token == "old")
        #expect(throws: (any Error).self) { try settings.save(old) }
        #expect(try settings.current()?.id == elsewhere.id)
        #expect(try settings.deliveryConfiguration(id: old.id)?.github?.token == "new")
    }

    @Test("Credential rotation repairs the same destination without rerouting old captures")
    func credentialRotation() throws {
        let url = try #require(URL(string: "https://example.com/notes"))
        let old = DirectSendConfiguration(mode: .direct,
            github: GitHubDestination(owner: "me", repository: "notes", folder: "Inbox", token: "old"),
            webhook: WebhookDestination(url: url, headers: ["Authorization": "old", "X-Target": "same"]))
        let replacement = DirectSendConfiguration(mode: .phone,
            github: GitHubDestination(owner: "me", repository: "notes", folder: "Inbox", token: "new"),
            webhook: WebhookDestination(url: url, headers: ["Authorization": "new", "X-Target": "same"]))
        let repaired = old.refreshingCredentials(from: replacement)
        #expect(repaired.id == old.id)
        #expect(repaired.route == old.route)
        #expect(repaired.github?.token == "new")
        #expect(repaired.webhook?.headers["authorization"] == "new")
        let changed = DirectSendConfiguration(mode: .direct,
            github: GitHubDestination(owner: "me", repository: "elsewhere", token: "new"),
            webhook: WebhookDestination(url: url, headers: ["Authorization": "new", "X-Target": "different"]))
        #expect(old.refreshingCredentials(from: changed) == old)
    }

    private func content(_ text: String, sha: String = "sha1") throws -> Data {
        try JSONSerialization.data(withJSONObject: ["encoding": "base64", "size": text.utf8.count,
            "content": Data(text.utf8).base64EncodedString(), "sha": sha])
    }
    private var destination: GitHubDestination {
        GitHubDestination(owner: "owner", repository: "notes", branch: "daily/notes", folder: "Inbox", token: "fixture")
    }

    @Test("GitHub conflict refetches SHA and preserves a concurrent writer")
    func conflict() async throws {
        let fixture = HTTPFixture([.response(200, try content("old\n")), .response(409, Data()),
            .response(200, try content("old\nconcurrent\n", sha: "sha2")), .response(200, Data())])
        let route = GitHubRoute(client: DirectHTTPClient { try await fixture.send($0) }, pause: { _ in })
        let note = CapturedNote(text: "new")
        try await route.send(note, to: destination)
        let requests = await fixture.requests
        #expect(requests.map(\.httpMethod) == ["GET", "PUT", "GET", "PUT"])
        #expect(requests[0].cachePolicy == .reloadIgnoringLocalCacheData)
        #expect(requests[0].url?.absoluteString.contains("ref=daily/notes") == true)
        let requestBody = try #require(requests[3].httpBody)
        let decodedBody = try JSONSerialization.jsonObject(with: requestBody)
        let body = try #require(decodedBody as? [String: String])
        #expect(body["sha"] == "sha2")
        let encodedContent = try #require(body["content"])
        let contentData = try #require(Data(base64Encoded: encodedContent))
        let appended = try #require(String(data: contentData, encoding: .utf8))
        #expect(appended.hasPrefix("old\nconcurrent\n"))
        #expect(appended.contains(note.deliveryMarker))
    }

    @Test("GitHub ambiguous timeout is recovered by UUID without another PUT")
    func ambiguousTimeout() async throws {
        let note = CapturedNote(text: "once")
        let fixture = HTTPFixture([.response(404, Data()), .timeout,
            .response(200, try content("once\n\(note.deliveryMarker)\n"))])
        let route = GitHubRoute(client: DirectHTTPClient { try await fixture.send($0) }, pause: { _ in })
        await #expect(throws: URLError.self) { try await route.send(note, to: destination) }
        try await route.send(note, to: destination)
        let requests = await fixture.requests
        #expect(requests.map(\.httpMethod) == ["GET", "PUT", "GET"])
        let requestBody = try #require(requests[1].httpBody)
        let decodedBody = try JSONSerialization.jsonObject(with: requestBody)
        let body = try #require(decodedBody as? [String: String])
        #expect(body["sha"] == nil)
    }

    @Test("Reply reads bypass caches and treat missing replies as empty")
    func replies() async throws {
        let fixture = HTTPFixture([.response(404, Data()), .response(200, try content("Reply text"))])
        let route = GitHubRoute(client: DirectHTTPClient { try await fixture.send($0) })
        #expect(try await route.reply(for: "2026-10-16", at: destination) == nil)
        #expect(try await route.reply(for: "2026-10-16", at: destination) == "Reply text")
        let requests = await fixture.requests
        #expect(requests.allSatisfy { $0.cachePolicy == .reloadIgnoringLocalCacheData })
        #expect(requests[0].url?.path.hasSuffix("Inbox/2026-10-16.reply.md") == true)
    }

    @Test("Webhook body and retry identity preserve the capture offset")
    func webhook() throws {
        let note = CapturedNote(text: "hello", timestamp: Date(timeIntervalSince1970: 0),
            timeZone: try #require(TimeZone(secondsFromGMT: 3600)))
        let endpoint = WebhookDestination(url: try #require(URL(string: "https://example.com/receive")),
            headers: ["Authorization": "Bearer fixture"])
        let upload = try WebhookRoute.upload(note, to: endpoint)
        let body = try #require(try JSONSerialization.jsonObject(with: upload.body) as? [String: String])
        #expect(body == ["id": note.id.uuidString, "text": "hello", "capturedAt": "1970-01-01T01:00:00+01:00",
            "source": "macromark-watch"])
        #expect(upload.request.value(forHTTPHeaderField: "Idempotency-Key") == note.id.uuidString)
        #expect(upload.request.value(forHTTPHeaderField: "Authorization") == "Bearer fixture")
        #expect(upload.request.httpMethod == "POST")
    }

    @Test("Unsafe endpoints, paths and headers are rejected before network access")
    func validation() throws {
        #expect(throws: (any Error).self) {
            try WebhookRoute.upload(CapturedNote(text: "private"), to: WebhookDestination(url: #require(URL(string: "http://example.com"))))
        }
        #expect(throws: (any Error).self) {
            try WebhookRoute.upload(CapturedNote(text: "private"), to: WebhookDestination(url: #require(URL(string: "https://example.com")), headers: ["Authorization": "a\r\nb"]))
        }
        #expect(throws: (any Error).self) {
            try GitHubDestination(owner: "owner", repository: "notes", folder: "../escape", token: "fixture").validate()
        }
    }

    @Test("Rate limiting retains retry information and never counts as success")
    func rateLimit() async throws {
        let fixture = HTTPFixture([.response(429, Data(), ["retry-after": "120"])])
        let route = GitHubRoute(client: DirectHTTPClient { try await fixture.send($0) })
        do {
            try await route.send(CapturedNote(text: "wait"), to: destination)
            Issue.record("Expected rate limit")
        } catch let error as DirectSendError {
            #expect(error.retryAfter == 120)
        }
    }

    @Test("Device flow uses encoded form data and handles slow-down without leaking errors")
    func deviceFlow() async throws {
        let fixture = HTTPFixture([
            .response(200, Data(#"{"device_code":"private-code","user_code":"ABCD-1234","expires_in":900,"interval":5}"#.utf8)),
            .response(200, Data(#"{"error":"authorization_pending"}"#.utf8)),
            .response(200, Data(#"{"error":"slow_down"}"#.utf8)),
            .response(200, Data(#"{"access_token":"fixture","token_type":"bearer"}"#.utf8))])
        let flow = GitHubDeviceFlow(clientID: "public+id", client: DirectHTTPClient { try await fixture.send($0) })
        let authorization = try await flow.start()
        #expect(authorization.userCode == "ABCD-1234")
        #expect(try await flow.poll(authorization, interval: 5) == .pending(interval: 5))
        #expect(try await flow.poll(authorization, interval: 5) == .pending(interval: 10))
        #expect(try await flow.poll(authorization, interval: 10) == .authorized(token: "fixture"))
        let requests = await fixture.requests
        let requestBody = try #require(requests[0].httpBody)
        #expect(String(data: requestBody, encoding: .utf8)?.contains("client_id=public%2Bid") == true)
    }
}
