import Foundation

// MARK: - Documents

public struct Document: Sendable, Codable, Equatable {
    public let id: String
    public let title: String
    public let source: String
    public let mimeType: String
    public let status: DocumentStatus
    public let contentHash: String
    public let sizeBytes: Int
    public let version: Int
    public let createdAt: String
    public let updatedAt: String
    public let chunkCount: Int?
    public let keywordCount: Int?
    public let language: String?
    public let error: String?
    public let processingStartedAt: String?
    public let processingCompletedAt: String?
}

public struct DocumentPage: Sendable, Codable, Equatable {
    public let documents: [Document]
    public let page: Int
    public let pageSize: Int
    public let total: Int
}

public struct UploadResponse: Sendable, Codable, Equatable {
    public let id: String
    public let status: DocumentStatus
    public let contentHash: String
    public let deduplicated: Bool

    public init(id: String, status: DocumentStatus, contentHash: String, deduplicated: Bool) {
        self.id = id; self.status = status
        self.contentHash = contentHash; self.deduplicated = deduplicated
    }
}

/// Metadata supplied alongside a document upload, sent as the JSON `metadata`
/// part of the multipart body before the `file` part.
public struct UploadMetadata: Sendable, Codable, Equatable {
    public let title: String?
    public let source: String?
    public let mimeType: String?

    public init(title: String? = nil, source: String? = nil, mimeType: String? = nil) {
        self.title = title; self.source = source; self.mimeType = mimeType
    }

    private enum CodingKeys: String, CodingKey {
        case title, source
        case mimeType = "mime_type"
    }

    var isEmpty: Bool {
        title == nil && source == nil && mimeType == nil
    }
}

// MARK: - Chunks

public struct Chunk: Sendable, Codable, Equatable {
    public let id: String
    public let document: String
    public let position: Int
    public let charStart: Int
    public let charEnd: Int
    public let text: String
    public let section: String?
    public let tokenCount: Int?
}

public struct ChunkPage: Sendable, Codable, Equatable {
    public let chunks: [Chunk]
    public let page: Int
    public let pageSize: Int
    public let total: Int
}

// MARK: - Keywords

public struct DocumentKeyword: Sendable, Codable, Equatable {
    public let id: String
    public let normalised: String
    public let text: String
    public let score: Double
}

struct DocumentKeywordsResponse: Codable {
    let keywords: [DocumentKeyword]
}

public struct Keyword: Sendable, Codable, Equatable {
    public let id: String
    public let normalised: String
    public let text: String
    public let documentCount: Int
}

public struct KeywordPage: Sendable, Codable, Equatable {
    public let keywords: [Keyword]
    public let page: Int
    public let pageSize: Int
    public let total: Int
}

public struct KeywordDocument: Sendable, Codable, Equatable {
    public let id: String
    public let title: String
    public let score: Double
}

public struct KeywordDetail: Sendable, Codable, Equatable {
    public let id: String
    public let normalised: String
    public let text: String
    public let documentCount: Int
    public let documents: [KeywordDocument]
}

public struct KeywordSearchHit: Sendable, Codable, Equatable {
    public let id: String
    public let normalised: String
    public let text: String
    public let score: Double
    public let documentCount: Int
}

public struct KeywordSearchResponse: Sendable, Codable, Equatable {
    public let queryMs: Int
    public let results: [KeywordSearchHit]
}

// MARK: - Document query

public struct QueryFilter: Sendable, Codable, Equatable {
    public var documentIds: [String]?
    public var mimeType: [String]?

    public init(documentIds: [String]? = nil, mimeType: [String]? = nil) {
        self.documentIds = documentIds; self.mimeType = mimeType
    }
}

/// Geospatial filter for a document query.
public struct DocGeoNear: Sendable, Codable, Equatable {
    public let lat: Double
    public let lng: Double
    public let radiusKm: Double

    public init(lat: Double, lng: Double, radiusKm: Double) {
        self.lat = lat; self.lng = lng; self.radiusKm = radiusKm
    }
}

public struct DocGeoFilter: Sendable, Codable, Equatable {
    public let near: DocGeoNear?
    public let within: String?

    public init(near: DocGeoNear? = nil, within: String? = nil) {
        self.near = near; self.within = within
    }
}

public struct QueryHitChunk: Sendable, Codable, Equatable {
    public let id: String
    public let document: String
    public let position: Int
    public let charStart: Int
    public let charEnd: Int
    public let text: String
    public let section: String?
}

public struct QueryHitDocument: Sendable, Codable, Equatable {
    public let id: String
    public let source: String
    public let title: String
}

public struct GraphEvidence: Sendable, Codable, Equatable {
    public let edgeKind: GraphEdgeKind
    public let neighbourLabel: String
    public let weight: Double
}

public struct QueryHit: Sendable, Codable, Equatable {
    public let chunk: QueryHitChunk
    public let document: QueryHitDocument
    public let score: Double
    public let graphEvidence: [GraphEvidence]?
    public let graphExpansion: JSONValue?
}

public struct QueryResponse: Sendable, Codable, Equatable {
    public let queryMs: Int
    public let results: [QueryHit]
}

public struct RecomputeLinksResponse: Sendable, Codable, Equatable {
    public let linksEmitted: Int
}
