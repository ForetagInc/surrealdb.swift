import Foundation

public struct Spectron: Sendable {
    public let contextId: String
    public let transport: SpectronTransport
    public let knowledge: KnowledgeNamespace
    public let memory: MemoryNamespace

    public var sessions: SessionsNamespace { memory.sessions }
    public var entities: EntitiesNamespace { memory.entities }
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
        self.contextId = context
        self.transport = try SpectronTransport(
            endpoint: endpoint,
            apiKey: apiKey,
            timeout: timeout,
            maxRetries: maxRetries,
            client: client
        )
        self.knowledge = KnowledgeNamespace(transport: transport, contextId: context)
        self.memory = MemoryNamespace(transport: transport, contextId: context)
    }

    public init(
        context: String,
        transport: SpectronTransport
    ) {
        self.contextId = context
        self.transport = transport
        self.knowledge = KnowledgeNamespace(transport: transport, contextId: context)
        self.memory = MemoryNamespace(transport: transport, contextId: context)
    }

    // MARK: - Memory shortcuts

    public func query(_ query: String, k: Int? = nil, sessionId: String? = nil) async throws -> MemoryQueryResponse {
        try await memory.query(query, k: k, sessionId: sessionId)
    }

    public func context(_ query: String, k: Int? = nil) async throws -> ContextResult {
        try await memory.context(query, k: k)
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

    public func forget(_ query: String) async throws -> ForgetResult {
        try await memory.forget(query)
    }
}
