import Foundation

public struct KnowledgeNamespace: Sendable {
    let transport: SpectronTransport
    let contextId: String
    let base: String

    public let keywords: KeywordsNamespace
    public let nodes: NodesNamespace
    public let traverseHelper: TraverseNamespace

    init(transport: SpectronTransport, contextId: String) {
        self.transport = transport
        self.contextId = contextId
        self.base = "\(Paths.endUserBase(contextId))/knowledge"
        self.keywords = KeywordsNamespace(transport: transport, contextId: contextId)
        self.nodes = NodesNamespace(transport: transport, contextId: contextId)
        self.traverseHelper = TraverseNamespace(transport: transport, contextId: contextId)
    }

    // MARK: - Documents

    @discardableResult
    public func upload(
        file: SpectronFile,
        title: String? = nil,
        profile: IngestProfile? = nil,
        scope: [String: String]? = nil
    ) async throws -> UploadResponse {
        let (data, filename, mime) = try file.read()
        var form = MultipartForm()
        if let title { form.appendField("title", value: title) }
        if let profile { form.appendField("profile", value: profile.rawValue) }
        if let scopeWire = Scope.serialise(scope) {
            let encoder = JSONEncoder()
            let jsonData = try encoder.encode(scopeWire)
            form.appendJSONField("scope", jsonData: jsonData)
        }
        form.appendFile("file", filename: filename, mimeType: mime, data: data)
        let body = form.finalize()
        let (respData, _) = try await transport.uploadMultipart(base, method: "POST", body: body, contentType: form.contentType)
        return try await transport.decode(UploadResponse.self, from: respData)
    }

    @discardableResult
    public func replace(
        documentId: String,
        file: SpectronFile,
        title: String? = nil,
        profile: IngestProfile? = nil
    ) async throws -> UploadResponse {
        let (data, filename, mime) = try file.read()
        var form = MultipartForm()
        if let title { form.appendField("title", value: title) }
        if let profile { form.appendField("profile", value: profile.rawValue) }
        form.appendFile("file", filename: filename, mimeType: mime, data: data)
        let body = form.finalize()
        let path = "\(base)/\(SpectronTransport.quotePath(documentId))"
        let (respData, _) = try await transport.uploadMultipart(path, method: "PUT", body: body, contentType: form.contentType)
        if respData.isEmpty {
            return UploadResponse(contentHash: "", deduplicated: false, id: documentId, status: "queued")
        }
        return try await transport.decode(UploadResponse.self, from: respData)
    }

    public func get(_ documentId: String) async throws -> Document {
        try await transport.get("\(base)/\(SpectronTransport.quotePath(documentId))", as: Document.self)
    }

    public func raw(_ documentId: String) async throws -> Data {
        try await transport.rawBytes("\(base)/\(SpectronTransport.quotePath(documentId))/raw")
    }

    public func chunks(_ documentId: String, page: Int? = nil, pageSize: Int? = nil) async throws -> ChunkPage {
        let q = QueryItems.from([("page", page), ("page_size", pageSize)])
        return try await transport.get(
            "\(base)/\(SpectronTransport.quotePath(documentId))/chunks",
            query: q,
            as: ChunkPage.self
        )
    }

    public func list(status: String? = nil, mimeType: String? = nil, page: Int? = nil, pageSize: Int? = nil) async throws -> DocumentPage {
        let q = QueryItems.from([
            ("status", status),
            ("mime_type", mimeType),
            ("page", page),
            ("page_size", pageSize)
        ])
        return try await transport.get(base, query: q, as: DocumentPage.self)
    }

    public func related(_ documentId: String) async throws -> TraverseResponse {
        try await transport.get("\(base)/\(SpectronTransport.quotePath(documentId))/related", as: TraverseResponse.self)
    }

    public func delete(_ documentId: String) async throws {
        try await transport.delete("\(base)/\(SpectronTransport.quotePath(documentId))")
    }

    // MARK: - Query

    public func query(
        _ query: String,
        mode: QueryMode? = nil,
        k: Int? = nil,
        threshold: Double? = nil,
        vectorWeight: Double? = nil,
        rrfK: Double? = nil,
        graphAlpha: Double? = nil,
        graphEdges: [String]? = nil,
        graphDepth: Int? = nil,
        expandGraph: Bool? = nil,
        filter: QueryFilter? = nil
    ) async throws -> QueryResponse {
        var payload: [String: JSONValue] = ["query": .string(query)]
        if let mode { payload["mode"] = .string(mode.rawValue) }
        if let k { payload["k"] = .int(Int64(k)) }
        if let threshold { payload["threshold"] = .double(threshold) }
        if let vectorWeight { payload["vectorWeight"] = .double(vectorWeight) }
        if let rrfK { payload["rrfK"] = .double(rrfK) }
        if let graphAlpha { payload["graphAlpha"] = .double(graphAlpha) }
        if let graphEdges { payload["graphEdges"] = .array(graphEdges.map { .string($0) }) }
        if let graphDepth { payload["graphDepth"] = .int(Int64(graphDepth)) }
        if let expandGraph { payload["expandGraph"] = .bool(expandGraph) }
        if let filter {
            let encoded = try await transport.encode(filter)
            if let value = try? JSONDecoder().decode(JSONValue.self, from: encoded) {
                payload["filter"] = value
            }
        }
        let data = try JSONValue.encodeObject(payload)
        let (respData, _) = try await transport.request(method: "POST", path: "\(base)/query", jsonBody: data)
        return try await transport.decode(QueryResponse.self, from: respData)
    }

