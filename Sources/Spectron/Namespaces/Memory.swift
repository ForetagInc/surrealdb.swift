import Foundation

public struct MemoryNamespace: Sendable {
    let transport: SpectronTransport
    let contextId: String
    let base: String

    public let sessions: SessionsNamespace
    public let entities: EntitiesNamespace
    public let facts: FactsNamespace
    public let lifecycle: LifecycleNamespace
    public let traces: TracesNamespace

    init(transport: SpectronTransport, contextId: String) {
        self.transport = transport
        self.contextId = contextId
        self.base = Paths.endUserBase(contextId)
        self.sessions = SessionsNamespace(transport: transport, contextId: contextId)
        self.entities = EntitiesNamespace(transport: transport, contextId: contextId)
        self.facts = FactsNamespace(transport: transport, contextId: contextId)
        self.lifecycle = LifecycleNamespace(transport: transport, contextId: contextId)
        self.traces = TracesNamespace(transport: transport, contextId: contextId)
    }

    // MARK: - Retrieval

    public func query(
        _ query: String,
        k: Int? = nil,
        mode: String? = nil,
        labels: [String]? = nil,
        lens: [String]? = nil,
        scopeView: String? = nil,
        sessionId: String? = nil,
        source: String? = nil,
        include: [String]? = nil,
        asOf: String? = nil,
        atInstant: String? = nil,
        validFrom: String? = nil,
        validUntil: String? = nil,
        location: GeoFilter? = nil
    ) async throws -> MemoryQueryResponse {
        var payload: [String: JSONValue] = ["query": .string(query)]
        if let k { payload["k"] = .int(Int64(k)) }
        if let mode { payload["mode"] = .string(mode) }
        if let labels { payload["labels"] = .array(labels.map { .string($0) }) }
        if let lens { payload["lens"] = .array(lens.map { .string($0) }) }
        if let scopeView { payload["scopeView"] = .string(scopeView) }
        if let sessionId { payload["sessionId"] = .string(sessionId) }
        if let source { payload["source"] = .string(source) }
        if let include { payload["include"] = .array(include.map { .string($0) }) }
        if let asOf { payload["asOf"] = .string(asOf) }
        if let atInstant { payload["atInstant"] = .string(atInstant) }
        if let validFrom { payload["validFrom"] = .string(validFrom) }
        if let validUntil { payload["validUntil"] = .string(validUntil) }
        if let location { payload["location"] = try await transport.jsonValue(location) }
        let data = try JSONValue.encodeObject(payload)
        let (respData, _) = try await transport.request(method: "POST", path: "\(base)/query", jsonBody: data)
        return try await transport.decode(MemoryQueryResponse.self, from: respData)
    }

    public func context(
        _ query: String,
        k: Int? = nil,
        labels: [String]? = nil,
        lens: [String]? = nil,
        scopeView: String? = nil
    ) async throws -> ContextResult {
        var payload: [String: JSONValue] = ["query": .string(query)]
        if let k { payload["k"] = .int(Int64(k)) }
        if let labels { payload["labels"] = .array(labels.map { .string($0) }) }
        if let lens { payload["lens"] = .array(lens.map { .string($0) }) }
        if let scopeView { payload["scopeView"] = .string(scopeView) }
        let data = try JSONValue.encodeObject(payload)
        let (respData, _) = try await transport.request(method: "POST", path: "\(base)/context", jsonBody: data)
        return try await transport.decode(ContextResult.self, from: respData)
    }

    public func chat(
        _ message: String,
        sessionId: String? = nil,
        labels: [String]? = nil,
        scope: [String]? = nil,
        model: String? = nil,
        bypassCache: Bool? = nil
    ) async throws -> ChatReply {
        var payload: [String: JSONValue] = ["message": .string(message)]
        if let sessionId { payload["sessionId"] = .string(sessionId) }
        if let labels { payload["labels"] = .array(labels.map { .string($0) }) }
        if let scope { payload["scope"] = .array(scope.map { .string($0) }) }
        if let model { payload["model"] = .string(model) }
        if let bypassCache { payload["bypassCache"] = .bool(bypassCache) }
        let data = try JSONValue.encodeObject(payload)
        let (respData, _) = try await transport.request(method: "POST", path: "\(base)/chat", jsonBody: data)
        return try await transport.decode(ChatReply.self, from: respData)
    }

