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

    func testKnowledgeQuery() async throws {
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
        let out = try await client.knowledge.query("question", mode: .hybrid, k: 5)
        XCTAssertEqual(out.queryMs, 10)
        XCTAssertEqual(out.results.first?.score, 0.5)

        let body = try JSONSerialization.jsonObject(with: http.recorded.first!.body!) as! [String: Any]
        XCTAssertEqual(body["query"] as? String, "question")
        XCTAssertEqual(body["mode"] as? String, "hybrid")
        XCTAssertEqual(body["k"] as? Int, 5)
    }

    func testKnowledgeListWithQueryParams() async throws {
        let http = MockHTTPClient()
        http.enqueue(.json([
            "documents": [],
            "page": 0,
            "pageSize": 10,
            "total": 0
        ]))
        let client = try makeClient(http)
        _ = try await client.knowledge.list(status: "ready", mimeType: "application/pdf", page: 1, pageSize: 10)
        let url = http.recorded.first!.url.absoluteString
        XCTAssertTrue(url.contains("status=ready"))
        XCTAssertTrue(url.contains("mime_type=application/pdf") || url.contains("mime_type=application%2Fpdf"))
        XCTAssertTrue(url.contains("page=1"))
        XCTAssertTrue(url.contains("page_size=10"))
    }

    func testKnowledgeNodesUpsert() async throws {
        let http = MockHTTPClient()
        http.enqueue(.init(status: 204, body: Data()))
        let client = try makeClient(http)
        try await client.knowledge.nodes.upsert(
            nodes: [KnowledgeNodeUpsertRow(kind: "product", slug: "airpods", title: "AirPods")],
            scope: ["org": "apple"]
        )
        let body = try JSONSerialization.jsonObject(with: http.recorded.first!.body!) as! [String: Any]
        let nodes = body["nodes"] as! [[String: Any]]
        XCTAssertEqual(nodes.first?["kind"] as? String, "product")
        XCTAssertEqual(nodes.first?["slug"] as? String, "airpods")
        XCTAssertEqual(nodes.first?["title"] as? String, "AirPods")
        let scope = body["scope"] as! [[String: String]]
        XCTAssertEqual(scope.first, ["key": "org", "value": "apple"])
    }

    func testKnowledgeTraverse() async throws {
        let http = MockHTTPClient()
        http.enqueue(.json(["edges": [], "nodes": []]))
        let client = try makeClient(http)
        _ = try await client.knowledge.traverse(
            start: [TraverseStart(type: "document", id: "doc:1")],
            edges: ["knowledge_has_keyword"],
            maxDepth: 2
        )
        let body = try JSONSerialization.jsonObject(with: http.recorded.first!.body!) as! [String: Any]
        let start = body["start"] as! [[String: Any]]
        XCTAssertEqual(start.first?["type"] as? String, "document")
        XCTAssertEqual(start.first?["id"] as? String, "doc:1")
        let edges = body["edges"] as! [String]
        XCTAssertEqual(edges, ["knowledge_has_keyword"])
        XCTAssertEqual(body["maxDepth"] as? Int, 2)
    }

    func testKnowledgeKeywordsSearch() async throws {
        let http = MockHTTPClient()
        http.enqueue(.json(["queryMs": 1, "results": []]))
        let client = try makeClient(http)
        _ = try await client.knowledge.keywords.search("refund", k: 10, threshold: 0.6)
        let body = try JSONSerialization.jsonObject(with: http.recorded.first!.body!) as! [String: Any]
        XCTAssertEqual(body["query"] as? String, "refund")
        XCTAssertEqual(body["k"] as? Int, 10)
        XCTAssertEqual(body["threshold"] as? Double, 0.6)
    }

    func testKnowledgeKeywordPathEncoded() async throws {
        let http = MockHTTPClient()
        http.enqueue(.json([
            "id": "k:1",
            "normalised": "RETURN POLICY",
            "text": "return policy",
            "documentCount": 2,
            "documents": []
        ]))
        let client = try makeClient(http)
        _ = try await client.knowledge.keywords.get("RETURN POLICY")
        let url = http.recorded.first!.url.absoluteString
        XCTAssertTrue(url.contains("%20"))
    }

    func testSessionsCreateAndTurn() async throws {
        let http = MockHTTPClient()
        http.enqueue(.json([
            "id": "session:abc",
            "scope": [["key": "user", "value": "tobie"]]
        ], status: 201))
        let client = try makeClient(http)
        let session = try await client.sessions.create(scope: ["user": "tobie"])
        XCTAssertEqual(session.id, "session:abc")

        let body = try JSONSerialization.jsonObject(with: http.recorded.first!.body!) as! [String: Any]
        let scope = body["scope"] as! [[String: String]]
        XCTAssertEqual(scope.first, ["key": "user", "value": "tobie"])

        http.enqueue(.json([
            "entities": [],
            "attributes": [],
            "relations": []
        ]))
        let diff = try await session.turn(role: .user, content: "I just got promoted to CTO")
        XCTAssertEqual(diff.entities, [])
    }

    func testMemoryQueryOneShot() async throws {
        let http = MockHTTPClient()
        http.enqueue(.json(["hits": [], "tier": "hybrid", "queryMs": 7]))
        let client = try makeClient(http)
        let out = try await client.query("what role does Christian have?", k: 10)
        XCTAssertEqual(out.tier, "hybrid")
        XCTAssertEqual(out.queryMs, 7)
    }

    func testMemoryState() async throws {
        let http = MockHTTPClient()
        http.enqueue(.json([
            "identity": ["name": "tobie"],
            "instructions": []
        ]))
        let client = try makeClient(http)
        let state = try await client.state()
        XCTAssertEqual(state.identity?["name"], .string("tobie"))
    }

    func testEntitiesGet() async throws {
        let http = MockHTTPClient()
        http.enqueue(.json([
            "type": "Person",
            "name": "christian_battaglia",
            "attributes": ["role": "CTO"]
        ]))
        let client = try makeClient(http)
        let e = try await client.entities.get(type: "Person", name: "christian_battaglia")
        XCTAssertEqual(e.attributes?["role"], .string("CTO"))
    }

    func testLifecycleDecay() async throws {
        let http = MockHTTPClient()
        http.enqueue(.init(status: 204, body: Data()))
        let client = try makeClient(http)
        try await client.lifecycle.decay()
        XCTAssertEqual(http.callCount, 1)
        XCTAssertEqual(http.recorded.first?.method, "POST")
        XCTAssertTrue(http.recorded.first!.url.absoluteString.contains("/lifecycle/decay"))
    }

    func testTracesStats() async throws {
        let http = MockHTTPClient()
        http.enqueue(.json([
            "totalQueries": 42,
            "cacheHits": 30,
            "avgLatencyMs": 4.5
        ]))
        let client = try makeClient(http)
        let stats = try await client.traces.stats()
        XCTAssertEqual(stats.totalQueries, 42)
        XCTAssertEqual(stats.cacheHits, 30)
        XCTAssertEqual(stats.avgLatencyMs, 4.5)
    }
}
