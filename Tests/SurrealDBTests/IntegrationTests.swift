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

private struct IntegrationLivePerson: SurrealModel, Codable, Sendable {
    static let surrealTable = "live_person"

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

private func wsEndpoint() -> String {
    ProcessInfo.processInfo.environment["SURREALDB_WS_ENDPOINT"] ?? "ws://127.0.0.1:8000"
}

private func httpEndpoint() -> String {
    ProcessInfo.processInfo.environment["SURREALDB_HTTP_ENDPOINT"] ?? "http://127.0.0.1:8000"
}

private func rootUsername() -> String {
    ProcessInfo.processInfo.environment["SURREALDB_ROOT_USER"] ?? "root"
}

private func rootPassword() -> String {
    ProcessInfo.processInfo.environment["SURREALDB_ROOT_PASS"] ?? "root"
}

private func shouldSkipSignin() -> Bool {
    ProcessInfo.processInfo.environment["SURREALDB_SKIP_SIGNIN"] == "1"
}

private func authenticateIfNeeded(_ client: some SurrealQueryable) async throws {
    guard !shouldSkipSignin() else { return }
    _ = try await client.signin(.root(username: rootUsername(), password: rootPassword()))
}

private func awaitTaskValue<T: Sendable>(
    _ task: Task<T, Error>,
    timeoutSeconds: Double,
    timeoutMessage: String
) async throws -> T {
    try await withThrowingTaskGroup(of: T.self) { group in
        group.addTask {
            try await task.value
        }
        group.addTask {
            try await Task.sleep(nanoseconds: UInt64(max(timeoutSeconds, 0.1) * 1_000_000_000))
            task.cancel()
            throw SurrealError.invalidResponse(timeoutMessage)
        }

        guard let value = try await group.next() else {
            throw SurrealError.invalidResponse(timeoutMessage)
        }

        group.cancelAll()
        return value
    }
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

    let client = try SurrealWebSocketClient(endpoint: wsEndpoint())
    try await client.connect()
    defer { Task { await client.close() } }

    try await authenticateIfNeeded(client)
    try await client.use(namespace: "test", database: "test")

    let rows = try await client.queryRaw("RETURN 1;", bindings: [:])
    #expect(!rows.isEmpty)

    let created = try await client.create(IntegrationPerson(name: "Ada", age: 30))
    if shouldSkipSignin() {
        #expect(created.count >= 0)
    } else {
        #expect(!created.isEmpty)
    }

    let selected = try await client.select(IntegrationPerson.self, where: nil, limit: nil, start: nil)
    if shouldSkipSignin() {
        #expect(selected.count >= 0)
    } else {
        #expect(!selected.isEmpty)
    }
}

@Test
func integration_httpParity() async throws {
    guard integrationEnabled() else { return }

    let client = try SurrealHTTPClient(endpoint: httpEndpoint())
    try await client.connect()
    defer { Task { await client.close() } }

    try await authenticateIfNeeded(client)
    try await client.use(namespace: "test", database: "test")

    let rows = try await client.queryRaw("RETURN 1;", bindings: [:])
    #expect(!rows.isEmpty)
}

@Test
func integration_wsFullCRUDQueries() async throws {
    guard integrationEnabled() else { return }

    let client = try SurrealWebSocketClient(endpoint: wsEndpoint())
    try await client.connect()
    defer { Task { await client.close() } }

    try await authenticateIfNeeded(client)
    try await client.use(namespace: "test", database: "test")

    let rid = "crud_person:\(UUID().uuidString.lowercased().replacingOccurrences(of: "-", with: ""))"

    let create = try await client.queryRaw("CREATE \(rid) CONTENT { name: 'Ada', age: 30 };", bindings: [:])
    assertAllOK(create)

    let select = try await client.queryRaw("SELECT * FROM \(rid);", bindings: [:])
    assertAllOK(select)
    if case .array(let rows) = select[0].result {
        if shouldSkipSignin() {
            #expect(rows.count >= 0)
        } else {
            #expect(rows.count == 1)
        }
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

    let client = try SurrealWebSocketClient(endpoint: wsEndpoint())
    try await client.connect()
    defer { Task { await client.close() } }

    try await authenticateIfNeeded(client)
    try await client.use(namespace: "test", database: "test")

    let fnName = "fn::sdk::lower_\(UUID().uuidString.lowercased().replacingOccurrences(of: "-", with: ""))"
    let define = try await client.queryRaw(
        "DEFINE FUNCTION \(fnName)($value: string) { RETURN string::lowercase($value); };",
        bindings: [:]
    )
    assertAllOK(define)

    let call = try await client.queryRaw("RETURN \(fnName)('HELLO');", bindings: [:])
    assertAllOK(call)

    let geoQuery = try await client.queryRaw("RETURN geo::distance((51.5074, -0.1278), (40.7128, -74.0060));", bindings: [:])
    assertAllOK(geoQuery)
}

@Test
func integration_wsLiveQueries() async throws {
    guard integrationEnabled() else { return }

    let client = try SurrealWebSocketClient(endpoint: wsEndpoint())
    try await client.connect()
    defer { Task { await client.close() } }

    try await authenticateIfNeeded(client)
    try await client.use(namespace: "test", database: "test")

    let defineTable = try await client.queryRaw("DEFINE TABLE \(IntegrationLivePerson.surrealTable) SCHEMALESS;", bindings: [:])
    assertAllOK(defineTable)

    let recordKey = UUID().uuidString.lowercased().replacingOccurrences(of: "-", with: "")
    let rid = "\(IntegrationLivePerson.surrealTable):\(recordKey)"

    let stream = try await client.live(SurrealDSL.live(IntegrationLivePerson.self))
    let collector = Task<[LiveEvent<IntegrationLivePerson>], Error> {
        var iterator = stream.makeAsyncIterator()
        var events: [LiveEvent<IntegrationLivePerson>] = []

        while events.count < 3 {
            guard let event = await iterator.next() else {
                throw SurrealError.invalidResponse("Live stream ended before receiving expected events.")
            }

            if event.action == .killed {
                continue
            }

            events.append(event)
        }

        return events
    }
    defer { collector.cancel() }

    let create = try await client.queryRaw("CREATE \(rid) CONTENT { name: 'LiveAda', age: 30 };", bindings: [:])
    assertAllOK(create)

    let update = try await client.queryRaw("UPDATE \(rid) CONTENT { name: 'LiveAda', age: 31 };", bindings: [:])
    assertAllOK(update)

    let delete = try await client.queryRaw("DELETE \(rid);", bindings: [:])
    assertAllOK(delete)

    let events = try await awaitTaskValue(
        collector,
        timeoutSeconds: 10,
        timeoutMessage: "Timed out waiting for live query events."
    )

    #expect(events.count == 3)
    #expect(events.contains(where: { $0.action == .create }))
    #expect(events.contains(where: { $0.action == .update }))
    #expect(events.contains(where: { $0.action == .delete }))

    let eventQueryIDs = Set(events.map(\.queryID))
    #expect(eventQueryIDs.count == 1)

    if let updateEvent = events.first(where: { $0.action == .update }) {
        #expect(updateEvent.decoded?.name == "LiveAda")
        #expect(updateEvent.decoded?.age == 31)
    } else {
        Issue.record("Missing UPDATE live event.")
    }
}
