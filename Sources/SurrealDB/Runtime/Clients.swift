import Foundation

public actor SurrealHTTPClient: SurrealQueryable {
    private let core: SurrealClientCore<HTTPRPCEngine>

    public init(
        endpoint: String,
        wireProtocol: SurrealWireProtocol = .cbor,
        options: SurrealClientOptions = .init(),
        session: SessionContext = .init()
    ) throws {
        let rpcURL = try Endpoint.normalizedRPCURL(from: endpoint)
        let transport = HTTPRPCEngine(
            endpoint: rpcURL,
            options: options,
            codec: makeWireCodec(wireProtocol)
        )
        self.core = SurrealClientCore(engine: transport, sessionContext: session)
    }

    public func connect() async throws {
        try await core.connect()
    }

    public func close() async {
        await core.close()
    }

    public func use(namespace: String?, database: String?) async throws {
        try await core.use(namespace: namespace, database: database)
    }

    public func signin(_ credentials: SignInCredentials) async throws -> AuthTokens {
        try await core.signin(credentials)
    }

    public func signup(_ credentials: SignUpCredentials) async throws -> AuthTokens {
        try await core.signup(credentials)
    }

    public func authenticate(_ token: String) async throws {
        try await core.authenticate(token)
    }

    public func invalidate() async throws {
        try await core.invalidate()
    }

    public func query<T: Decodable & Sendable>(_ query: SurrealQuery<T>) async throws -> [T] {
        try await core.query(query)
    }

    public func queryRaw(_ sql: String, bindings: [String: SurrealValue] = [:]) async throws -> [RPCQueryResult] {
        try await core.queryRaw(sql, bindings: bindings)
    }

    public func transaction(
        _ build: @Sendable (SurrealTransaction) throws -> Void
    ) async throws -> [RPCQueryResult] {
        try await core.transaction(build)
    }

    public func select<Model: SurrealModel & Decodable & Sendable>(
        _ model: Model.Type,
        where predicate: SurrealPredicate? = nil,
        limit: Int? = nil,
        start: Int? = nil
    ) async throws -> [Model] {
        try await core.select(model, where: predicate, limit: limit, start: start)
    }

    public func create<Model: SurrealModel & Codable & Sendable>(_ value: Model) async throws -> [Model] {
        try await core.create(value)
    }

    public func select<Model: SurrealModel & Decodable & Sendable>(
        recordID: SurrealRecordID,
        as model: Model.Type
    ) async throws -> Model? {
        try await core.select(recordID: recordID, as: model)
    }

    public func create<Model: SurrealModel & Codable & Sendable>(
        recordID: SurrealRecordID,
        content: Model
    ) async throws -> Model? {
        try await core.create(recordID: recordID, content: content)
    }

    public func update<Model: SurrealModel & Codable & Sendable>(
        _ model: Model.Type,
        content: Model,
        where predicate: SurrealPredicate? = nil
    ) async throws -> [Model] {
        try await core.update(model, content: content, where: predicate)
    }

    public func upsert<Model: SurrealModel & Codable & Sendable>(
        _ model: Model.Type,
        content: Model,
        where predicate: SurrealPredicate? = nil
    ) async throws -> [Model] {
        try await core.upsert(model, content: content, where: predicate)
    }

    public func delete<Model: SurrealModel & Decodable & Sendable>(
        _ model: Model.Type,
        where predicate: SurrealPredicate? = nil
    ) async throws -> [Model] {
        try await core.delete(model, where: predicate)
    }

    public func update<Model: SurrealModel & Codable & Sendable>(
        recordID: SurrealRecordID,
        content: Model
    ) async throws -> Model? {
        try await core.update(recordID: recordID, content: content)
    }

    public func upsert<Model: SurrealModel & Codable & Sendable>(
        recordID: SurrealRecordID,
        content: Model
    ) async throws -> Model? {
        try await core.upsert(recordID: recordID, content: content)
    }

    public func delete<Model: SurrealModel & Decodable & Sendable>(
        recordID: SurrealRecordID,
        as model: Model.Type
    ) async throws -> Model? {
        try await core.delete(recordID: recordID, as: model)
    }
}

