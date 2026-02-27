import Foundation
import Testing
@testable import SurrealDB

private struct IntegrationPerson: SurrealModel, Codable, Sendable {
    static let surrealTable = "person"

    let id: String?
    let name: String
    let age: Int

    init(id: String? = nil, name: String, age: Int) {
        self.id = id
        self.name = name
        self.age = age
    }
}

private func integrationEnabled() -> Bool {
    ProcessInfo.processInfo.environment["SURREALDB_RUN_INTEGRATION"] == "1"
}

private func assertAllOK(_ rows: [RPCQueryResult]) {
    #expect(!rows.isEmpty)
    for row in rows {
        #expect(row.status == .ok)
    }
}

@Test
func integration_wsAuthQueryCrud() async throws {
    guard integrationEnabled() else { return }

    let client = try SurrealWebSocketClient(endpoint: "ws://127.0.0.1:8000")
    try await client.connect()
    defer { Task { await client.close() } }

    _ = try await client.signin(.root(username: "root", password: "root"))
    try await client.use(namespace: "test", database: "test")

    let rows = try await client.queryRaw("SELECT 1 AS value;", bindings: [:])
    #expect(!rows.isEmpty)

    let created = try await client.create(IntegrationPerson(name: "Ada", age: 30))
    #expect(!created.isEmpty)

    let selected = try await client.select(IntegrationPerson.self, where: nil, limit: nil, start: nil)
    #expect(!selected.isEmpty)
}

@Test
func integration_httpParity() async throws {
    guard integrationEnabled() else { return }

    let client = try SurrealHTTPClient(endpoint: "http://127.0.0.1:8000")
    try await client.connect()
    defer { Task { await client.close() } }

    _ = try await client.signin(.root(username: "root", password: "root"))
    try await client.use(namespace: "test", database: "test")

    let rows = try await client.queryRaw("SELECT 1 AS value;", bindings: [:])
    #expect(!rows.isEmpty)
}

@Test
func integration_wsFullCRUDQueries() async throws {
    guard integrationEnabled() else { return }

    let client = try SurrealWebSocketClient(endpoint: "ws://127.0.0.1:8000")
    try await client.connect()
    defer { Task { await client.close() } }

    _ = try await client.signin(.root(username: "root", password: "root"))
    try await client.use(namespace: "test", database: "test")

    let rid = "crud_person:\(UUID().uuidString.lowercased())"

    let create = try await client.queryRaw("CREATE \(rid) CONTENT { name: 'Ada', age: 30 };", bindings: [:])
    assertAllOK(create)

    let select = try await client.queryRaw("SELECT * FROM \(rid);", bindings: [:])
    assertAllOK(select)
    if case .array(let rows) = select[0].result {
        #expect(rows.count == 1)
    } else {
        Issue.record("Expected SELECT result array for created record.")
    }

    let update = try await client.queryRaw("UPDATE \(rid) CONTENT { name: 'Ada', age: 31 };", bindings: [:])
    assertAllOK(update)

    let upsert = try await client.queryRaw("UPSERT \(rid) CONTENT { name: 'Ada', age: 32, city: 'Paris' };", bindings: [:])
    assertAllOK(upsert)

    let delete = try await client.queryRaw("DELETE \(rid);", bindings: [:])
    assertAllOK(delete)

    let selectAfterDelete = try await client.queryRaw("SELECT * FROM \(rid);", bindings: [:])
    assertAllOK(selectAfterDelete)
    if case .array(let rows) = selectAfterDelete[0].result {
        #expect(rows.isEmpty)
    } else {
        Issue.record("Expected SELECT result array after delete.")
    }
}

@Test
func integration_wsFunctionAndGeoQueries() async throws {
    guard integrationEnabled() else { return }

    let client = try SurrealWebSocketClient(endpoint: "ws://127.0.0.1:8000")
    try await client.connect()
    defer { Task { await client.close() } }

    _ = try await client.signin(.root(username: "root", password: "root"))
    try await client.use(namespace: "test", database: "test")

    let defineAndCall = try await client.queryRaw(
        """
        DEFINE FUNCTION fn::sdk::lower($value: string) { RETURN string::lowercase($value); };
        RETURN fn::sdk::lower('HELLO');
        """,
        bindings: [:]
    )
    assertAllOK(defineAndCall)

    let geoQuery = try await client.queryRaw("RETURN geo::distance([51.5074, -0.1278], [40.7128, -74.0060]);", bindings: [:])
    assertAllOK(geoQuery)
}
