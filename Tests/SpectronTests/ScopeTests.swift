import Foundation
import XCTest
@testable import Spectron

final class ScopeTests: XCTestCase {
    let base = "https://api.spectron.test"
    let apiKey = "test-key"
    let ctx = "acme-prod"

    private func makeClient(_ http: MockHTTPClient) throws -> Spectron {
        let transport = try SpectronTransport(endpoint: base, apiKey: apiKey, client: http, sleeper: { _ in })
        return Spectron(context: ctx, transport: transport)
    }

    // MARK: - Normalisation (mirrors the Python scope_paths cases)

    func testEmptyForms() {
        XCTAssertEqual(Scope([]).paths, [])
        XCTAssertEqual(Scope([String]()).paths, [])
        XCTAssertEqual((Scope(pairs: [])).paths, [])
    }

    func testStringPassthrough() {
        let scope: Scope = "team/eng"
        XCTAssertEqual(scope.paths, ["team/eng"])
    }

    func testDictionaryBecomesSlashPaths() {
        let single: Scope = ["user": "alex"]
        XCTAssertEqual(single.paths, ["user/alex"])

        // Dictionary literal preserves source order.
        let multi: Scope = ["team": "eng", "org": "acme"]
        XCTAssertEqual(multi.paths, ["team/eng", "org/acme"])
    }

    func testTuplesBecomeSlashPaths() {
        let scope = Scope(pairs: [("team", "eng"), ("org", "acme")])
        XCTAssertEqual(scope.paths, ["team/eng", "org/acme"])
    }

    func testDedupPreservesOrder() {
        let scope: Scope = ["org/acme", "team/eng", "org/acme"]
        XCTAssertEqual(scope.paths, ["org/acme", "team/eng"])
    }

    func testDropsEmpties() {
        let scope: Scope = ["", "team/eng"]
        XCTAssertEqual(scope.paths, ["team/eng"])
    }

    // MARK: - Wire serialisation

    func testRememberSerialisesDictScopeToSlashPaths() async throws {
        let http = MockHTTPClient()
        http.enqueue(.json(["sessionId": "s", "mode": "full"]))
        let client = try makeClient(http)
        _ = try await client.remember("x", scope: ["org": "acme"])
        let body = try JSONSerialization.jsonObject(with: http.recorded.first!.body!) as! [String: Any]
        XCTAssertEqual(body["scope"] as? [String], ["org/acme"])
    }

    func testChatPassesPathListUnchanged() async throws {
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
        XCTAssertEqual(body["scope"] as? [String], ["team/acme", "project/x"])
    }

    func testEmptyScopeOmittedFromPayload() async throws {
        let http = MockHTTPClient()
        http.enqueue(.json(["sessionId": "s", "mode": "full"]))
        let client = try makeClient(http)
        _ = try await client.remember("x", scope: [])
        let body = try JSONSerialization.jsonObject(with: http.recorded.first!.body!) as! [String: Any]
        XCTAssertNil(body["scope"])
    }

    func testSessionCreateSerialisesScope() async throws {
        let http = MockHTTPClient()
        http.enqueue(.json(["id": "sess:1", "createdAt": "t", "scope": ["org/acme"]], status: 201))
        let client = try makeClient(http)
        let session = try await client.sessions.create(scope: ["org": "acme"])
        XCTAssertEqual(session.info.scope, ["org/acme"])
        let body = try JSONSerialization.jsonObject(with: http.recorded.first!.body!) as! [String: Any]
        XCTAssertEqual(body["scope"] as? [String], ["org/acme"])
    }
}
