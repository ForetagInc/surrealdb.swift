import Foundation
import XCTest
@testable import Spectron

final class EndpointTests: XCTestCase {
    let base = "https://api.spectron.test"
    let apiKey = "test-key"
    let ctx = "acme-prod"

    private func makeClient(_ http: MockHTTPClient) throws -> Spectron {
        let transport = try SpectronTransport(
            endpoint: base,
            apiKey: apiKey,
            client: http,
            sleeper: { _ in }
        )
        return Spectron(context: ctx, transport: transport)
    }

    private func body(_ http: MockHTTPClient) throws -> [String: Any] {
        try JSONSerialization.jsonObject(with: http.recorded.first!.body!) as! [String: Any]
    }

    // MARK: - Documents

    func testDocumentQuery() async throws {
        let http = MockHTTPClient()
        http.enqueue(.json([
            "queryMs": 10,
            "results": [[
                "score": 0.5,
                "chunk": [
                    "id": "c", "document": "d", "charStart": 0, "charEnd": 1,
                    "position": 0, "text": "t"
                ],
                "document": ["id": "d", "title": "T", "source": "s"]
            ]]
        ]))
        let client = try makeClient(http)
        let out = try await client.documents.query("question", mode: .hybrid, k: 5)
        XCTAssertEqual(out.queryMs, 10)
        XCTAssertEqual(out.results.first?.score, 0.5)
        XCTAssertTrue(http.recorded.first!.url.absoluteString.hasSuffix("/documents/query"))

        let body = try body(http)
        XCTAssertEqual(body["query"] as? String, "question")
        XCTAssertEqual(body["mode"] as? String, "hybrid")
        XCTAssertEqual(body["k"] as? Int, 5)
    }

    func testDocumentListWithQueryParams() async throws {
        let http = MockHTTPClient()
        http.enqueue(.json([
            "documents": [],
            "page": 0,
            "pageSize": 10,
            "total": 0
        ]))
        let client = try makeClient(http)
        _ = try await client.documents.list(status: .ready, mimeType: "application/pdf", page: 1, pageSize: 10)
        let url = http.recorded.first!.url.absoluteString
        XCTAssertTrue(url.contains("/documents?"))
        XCTAssertTrue(url.contains("status=ready"))
        XCTAssertTrue(url.contains("mime_type=application/pdf") || url.contains("mime_type=application%2Fpdf"))
        XCTAssertTrue(url.contains("page=1"))
        XCTAssertTrue(url.contains("page_size=10"))
    }

    func testDocumentUploadSendsMetadataPart() async throws {
        let http = MockHTTPClient()
        http.enqueue(.json([
            "id": "doc:1",
            "status": "queued",
            "contentHash": "abc",
            "deduplicated": false
        ], status: 202))
        let client = try makeClient(http)
        let resp = try await client.documents.upload(
            file: .data("hello".data(using: .utf8)!, filename: "returns.pdf", mimeType: "application/pdf"),
            title: "Returns Policy",
            source: "https://example/returns"
        )
        XCTAssertEqual(resp.id, "doc:1")
        XCTAssertEqual(resp.status, .queued)

        let rec = http.recorded.first!
        XCTAssertEqual(rec.method, "POST")
        XCTAssertTrue(rec.url.absoluteString.hasSuffix("/documents"))
        let raw = String(data: rec.body!, encoding: .utf8)!
        XCTAssertTrue(raw.contains("name=\"metadata\""))
        XCTAssertTrue(raw.contains("name=\"file\""))
        XCTAssertTrue(raw.contains("\"title\":\"Returns Policy\""))
        XCTAssertTrue(raw.contains("\"mime_type\":\"application/pdf\""))
    }

    func testKeywordsSearch() async throws {
        let http = MockHTTPClient()
        http.enqueue(.json(["queryMs": 1, "results": []]))
        let client = try makeClient(http)
        _ = try await client.documents.keywords.search("refund", k: 10, threshold: 0.6)
        XCTAssertTrue(http.recorded.first!.url.absoluteString.hasSuffix("/documents/keywords/search"))
        let body = try body(http)
        XCTAssertEqual(body["query"] as? String, "refund")
        XCTAssertEqual(body["k"] as? Int, 10)
        XCTAssertEqual(body["threshold"] as? Double, 0.6)
    }

