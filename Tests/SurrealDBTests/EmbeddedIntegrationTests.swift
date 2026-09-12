#if SURREALDB_EMBEDDED
import Foundation
import Testing
@testable import SurrealDB

private struct EmbeddedPerson: SurrealModel, Codable, Sendable, Equatable {
    static let surrealTable = "embedded_person"
    let id: String?
    let name: String
    let age: Int
}

// No runtime gate here, unlike the ws/http suites. Those need a server that may
// not be running; these need only the native library, and `SURREALDB_EMBEDDED`
// already guarantees it is linked. Reusing SURREALDB_RUN_INTEGRATION would
// conflate "I have a server" with "I have the native library".

private func makeClient() async throws -> SurrealClient {
    let client = try SurrealClient(endpoint: "mem://")
    try await client.connect()
    try await client.use(namespace: "test", database: "test")
    return client
}

@Test
func integration_embeddedConnectUseAndClose() async throws {
    let client = try SurrealClient(endpoint: "mem://")
    #expect(client.engine == .embedded)
    try await client.connect()
    try await client.use(namespace: "test", database: "test")
    await client.close()
    await client.close()
}

@Test
func integration_embeddedQueryRaw() async throws {
    let client = try await makeClient()
    defer { Task { await client.close() } }

    let results = try await client.queryRaw("RETURN 1;")
    #expect(results.count == 1)
    #expect(results[0].status == .ok)
    #expect(!results[0].time.isEmpty)
}

@Test
func integration_embeddedDefineStatementDoesNotBreakTypedDecode() async throws {
    let client = try await makeClient()
    defer { Task { await client.close() } }

    // `sr_query` wraps a unit statement result as `[NONE]`; without the
    // single-unit unwrap this throws while decoding NONE into the model.
    let defined = try await client.query(
        SurrealQuery<EmbeddedPerson>(sql: "DEFINE TABLE embedded_person SCHEMALESS;", bindings: [:])
    )
    #expect(defined.isEmpty)
}

@Test
func integration_embeddedTypedCRUDRoundTrip() async throws {
    let client = try await makeClient()
    defer { Task { await client.close() } }

    _ = try await client.queryRaw("DELETE embedded_person;")

    let created = try await client.create(EmbeddedPerson(id: nil, name: "Ada", age: 36))
    #expect(created.count == 1)
    #expect(created.first?.name == "Ada")

    let selected = try await client.select(EmbeddedPerson.self)
    #expect(selected.contains { $0.name == "Ada" && $0.age == 36 })

    _ = try await client.delete(EmbeddedPerson.self)
    #expect(try await client.select(EmbeddedPerson.self).isEmpty)
}

@Test
func integration_embeddedBindingsRoundTripEveryValueKind() async throws {
    let client = try await makeClient()
    defer { Task { await client.close() } }

    let uuid = UUID()
    let date = Date(timeIntervalSince1970: 1_700_000_000)
    let bindings: [String: SurrealValue] = [
        "v": .object([
            "none": .none,
            "null": .null,
            "bool": .bool(true),
            "int": .int(42),
            "double": .double(1.5),
            "string": .string("hello"),
            "bytes": .bytes(Data([1, 2, 3])),
            "datetime": .datetime(date),
            "uuid": .uuid(uuid),
            "decimal": .decimal("1.25"),
            "duration": .duration("1h30m"),
            "recordString": .recordID(SurrealRecordID(table: "person", id: .string("ada"))),
            "recordInt": .recordID(SurrealRecordID(table: "person", id: .int(7))),
            "point": .geometry(.point([1.0, 2.0])),
            "array": .array([.int(1), .string("two")]),
            "object": .object(["nested": .bool(false)]),
        ])
    ]

    let results = try await client.queryRaw("RETURN $v;", bindings: bindings)
    #expect(results.count == 1)
    #expect(results[0].status == .ok)

    guard case .array(let rows) = results[0].result, case .object(let echoed)? = rows.first else {
        Issue.record("Expected an object back, got \(results[0].result)")
        return
    }

    #expect(echoed["bool"] == .bool(true))
    #expect(echoed["int"] == .int(42))
    #expect(echoed["double"] == .double(1.5))
    #expect(echoed["string"] == .string("hello"))
    #expect(echoed["bytes"] == .bytes(Data([1, 2, 3])))
    #expect(echoed["uuid"] == .uuid(uuid))
    #expect(echoed["decimal"] == .decimal("1.25"))
    #expect(echoed["duration"] == .duration("1h30m"))
    #expect(echoed["recordString"] == .recordID(SurrealRecordID(table: "person", id: .string("ada"))))
    #expect(echoed["recordInt"] == .recordID(SurrealRecordID(table: "person", id: .int(7))))
    #expect(echoed["point"] == .geometry(.point([1.0, 2.0])))
    #expect(echoed["array"] == .array([.int(1), .string("two")]))
    #expect(echoed["object"] == .object(["nested": .bool(false)]))

    if case .datetime(let echoedDate)? = echoed["datetime"] {
        #expect(abs(echoedDate.timeIntervalSince(date)) < 0.001)
    } else {
        Issue.record("Expected a datetime, got \(String(describing: echoed["datetime"]))")
    }
}

