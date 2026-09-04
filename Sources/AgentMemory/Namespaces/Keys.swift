import Foundation

/// Self-service API keys scoped to the context.
public struct KeysNamespace: Sendable {
    let transport: AgentMemoryTransport
    let base: String

    init(transport: AgentMemoryTransport, contextId: String) {
        self.transport = transport
        self.base = "\(Paths.endUserBase(contextId))/keys"
    }

    /// Mints a new key. The returned `MintedKey.key` is the full secret and is
    /// only returned once.
    @discardableResult
    public func create(
        name: String? = nil,
        grants: [String: [String]]? = nil,
        ttlSeconds: Int? = nil,
        onBehalfOf: String? = nil
    ) async throws -> MintedKey {
        var payload: [String: JSONValue] = [:]
        if let name { payload["name"] = .string(name) }
        if let grants { payload["grants"] = .object(grants.mapValues { .array($0.map { .string($0) }) }) }
        let data = try JSONValue.encodeObject(payload)
        let query = QueryItems.from([("ttlSeconds", ttlSeconds)])
        let (respData, _) = try await transport.request(
            method: "POST",
            path: base,
            query: query,
            jsonBody: data,
            extraHeaders: delegationHeaders(onBehalfOf)
        )
        return try await transport.decode(MintedKey.self, from: respData)
    }

    public func list(onBehalfOf: String? = nil) async throws -> [KeyDetail] {
        try await transport.get(base, extraHeaders: delegationHeaders(onBehalfOf), as: [KeyDetail].self)
    }

    public func delete(_ keyName: String, onBehalfOf: String? = nil) async throws {
        try await transport.delete(
            "\(base)/\(AgentMemoryTransport.quotePath(keyName))",
            extraHeaders: delegationHeaders(onBehalfOf)
        )
    }

    @discardableResult
    public func rotate(_ keyName: String, ttlSeconds: Int? = nil, onBehalfOf: String? = nil) async throws -> MintedKey {
        let query = QueryItems.from([("ttlSeconds", ttlSeconds)])
        let path = "\(base)/\(AgentMemoryTransport.quotePath(keyName))/rotate"
        let (respData, _) = try await transport.request(
            method: "POST",
            path: path,
            query: query,
            extraHeaders: delegationHeaders(onBehalfOf)
        )
        return try await transport.decode(MintedKey.self, from: respData)
    }
}
