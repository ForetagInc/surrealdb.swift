import Foundation

public struct MemoryNamespace: Sendable {
    let transport: SpectronTransport
    let contextId: String
    let base: String

    public let sessions: SessionsNamespace
    public let entities: EntitiesNamespace
    public let lifecycle: LifecycleNamespace
    public let traces: TracesNamespace

    init(transport: SpectronTransport, contextId: String) {
        self.transport = transport
        self.contextId = contextId
        self.base = Paths.endUserBase(contextId)
        self.sessions = SessionsNamespace(transport: transport, contextId: contextId)
        self.entities = EntitiesNamespace(transport: transport, contextId: contextId)
        self.lifecycle = LifecycleNamespace(transport: transport, contextId: contextId)
        self.traces = TracesNamespace(transport: transport, contextId: contextId)
    }

    public func query(_ query: String, k: Int? = nil, sessionId: String? = nil) async throws -> MemoryQueryResponse {
        var payload: [String: JSONValue] = ["query": .string(query)]
        if let k { payload["k"] = .int(Int64(k)) }
        if let sessionId { payload["sessionId"] = .string(sessionId) }
        let data = try JSONValue.encodeObject(payload)
        let (respData, _) = try await transport.request(method: "POST", path: "\(base)/query", jsonBody: data)
        return try await transport.decode(MemoryQueryResponse.self, from: respData)
    }

    public func context(_ query: String, k: Int? = nil) async throws -> ContextResult {
        var payload: [String: JSONValue] = ["query": .string(query)]
        if let k { payload["k"] = .int(Int64(k)) }
        let data = try JSONValue.encodeObject(payload)
        let (respData, _) = try await transport.request(method: "POST", path: "\(base)/context", jsonBody: data)
        return try await transport.decode(ContextResult.self, from: respData)
    }

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

    public func forget(_ query: String) async throws -> ForgetResult {
        let payload: [String: JSONValue] = ["query": .string(query)]
        let data = try JSONValue.encodeObject(payload)
        let (respData, json) = try await transport.request(method: "POST", path: "\(base)/forget", jsonBody: data)
        if case .int(let n)? = json {
            return ForgetResult(deleted: Int(n))
        }
        return try await transport.decode(ForgetResult.self, from: respData)
    }
}

public struct SessionsNamespace: Sendable {
    let transport: SpectronTransport
    let contextId: String
    let base: String

    init(transport: SpectronTransport, contextId: String) {
        self.transport = transport
        self.contextId = contextId
        self.base = "\(Paths.endUserBase(contextId))/sessions"
    }

    public func create(scope: [String: String]? = nil, metadata: [String: JSONValue]? = nil) async throws -> SpectronSession {
        var payload: [String: JSONValue] = [:]
        if let scopeWire = Scope.serialise(scope) {
            let encoder = JSONEncoder()
            let scopeData = try encoder.encode(scopeWire)
            let scopeValue = try JSONDecoder().decode(JSONValue.self, from: scopeData)
            payload["scope"] = scopeValue
        }
        if let metadata { payload["metadata"] = .object(metadata) }
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

    public func turn(role: TurnRole, content: String) async throws -> ExtractionResult {
        let payload: [String: JSONValue] = [
            "role": .string(role.rawValue),
            "content": .string(content)
        ]
        let data = try JSONValue.encodeObject(payload)
        let (respData, _) = try await transport.request(method: "POST", path: "\(base)/turns", jsonBody: data)
        return try await transport.decode(ExtractionResult.self, from: respData)
    }

    public func turns() async throws -> [Turn] {
        let (data, json) = try await transport.request(method: "GET", path: "\(base)/turns")
        if case .object(let dict)? = json, let arr = dict["turns"], case .array(let items) = arr {
            let listData = try JSONEncoder().encode(items)
            return try await transport.decode([Turn].self, from: listData)
        }
        if case .array? = json {
            return try await transport.decode([Turn].self, from: data)
        }
        return []
    }

    public func context(_ query: String, k: Int? = nil) async throws -> ContextResult {
        var payload: [String: JSONValue] = ["query": .string(query)]
        if let k { payload["k"] = .int(Int64(k)) }
        let data = try JSONValue.encodeObject(payload)
        let (respData, _) = try await transport.request(method: "POST", path: "\(base)/context", jsonBody: data)
        return try await transport.decode(ContextResult.self, from: respData)
    }

    public func chat(_ message: String) async throws -> ChatReply {
        let payload: [String: JSONValue] = ["message": .string(message)]
        let data = try JSONValue.encodeObject(payload)
        let (respData, _) = try await transport.request(method: "POST", path: "\(base)/chat", jsonBody: data)
        return try await transport.decode(ChatReply.self, from: respData)
    }
}

public struct EntitiesNamespace: Sendable {
    let transport: SpectronTransport
    let base: String

