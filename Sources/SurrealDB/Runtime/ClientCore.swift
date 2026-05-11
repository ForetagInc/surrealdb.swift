import Foundation

actor SurrealClientCore<Engine: RPCEngine> {
    private let engine: Engine
    private var sessionContext: SessionContext

    init(engine: Engine, sessionContext: SessionContext = .init()) {
        self.engine = engine
        self.sessionContext = sessionContext
    }

    func connect() async throws {
        try await engine.connect()
    }

    func close() async {
        await engine.close()
    }

    func use(namespace: String?, database: String?) async throws {
        _ = try await rpc(
            "use",
            params: [
                namespace.map(SurrealValue.string) ?? .none,
                database.map(SurrealValue.string) ?? .none,
            ]
        )

        if let namespace {
            sessionContext.namespace = namespace
        }
        if let database {
            sessionContext.database = database
        }
    }

    func signin(_ credentials: SignInCredentials) async throws -> AuthTokens {
        let payload = try credentials.payload(using: sessionContext)
        let response = try await rpc("signin", params: [payload])

        let tokens = try parseAuthTokens(response)
        sessionContext.accessToken = tokens.access
        return tokens
    }

    func signup(_ credentials: SignUpCredentials) async throws -> AuthTokens {
        let payload = try credentials.payload(using: sessionContext)
        let response = try await rpc("signup", params: [payload])

        let tokens = try parseAuthTokens(response)
        sessionContext.accessToken = tokens.access
        return tokens
    }

    func authenticate(_ token: String) async throws {
        _ = try await rpc("authenticate", params: [.string(token)])
        sessionContext.accessToken = token
    }

    func invalidate() async throws {
        _ = try await rpc("invalidate")
        sessionContext.accessToken = nil
    }

    func queryRaw(_ sql: String, bindings: [String: SurrealValue]) async throws -> [RPCQueryResult] {
        var mergedBindings = sessionContext.variables
        for (key, value) in bindings {
            mergedBindings[key] = value
        }

        let response = try await rpc(
            "query",
            params: [
                .string(sql),
                .object(mergedBindings),
            ]
        )

        return try RPCWire.decodeQueryResults(from: response)
    }

    func transaction(_ build: (SurrealTransaction) throws -> Void) async throws -> [RPCQueryResult] {
        let tx = SurrealTransaction()
        try build(tx)
        let (sql, bindings) = tx.build()
        return try await queryRaw(sql, bindings: bindings)
    }

    func query<T: Decodable & Sendable>(_ query: SurrealQuery<T>) async throws -> [T] {
        let results = try await queryRaw(query.sql, bindings: query.bindings)
        return try decodeQueryResults(results, as: T.self)
    }

    func select<Model: SurrealModel & Decodable & Sendable>(
        _ model: Model.Type,
        where predicate: SurrealPredicate?,
        limit: Int?,
        start: Int?
    ) async throws -> [Model] {
        let query = SurrealDSL.select(model, where: predicate, limit: limit, start: start)
        return try await self.query(query)
    }

    func create<Model: SurrealModel & Codable & Sendable>(_ value: Model) async throws -> [Model] {
        let content = try SurrealValue.fromEncodable(value)
        let query = SurrealDSL.create(Model.self, bindings: ["content": content])
        return try await self.query(query)
    }

    func select<Model: SurrealModel & Decodable & Sendable>(
        recordID: SurrealRecordID,
        as model: Model.Type
    ) async throws -> Model? {
        let query = SurrealQuery<Model>(sql: "SELECT * FROM \(recordID.rawValue) LIMIT 1;")
        return try await self.query(query).first
    }

    func create<Model: SurrealModel & Codable & Sendable>(
        recordID: SurrealRecordID,
        content: Model
    ) async throws -> Model? {
        let payload = try SurrealValue.fromEncodable(content)
        let query = SurrealQuery<Model>(
            sql: "CREATE \(recordID.rawValue) CONTENT $content;",
            bindings: ["content": payload]
        )
        return try await self.query(query).first
    }

    func update<Model: SurrealModel & Codable & Sendable>(
        _ model: Model.Type,
        content: Model,
        where predicate: SurrealPredicate?
    ) async throws -> [Model] {
        let payload = try SurrealValue.fromEncodable(content)
        let query = SurrealDSL.update(model, where: predicate, bindings: ["content": payload])
        return try await self.query(query)
    }

    func upsert<Model: SurrealModel & Codable & Sendable>(
        _ model: Model.Type,
        content: Model,
        where predicate: SurrealPredicate?
    ) async throws -> [Model] {
        let payload = try SurrealValue.fromEncodable(content)
        let query = SurrealDSL.upsert(model, where: predicate, bindings: ["content": payload])
        return try await self.query(query)
    }

    func delete<Model: SurrealModel & Decodable & Sendable>(
        _ model: Model.Type,
        where predicate: SurrealPredicate?
    ) async throws -> [Model] {
        let query = SurrealDSL.delete(model, where: predicate)
        return try await self.query(query)
    }

    func update<Model: SurrealModel & Codable & Sendable>(
        recordID: SurrealRecordID,
        content: Model
    ) async throws -> Model? {
        let payload = try SurrealValue.fromEncodable(content)
        let query = SurrealQuery<Model>(
            sql: "UPDATE \(recordID.rawValue) CONTENT $content;",
            bindings: ["content": payload]
        )
        return try await self.query(query).first
    }

    func upsert<Model: SurrealModel & Codable & Sendable>(
        recordID: SurrealRecordID,
        content: Model
    ) async throws -> Model? {
        let payload = try SurrealValue.fromEncodable(content)
        let query = SurrealQuery<Model>(
            sql: "UPSERT \(recordID.rawValue) CONTENT $content;",
            bindings: ["content": payload]
        )
        return try await self.query(query).first
    }

    func delete<Model: SurrealModel & Decodable & Sendable>(
        recordID: SurrealRecordID,
        as model: Model.Type
    ) async throws -> Model? {
        let query = SurrealQuery<Model>(sql: "DELETE \(recordID.rawValue);")
        return try await self.query(query).first
    }

    func kill(liveQueryID: UUID) async throws {
        _ = try await rpc("kill", params: [.uuid(liveQueryID)])
    }

    private func rpc(_ method: String, params: [SurrealValue]? = nil) async throws -> SurrealValue {
        let request = RPCRequest(
            id: UUID().uuidString,
            method: method,
            params: params,
            session: nil,
            txn: nil
        )

        let envelope = try await engine.send(request, session: sessionContext)

        if let error = envelope.error {
            throw SurrealError.serverError(error)
        }

        return envelope.result ?? .null
    }

    private func parseAuthTokens(_ value: SurrealValue) throws -> AuthTokens {
        switch value {
        case .string(let token):
            return .init(access: token)
        case .object(let payload):
            let access = payload["access"].flatMap(extractString(_:))
                ?? payload["token"].flatMap(extractString(_:))
            guard let access else {
                throw SurrealError.invalidResponse("Missing access token in auth response.")
            }

            let refresh = payload["refresh"].flatMap(extractString(_:))
            return .init(access: access, refresh: refresh)
        default:
            throw SurrealError.invalidResponse("Unexpected auth response format.")
        }
    }

    private func extractString(_ value: SurrealValue) -> String? {
        if case .string(let string) = value {
            return string
        }
        return nil
    }

    private func decodeQueryResults<T: Decodable & Sendable>(
        _ results: [RPCQueryResult],
        as type: T.Type
    ) throws -> [T] {
        var decoded: [T] = []
        var errors: [QueryErrorDetail] = []

        for (index, row) in results.enumerated() {
            if row.status == .err {
                let message: String
                if case .string(let queryError) = row.result {
                    message = queryError
                } else {
                    message = "Unknown query error"
                }
                errors.append(QueryErrorDetail(index: index, message: message, details: row.details))
                continue
            }

            switch row.result {
            case .array(let array):
                for element in array {
                    decoded.append(try element.decode(T.self))
                }
            case .null, .none:
                continue
            default:
                decoded.append(try row.result.decode(T.self))
            }
        }

        if !errors.isEmpty {
            throw SurrealError.queryErrors(errors)
        }

        return decoded
    }
}