    // MARK: - Traversal

    public func traverse(
        start: [TraverseStart],
        edges: [String],
        direction: String? = nil,
        labels: [String]? = nil,
        maxDepth: Int? = nil,
        limitPerHop: Int? = nil,
        minScore: Double? = nil
    ) async throws -> TraverseResponse {
        try await traverseHelper.run(
            start: start, edges: edges, direction: direction, labels: labels,
            maxDepth: maxDepth, limitPerHop: limitPerHop, minScore: minScore
        )
    }

    public func traverseRecursive(start: TraverseStart, edge: String, maxDepth: Int = 3, direction: String? = nil) async throws -> TraverseResponse {
        try await traverseHelper.recursive(start: start, edge: edge, maxDepth: maxDepth, direction: direction)
    }

    public func traverseSiblings(start: TraverseStart, edge: String) async throws -> TraverseResponse {
        try await traverseHelper.siblings(start: start, edge: edge)
    }
}

// MARK: - Keywords

public struct KeywordsNamespace: Sendable {
    let transport: SpectronTransport
    let base: String
    let knowledgeBase: String

    init(transport: SpectronTransport, contextId: String) {
        self.transport = transport
        let kb = "\(Paths.endUserBase(contextId))/knowledge"
        self.knowledgeBase = kb
        self.base = "\(kb)/keywords"
    }

    public func list(
        q: String? = nil,
        minDocumentCount: Int? = nil,
        sort: String? = nil,
        page: Int? = nil,
        pageSize: Int? = nil
    ) async throws -> KeywordPage {
        let qi = QueryItems.from([
            ("q", q),
            ("minDocumentCount", minDocumentCount),
            ("sort", sort),
            ("page", page),
            ("pageSize", pageSize)
        ])
        return try await transport.get(base, query: qi, as: KeywordPage.self)
    }

    public func search(_ query: String, k: Int? = nil, threshold: Double? = nil) async throws -> KeywordSearchResponse {
        var payload: [String: JSONValue] = ["query": .string(query)]
        if let k { payload["k"] = .int(Int64(k)) }
        if let threshold { payload["threshold"] = .double(threshold) }
        let data = try JSONValue.encodeObject(payload)
        let (respData, _) = try await transport.request(method: "POST", path: "\(base)/search", jsonBody: data)
        return try await transport.decode(KeywordSearchResponse.self, from: respData)
    }

    public func get(_ normalised: String) async throws -> KeywordDetail {
        try await transport.get("\(base)/\(SpectronTransport.quotePath(normalised))", as: KeywordDetail.self)
    }

    public func related(_ normalised: String) async throws -> TraverseResponse {
        try await transport.get("\(base)/\(SpectronTransport.quotePath(normalised))/related", as: TraverseResponse.self)
    }

    public func forDocument(_ documentId: String) async throws -> [DocumentKeyword] {
        let path = "\(knowledgeBase)/\(SpectronTransport.quotePath(documentId))/keywords"
        let resp = try await transport.get(path, as: DocumentKeywordsResponse.self)
        return resp.keywords
    }
}

// MARK: - Nodes

public struct NodesNamespace: Sendable {
    let transport: SpectronTransport
    let base: String

    init(transport: SpectronTransport, contextId: String) {
        self.transport = transport
        self.base = "\(Paths.endUserBase(contextId))/knowledge/nodes"
    }

    public func list(kind: String? = nil, q: String? = nil, page: Int? = nil, pageSize: Int? = nil) async throws -> KnowledgeNodePage {
        let qi = QueryItems.from([("kind", kind), ("q", q), ("page", page), ("pageSize", pageSize)])
        return try await transport.get(base, query: qi, as: KnowledgeNodePage.self)
    }

    public func upsert(
        nodes: [KnowledgeNodeUpsertRow],
        relations: [KnowledgeLinkUpsert]? = nil,
        scope: [String: String]? = nil
    ) async throws {
        let encoder = JSONEncoder()
        let nodesData = try encoder.encode(nodes)
        let nodesValue = try JSONDecoder().decode([JSONValue].self, from: nodesData)
        var payload: [String: JSONValue] = ["nodes": .array(nodesValue)]
        if let relations {
            let relData = try encoder.encode(relations)
            let relValue = try JSONDecoder().decode([JSONValue].self, from: relData)
            payload["relations"] = .array(relValue)
        }
        if let scopeWire = Scope.serialise(scope) {
            let scopeData = try encoder.encode(scopeWire)
            let scopeValue = try JSONDecoder().decode(JSONValue.self, from: scopeData)
            payload["scope"] = scopeValue
        }
        let data = try JSONValue.encodeObject(payload)
        _ = try await transport.request(method: "POST", path: "\(base)/batch", jsonBody: data)
    }

