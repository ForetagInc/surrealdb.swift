import Foundation

public struct DocumentsNamespace: Sendable {
    let transport: SpectronTransport
    let contextId: String
    let base: String

    public let keywords: KeywordsNamespace

    init(transport: SpectronTransport, contextId: String) {
        self.transport = transport
        self.contextId = contextId
        self.base = "\(Paths.endUserBase(contextId))/documents"
        self.keywords = KeywordsNamespace(transport: transport, contextId: contextId)
    }

    // MARK: - Upload and reprocess

    @discardableResult
    public func upload(
        file: SpectronFile,
        title: String? = nil,
        source: String? = nil,
        onBehalfOf: String? = nil
    ) async throws -> UploadResponse {
        let (data, filename, mime) = try file.read()
        let metadata = UploadMetadata(title: title, source: source, mimeType: mime)
        var form = MultipartForm()
        try appendMetadata(metadata, to: &form)
        form.appendFile("file", filename: filename, mimeType: mime, data: data)
        let body = form.finalize()
        let (respData, _) = try await transport.uploadMultipart(
            base,
            method: "POST",
            body: body,
            contentType: form.contentType,
            extraHeaders: delegationHeaders(onBehalfOf)
        )
        return try await transport.decode(UploadResponse.self, from: respData)
    }

    @discardableResult
    public func replace(
        documentId: String,
        file: SpectronFile,
        title: String? = nil,
        source: String? = nil,
        onBehalfOf: String? = nil
    ) async throws -> UploadResponse {
        let (data, filename, mime) = try file.read()
        let metadata = UploadMetadata(title: title, source: source, mimeType: mime)
        var form = MultipartForm()
        try appendMetadata(metadata, to: &form)
        form.appendFile("file", filename: filename, mimeType: mime, data: data)
        let body = form.finalize()
        let path = "\(base)/\(SpectronTransport.quotePath(documentId))"
        let (respData, _) = try await transport.uploadMultipart(
            path,
            method: "PUT",
            body: body,
            contentType: form.contentType,
            extraHeaders: delegationHeaders(onBehalfOf)
        )
        return try await transport.decode(UploadResponse.self, from: respData)
    }