extension SurrealClientCore where Engine: LiveRPCEngine {
    func live<T: Decodable & Sendable>(_ query: LiveQuery<T>) async throws -> AsyncStream<LiveEvent<T>> {
        let queryID = try await registerLiveQuery(query)
        let wireStream = await engine.openLiveStream(for: queryID)

        return AsyncStream { continuation in
            let forwardTask = Task {
                for await event in wireStream {
                    let decoded = try? event.payload.decode(T.self)
                    continuation.yield(
                        LiveEvent(
                            queryID: event.queryID,
                            action: event.action,
                            recordID: event.recordID,
                            rawPayload: event.payload,
                            decoded: decoded
                        )
                    )
                }
                continuation.finish()
            }

            continuation.onTermination = { [queryID] _ in
                forwardTask.cancel()
                Task {
                    try? await self.kill(liveQueryID: queryID)
                    await self.engine.closeLiveStream(for: queryID)
                }
            }
        }
    }

    private func registerLiveQuery<T: Decodable & Sendable>(_ query: LiveQuery<T>) async throws -> UUID {
        let results = try await queryRaw(query.sql, bindings: query.bindings)

        guard let first = results.first else {
            throw SurrealError.invalidResponse("Expected live query registration result.")
        }

        let candidate = first.result
        switch candidate {
        case .uuid(let uuid):
            return uuid
        case .string(let raw):
            if let uuid = UUID(uuidString: raw) {
                return uuid
            }
            throw SurrealError.invalidResponse("Live query id is not a UUID: \(raw)")
        case .array(let rows):
            if let first = rows.first {
                if case .uuid(let uuid) = first {
                    return uuid
                }
                if case .string(let raw) = first, let uuid = UUID(uuidString: raw) {
                    return uuid
                }
            }
            throw SurrealError.invalidResponse("Unable to parse live query identifier.")
        default:
            throw SurrealError.invalidResponse("Unexpected live query registration format.")
        }
    }
}
