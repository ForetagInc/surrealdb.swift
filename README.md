# SurrealDB Swift SDK

A Swift SDK for [SurrealDB](https://surrealdb.com) with full async/await support, type-safe query macros, and live query streaming.

> **Alpha release** - this SDK is in early development and the public API is subject to breaking changes without notice.

## Requirements

- Swift 6.1+
- SurrealDB v3+

## Platforms

iOS 17+ · macOS 14+ · tvOS 17+ · watchOS 10+ · visionOS 1+

## Features

- Pluggable transport engines (HTTP, WebSocket) with room for additional engines (e.g. embedded) down the line
- Pluggable wire protocols (CBOR, JSON-RPC) — opt into either per-client
- Type-safe CRUD via `@SurrealModel` macro and query DSL
- Live queries over WebSocket via `AsyncStream`
- Client-side transactions (`BEGIN; … COMMIT;`) with automatic binding-collision rewriting
- Raw SQL queries with bound parameters
- Root, namespace, database, and record-access authentication
- Automatic WebSocket reconnection

---

## Installation

Add the package to your `Package.swift`:

```swift
dependencies: [
    .package(url: "https://github.com/surrealdb/surrealdb.swift.git", from: "0.1.0"),
],
targets: [
    .target(
        name: "YourTarget",
        dependencies: [
            .product(name: "SurrealDB", package: "surrealdb.swift")
        ]
    )
]
```

---

## Quick Start

```swift
import SurrealDB

// 1. Define a model
@SurrealModel("person")
struct Person: Codable, Sendable {
    let id: String?
    let name: String
    let age: Int
}

// 2. Create a client and connect
let client = try SurrealWebSocketClient(endpoint: "ws://localhost:8000")
try await client.connect()

// 3. Authenticate and select a namespace/database
_ = try await client.signin(.root(username: "root", password: "root"))
try await client.use(namespace: "myapp", database: "mydb")

// 4. Create a record
let people = try await client.create(Person(id: nil, name: "Ada", age: 30))

// 5. Query records
let results = try await client.select(Person.self, where: Person.Fields.age > 18, limit: 10)
```

---

## Defining Models

Annotate any `struct`, `class`, or `actor` with `@SurrealModel` to bind it to a SurrealDB table. The macro generates a `surrealTable` constant, a `SurrealModel` conformance, and a `Fields` namespace for type-safe predicates.

```swift
@SurrealModel("article")
struct Article: Codable, Sendable {
    let id: String?
    let title: String
    let published: Bool
    let views: Int
}

// Generated Fields:
// Article.Fields.id      → SurrealField<Article, String?>
// Article.Fields.title   → SurrealField<Article, String>
// Article.Fields.published → SurrealField<Article, Bool>
// Article.Fields.views   → SurrealField<Article, Int>
```

If you prefer not to use the macro, conform to `SurrealModel` manually:

```swift
struct Article: SurrealModel, Codable, Sendable {
    static let surrealTable = "article"
    let id: String?
    let title: String
}
```

---

## Connecting

### HTTP Client

Suitable for request/response workloads. Does not support live queries.

```swift
let client = try SurrealHTTPClient(endpoint: "http://localhost:8000")
try await client.connect()
defer { Task { await client.close() } }
```

### WebSocket Client

Required for live queries. Reconnects automatically by default.

```swift
let client = try SurrealWebSocketClient(
    endpoint: "ws://localhost:8000",
    websocketOptions: SurrealWebSocketOptions(
        reconnectEnabled: true,
        maxReconnectAttempts: 8,
        reconnectBaseDelay: 0.5
    )
)
try await client.connect()
defer { Task { await client.close() } }
```

### Wire Protocol

Both clients default to SurrealDB's tagged CBOR encoding, which preserves all `SurrealValue` types (UUID, datetime, decimal, duration, record IDs, geometries, ranges, …) losslessly. JSON-RPC is also supported and may be preferable for environments where CBOR is harder to inspect.

```swift
// CBOR (default) — full fidelity
let cbor = try SurrealWebSocketClient(endpoint: "ws://localhost:8000")

// JSON-RPC — primitives only; SurrealDB-specific types are coerced to strings
let json = try SurrealHTTPClient(
    endpoint: "http://localhost:8000",
    wireProtocol: .json
)
```

The wire protocol controls both the HTTP `Content-Type` and the WebSocket sub-protocol negotiated during the handshake.

### Selecting a Namespace and Database

```swift
try await client.use(namespace: "myapp", database: "mydb")
```

---

## Authentication

### Root

```swift
let tokens = try await client.signin(.root(username: "root", password: "root"))
```

### Namespace user

```swift
let tokens = try await client.signin(.namespace(
    namespace: "myapp",
    username: "ns_user",
    password: "secret"
))
```

### Database user

```swift
let tokens = try await client.signin(.database(
    namespace: "myapp",
    database: "mydb",
    username: "db_user",
    password: "secret"
))
```

### Record access (custom variables)

```swift
let tokens = try await client.signin(.accessVariables(
    namespace: "myapp",
    database: "mydb",
    access: "account",
    variables: ["email": .string("user@example.com"), "pass": .string("secret")]
))
```

### Bearer token access

```swift
let tokens = try await client.signin(.accessBearer(
    namespace: "myapp",
    database: "mydb",
    access: "account",
    key: "bearer-token-value"
))
```

### Sign up (record access)

```swift
let tokens = try await client.signup(.accessRecord(
    namespace: "myapp",
    database: "mydb",
    access: "account",
    variables: ["email": .string("new@example.com"), "pass": .string("secret")]
))
```

### Resuming a session

```swift
try await client.authenticate(tokens.access)

// Or start with a pre-existing token
let client = try SurrealHTTPClient(
    endpoint: "http://localhost:8000",
    session: SessionContext(
        namespace: "myapp",
        database: "mydb",
        accessToken: "existing-jwt"
    )
)
```

### Invalidating a session

```swift
try await client.invalidate()
```

---

## CRUD Operations

### Select (all records)

```swift
// All records
let people = try await client.select(Person.self)

// With a predicate, limit, and offset
let adults = try await client.select(
    Person.self,
    where: Person.Fields.age >= 18,
    limit: 20,
    start: 0
)
```

### Select (single record by ID)

```swift
let id = SurrealRecordID(table: "person", id: .string("ada"))
let person: Person? = try await client.select(recordID: id, as: Person.self)
```

### Create

```swift
// Auto-generated ID
let created: [Person] = try await client.create(Person(id: nil, name: "Ada", age: 30))

// Specific record ID
let id = SurrealRecordID(table: "person", id: .string("ada"))
let record: Person? = try await client.create(
    recordID: id,
    content: Person(id: nil, name: "Ada", age: 30)
)
```

### Update

```swift
// Update all matching records
let updated = try await client.update(
    Person.self,
    content: Person(id: nil, name: "Ada", age: 31),
    where: Person.Fields.name == "Ada"
)

// Update a specific record
let id = SurrealRecordID(table: "person", id: .string("ada"))
let record: Person? = try await client.update(
    recordID: id,
    content: Person(id: nil, name: "Ada", age: 31)
)
```

### Upsert

```swift
let upserted = try await client.upsert(
    Person.self,
    content: Person(id: nil, name: "Ada", age: 31),
    where: Person.Fields.name == "Ada"
)
```

### Delete

```swift
// Delete matching records
let deleted = try await client.delete(Person.self, where: Person.Fields.age < 18)

// Delete a specific record
let id = SurrealRecordID(table: "person", id: .string("ada"))
let record: Person? = try await client.delete(recordID: id, as: Person.self)
```

---

## Predicates

`Fields` properties support Swift comparison operators that produce type-safe `SurrealPredicate` values.

```swift
// Equality
Person.Fields.name == "Ada"
Person.Fields.name != "Bob"

// Comparisons
Person.Fields.age > 18
Person.Fields.age >= 21
Person.Fields.age < 65
Person.Fields.age <= 60

// Combining
let predicate = Person.Fields.age >= 18 && Person.Fields.published == true
let either    = Person.Fields.age < 18  || Person.Fields.name == "Admin"
let negated   = !(Person.Fields.published == false)

// Raw string predicate
let raw = SurrealPredicate(raw: "age > 18 AND name != 'Bot'")
```

---

## Query Macros

The SDK ships expression macros that resolve to `SurrealDSL` calls at compile time. Use them anywhere you would build a `SurrealQuery` by hand.

```swift
import SurrealDB

let selectQuery  = #select(Person.self, where: Person.Fields.age > 18, limit: 10)
let createQuery  = #create(Person.self)
let updateQuery  = #update(Person.self, where: Person.Fields.name == "Ada")
let upsertQuery  = #upsert(Person.self)
let deleteQuery  = #delete(Person.self, where: Person.Fields.age < 18)
let liveQuery    = #live(Person.self)

let people = try await client.query(selectQuery)
```

---

## Type-Safe Query DSL

`SurrealDSL` is the programmatic alternative to the macros, useful when you need to build queries at runtime.

```swift
let query = SurrealDSL.select(
    Person.self,
    where: Person.Fields.age >= 21,
    limit: 50,
    start: 0
)
let people = try await client.query(query)

let createQuery = SurrealDSL.create(
    Person.self,
    contentBinding: "content",
    bindings: ["content": try .fromEncodable(newPerson)]
)
let created = try await client.query(createQuery)
```

---

## Live Queries

Live queries require `SurrealWebSocketClient` and return an `AsyncStream<LiveEvent<T>>`.

```swift
let client = try SurrealWebSocketClient(endpoint: "ws://localhost:8000")
try await client.connect()
_ = try await client.signin(.root(username: "root", password: "root"))
try await client.use(namespace: "myapp", database: "mydb")

let stream = try await client.live(SurrealDSL.live(Person.self))

for await event in stream {
    switch event.action {
    case .create:
        print("Created:", event.decoded as Any)
    case .update:
        print("Updated:", event.decoded as Any)
    case .delete:
        print("Deleted record:", event.recordID)
    case .killed:
        print("Live query was killed")
    }
}
```

Cancel the stream by killing the live query:

```swift
// Capture the queryID from the first event, then:
try await client.kill(liveQueryID: event.queryID)
```

---

## Raw Queries

Run arbitrary SurrealQL with bound parameters:

```swift
let results: [RPCQueryResult] = try await client.queryRaw(
    "SELECT * FROM person WHERE age > $minAge LIMIT $limit;",
    bindings: [
        "minAge": .int(18),
        "limit":  .int(50)
    ]
)

for row in results {
    if row.status == .ok {
        print(row.result) // SurrealValue
    }
}
```

---

## Transactions

`transaction { tx in … }` bundles multiple statements into a single `BEGIN; … COMMIT;` query call. SurrealDB cancels the transaction server-side if any statement fails.

```swift
let results = try await client.transaction { tx in
    tx.append(
        "CREATE person CONTENT $content",
        bindings: ["content": try .fromEncodable(Person(id: nil, name: "Ada", age: 30))]
    )
    tx.append(
        "UPDATE person SET age = 31 WHERE name = $name",
        bindings: ["name": .string("Ada")]
    )
}
```

Typed `SurrealQuery<T>` values (including those produced by the macros and DSL) can be appended directly:

```swift
try await client.transaction { tx in
    tx.append(#create(Person.self))
    tx.append(#update(Person.self, where: Person.Fields.name == "Ada"))
}
```

If two statements share a binding name with different values, the second one is automatically renamed (`$content` → `$content_tx1`) and its SQL is rewritten to match — so you can freely combine independently built queries.

To abort before flushing, simply throw from the closure; no `BEGIN` is sent.

```swift
try await client.transaction { tx in
    tx.append(#create(Person.self))
    if shouldAbort { throw MyError.cancelled } // nothing is sent to the server
    tx.append(#update(Person.self))
}
```

---

## SurrealValue

`SurrealValue` is the SDK's universal value type for working with raw SurrealDB data.

```swift
// Constructing values
let v: SurrealValue = .string("hello")
let v: SurrealValue = .int(42)
let v: SurrealValue = .double(3.14)
let v: SurrealValue = .bool(true)
let v: SurrealValue = .null
let v: SurrealValue = .array([.string("a"), .int(1)])
let v: SurrealValue = .object(["name": .string("Ada"), "age": .int(30)])
let v: SurrealValue = .uuid(UUID())
let v: SurrealValue = .datetime(Date())
let v: SurrealValue = .recordID(SurrealRecordID(table: "person", id: .string("ada")))

// Convert any Encodable to SurrealValue
let value = try SurrealValue.fromEncodable(myStruct)

// Decode a SurrealValue back to a Swift type
let person = try value.decode(Person.self)
```

---

## Configuration

### `SurrealClientOptions`

Applies to both HTTP and WebSocket clients:

```swift
SurrealClientOptions(
    requestTimeout: 20,   // seconds, default 20
    pingInterval: 30      // seconds, default 30
)
```

### `SurrealWebSocketOptions`

```swift
SurrealWebSocketOptions(
    reconnectEnabled: true,       // default true
    maxReconnectAttempts: 8,      // default 8
    reconnectBaseDelay: 0.5       // seconds, default 0.5
)
```

### `SessionContext`

Pre-populate namespace, database, and access token at init time:

```swift
SessionContext(
    namespace: "myapp",
    database: "mydb",
    accessToken: nil,
    variables: [:]
)
```

---

## Spectron

The package also ships a `Spectron` library product, a client for [Spectron](https://surrealdb.com/platform/spectron), SurrealDB's memory and knowledge API. Add it to your target alongside `SurrealDB` (or on its own):

```swift
.product(name: "Spectron", package: "surrealdb.swift")
```

```swift
import Spectron

let memory = try Spectron(
    context: "acme-prod",
    endpoint: "https://api.spectron.example",
    apiKey: "sk-spec-..."
)

let hits = try await memory.knowledge.query("returns policy", k: 5)
```

The client is `Sendable` and built on Swift `async/await`. The underlying `SpectronTransport` is an actor backed by `URLSession`, and you can swap in your own `HTTPClient` for testing.

### Knowledge

Documents:

```swift
let doc = try await memory.knowledge.upload(
    file: .fileURL(URL(fileURLWithPath: "returns.pdf"), filename: nil, mimeType: "application/pdf"),
    title: "Returns Policy",
    profile: .multimodalBalanced,
    scope: ["org": "anneal"]
)

_ = try await memory.knowledge.get(doc.id)
_ = try await memory.knowledge.replace(documentId: doc.id, file: .fileURL(URL(fileURLWithPath: "returns_v2.pdf"), filename: nil, mimeType: "application/pdf"))
_ = try await memory.knowledge.raw(doc.id)
_ = try await memory.knowledge.chunks(doc.id, page: 0, pageSize: 50)
_ = try await memory.knowledge.list(status: "ready", mimeType: "application/pdf")
_ = try await memory.knowledge.related(doc.id)
try await memory.knowledge.delete(doc.id)
```

Query:

```swift
let hits = try await memory.knowledge.query(
    "what is the return window for unopened items?",
    mode: .hybridGraph,
    k: 10,
    threshold: 0.5,
    vectorWeight: 0.5,
    rrfK: 60,
    graphAlpha: 0.3,
    graphEdges: ["knowledge_has_keyword", "knowledge_relates_to"],
    graphDepth: 2,
    expandGraph: true,
    filter: QueryFilter(mimeType: ["application/pdf"], scope: ["org": "anneal"])
)
```

Keywords and nodes:

```swift
_ = try await memory.knowledge.keywords.list(minDocumentCount: 2, sort: "-document_count", q: "return")
_ = try await memory.knowledge.keywords.search("refund policies", k: 10, threshold: 0.6)
_ = try await memory.knowledge.keywords.forDocument(doc.id)

try await memory.knowledge.nodes.upsert(
    nodes: [
        KnowledgeNodeUpsertRow(kind: "product", slug: "airpods_pro_2", title: "AirPods Pro 2",
                               content: ["price": .int(249), "category": .string("Audio")]),
        KnowledgeNodeUpsertRow(kind: "policy", slug: "returns", title: "Returns",
                               content: ["duration": .string("30 days")])
    ],
    relations: [
        KnowledgeLinkUpsert(label: "covered_by",
                            to: KnowledgeLinkTarget(kind: "policy", slug: "returns"))
    ],
    scope: ["org": "apple"]
)
```

Traversal:

```swift
_ = try await memory.knowledge.traverse(
    start: [TraverseStart(type: "document", id: doc.id)],
    edges: ["knowledge_has_keyword", "knowledge_relates_to"],
    maxDepth: 2
)

_ = try await memory.knowledge.traverseRecursive(
    start: TraverseStart(type: "knowledge", kind: "product", slug: "airpods_pro_2"),
    edge: "knowledge_relates_to",
    maxDepth: 3
)
```

### Sessions

Drive the chat loop with a session:

```swift
let session = try await memory.sessions.create(scope: ["user": "tobie"])

_ = try await session.turn(role: .user, content: "I just got promoted to CTO")

let ctx = try await session.context("What is Tobie's role?")
let reply = try await myLLM.chat(system: ctx.context, user: userMessage)
_ = try await session.turn(role: .assistant, content: reply)

_ = try await session.turns()
try await session.close()
```

Or let Spectron run the loop:

```swift
let reply = try await session.chat("What do you know about me?")
```

### One-shot retrieval, state, profile, entities

```swift
_ = try await memory.query("What role does Christian have?", k: 10)
_ = try await memory.context("brief on tobie", k: 10)

_ = try await memory.state()
_ = try await memory.profile()

_ = try await memory.entities.list(type: "Person")
_ = try await memory.entities.get(type: "Person", name: "christian_battaglia")
_ = try await memory.entities.history(type: "Person", name: "christian_battaglia", key: "role")
try await memory.entities.delete(type: "Person", name: "christian_battaglia")
```

`entities.delete` is a soft delete.

### Reflect, forget, lifecycle, traces

```swift
_ = try await memory.reflect("patterns in customer complaints this month?", persist: true)
_ = try await memory.forget("anything about my old job")

try await memory.lifecycle.expire()
try await memory.lifecycle.decay()

_ = try await memory.traces.list(limit: 50)
_ = try await memory.traces.get("decision_trace:abc123")
_ = try await memory.traces.stats()
```

### Errors

All failures throw `SpectronError`, a single struct carrying `status`, `title`, `detail`, `typeURI`, `instance`, `extensions`, and `retryAfter`. The `kind` field maps the HTTP status to one of `.base`, `.auth`, `.scope`, `.notFound`, `.validation`, `.rateLimit`, or `.server`.

```swift
do {
    _ = try await memory.knowledge.get("doc:missing")
} catch let error as SpectronError where error.isNotFound {
    print(error.status, error.detail ?? "")
} catch let error as SpectronError where error.isRateLimit {
    print("retry after", error.retryAfter ?? 0, "seconds")
}
```

| Status | `kind` |
|---|---|
| 400, 422 | `.validation` |
| 401 | `.auth` |
| 403 | `.scope` |
| 404 | `.notFound` |
| 429 | `.rateLimit` (with `retryAfter`) |
| 5xx | `.server` |

### Retries, timeouts, scope

`GET` requests retry on connection errors and 5xx responses with backoff 250ms, 500ms, 1s (up to `maxRetries`, default 3). Writes are never retried. Default request timeout is 30 seconds, overridable on the `Spectron` initialiser.

Scope is a `[String: String]` dictionary on the API surface. The transport serialises it to the wire format `[{"key": "...", "value": "..."}]` and back. If you need the raw conversion:

```swift
let wire = Scope.serialise(["org": "anneal"])
let back = Scope.deserialise(wire)
```

### Custom transport for testing

`SpectronTransport` accepts any `HTTPClient`, so unit tests can replay canned responses without hitting the network:

```swift
let mock = MyMockHTTPClient()
mock.enqueue(.json(["ok": true]))
let transport = try SpectronTransport(endpoint: "https://example", apiKey: "k", client: mock, sleeper: { _ in })
let client = Spectron(context: "ctx", transport: transport)
```

---

## Tests

Run unit tests:

```sh
swift test
```

Run integration tests (requires a running SurrealDB instance):

```sh
SURREALDB_RUN_INTEGRATION=1 swift test
```

Integration environment variables:

| Variable | Default | Notes |
|---|---|---|
| `SURREALDB_HOST` | `127.0.0.1:8000` | `host[:port]` or a full URL with scheme. WS/HTTP endpoints are derived. |
| `SURREALDB_NAMESPACE` | `test` | Passed to `client.use(namespace:database:)`. |
| `SURREALDB_NAME` | `test` | Database name. |
| `SURREALDB_USER` | _(unset)_ | If unset, sign-in is skipped. |
| `SURREALDB_PASSWORD` | _(unset)_ | If unset, sign-in is skipped. |
| `SURREALDB_AUTH_LEVEL` | `root` | One of `root`, `namespace` / `ns`, `database` / `db`. |

---

## License

Apache 2.0 - see [LICENSE](LICENSE).
