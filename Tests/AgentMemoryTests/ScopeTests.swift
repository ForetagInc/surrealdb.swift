import Foundation
import XCTest
@testable import AgentMemory

final class ScopeTests: XCTestCase {
    let base = "https://api.memory.test"
    let apiKey = "test-key"
    let ctx = "acme-prod"

    private func makeClient(_ http: MockHTTPClient) throws -> AgentMemory {
        let transport = try AgentMemoryTransport(endpoint: base, apiKey: apiKey, client: http, sleeper: { _ in })
        return AgentMemory(context: ctx, transport: transport)
    }

    // MARK: - Normalisation (disjunctive normal form: an OR of AND-clauses)

    func testEmptyForms() {
        XCTAssertEqual(Scope([]).clauses, [])
        XCTAssertEqual(Scope([[String]]()).clauses, [])
    }

    func testStringIsSinglePathClause() {
        let scope: Scope = "team/eng"
        XCTAssertEqual(scope.clauses, [["team/eng"]])
    }

    func testFlatListIsOrOfClauses() {
        let scope: Scope = ["team/eng", "org/acme"]
        XCTAssertEqual(scope.clauses, [["team/eng"], ["org/acme"]])
    }

    func testNestedListIsAndClause() {
        let scope: Scope = [["team/eng", "org/acme"]]
        XCTAssertEqual(scope.clauses, [["team/eng", "org/acme"]])
    }

    func testMixedLiteralCombinesOrAndAnd() {
        let scope: Scope = ["team/eng", ["org/acme", "tier/gold"]]
        XCTAssertEqual(scope.clauses, [["team/eng"], ["org/acme", "tier/gold"]])
    }

    func testDedupPreservesOrder() {
        let scope: Scope = ["org/acme", "team/eng", "org/acme"]
        XCTAssertEqual(scope.clauses, [["org/acme"], ["team/eng"]])
    }

    func testDropsEmpties() {
        let scope: Scope = ["", "team/eng", [""]]
        XCTAssertEqual(scope.clauses, [["team/eng"]])
    }

    // MARK: - Wire serialisation

    func testRememberSerialisesScopesAsDNF() async throws {
        let http = MockHTTPClient()
        http.enqueue(.json(["sessionId": "s", "mode": "full"]))
        let client = try makeClient(http)
        _ = try await client.remember("x", scope: "org/acme")
        let body = try JSONSerialization.jsonObject(with: http.recorded.first!.body!) as! [String: Any]
        XCTAssertEqual(body["scopes"] as? [[String]], [["org/acme"]])
    }

    func testFlatScopeSerialisesAsOrClauses() async throws {
        let http = MockHTTPClient()
        http.enqueue(.json([
            "reply": "ok", "sessionId": "s", "traceId": "t",
            "memoryUpdates": [
                "turnId": "u", "entities": [], "attributes": [], "relations": [],
                "corrections": [], "instructions": [], "uncertainties": []
            ]
        ]))
        let client = try makeClient(http)
        _ = try await client.chat("y", scope: ["team/acme", "project/x"])
        let body = try JSONSerialization.jsonObject(with: http.recorded.first!.body!) as! [String: Any]
        XCTAssertEqual(body["scopes"] as? [[String]], [["team/acme"], ["project/x"]])
    }

    func testNestedScopeSerialisesAsAndClause() async throws {
        let http = MockHTTPClient()
        http.enqueue(.json(["sessionId": "s", "mode": "full"]))
        let client = try makeClient(http)
        _ = try await client.remember("x", scope: [["team/acme", "project/x"]])
        let body = try JSONSerialization.jsonObject(with: http.recorded.first!.body!) as! [String: Any]
        XCTAssertEqual(body["scopes"] as? [[String]], [["team/acme", "project/x"]])
    }

    func testEmptyScopeOmittedFromPayload() async throws {
        let http = MockHTTPClient()
        http.enqueue(.json(["sessionId": "s", "mode": "full"]))
        let client = try makeClient(http)
        _ = try await client.remember("x", scope: [])
        let body = try JSONSerialization.jsonObject(with: http.recorded.first!.body!) as! [String: Any]
        XCTAssertNil(body["scopes"])
    }

    func testRecallSerialisesLensAsDNF() async throws {
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
        _ = try await client.recall("q", lens: ["team/eng", ["org/acme", "tier/gold"]])
        let body = try JSONSerialization.jsonObject(with: http.recorded.first!.body!) as! [String: Any]
        XCTAssertEqual(body["lens"] as? [[String]], [["team/eng"], ["org/acme", "tier/gold"]])
    }

    func testSessionCreateSerialisesScope() async throws {
        let http = MockHTTPClient()
        http.enqueue(.json(["id": "sess:1", "createdAt": "t", "scopes": [["org/acme"]]], status: 201))
        let client = try makeClient(http)
        let session = try await client.sessions.create(scope: "org/acme")
        XCTAssertEqual(session.info.scopes, [["org/acme"]])
        let body = try JSONSerialization.jsonObject(with: http.recorded.first!.body!) as! [String: Any]
        XCTAssertEqual(body["scopes"] as? [[String]], [["org/acme"]])
    }
}