    // MARK: - Structured views

    public func state() async throws -> StructuredState {
        try await transport.get("\(base)/state", as: StructuredState.self)
    }

    public func profile() async throws -> ProfileResponse {
        try await transport.get("\(base)/profile", as: ProfileResponse.self)
    }

    public func reflect(_ query: String, persist: Bool = false) async throws -> ReflectionResult {
        let payload: [String: JSONValue] = [
            "query": .string(query),
            "persist": .bool(persist)
        ]
        let data = try JSONValue.encodeObject(payload)
        let (respData, _) = try await transport.request(method: "POST", path: "\(base)/reflect", jsonBody: data)
        return try await transport.decode(ReflectionResult.self, from: respData)
    }

    public func forget(_ query: String, purge: Bool = false) async throws -> ForgetResult {
        let payload: [String: JSONValue] = [
            "query": .string(query),
            "purge": .bool(purge)
        ]
        let data = try JSONValue.encodeObject(payload)
        let (respData, _) = try await transport.request(method: "POST", path: "\(base)/forget", jsonBody: data)
        return try await transport.decode(ForgetResult.self, from: respData)
    }

    // MARK: - Maintenance

    public func consolidate(
        dryRun: Bool = false,
        factLimit: Int? = nil,
        observationLimit: Int? = nil
    ) async throws -> ConsolidateResponse {
        var payload: [String: JSONValue] = ["dryRun": .bool(dryRun)]
        if let factLimit { payload["factLimit"] = .int(Int64(factLimit)) }
        if let observationLimit { payload["observationLimit"] = .int(Int64(observationLimit)) }
        let data = try JSONValue.encodeObject(payload)
        let (respData, _) = try await transport.request(method: "POST", path: "\(base)/consolidate", jsonBody: data)
        return try await transport.decode(ConsolidateResponse.self, from: respData)
    }

    public func elaborate(
        entityRef: String? = nil,
        sweep: Bool = false,
        dryRun: Bool = false,
        budget: Int? = nil
    ) async throws -> ElaborateResponse {
        var payload: [String: JSONValue] = [
            "sweep": .bool(sweep),
            "dryRun": .bool(dryRun)
        ]
        if let entityRef { payload["entityRef"] = .string(entityRef) }
        if let budget { payload["budget"] = .int(Int64(budget)) }
        let data = try JSONValue.encodeObject(payload)
        let (respData, _) = try await transport.request(method: "POST", path: "\(base)/elaborate", jsonBody: data)
        return try await transport.decode(ElaborateResponse.self, from: respData)
    }

    public func fsck(
        check: String? = nil,
        duplicateThreshold: Double? = nil,
        maxResults: Int? = nil
    ) async throws -> FsckReport {
        var payload: [String: JSONValue] = [:]
        if let check { payload["check"] = .string(check) }
        if let duplicateThreshold { payload["duplicateThreshold"] = .double(duplicateThreshold) }
        if let maxResults { payload["maxResults"] = .int(Int64(maxResults)) }
        let data = try JSONValue.encodeObject(payload)
        let (respData, _) = try await transport.request(method: "POST", path: "\(base)/fsck", jsonBody: data)
        return try await transport.decode(FsckReport.self, from: respData)
    }

    // MARK: - Inspection and audit

    public func inspect(
        ref: String,
        asOf: String? = nil,
        atInstant: String? = nil,
        validFrom: String? = nil,
        validUntil: String? = nil
    ) async throws -> InspectResponse {
        let q = QueryItems.from([
            ("ref", ref),
            ("asOf", asOf),
            ("atInstant", atInstant),
            ("validFrom", validFrom),
            ("validUntil", validUntil)
        ])
        return try await transport.get("\(base)/inspect", query: q, as: InspectResponse.self)
    }

    public func audit(
        principal: String? = nil,
        key: String? = nil,
        kind: String? = nil,
        since: String? = nil,
        until: String? = nil,
        limit: Int? = nil
    ) async throws -> [AuditRow] {
        let q = QueryItems.from([
            ("principal", principal),
            ("key", key),
            ("kind", kind),
            ("since", since),
            ("until", until),
            ("limit", limit)
        ])
        let resp = try await transport.get("\(base)/audit", query: q, as: AuditResponse.self)
        return resp.rows
    }
}