    func testKeywordGetPathEncoded() async throws {
        let http = MockHTTPClient()
        http.enqueue(.json([
            "id": "k:1",
            "normalised": "RETURN POLICY",
            "text": "return policy",
            "documentCount": 2,
            "documents": []
        ]))
        let client = try makeClient(http)
        _ = try await client.documents.keywords.get("RETURN POLICY")
        let url = http.recorded.first!.url.absoluteString
        XCTAssertTrue(url.contains("/documents/keywords/"))
        XCTAssertTrue(url.contains("%20"))
    }

    // MARK: - Sessions and facts

    func testSessionsCreateWithStringScope() async throws {
        let http = MockHTTPClient()
        http.enqueue(.json([
            "id": "session:abc",
            "scope": [["user/tobie"]],
            "createdAt": "2026-01-01T00:00:00Z"
        ], status: 201))
        let client = try makeClient(http)
        let session = try await client.sessions.create(scope: "user/tobie")
        XCTAssertEqual(session.id, "session:abc")
        XCTAssertEqual(session.info.scope, [["user/tobie"]])

        let body = try body(http)
        XCTAssertEqual(body["scopes"] as? [[String]], [["user/tobie"]])
    }

    func testFactsCreateUsesSnakeCaseKeys() async throws {
        let http = MockHTTPClient()
        http.enqueue(.json([
            "sessionId": "session:abc",
            "mode": "full",
            "turnId": "turn:1"
        ]))
        let client = try makeClient(http)
        let resp = try await client.facts.create(
            text: "I just got promoted to CTO",
            role: .user,
            memoryCategory: .identity,
            infer: .full,
            sessionId: "session:abc"
        )
        XCTAssertEqual(resp.sessionId, "session:abc")
        XCTAssertEqual(resp.mode, .full)

        XCTAssertTrue(http.recorded.first!.url.absoluteString.hasSuffix("/facts"))
        let body = try body(http)
        XCTAssertEqual(body["text"] as? String, "I just got promoted to CTO")
        XCTAssertEqual(body["role"] as? String, "user")
        XCTAssertEqual(body["memory_category"] as? String, "identity")
        XCTAssertEqual(body["session_id"] as? String, "session:abc")
    }

    func testFactsCreateWithTriples() async throws {
        let http = MockHTTPClient()
        http.enqueue(.json(["sessionId": "session:abc", "mode": "triples"]))
        let client = try makeClient(http)
        _ = try await client.facts.create(
            triples: [
                Triple(
                    entity: TripleEntity(type: "Person", name: "tobie"),
                    key: "role",
                    value: "CTO",
                    memoryCategory: .identity
                )
            ],
            infer: .triples
        )
        let body = try body(http)
        let triples = body["triples"] as! [[String: Any]]
        XCTAssertEqual((triples.first?["entity"] as? [String: Any])?["name"] as? String, "tobie")
        XCTAssertEqual(triples.first?["key"] as? String, "role")
        XCTAssertEqual(triples.first?["value"] as? String, "CTO")
        XCTAssertEqual(triples.first?["memory_category"] as? String, "identity")
    }

    // MARK: - Memory

    func testMemoryQueryOneShot() async throws {
        let http = MockHTTPClient()
        http.enqueue(.json([
            "hits": [],
            "tier": "hybrid",
            "classificationKind": "hybrid",
            "seedEntities": [],
            "queryMs": 7,
            "trace": [
                "traceId": "t:1",
                "resolutionTier": "hybrid",
                "tierReason": "router",
                "latencyMs": 7,
                "retrievedCount": 0,
                "topScores": []
            ]
        ]))
        let client = try makeClient(http)
        let out = try await client.query("what role does Christian have?", k: 10)
        XCTAssertEqual(out.tier, .hybrid)
        XCTAssertEqual(out.classificationKind, .hybrid)
        XCTAssertEqual(out.queryMs, 7)
    }

    func testMemoryChat() async throws {
        let http = MockHTTPClient()
        http.enqueue(.json([
            "reply": "You are the CTO.",
            "sessionId": "session:abc",
            "traceId": "t:1",
            "memoryUpdates": [
                "turnId": "turn:1",
                "entities": [],
                "attributes": [],
                "relations": [],
                "corrections": [],
                "instructions": [],
                "uncertainties": []
            ]
        ]))
        let client = try makeClient(http)
        let reply = try await client.chat("What do you know about me?", sessionId: "session:abc")
        XCTAssertEqual(reply.reply, "You are the CTO.")
        XCTAssertEqual(reply.sessionId, "session:abc")
        XCTAssertTrue(http.recorded.first!.url.absoluteString.hasSuffix("/chat"))
        let body = try body(http)
        XCTAssertEqual(body["sessionId"] as? String, "session:abc")
    }

