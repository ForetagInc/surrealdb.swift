# SurrealDB Swift SDK

A Swift SDK for [SurrealDB](https://surrealdb.com) with full async/await support, type-safe query macros, and live query streaming.

> **Alpha release** - this SDK is in early development and the public API is subject to breaking changes without notice.

## Requirements

- Swift 6.1+
- SurrealDB v3+ (designed for v3.0.1)

## Platforms

iOS 17+ · macOS 14+ · tvOS 17+ · watchOS 10+ · visionOS 1+

## Features

- HTTP and WebSocket transports
- Type-safe CRUD via `@SurrealModel` macro and query DSL
- Live queries over WebSocket via `AsyncStream`
- Raw SQL queries with bound parameters
- Root, namespace, database, and record-access authentication
- Automatic WebSocket reconnection

## Roadmap

- [ ] Standalone Query Builder
- [ ] Advanced Error Handling
- [ ] Embedded / In-memory SurrealDB
- [ ] File Uploads (Buckets)

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

| Variable | Default |
|---|---|
| `SURREALDB_WS_ENDPOINT` | `ws://127.0.0.1:8000` |
| `SURREALDB_HTTP_ENDPOINT` | `http://127.0.0.1:8000` |
| `SURREALDB_ROOT_USER` | `root` |
| `SURREALDB_ROOT_PASS` | `root` |
| `SURREALDB_SKIP_SIGNIN` | _(unset)_ |

---

## License

Apache 2.0 - see [LICENSE](LICENSE).
