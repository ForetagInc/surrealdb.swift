import Foundation

public struct AgentMemory: Sendable {
    public let contextId: String
    public let transport: AgentMemoryTransport
    public let documents: DocumentsNamespace
    public let memory: MemoryNamespace
    public let scopes: ScopesNamespace
    public let principals: PrincipalsNamespace
    public let keys: KeysNamespace

    public var sessions: SessionsNamespace { memory.sessions }
    public var entities: EntitiesNamespace { memory.entities }
    public var facts: FactsNamespace { memory.facts }
    public var lifecycle: LifecycleNamespace { memory.lifecycle }
    public var traces: TracesNamespace { memory.traces }

    private var base: String { Paths.endUserBase(contextId) }

    public init(
        context: String,
        endpoint: String,
        apiKey: String,
        timeout: TimeInterval = AgentMemoryTransport.defaultTimeout,
        maxRetries: Int = AgentMemoryTransport.defaultMaxRetries,
        client: (any HTTPClient)? = nil
    ) throws {
        let transport = try AgentMemoryTransport(
            endpoint: endpoint,
            apiKey: apiKey,
            timeout: timeout,
            maxRetries: maxRetries,
            client: client
        )
        self.init(context: context, transport: transport)
    }

    public init(
        context: String,
        transport: AgentMemoryTransport
    ) {
        self.contextId = context
        self.transport = transport
        self.documents = DocumentsNamespace(transport: transport, contextId: context)
        self.memory = MemoryNamespace(transport: transport, contextId: context)
        self.scopes = ScopesNamespace(transport: transport, contextId: context)
        self.principals = PrincipalsNamespace(transport: transport, contextId: context)
        self.keys = KeysNamespace(transport: transport, contextId: context)
    }

    // MARK: - Health and identity

    /// Pings the service health endpoint. Returns `true` on a 200 response and
    /// throws a `AgentMemoryError` otherwise. Not context-scoped.
    @discardableResult
    public func health() async throws -> Bool {
        _ = try await transport.request(method: "GET", path: "/api/v1/health")
        return true
    }

    /// Resolves the effective identity for the current request, including any
    /// delegation applied via `onBehalfOf`.
    public func whoami(onBehalfOf: String? = nil) async throws -> WhoamiResponse {
        try await transport.get("\(base)/me", extraHeaders: delegationHeaders(onBehalfOf), as: WhoamiResponse.self)
    }

    // MARK: - Memory: ingest

    /// Records a fact. Provide free `text` (the server extracts structured
    /// memory) and/or explicit `triples`.
    @discardableResult
    public func remember(
        _ text: String? = nil,
        triples: [Triple]? = nil,
        infer: InferMode? = nil,
        sessionId: String? = nil,
        scope: Scope? = nil,
        role: TurnRole? = nil,
        memoryCategory: MemoryCategory? = nil,
        labels: [String]? = nil,
        onBehalfOf: String? = nil
    ) async throws -> FactsResponse {
        try await memory.facts.create(
            text: text,
            triples: triples,
            role: role,
            memoryCategory: memoryCategory,
            infer: infer,
            labels: labels,
            scope: scope,
            sessionId: sessionId,
            onBehalfOf: onBehalfOf
        )
    }

    /// Records a batch of conversational messages in one call.
    @discardableResult
    public func rememberMany(
        _ messages: [BatchMessage],
        sessionId: String? = nil,
        scope: Scope? = nil,
        extract: BatchExtractionMode? = nil,
        infer: InferMode? = nil,
        labels: [String]? = nil,
        onBehalfOf: String? = nil
    ) async throws -> FactsBatchResponse {
        try await memory.facts.batch(
            messages: messages,
            extract: extract,
            infer: infer,
            labels: labels,
            scope: scope,
            sessionId: sessionId,
            onBehalfOf: onBehalfOf
        )
    }

    // MARK: - Memory: retrieve

