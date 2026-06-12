import Foundation
import XCTest
@testable import Spectron

final class TransportTests: XCTestCase {
    let base = "https://api.spectron.test"
    let apiKey = "test-key"

    private func makeTransport(client: MockHTTPClient, maxRetries: Int = 3) throws -> SpectronTransport {
        try SpectronTransport(
            endpoint: base,
            apiKey: apiKey,
            timeout: 5,
            maxRetries: maxRetries,
            client: client,
            sleeper: { _ in }
        )
    }

    func testGetSendsBearerHeader() async throws {
        let client = MockHTTPClient()
        client.enqueue(.json(["ok": true]))
        let t = try makeTransport(client: client)
        let (_, json) = try await t.request(method: "GET", path: "/api/v1/x/health")
        XCTAssertEqual(json?.asObject?["ok"], .bool(true))
        XCTAssertEqual(client.recorded.first?.headers["Authorization"], "Bearer \(apiKey)")
        XCTAssertEqual(client.recorded.first?.headers["Accept"], "application/json")
    }

    func testGetRetriesOn5xxThenSucceeds() async throws {
        let client = MockHTTPClient()
        client.enqueueMany([
            .json(["e": 1], status: 503),
            .json(["e": 2], status: 502),
            .json(["ok": true], status: 200)
        ])
        let t = try makeTransport(client: client)
        let (_, json) = try await t.request(method: "GET", path: "/api/v1/x/y")
        XCTAssertEqual(json?.asObject?["ok"], .bool(true))
        XCTAssertEqual(client.callCount, 3)
    }

    func testGetRetriesExhaustRaisesServerError() async throws {
        let client = MockHTTPClient()
        for _ in 0..<4 {
            client.enqueue(.json(["title": "down"], status: 500))
        }
        let t = try makeTransport(client: client)
        do {
            _ = try await t.request(method: "GET", path: "/api/v1/x/y")
            XCTFail("Expected SpectronError")
        } catch let err as SpectronError {
            XCTAssertEqual(err.kind, .server)
            XCTAssertEqual(err.status, 500)
        }
        XCTAssertEqual(client.callCount, 4)
    }

    func testPostDoesNotRetryOn5xx() async throws {
        let client = MockHTTPClient()
        client.enqueue(.json(["title": "down"], status: 503))
        let t = try makeTransport(client: client)
        let body = try JSONEncoder().encode(["hello": "world"])
        do {
            _ = try await t.request(method: "POST", path: "/api/v1/x/z", jsonBody: body)
            XCTFail("Expected SpectronError")
        } catch let err as SpectronError {
            XCTAssertEqual(err.kind, .server)
        }
        XCTAssertEqual(client.callCount, 1)
    }

    func test404MapsToNotFound() async throws {
        let client = MockHTTPClient()
        client.enqueue(.json(["title": "gone", "detail": "no such doc"], status: 404))
        let t = try makeTransport(client: client)
        do {
            _ = try await t.request(method: "GET", path: "/api/v1/x/missing")
            XCTFail("Expected SpectronError")
        } catch let err as SpectronError {
            XCTAssertEqual(err.kind, .notFound)
            XCTAssertEqual(err.detail, "no such doc")
        }
    }

    func test401MapsToAuthError() async throws {
        let client = MockHTTPClient()
        client.enqueue(.json(["title": "auth"], status: 401))
        let t = try makeTransport(client: client)
        do {
            _ = try await t.request(method: "GET", path: "/api/v1/x/secure")
            XCTFail("Expected SpectronError")
        } catch let err as SpectronError {
            XCTAssertEqual(err.kind, .auth)
        }
    }

    func test429PreservesRetryAfter() async throws {
        let client = MockHTTPClient()
        client.enqueue(.json(["title": "slow"], status: 429, headers: ["Retry-After": "7"]))
        let t = try makeTransport(client: client)
        do {
            let body = try JSONEncoder().encode([String: String]())
            _ = try await t.request(method: "POST", path: "/api/v1/x/burst", jsonBody: body)
            XCTFail("Expected SpectronError")
        } catch let err as SpectronError {
            XCTAssertEqual(err.kind, .rateLimit)
            XCTAssertEqual(err.retryAfter, 7.0)
        }
    }

    func testBodyJSONPayloadSent() async throws {
        let client = MockHTTPClient()
        client.enqueue(.json(["ack": true]))
        let t = try makeTransport(client: client)
        let body = try JSONEncoder().encode(["hello": "world"])
        _ = try await t.request(method: "POST", path: "/api/v1/x/echo", jsonBody: body)
        let rec = client.recorded.first!
        XCTAssertEqual(rec.headers["Content-Type"], "application/json")
        let sent = try JSONDecoder().decode([String: String].self, from: rec.body!)
        XCTAssertEqual(sent, ["hello": "world"])
    }

    func testNoContentReturnsNil() async throws {
        let client = MockHTTPClient()
        client.enqueue(.init(status: 204, body: Data()))
        let t = try makeTransport(client: client)
        let (data, json) = try await t.request(method: "DELETE", path: "/api/v1/x/r")
        XCTAssertEqual(data, Data())
        XCTAssertNil(json)
    }

    func testEndpointTrimsTrailingSlash() async throws {
        let client = MockHTTPClient()
        client.enqueue(.json(["ok": true]))
        let t = try SpectronTransport(
            endpoint: "\(base)/",
            apiKey: apiKey,
            client: client,
            sleeper: { _ in }
        )
        _ = try await t.request(method: "GET", path: "/api/v1/x/y")
        XCTAssertEqual(client.recorded.first?.url.absoluteString, "\(base)/api/v1/x/y")
    }

    func testAPIKeyRequired() {
        XCTAssertThrowsError(try SpectronTransport(endpoint: base, apiKey: ""))
    }

    func testEndpointRequired() {
        XCTAssertThrowsError(try SpectronTransport(endpoint: "", apiKey: apiKey))
    }
}