    func testMemoryState() async throws {
        let http = MockHTTPClient()
        let emptyCategory: [String: Any] = ["entities": [], "attributes": [], "relations": []]
        http.enqueue(.json([
            "identity": emptyCategory,
            "knowledge": emptyCategory,
            "context": emptyCategory,
            "instructions": [],
            "unknowns": []
        ]))
        let client = try makeClient(http)
        let state = try await client.state()
        XCTAssertEqual(state.identity.entities.count, 0)
        XCTAssertEqual(state.instructions.count, 0)
    }

    func testEntitiesGet() async throws {
        let http = MockHTTPClient()
        http.enqueue(.json([
            "entity": [
                "id": "entity:1",
                "entityType": "Person",
                "name": "christian_battaglia",
                "memoryCategory": "identity",
                "importance": 0.9,
                "createdAt": "2026-01-01T00:00:00Z",
                "updatedAt": "2026-01-02T00:00:00Z"
            ],
            "attributes": [[
                "id": "attr:1",
                "entity": "entity:1",
                "key": "role",
                "value": "CTO",
                "memoryCategory": "identity",
                "importance": 0.9,
                "createdAt": "2026-01-01T00:00:00Z"
            ]],
            "relations": []
        ]))
        let client = try makeClient(http)
        let view = try await client.entities.get(type: "Person", name: "christian_battaglia")
        XCTAssertEqual(view.entity.name, "christian_battaglia")
        XCTAssertEqual(view.attributes.first?.value, "CTO")
    }

    func testLifecycleDecay() async throws {
        let http = MockHTTPClient()
        http.enqueue(.json(["affected": 3]))
        let client = try makeClient(http)
        let result = try await client.lifecycle.decay()
        XCTAssertEqual(result.affected, 3)
        XCTAssertEqual(http.callCount, 1)
        XCTAssertEqual(http.recorded.first?.method, "POST")
        XCTAssertTrue(http.recorded.first!.url.absoluteString.hasSuffix("/lifecycle/decay"))
    }

    func testTracesList() async throws {
        let http = MockHTTPClient()
        http.enqueue(.json(["traces": [[
            "id": "trace:1",
            "queryText": "who is tobie",
            "resolutionTier": "hybrid",
            "tierReason": "router",
            "latencyMs": 12,
            "cached": false,
            "createdAt": "2026-01-01T00:00:00Z"
        ]]]))
        let client = try makeClient(http)
        let traces = try await client.traces.list(limit: 50)
        XCTAssertEqual(traces.count, 1)
        XCTAssertEqual(traces.first?.id, "trace:1")
        XCTAssertTrue(http.recorded.first!.url.absoluteString.contains("limit=50"))
    }

    // MARK: - Governance

    func testScopesRegister() async throws {
        let http = MockHTTPClient()
        http.enqueue(.json([
            "path": "org/anneal",
            "createdAt": "2026-01-01T00:00:00Z"
        ], status: 201))
        let client = try makeClient(http)
        let node = try await client.scopes.register(path: "org/anneal", displayName: "Anneal")
        XCTAssertEqual(node.path, "org/anneal")
        XCTAssertNil(node.tombstonedAt)
        XCTAssertTrue(http.recorded.first!.url.absoluteString.hasSuffix("/scopes"))
        let body = try body(http)
        XCTAssertEqual(body["path"] as? String, "org/anneal")
        XCTAssertEqual(body["displayName"] as? String, "Anneal")
    }

    func testPrincipalsGrant() async throws {
        let http = MockHTTPClient()
        http.enqueue(.json([
            "id": "principal:1",
            "kind": "agent",
            "displayName": "Agent One",
            "grants": ["org/anneal": ["read", "write"]]
        ]))
        let client = try makeClient(http)
        let principal = try await client.principals.grant(
            principalId: "principal:1",
            path: "org/anneal",
            verbs: ["read", "write"]
        )
        XCTAssertEqual(principal.grants["org/anneal"], ["read", "write"])
        XCTAssertEqual(http.recorded.first?.method, "POST")
        XCTAssertTrue(http.recorded.first!.url.absoluteString.hasSuffix("/principals/principal%3A1/grants"))
        let body = try body(http)
        XCTAssertEqual(body["path"] as? String, "org/anneal")
        XCTAssertEqual(body["verbs"] as? [String], ["read", "write"])
    }
}
