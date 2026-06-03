import Foundation

// MARK: - Scopes

public struct ScopesNamespace: Sendable {
    let transport: SpectronTransport
    let contextId: String
    let base: String

    init(transport: SpectronTransport, contextId: String) {
        self.transport = transport
        self.contextId = contextId
        self.base = "\(Paths.endUserBase(contextId))/scopes"
    }

    public func list() async throws -> [ScopeNode] {
        try await transport.get(base, as: [ScopeNode].self)
    }

    @discardableResult
    public func register(
        path: String,
        displayName: String? = nil,
        description: String? = nil
    ) async throws -> ScopeNode {
        var payload: [String: JSONValue] = ["path": .string(path)]
        if let displayName { payload["displayName"] = .string(displayName) }
        if let description { payload["description"] = .string(description) }
        let data = try JSONValue.encodeObject(payload)
        let (respData, _) = try await transport.request(method: "POST", path: base, jsonBody: data)
        return try await transport.decode(ScopeNode.self, from: respData)
    }

    public func delete(path: String) async throws {
        let q = QueryItems.from([("path", path)])
        _ = try await transport.request(method: "DELETE", path: base, query: q)
    }

    @discardableResult
    public func forget(path: String? = nil) async throws -> ForgetScopeResult {
        var payload: [String: JSONValue] = [:]
        if let path { payload["path"] = .string(path) }
        let data = try JSONValue.encodeObject(payload)
        let (respData, _) = try await transport.request(method: "POST", path: "\(base)/forget", jsonBody: data)
        return try await transport.decode(ForgetScopeResult.self, from: respData)
    }

    /// Grants verbs on scope paths to a subject. This endpoint is a server-side
    /// stub today and currently returns `501 Not Implemented`.
    public func grant(subject: String? = nil, grants: [String: [String]]) async throws {
        var payload: [String: JSONValue] = [
            "grants": .object(grants.mapValues { .array($0.map { .string($0) }) })
        ]
        if let subject { payload["subject"] = .string(subject) }
        let data = try JSONValue.encodeObject(payload)
        let path = "\(Paths.endUserBase(contextId))/scope-grants"
        _ = try await transport.request(method: "POST", path: path, jsonBody: data)
    }
}

// MARK: - Principals

public struct PrincipalsNamespace: Sendable {
    let transport: SpectronTransport
    let base: String

    init(transport: SpectronTransport, contextId: String) {
        self.transport = transport
        self.base = "\(Paths.endUserBase(contextId))/principals"
    }

    public func list() async throws -> [Principal] {
        try await transport.get(base, as: [Principal].self)
    }

    public func get(_ principalId: String) async throws -> Principal {
        try await transport.get("\(base)/\(SpectronTransport.quotePath(principalId))", as: Principal.self)
    }

    public func effective(principalId: String, path: String, asOf: String? = nil) async throws -> EffectiveGrants {
        let q = QueryItems.from([("path", path), ("asOf", asOf)])
        let url = "\(base)/\(SpectronTransport.quotePath(principalId))/effective"
        return try await transport.get(url, query: q, as: EffectiveGrants.self)
    }

    @discardableResult
    public func grant(principalId: String, path: String, verbs: [String]) async throws -> Principal {
        try await mutateGrant(method: "POST", principalId: principalId, path: path, verbs: verbs)
    }

    @discardableResult
    public func revoke(principalId: String, path: String, verbs: [String]) async throws -> Principal {
        try await mutateGrant(method: "DELETE", principalId: principalId, path: path, verbs: verbs)
    }

    private func mutateGrant(method: String, principalId: String, path: String, verbs: [String]) async throws -> Principal {
        let payload: [String: JSONValue] = [
            "path": .string(path),
            "verbs": .array(verbs.map { .string($0) })
        ]
        let data = try JSONValue.encodeObject(payload)
        let url = "\(base)/\(SpectronTransport.quotePath(principalId))/grants"
        let (respData, _) = try await transport.request(method: method, path: url, jsonBody: data)
        return try await transport.decode(Principal.self, from: respData)
    }
}