// MARK: - Sessions

public struct SessionsNamespace: Sendable {
    let transport: SpectronTransport
    let contextId: String
    let base: String

    init(transport: SpectronTransport, contextId: String) {
        self.transport = transport
        self.contextId = contextId
        self.base = "\(Paths.endUserBase(contextId))/sessions"
    }

    public func create(scope: [String]? = nil, metadata: JSONValue? = nil) async throws -> SpectronSession {
        var payload: [String: JSONValue] = [:]
        if let scope { payload["scope"] = .array(scope.map { .string($0) }) }
        if let metadata { payload["metadata"] = metadata }
        let data = try JSONValue.encodeObject(payload)
        let (respData, _) = try await transport.request(method: "POST", path: base, jsonBody: data)
        let info = try await transport.decode(SessionInfo.self, from: respData)
        return SpectronSession(transport: transport, contextId: contextId, info: info)
    }
}

public struct SpectronSession: Sendable {
    public let info: SessionInfo
    let transport: SpectronTransport
    let contextId: String
    let base: String

    init(transport: SpectronTransport, contextId: String, info: SessionInfo) {
        self.transport = transport
        self.contextId = contextId
        self.info = info
        self.base = "\(Paths.endUserBase(contextId))/sessions/\(SpectronTransport.quotePath(info.id))"
    }

    public var id: String { info.id }

    public func close() async throws {
        try await transport.delete(base)
    }

    public func turns() async throws -> [Turn] {
        let resp = try await transport.get("\(base)/turns", as: TurnListResponse.self)
        return resp.turns
    }

    public func context(_ query: String) async throws -> SessionContextResult {
        let payload: [String: JSONValue] = ["query": .string(query)]
        let data = try JSONValue.encodeObject(payload)
        let (respData, _) = try await transport.request(method: "POST", path: "\(base)/context", jsonBody: data)
        return try await transport.decode(SessionContextResult.self, from: respData)
    }

    /// Ingest a fact scoped to this session.
    @discardableResult
    public func ingest(
        text: String? = nil,
        triples: [Triple]? = nil,
        role: TurnRole? = nil,
        memoryCategory: MemoryCategory? = nil,
        infer: InferMode? = nil,
        labels: [String]? = nil
    ) async throws -> FactsResponse {
        try await FactsNamespace(transport: transport, contextId: contextId).create(
            text: text,
            triples: triples,
            role: role,
            memoryCategory: memoryCategory,
            infer: infer,
            labels: labels,
            sessionId: info.id
        )
    }

    /// Run the managed chat loop with replies scoped to this session.
    public func chat(_ message: String) async throws -> ChatReply {
        try await MemoryNamespace(transport: transport, contextId: contextId).chat(message, sessionId: info.id)
    }
}

// MARK: - Facts

public struct FactsNamespace: Sendable {
    let transport: SpectronTransport
    let base: String

    init(transport: SpectronTransport, contextId: String) {
        self.transport = transport
        self.base = "\(Paths.endUserBase(contextId))/facts"
    }

    @discardableResult
    public func create(
        text: String? = nil,
        triples: [Triple]? = nil,
        role: TurnRole? = nil,
        memoryCategory: MemoryCategory? = nil,
        infer: InferMode? = nil,
        labels: [String]? = nil,
        scope: [String]? = nil,
        sessionId: String? = nil
    ) async throws -> FactsResponse {
        var payload: [String: JSONValue] = [:]
        if let text { payload["text"] = .string(text) }
        if let triples { payload["triples"] = try await transport.jsonValue(triples) }
        if let role { payload["role"] = .string(role.rawValue) }
        if let memoryCategory { payload["memory_category"] = .string(memoryCategory.rawValue) }
        if let infer { payload["infer"] = .string(infer.rawValue) }
        if let labels { payload["labels"] = .array(labels.map { .string($0) }) }
        if let scope { payload["scope"] = .array(scope.map { .string($0) }) }
        if let sessionId { payload["session_id"] = .string(sessionId) }
        let data = try JSONValue.encodeObject(payload)
        let (respData, _) = try await transport.request(method: "POST", path: base, jsonBody: data)
        return try await transport.decode(FactsResponse.self, from: respData)
    }