    /// Retrieves memory relevant to a query.
    public func recall(
        _ query: String,
        k: Int? = nil,
        mode: String? = nil,
        sessionId: String? = nil,
        include: [String]? = nil,
        asOf: String? = nil,
        atInstant: String? = nil,
        labels: [String]? = nil,
        lens: Scope? = nil,
        scopeView: String? = nil,
        validFrom: String? = nil,
        validUntil: String? = nil,
        source: String? = nil,
        location: GeoFilter? = nil,
        onBehalfOf: String? = nil
    ) async throws -> MemoryQueryResponse {
        try await memory.query(
            query,
            k: k,
            mode: mode,
            labels: labels,
            lens: lens,
            scopeView: scopeView,
            sessionId: sessionId,
            source: source,
            include: include,
            asOf: asOf,
            atInstant: atInstant,
            validFrom: validFrom,
            validUntil: validUntil,
            location: location,
            onBehalfOf: onBehalfOf
        )
    }

    public func query(_ query: String, k: Int? = nil, sessionId: String? = nil, onBehalfOf: String? = nil) async throws -> MemoryQueryResponse {
        try await memory.query(query, k: k, sessionId: sessionId, onBehalfOf: onBehalfOf)
    }

    public func context(_ query: String, k: Int? = nil, onBehalfOf: String? = nil) async throws -> ContextResult {
        try await memory.context(query, k: k, onBehalfOf: onBehalfOf)
    }

    // MARK: - Chat

    public func chat(
        _ message: String,
        sessionId: String? = nil,
        scope: Scope? = nil,
        model: String? = nil,
        bypassCache: Bool? = nil,
        labels: [String]? = nil,
        onBehalfOf: String? = nil
    ) async throws -> ChatReply {
        try await memory.chat(
            message,
            sessionId: sessionId,
            labels: labels,
            scope: scope,
            model: model,
            bypassCache: bypassCache,
            onBehalfOf: onBehalfOf
        )
    }

    public func chatStream(
        _ message: String,
        sessionId: String? = nil,
        scope: Scope? = nil,
        model: String? = nil,
        bypassCache: Bool? = nil,
        labels: [String]? = nil,
        onBehalfOf: String? = nil
    ) async throws -> AsyncThrowingStream<ChatChunk, any Error> {
        try await memory.chatStream(
            message,
            sessionId: sessionId,
            labels: labels,
            scope: scope,
            model: model,
            bypassCache: bypassCache,
            onBehalfOf: onBehalfOf
        )
    }

    // MARK: - Structured views and maintenance

    public func state(onBehalfOf: String? = nil) async throws -> StructuredState {
        try await memory.state(onBehalfOf: onBehalfOf)
    }

    public func profile(onBehalfOf: String? = nil) async throws -> ProfileResponse {
        try await memory.profile(onBehalfOf: onBehalfOf)
    }

    public func reflect(_ query: String, persist: Bool = false, onBehalfOf: String? = nil) async throws -> ReflectionResult {
        try await memory.reflect(query, persist: persist, onBehalfOf: onBehalfOf)
    }

    public func forget(_ query: String, purge: Bool = false, onBehalfOf: String? = nil) async throws -> ForgetResult {
        try await memory.forget(query, purge: purge, onBehalfOf: onBehalfOf)
    }

    public func consolidate(dryRun: Bool = false, onBehalfOf: String? = nil) async throws -> ConsolidateResponse {
        try await memory.consolidate(dryRun: dryRun, onBehalfOf: onBehalfOf)
    }

    public func elaborate(entityRef: String? = nil, sweep: Bool = false, dryRun: Bool = false, onBehalfOf: String? = nil) async throws -> ElaborateResponse {
        try await memory.elaborate(entityRef: entityRef, sweep: sweep, dryRun: dryRun, onBehalfOf: onBehalfOf)
    }

    public func fsck(onBehalfOf: String? = nil) async throws -> FsckReport {
        try await memory.fsck(onBehalfOf: onBehalfOf)
    }

    public func inspect(ref: String, onBehalfOf: String? = nil) async throws -> InspectResponse {
        try await memory.inspect(ref: ref, onBehalfOf: onBehalfOf)
    }

    public func audit(limit: Int? = nil, onBehalfOf: String? = nil) async throws -> [AuditRow] {
        try await memory.audit(limit: limit, onBehalfOf: onBehalfOf)
    }
}