    init(transport: SpectronTransport, contextId: String) {
        self.transport = transport
        self.base = "\(Paths.endUserBase(contextId))/entities"
    }

    public func list(type: String? = nil) async throws -> [Entity] {
        let qi = QueryItems.from([("type", type)])
        let (data, json) = try await transport.request(method: "GET", path: base, query: qi)
        if case .object(let dict)? = json, let arr = dict["entities"], case .array(let items) = arr {
            let listData = try JSONEncoder().encode(items)
            return try await transport.decode([Entity].self, from: listData)
        }
        if case .array? = json {
            return try await transport.decode([Entity].self, from: data)
        }
        return []
    }

    public func get(type: String, name: String) async throws -> Entity {
        let path = "\(base)/\(SpectronTransport.quotePath(type))/\(SpectronTransport.quotePath(name))"
        return try await transport.get(path, as: Entity.self)
    }

    public func history(type: String, name: String, key: String) async throws -> [EntityHistoryEntry] {
        let path = "\(base)/\(SpectronTransport.quotePath(type))/\(SpectronTransport.quotePath(name))/history/\(SpectronTransport.quotePath(key))"
        let (data, json) = try await transport.request(method: "GET", path: path)
        if case .object(let dict)? = json, let arr = dict["history"], case .array(let items) = arr {
            let listData = try JSONEncoder().encode(items)
            return try await transport.decode([EntityHistoryEntry].self, from: listData)
        }
        if case .array? = json {
            return try await transport.decode([EntityHistoryEntry].self, from: data)
        }
        return []
    }

    public func delete(type: String, name: String) async throws {
        let path = "\(base)/\(SpectronTransport.quotePath(type))/\(SpectronTransport.quotePath(name))"
        try await transport.delete(path)
    }
}

public struct LifecycleNamespace: Sendable {
    let transport: SpectronTransport
    let base: String

    init(transport: SpectronTransport, contextId: String) {
        self.transport = transport
        self.base = "\(Paths.endUserBase(contextId))/lifecycle"
    }

    public func expire() async throws {
        let data = try JSONValue.encodeObject([:])
        _ = try await transport.request(method: "POST", path: "\(base)/expire", jsonBody: data)
    }

    public func decay() async throws {
        let data = try JSONValue.encodeObject([:])
        _ = try await transport.request(method: "POST", path: "\(base)/decay", jsonBody: data)
    }
}

public struct TracesNamespace: Sendable {
    let transport: SpectronTransport
    let base: String

    init(transport: SpectronTransport, contextId: String) {
        self.transport = transport
        self.base = "\(Paths.endUserBase(contextId))/traces"
    }

    public func list(limit: Int? = nil) async throws -> [TraceRecord] {
        let qi = QueryItems.from([("limit", limit)])
        let (data, json) = try await transport.request(method: "GET", path: base, query: qi)
        if case .object(let dict)? = json, let arr = dict["traces"], case .array(let items) = arr {
            let listData = try JSONEncoder().encode(items)
            return try await transport.decode([TraceRecord].self, from: listData)
        }
        if case .array? = json {
            return try await transport.decode([TraceRecord].self, from: data)
        }
        return []
    }

    public func get(_ traceId: String) async throws -> TraceRecord {
        try await transport.get("\(base)/\(SpectronTransport.quotePath(traceId))", as: TraceRecord.self)
    }

    public func stats() async throws -> TraceStats {
        try await transport.get("\(base)/stats", as: TraceStats.self)
    }
}