@Test
func integration_embeddedRejectsUnsupportedValueKinds() async throws {
    let client = try await makeClient()
    defer { Task { await client.close() } }

    let unsupported: [String: SurrealValue] = [
        "table": .table("person"),
        "range": .range(SurrealRange(begin: .included(.int(1)), end: .excluded(.int(9)))),
        "collection": .geometry(.collection([.point([0, 0])])),
    ]

    for (name, value) in unsupported {
        await #expect(throws: SurrealError.self, "\(name) should be rejected") {
            _ = try await client.queryRaw("RETURN $v;", bindings: ["v": value])
        }
    }
}

@Test
func integration_embeddedPerStatementErrorSurfacesQueryErrors() async throws {
    let client = try await makeClient()
    defer { Task { await client.close() } }

    let results = try await client.queryRaw("RETURN 1; THROW 'boom';")
    #expect(results.count == 2)
    #expect(results[0].status == .ok)
    #expect(results[1].status == .err)
    #expect(!results[1].time.isEmpty)

    // The per-statement error must still reach the typed path as queryErrors.
    await #expect(throws: SurrealError.self) {
        _ = try await client.query(
            SurrealQuery<EmbeddedPerson>(sql: "THROW 'boom';", bindings: [:])
        )
    }
}

@Test
func integration_embeddedTransactionCommits() async throws {
    let client = try await makeClient()
    defer { Task { await client.close() } }

    _ = try await client.queryRaw("DELETE embedded_person;")

    _ = try await client.transaction { transaction in
        transaction.append("CREATE embedded_person SET name = 'Grace', age = 45;")
    }

    let people = try await client.select(EmbeddedPerson.self)
    #expect(people.contains { $0.name == "Grace" })
}

@Test
func integration_embeddedLiveQueryThrowsUnsupportedFeature() async throws {
    let client = try await makeClient()
    defer { Task { await client.close() } }

    await #expect(throws: SurrealError.self) {
        _ = try await client.live(SurrealDSL.live(EmbeddedPerson.self))
    }
}

@Test
func integration_embeddedSessionAPIsThrowUnsupportedFeature() async throws {
    let client = try await makeClient()
    defer { Task { await client.close() } }

    await #expect(throws: SurrealError.self) { _ = try await client.newSession() }
    await #expect(throws: SurrealError.self) { _ = try await client.sessions() }
}

@Test
func integration_embeddedTwoClientsAreIsolated() async throws {
    let first = try await makeClient()
    let second = try await makeClient()
    defer {
        Task {
            await first.close()
            await second.close()
        }
    }

    for client in [first, second] {
        _ = try await client.queryRaw("DEFINE TABLE embedded_person SCHEMALESS;")
    }
    _ = try await first.queryRaw("CREATE embedded_person SET name = 'OnlyHere', age = 1;")

    #expect(try await first.select(EmbeddedPerson.self).contains { $0.name == "OnlyHere" })
    #expect(try await second.select(EmbeddedPerson.self).isEmpty)
}

@Test
func integration_embeddedConcurrentQueriesDoNotDeadlock() async throws {
    let client = try await makeClient()
    defer { Task { await client.close() } }

    try await withThrowingTaskGroup(of: Int.self) { group in
        for index in 0..<32 {
            group.addTask { _ = try await client.queryRaw("RETURN \(index);"); return index }
        }
        var seen = 0
        for try await _ in group { seen += 1 }
        #expect(seen == 32)
    }
}

@Test
func integration_embeddedSendAfterCloseThrowsNotConnected() async throws {
    let client = try await makeClient()
    await client.close()

    await #expect(throws: SurrealError.self) {
        _ = try await client.queryRaw("RETURN 1;")
    }
}
#endif
