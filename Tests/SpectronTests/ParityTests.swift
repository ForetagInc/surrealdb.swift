import Foundation
import XCTest
@testable import Spectron

final class ParityTests: XCTestCase {
    let base = "https://api.spectron.test"
    let apiKey = "test-key"
    let ctx = "acme-prod"

    private func makeClient(_ http: MockHTTPClient, maxRetries: Int = 3) throws -> Spectron {
        let transport = try SpectronTransport(
            endpoint: base,
            apiKey: apiKey,
            maxRetries: maxRetries,
            client: http,
            sleeper: { _ in }
        )
        return Spectron(context: ctx, transport: transport)
    }

    private func header(_ rec: MockHTTPClient.Recorded, _ name: String) -> String? {
        for (k, v) in rec.headers where k.caseInsensitiveCompare(name) == .orderedSame {
            return v
        }
        return nil
    }

    // MARK: - Delegation

    func testOnBehalfOfHeaderSentOnGet() async throws {
        let http = MockHTTPClient()
        http.enqueue(.json([
            "id": "doc:1", "title": "T", "source": "s", "mimeType": "text/plain",
            "status": "ready", "contentHash": "h", "sizeBytes": 1, "version": 1,
            "createdAt": "t", "updatedAt": "t"
        ]))
        let client = try makeClient(http)
        _ = try await client.documents.get("doc:1", onBehalfOf: "principal:analyst")
        XCTAssertEqual(header(http.recorded.first!, "X-Spectron-On-Behalf-Of"), "principal:analyst")
    }

    func testOnBehalfOfHeaderOmittedWhenNil() async throws {
        let http = MockHTTPClient()
        http.enqueue(.json(["affected": 0]))
        let client = try makeClient(http)
        _ = try await client.lifecycle.decay()
        XCTAssertNil(header(http.recorded.first!, "X-Spectron-On-Behalf-Of"))
    }

    // MARK: - Idempotency

    func testFactsCreateSendsIdempotencyKey() async throws {
        let http = MockHTTPClient()
        http.enqueue(.json(["sessionId": "s", "mode": "full"]))
        let client = try makeClient(http)
        _ = try await client.remember("I was promoted", role: .user, onBehalfOf: "principal:x")
        let rec = http.recorded.first!
        XCTAssertTrue(rec.url.absoluteString.hasSuffix("/facts"))
        let key = header(rec, "Idempotency-Key")
        XCTAssertNotNil(key)
        XCTAssertEqual(key?.count, 64) // SHA-256 hex
        XCTAssertEqual(header(rec, "X-Spectron-On-Behalf-Of"), "principal:x")
    }

    func testIdempotencyKeyStableWithinBucketAndChangesAcross() {
        let body = Data("payload".utf8)
        let t100 = Date(timeIntervalSince1970: 100)
        let a = Idempotency.key(method: "POST", path: "/p", body: body, now: t100, bucketSeconds: 30)
        let b = Idempotency.key(method: "POST", path: "/p", body: body, now: t100, bucketSeconds: 30)
        XCTAssertEqual(a, b)

        let nextBucket = Date(timeIntervalSince1970: 131)
        let c = Idempotency.key(method: "POST", path: "/p", body: body, now: nextBucket, bucketSeconds: 30)
        XCTAssertNotEqual(a, c)

        let otherBody = Idempotency.key(method: "POST", path: "/p", body: Data("other".utf8), now: t100, bucketSeconds: 30)
        XCTAssertNotEqual(a, otherBody)
    }

    func testPortableSHA256MatchesKnownVector() {
        // NIST: SHA-256("abc")
        let digest = PortableSHA256.hash(Data("abc".utf8))
        let hex = digest.map { String(format: "%02x", $0) }.joined()
        XCTAssertEqual(hex, "ba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad")
    }

    func testFactsWriteRetriesOn5xx() async throws {
        let http = MockHTTPClient()
        http.enqueueMany([
            .json(["message": "down"], status: 503),
            .json(["sessionId": "s", "mode": "full"], status: 200)
        ])
        let client = try makeClient(http)
        _ = try await client.remember("retryable write")
        XCTAssertEqual(http.callCount, 2) // POST retried because it is idempotent
    }

    // MARK: - Keys