    public func search(
        _ query: String,
        k: Int = 10,
        threshold: Double = 0.0,
        rrfK: Int? = nil,
        vectorWeight: Double? = nil,
        kindFilter: String? = nil
    ) async throws -> KnowledgeNodeSearchResponse {
        var payload: [String: JSONValue] = [
            "query": .string(query),
            "k": .int(Int64(k)),
            "threshold": .double(threshold)
        ]
        if let rrfK { payload["rrfK"] = .int(Int64(rrfK)) }
        if let vectorWeight { payload["vectorWeight"] = .double(vectorWeight) }
        if let kindFilter { payload["kindFilter"] = .string(kindFilter) }
        let data = try JSONValue.encodeObject(payload)
        let (respData, _) = try await transport.request(method: "POST", path: "\(base)/search", jsonBody: data)
        return try await transport.decode(KnowledgeNodeSearchResponse.self, from: respData)
    }

    public func get(kind: String, slug: String) async throws -> KnowledgeNodeFull {
        let path = "\(base)/\(SpectronTransport.quotePath(kind))/\(SpectronTransport.quotePath(slug))"
        return try await transport.get(path, as: KnowledgeNodeFull.self)
    }

    public func related(kind: String, slug: String, label: String? = nil, depth: Int? = nil) async throws -> TraverseResponse {
        let qi = QueryItems.from([("label", label), ("depth", depth)])
        let path = "\(base)/\(SpectronTransport.quotePath(kind))/\(SpectronTransport.quotePath(slug))/related"
        return try await transport.get(path, query: qi, as: TraverseResponse.self)
    }

    public func delete(kind: String, slug: String) async throws {
        let path = "\(base)/\(SpectronTransport.quotePath(kind))/\(SpectronTransport.quotePath(slug))"
        try await transport.delete(path)
    }
}

// MARK: - Traverse

public struct TraverseNamespace: Sendable {
    let transport: SpectronTransport
    let base: String

    init(transport: SpectronTransport, contextId: String) {
        self.transport = transport
        self.base = "\(Paths.endUserBase(contextId))/knowledge/traverse"
    }

    public func run(
        start: [TraverseStart],
        edges: [String],
        direction: String? = nil,
        labels: [String]? = nil,
        maxDepth: Int? = nil,
        limitPerHop: Int? = nil,
        minScore: Double? = nil
    ) async throws -> TraverseResponse {
        let encoder = JSONEncoder()
        let startData = try encoder.encode(start)
        let startValue = try JSONDecoder().decode([JSONValue].self, from: startData)
        var payload: [String: JSONValue] = [
            "start": .array(startValue),
            "edges": .array(edges.map { .string($0) })
        ]
        if let direction { payload["direction"] = .string(direction) }
        if let labels { payload["labels"] = .array(labels.map { .string($0) }) }
        if let maxDepth { payload["maxDepth"] = .int(Int64(maxDepth)) }
        if let limitPerHop { payload["limitPerHop"] = .int(Int64(limitPerHop)) }
        if let minScore { payload["minScore"] = .double(minScore) }
        let data = try JSONValue.encodeObject(payload)
        let (respData, _) = try await transport.request(method: "POST", path: base, jsonBody: data)
        return try await transport.decode(TraverseResponse.self, from: respData)
    }

    public func recursive(start: TraverseStart, edge: String, maxDepth: Int = 3, direction: String? = nil) async throws -> TraverseResponse {
        let encoder = JSONEncoder()
        let startData = try encoder.encode(start)
        let startValue = try JSONDecoder().decode(JSONValue.self, from: startData)
        var payload: [String: JSONValue] = [
            "start": startValue,
            "edge": .string(edge),
            "maxDepth": .int(Int64(maxDepth))
        ]
        if let direction { payload["direction"] = .string(direction) }
        let data = try JSONValue.encodeObject(payload)
        let (respData, _) = try await transport.request(method: "POST", path: "\(base)/recursive", jsonBody: data)
        return try await transport.decode(TraverseResponse.self, from: respData)
    }

    public func siblings(start: TraverseStart, edge: String) async throws -> TraverseResponse {
        let encoder = JSONEncoder()
        let startData = try encoder.encode(start)
        let startValue = try JSONDecoder().decode(JSONValue.self, from: startData)
        let payload: [String: JSONValue] = [
            "start": startValue,
            "edge": .string(edge)
        ]
        let data = try JSONValue.encodeObject(payload)
        let (respData, _) = try await transport.request(method: "POST", path: "\(base)/siblings", jsonBody: data)
        return try await transport.decode(TraverseResponse.self, from: respData)
    }
}
