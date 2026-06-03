import Foundation

public struct Spectron: Sendable {
    public let contextId: String
    public let transport: SpectronTransport
    public let documents: DocumentsNamespace
    public let memory: MemoryNamespace
    public let scopes: ScopesNamespace
    public let principals: PrincipalsNamespace

    public var sessions: SessionsNamespace { memory.sessions }
    public var entities: EntitiesNamespace { memory.entities }
    public var facts: FactsNamespace { memory.facts }
    public var lifecycle: LifecycleNamespace { memory.lifecycle }
    public var traces: TracesNamespace { memory.traces }

    public init(
        context: String,
        endpoint: String,
        apiKey: String,
        timeout: TimeInterval = SpectronTransport.defaultTimeout,
        maxRetries: Int = SpectronTransport.defaultMaxRetries,
        client: (any HTTPClient)? = nil
    ) throws {
        let transport = try SpectronTransport(
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
        transport: SpectronTransport
    ) {
        self.contextId = context
        self.transport = transport
        self.documents = DocumentsNamespace(transport: transport, contextId: context)
        self.memory = MemoryNamespace(transport: transport, contextId: context)
        self.scopes = ScopesNamespace(transport: transport, contextId: context)
        self.principals = PrincipalsNamespace(transport: transport, contextId: context)
    }

    // MARK: - Health

    /// Pings the service health endpoint. Returns `true` on a 200 response and
    /// throws a `SpectronError` otherwise.
    @discardableResult
    public func health() async throws -> Bool {
        _ = try await transport.request(method: "GET", path: "/api/v1/health")
        return true
    }

    // MARK: - Memory shortcuts

    public func query(_ query: String, k: Int? = nil, sessionId: String? = nil) async throws -> MemoryQueryResponse {
        try await memory.query(query, k: k, sessionId: sessionId)
    }

    public func context(_ query: String, k: Int? = nil) async throws -> ContextResult {
        try await memory.context(query, k: k)
    }

    public func chat(_ message: String, sessionId: String? = nil) async throws -> ChatReply {
        try await memory.chat(message, sessionId: sessionId)
    }

    public func state() async throws -> StructuredState {
        try await memory.state()
    }

    public func profile() async throws -> ProfileResponse {
        try await memory.profile()
    }

    public func reflect(_ query: String, persist: Bool = false) async throws -> ReflectionResult {
        try await memory.reflect(query, persist: persist)
    }

    public func forget(_ query: String, purge: Bool = false) async throws -> ForgetResult {
        try await memory.forget(query, purge: purge)
    }

    public func consolidate(dryRun: Bool = false) async throws -> ConsolidateResponse {
        try await memory.consolidate(dryRun: dryRun)
    }

    public func elaborate(entityRef: String? = nil, sweep: Bool = false, dryRun: Bool = false) async throws -> ElaborateResponse {
        try await memory.elaborate(entityRef: entityRef, sweep: sweep, dryRun: dryRun)
    }

    public func fsck() async throws -> FsckReport {
        try await memory.fsck()
    }

    public func inspect(ref: String) async throws -> InspectResponse {
        try await memory.inspect(ref: ref)
    }

    public func audit(limit: Int? = nil) async throws -> [AuditRow] {
        try await memory.audit(limit: limit)
    }
}