    func testKeysCreateSendsTTLAndBody() async throws {
        let http = MockHTTPClient()
        http.enqueue(.json(["id": "key:1", "key": "sp-key:1-secret", "validUntil": "later"]))
        let client = try makeClient(http)
        let minted = try await client.keys.create(name: "ci", grants: ["org/anneal": ["read"]], ttlSeconds: 3600)
        XCTAssertEqual(minted.id, "key:1")
        XCTAssertEqual(minted.key, "sp-key:1-secret")
        let rec = http.recorded.first!
        XCTAssertTrue(rec.url.absoluteString.contains("/keys"))
        XCTAssertTrue(rec.url.absoluteString.contains("ttlSeconds=3600"))
        let body = try JSONSerialization.jsonObject(with: rec.body!) as! [String: Any]
        XCTAssertEqual(body["name"] as? String, "ci")
        XCTAssertEqual((body["grants"] as? [String: Any])?["org/anneal"] as? [String], ["read"])
    }

    func testKeysListAndRotate() async throws {
        let http = MockHTTPClient()
        http.enqueue(.json([[
            "id": "key:1", "name": "ci", "createdAt": "t", "grants": ["org/anneal": ["read"]]
        ]]))
        let client = try makeClient(http)
        let keys = try await client.keys.list()
        XCTAssertEqual(keys.first?.name, "ci")

        http.enqueue(.json(["id": "key:1", "key": "sp-key:1-rotated"]))
        let rotated = try await client.keys.rotate("key:1", ttlSeconds: 60)
        XCTAssertEqual(rotated.key, "sp-key:1-rotated")
        let rec = http.recorded.last!
        XCTAssertEqual(rec.method, "POST")
        XCTAssertTrue(rec.url.absoluteString.hasSuffix("/keys/key%3A1/rotate?ttlSeconds=60"))
    }

    // MARK: - Whoami

    func testWhoamiHitsMeEndpoint() async throws {
        let http = MockHTTPClient()
        http.enqueue(.json([
            "principalId": "principal:owner",
            "displayName": "Owner",
            "kind": "user",
            "enforce": true,
            "grants": ["org/anneal": ["read", "write"]],
            "effectiveGrants": [:]
        ]))
        let client = try makeClient(http)
        let me = try await client.whoami(onBehalfOf: "principal:analyst")
        XCTAssertEqual(me.principalId, "principal:owner")
        XCTAssertTrue(me.enforce)
        let rec = http.recorded.first!
        XCTAssertTrue(rec.url.absoluteString.hasSuffix("/me"))
        XCTAssertEqual(header(rec, "X-Spectron-On-Behalf-Of"), "principal:analyst")
    }

    // MARK: - Streaming chat

    func testChatStreamParsesSSEFrames() async throws {
        let sse = """
        data: {"delta":"Hel"}

        data: {"delta":"lo"}

        event: done
        data: {"sessionId":"session:1","traceId":"trace:1"}

        """
        let http = MockHTTPClient()
        http.enqueue(.text(sse))
        let client = try makeClient(http)

        var deltas: [String] = []
        var sawDone = false
        var doneSessionId: String?
        let stream = try await client.chatStream("hi", sessionId: "session:1")
        for try await chunk in stream {
            if chunk.done {
                sawDone = true
                doneSessionId = chunk.sessionId
            } else if !chunk.delta.isEmpty {
                deltas.append(chunk.delta)
            }
        }
        XCTAssertEqual(deltas, ["Hel", "lo"])
        XCTAssertTrue(sawDone)
        XCTAssertEqual(doneSessionId, "session:1")

        let rec = http.recorded.first!
        XCTAssertTrue(rec.url.absoluteString.hasSuffix("/chat"))
        let body = try JSONSerialization.jsonObject(with: rec.body!) as! [String: Any]
        XCTAssertEqual(body["stream"] as? Bool, true)
    }

    func testSSEParserDoneSentinel() {
        var parser = SSEParser()
        XCTAssertNil(parser.consume("data: [DONE]"))
        let chunk = parser.consume("")
        XCTAssertEqual(chunk?.done, true)
    }

    // MARK: - Top-level verbs

    func testRecallForwardsToQuery() async throws {
        let http = MockHTTPClient()
        http.enqueue(.json([
            "hits": [], "tier": "direct", "classificationKind": "direct_lookup",
            "seedEntities": [], "queryMs": 3,
            "trace": [
                "traceId": "t", "resolutionTier": "direct", "tierReason": "r",
                "latencyMs": 3, "retrievedCount": 0, "topScores": []
            ]
        ]))
        let client = try makeClient(http)
        let out = try await client.recall("who am I", k: 5, mode: "direct")
        XCTAssertEqual(out.tier, .direct)
        XCTAssertTrue(http.recorded.first!.url.absoluteString.hasSuffix("/query"))
        let body = try JSONSerialization.jsonObject(with: http.recorded.first!.body!) as! [String: Any]
        XCTAssertEqual(body["query"] as? String, "who am I")
        XCTAssertEqual(body["mode"] as? String, "direct")
    }
}