public actor SurrealWebSocketClient: SurrealLiveQueryable {
    private let core: SurrealClientCore<WebSocketRPCEngine>

    public init(
        endpoint: String,
        wireProtocol: SurrealWireProtocol = .cbor,
        options: SurrealClientOptions = .init(),
        websocketOptions: SurrealWebSocketOptions = .init(),
        session: SessionContext = .init()
    ) throws {
        let rpcURL = try Endpoint.normalizedRPCURL(from: endpoint)
        let transport = WebSocketRPCEngine(
            endpoint: rpcURL,
            clientOptions: options,
            wsOptions: websocketOptions,
            codec: makeWireCodec(wireProtocol)
        )
        self.core = SurrealClientCore(engine: transport, sessionContext: session)
    }

    public func connect() async throws {
        try await core.connect()
    }

    public func close() async {
        await core.close()
    }

    public func use(namespace: String?, database: String?) async throws {
        try await core.use(namespace: namespace, database: database)
    }

    public func signin(_ credentials: SignInCredentials) async throws -> AuthTokens {
        try await core.signin(credentials)
    }

    public func signup(_ credentials: SignUpCredentials) async throws -> AuthTokens {
        try await core.signup(credentials)
    }

    public func authenticate(_ token: String) async throws {
        try await core.authenticate(token)
    }

    public func invalidate() async throws {
        try await core.invalidate()
    }

    public func query<T: Decodable & Sendable>(_ query: SurrealQuery<T>) async throws -> [T] {
        try await core.query(query)
    }

    public func queryRaw(_ sql: String, bindings: [String: SurrealValue] = [:]) async throws -> [RPCQueryResult] {
        try await core.queryRaw(sql, bindings: bindings)
    }

    public func transaction(
        _ build: @Sendable (SurrealTransaction) throws -> Void
    ) async throws -> [RPCQueryResult] {
        try await core.transaction(build)
    }

    public func select<Model: SurrealModel & Decodable & Sendable>(
        _ model: Model.Type,
        where predicate: SurrealPredicate? = nil,
        limit: Int? = nil,
        start: Int? = nil
    ) async throws -> [Model] {
        try await core.select(model, where: predicate, limit: limit, start: start)
    }

    public func create<Model: SurrealModel & Codable & Sendable>(_ value: Model) async throws -> [Model] {
        try await core.create(value)
    }

    public func select<Model: SurrealModel & Decodable & Sendable>(
        recordID: SurrealRecordID,
        as model: Model.Type
    ) async throws -> Model? {
        try await core.select(recordID: recordID, as: model)
    }

    public func create<Model: SurrealModel & Codable & Sendable>(
        recordID: SurrealRecordID,
        content: Model
    ) async throws -> Model? {
        try await core.create(recordID: recordID, content: content)
    }

    public func update<Model: SurrealModel & Codable & Sendable>(
        _ model: Model.Type,
        content: Model,
        where predicate: SurrealPredicate? = nil
    ) async throws -> [Model] {
        try await core.update(model, content: content, where: predicate)
    }

    public func upsert<Model: SurrealModel & Codable & Sendable>(
        _ model: Model.Type,
        content: Model,
        where predicate: SurrealPredicate? = nil
    ) async throws -> [Model] {
        try await core.upsert(model, content: content, where: predicate)
    }

    public func delete<Model: SurrealModel & Decodable & Sendable>(
        _ model: Model.Type,
        where predicate: SurrealPredicate? = nil
    ) async throws -> [Model] {
        try await core.delete(model, where: predicate)
    }

    public func update<Model: SurrealModel & Codable & Sendable>(
        recordID: SurrealRecordID,
        content: Model
    ) async throws -> Model? {
        try await core.update(recordID: recordID, content: content)
    }

    public func upsert<Model: SurrealModel & Codable & Sendable>(
        recordID: SurrealRecordID,
        content: Model
    ) async throws -> Model? {
        try await core.upsert(recordID: recordID, content: content)
    }

    public func delete<Model: SurrealModel & Decodable & Sendable>(
        recordID: SurrealRecordID,
        as model: Model.Type
    ) async throws -> Model? {
        try await core.delete(recordID: recordID, as: model)
    }

    public func live<T: Decodable & Sendable>(_ query: LiveQuery<T>) async throws -> AsyncStream<LiveEvent<T>> {
        try await core.live(query)
    }

    public func kill(liveQueryID: UUID) async throws {
        try await core.kill(liveQueryID: liveQueryID)
    }
}
