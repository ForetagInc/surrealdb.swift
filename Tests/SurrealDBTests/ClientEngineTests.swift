import Foundation
import Testing
@testable import SurrealDB

private struct EngineProbe: SurrealModel, Codable, Sendable {
    static let surrealTable = "engine_probe"
    let id: String?
    let name: String
}

@Test
func client_selectsWebSocketEngineForWSSchemes() throws {
    #expect(try SurrealClient(endpoint: "ws://localhost:8000").engine == .webSocket)
    #expect(try SurrealClient(endpoint: "wss://example.com").engine == .webSocket)
}

@Test
func client_selectsHTTPEngineForHTTPSchemes() throws {
    #expect(try SurrealClient(endpoint: "http://localhost:8000").engine == .http)
    #expect(try SurrealClient(endpoint: "https://example.com").engine == .http)
}

@Test
func client_handlesMemScheme() throws {
    #if SURREALDB_EMBEDDED
    #expect(try SurrealClient(endpoint: "mem://").engine == .embedded)
    #else
    // Without the native library the scheme is still recognised; the failure
    // tells the caller how to get embedded support rather than claiming the
    // endpoint is malformed.
    #expect(throws: SurrealError.self) {
        _ = try SurrealClient(endpoint: "mem://")
    }
    #endif
}

@Test
func client_rejectsUnknownSchemes() {
    #expect(throws: SurrealError.self) {
        _ = try SurrealClient(endpoint: "ftp://localhost:8000")
    }
    #expect(throws: SurrealError.self) {
        _ = try SurrealClient(endpoint: "not a url")
    }
}

@Test
func client_liveQueryOnHTTPThrowsUnsupportedFeature() async throws {
    let client = try SurrealClient(endpoint: "http://localhost:8000")
    await #expect(throws: SurrealError.self) {
        _ = try await client.live(SurrealDSL.live(EngineProbe.self))
    }
}
