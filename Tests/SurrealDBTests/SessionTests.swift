import Foundation
import Testing
@testable import SurrealDB

@Test
func sessionID_equalityIsByRawValue() {
    let raw = UUID()
    let a = SessionID(raw)
    let b = SessionID(raw)
    let c = SessionID()

    #expect(a == b)
    #expect(a != c)
    #expect(a.description == raw.uuidString)
}

@Test
func invalidSession_messageAndRecoverySuggestion() {
    let id = SessionID()
    let error = SurrealError.invalidSession(id)

    #expect(error.message.contains(id.description))
    #expect(error.recoverySuggestion != nil)
}

@Test
func client_newSessionOnHTTPThrowsUnsupportedFeature() async throws {
    let client = try SurrealClient(endpoint: "http://localhost:8000")
    await #expect(throws: SurrealError.self) {
        _ = try await client.newSession()
    }
}

@Test
func client_sessionsOnHTTPThrowsUnsupportedFeature() async throws {
    let client = try SurrealClient(endpoint: "http://localhost:8000")
    await #expect(throws: SurrealError.self) {
        _ = try await client.sessions()
    }
}

@Test
func client_newSessionOnWebSocketReachesAttachAttempt() async throws {
    // Not connected, so the session-capability gate should pass (no
    // .unsupportedFeature) and the real attach RPC should be attempted,
    // failing with .notConnected rather than a gating error.
    let client = try SurrealClient(endpoint: "ws://localhost:8000")
    do {
        _ = try await client.newSession()
        Issue.record("Expected newSession() to throw without a connection")
    } catch SurrealError.notConnected {
        // expected
    }
}

@Test
func client_rootSessionIDIsNil() throws {
    let client = try SurrealClient(endpoint: "ws://localhost:8000")
    #expect(client.id == nil)
}

@Test
func session_unattachedIDThrowsInvalidSessionLocally() async throws {
    let client = try SurrealClient(endpoint: "ws://localhost:8000")
    let stray = client.session(id: SessionID())

    await #expect(throws: SurrealError.self) {
        try await stray.use(namespace: "n", database: "d")
    }
}

@Test
func session_handleCarriesTheGivenID() throws {
    let client = try SurrealClient(endpoint: "ws://localhost:8000")
    let id = SessionID()
    let session = client.session(id: id)
    #expect(session.id == id)
}

@Test
func client_setAndUnsetSucceedWithoutAConnection() async throws {
    // Variables are purely local, client-merged-at-query-time state — no RPC
    // round trip, so these must succeed even before connect() is called.
    let client = try SurrealClient(endpoint: "http://localhost:8000")
    try await client.set("foo", value: .int(1))
    try await client.unset("foo")
}

@Test
func surrealQueryable_conformanceHoldsForClientAndSession() throws {
    let client = try SurrealClient(endpoint: "ws://localhost:8000")
    let session = client.session(id: SessionID())

    let clientAsQueryable: any SurrealQueryable = client
    let clientAsLiveQueryable: any SurrealLiveQueryable = client
    let sessionAsQueryable: any SurrealQueryable = session
    let sessionAsLiveQueryable: any SurrealLiveQueryable = session

    _ = clientAsQueryable
    _ = clientAsLiveQueryable
    _ = sessionAsQueryable
    _ = sessionAsLiveQueryable
}