    @discardableResult
    public func batch(
        messages: [BatchMessage],
        extract: BatchExtractionMode? = nil,
        infer: InferMode? = nil,
        labels: [String]? = nil,
        scope: [String]? = nil,
        sessionId: String? = nil
    ) async throws -> FactsBatchResponse {
        var payload: [String: JSONValue] = [
            "messages": try await transport.jsonValue(messages)
        ]
        if let extract { payload["extract"] = .string(extract.rawValue) }
        if let infer { payload["infer"] = .string(infer.rawValue) }
        if let labels { payload["labels"] = .array(labels.map { .string($0) }) }
        if let scope { payload["scope"] = .array(scope.map { .string($0) }) }
        if let sessionId { payload["session_id"] = .string(sessionId) }
        let data = try JSONValue.encodeObject(payload)
        let (respData, _) = try await transport.request(method: "POST", path: "\(base)/batch", jsonBody: data)
        return try await transport.decode(FactsBatchResponse.self, from: respData)
    }
}

// MARK: - Entities

public struct EntitiesNamespace: Sendable {
    let transport: SpectronTransport
    let base: String

    init(transport: SpectronTransport, contextId: String) {
        self.transport = transport
        self.base = "\(Paths.endUserBase(contextId))/entities"
    }

    public func list(type: String? = nil) async throws -> [EntityDetail] {
        let qi = QueryItems.from([("type", type)])
        let resp = try await transport.get(base, query: qi, as: EntityListResponse.self)
        return resp.entities
    }

    public func get(type: String, name: String) async throws -> EntityView {
        let path = "\(base)/\(SpectronTransport.quotePath(type))/\(SpectronTransport.quotePath(name))"
        return try await transport.get(path, as: EntityView.self)
    }

    public func history(type: String, name: String, key: String) async throws -> [AttributeDetail] {
        let path = "\(base)/\(SpectronTransport.quotePath(type))/\(SpectronTransport.quotePath(name))/history/\(SpectronTransport.quotePath(key))"
        let resp = try await transport.get(path, as: EntityHistoryResponse.self)
        return resp.history
    }

    public func delete(type: String, name: String) async throws {
        let path = "\(base)/\(SpectronTransport.quotePath(type))/\(SpectronTransport.quotePath(name))"
        try await transport.delete(path)
    }
}

// MARK: - Lifecycle

public struct LifecycleNamespace: Sendable {
    let transport: SpectronTransport
    let base: String

    init(transport: SpectronTransport, contextId: String) {
        self.transport = transport
        self.base = "\(Paths.endUserBase(contextId))/lifecycle"
    }

    @discardableResult
    public func expire() async throws -> LifecycleResult {
        let data = try JSONValue.encodeObject([:])
        let (respData, _) = try await transport.request(method: "POST", path: "\(base)/expire", jsonBody: data)
        return try await transport.decode(LifecycleResult.self, from: respData)
    }

    @discardableResult
    public func decay() async throws -> LifecycleResult {
        let data = try JSONValue.encodeObject([:])
        let (respData, _) = try await transport.request(method: "POST", path: "\(base)/decay", jsonBody: data)
        return try await transport.decode(LifecycleResult.self, from: respData)
    }
}

// MARK: - Traces

public struct TracesNamespace: Sendable {
    let transport: SpectronTransport
    let base: String

    init(transport: SpectronTransport, contextId: String) {
        self.transport = transport
        self.base = "\(Paths.endUserBase(contextId))/traces"
    }

    public func list(limit: Int? = nil) async throws -> [TraceRecord] {
        let qi = QueryItems.from([("limit", limit)])
        let resp = try await transport.get(base, query: qi, as: TraceListResponse.self)
        return resp.traces
    }

    public func get(_ traceId: String) async throws -> TraceRecord {
        try await transport.get("\(base)/\(SpectronTransport.quotePath(traceId))", as: TraceRecord.self)
    }

    public func stats() async throws -> TraceStats {
        try await transport.get("\(base)/stats", as: TraceStats.self)
    }
}