    private func appendMetadata(_ metadata: UploadMetadata, to form: inout MultipartForm) throws {
        guard !metadata.isEmpty else { return }
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.withoutEscapingSlashes]
        let jsonData = try encoder.encode(metadata)
        form.appendJSONField("metadata", jsonData: jsonData)
    }

    // MARK: - Read

    public func get(_ documentId: String, onBehalfOf: String? = nil) async throws -> Document {
        try await transport.get(
            "\(base)/\(SpectronTransport.quotePath(documentId))",
            extraHeaders: delegationHeaders(onBehalfOf),
            as: Document.self
        )
    }

    public func raw(_ documentId: String, onBehalfOf: String? = nil) async throws -> Data {
        try await transport.rawBytes(
            "\(base)/\(SpectronTransport.quotePath(documentId))/raw",
            extraHeaders: delegationHeaders(onBehalfOf)
        )
    }

    public func chunks(_ documentId: String, page: Int? = nil, pageSize: Int? = nil, onBehalfOf: String? = nil) async throws -> ChunkPage {
        let q = QueryItems.from([("page", page), ("page_size", pageSize)])
        return try await transport.get(
            "\(base)/\(SpectronTransport.quotePath(documentId))/chunks",
            query: q,
            extraHeaders: delegationHeaders(onBehalfOf),
            as: ChunkPage.self
        )
    }

    public func keywordsFor(_ documentId: String, onBehalfOf: String? = nil) async throws -> [DocumentKeyword] {
        let path = "\(base)/\(SpectronTransport.quotePath(documentId))/keywords"
        let resp = try await transport.get(path, extraHeaders: delegationHeaders(onBehalfOf), as: DocumentKeywordsResponse.self)
        return resp.keywords
    }

    public func list(
        status: DocumentStatus? = nil,
        mimeType: String? = nil,
        page: Int? = nil,
        pageSize: Int? = nil,
        onBehalfOf: String? = nil
    ) async throws -> DocumentPage {
        let q = QueryItems.from([
            ("status", status?.rawValue),
            ("mime_type", mimeType),
            ("page", page),
            ("page_size", pageSize)
        ])
        return try await transport.get(base, query: q, extraHeaders: delegationHeaders(onBehalfOf), as: DocumentPage.self)
    }

    public func delete(_ documentId: String, onBehalfOf: String? = nil) async throws {
        try await transport.delete(
            "\(base)/\(SpectronTransport.quotePath(documentId))",
            extraHeaders: delegationHeaders(onBehalfOf)
        )
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
        graphEdges: [GraphEdgeKind]? = nil,
        graphDepth: Int? = nil,
        expandGraph: Bool? = nil,
        decomposeQuery: Bool? = nil,
        useHyde: Bool? = nil,
        useReranker: Bool? = nil,
        filter: QueryFilter? = nil,
        location: DocGeoFilter? = nil,
        onBehalfOf: String? = nil
    ) async throws -> QueryResponse {
        var payload: [String: JSONValue] = ["query": .string(query)]
        if let mode { payload["mode"] = .string(mode.rawValue) }
        if let k { payload["k"] = .int(Int64(k)) }
        if let threshold { payload["threshold"] = .double(threshold) }
        if let vectorWeight { payload["vectorWeight"] = .double(vectorWeight) }
        if let rrfK { payload["rrfK"] = .double(rrfK) }
        if let graphAlpha { payload["graphAlpha"] = .double(graphAlpha) }
        if let graphEdges { payload["graphEdges"] = .array(graphEdges.map { .string($0.rawValue) }) }
        if let graphDepth { payload["graphDepth"] = .int(Int64(graphDepth)) }
        if let expandGraph { payload["expandGraph"] = .bool(expandGraph) }
        if let decomposeQuery { payload["decomposeQuery"] = .bool(decomposeQuery) }
        if let useHyde { payload["useHyde"] = .bool(useHyde) }
        if let useReranker { payload["useReranker"] = .bool(useReranker) }
        if let filter { payload["filter"] = try await transport.jsonValue(filter) }
        if let location { payload["location"] = try await transport.jsonValue(location) }
        let data = try JSONValue.encodeObject(payload)
        let (respData, _) = try await transport.request(
            method: "POST",
            path: "\(base)/query",
            jsonBody: data,
            extraHeaders: delegationHeaders(onBehalfOf)
        )
        return try await transport.decode(QueryResponse.self, from: respData)
    }

    public func recomputeLinks(onBehalfOf: String? = nil) async throws -> RecomputeLinksResponse {
        let data = try JSONValue.encodeObject([:])
        let (respData, _) = try await transport.request(
            method: "POST",
            path: "\(base)/recompute-links",
            jsonBody: data,
            extraHeaders: delegationHeaders(onBehalfOf)
        )
        return try await transport.decode(RecomputeLinksResponse.self, from: respData)
    }
}

// MARK: - Keywords

public struct KeywordsNamespace: Sendable {
    let transport: SpectronTransport
    let base: String

    init(transport: SpectronTransport, contextId: String) {
        self.transport = transport
        self.base = "\(Paths.endUserBase(contextId))/documents/keywords"
    }

    public func list(
        q: String? = nil,
        minDocumentCount: Int? = nil,
        sort: String? = nil,
        page: Int? = nil,
        pageSize: Int? = nil,
        onBehalfOf: String? = nil
    ) async throws -> KeywordPage {
        let qi = QueryItems.from([
            ("q", q),
            ("minDocumentCount", minDocumentCount),
            ("sort", sort),
            ("page", page),
            ("pageSize", pageSize)
        ])
        return try await transport.get(base, query: qi, extraHeaders: delegationHeaders(onBehalfOf), as: KeywordPage.self)
    }

    public func search(_ query: String, k: Int? = nil, threshold: Double? = nil, onBehalfOf: String? = nil) async throws -> KeywordSearchResponse {
        var payload: [String: JSONValue] = ["query": .string(query)]
        if let k { payload["k"] = .int(Int64(k)) }
        if let threshold { payload["threshold"] = .double(threshold) }
        let data = try JSONValue.encodeObject(payload)
        let (respData, _) = try await transport.request(
            method: "POST",
            path: "\(base)/search",
            jsonBody: data,
            extraHeaders: delegationHeaders(onBehalfOf)
        )
        return try await transport.decode(KeywordSearchResponse.self, from: respData)
    }

    public func get(_ normalised: String, onBehalfOf: String? = nil) async throws -> KeywordDetail {
        try await transport.get(
            "\(base)/\(SpectronTransport.quotePath(normalised))",
            extraHeaders: delegationHeaders(onBehalfOf),
            as: KeywordDetail.self
        )
    }
}
