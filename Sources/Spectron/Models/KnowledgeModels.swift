import Foundation

public struct Chunk: Sendable, Codable, Equatable {
    public let charEnd: Int
    public let charStart: Int
    public let document: String
    public let id: String
    public let position: Int
    public let text: String
    public let section: String?
    public let tokenCount: Int?

    public init(charEnd: Int, charStart: Int, document: String, id: String, position: Int, text: String, section: String? = nil, tokenCount: Int? = nil) {
        self.charEnd = charEnd; self.charStart = charStart; self.document = document; self.id = id
        self.position = position; self.text = text; self.section = section; self.tokenCount = tokenCount
    }
}

public struct ChunkPage: Sendable, Codable, Equatable {
    public let chunks: [Chunk]
    public let page: Int
    public let pageSize: Int
    public let total: Int
}

public struct Document: Sendable, Codable, Equatable {
    public let contentHash: String
    public let createdAt: String
    public let id: String
    public let mimeType: String
    public let sizeBytes: Int
    public let source: String
    public let status: String
    public let title: String
    public let updatedAt: String
    public let version: Int
    public let chunkCount: Int?
    public let error: String?
    public let keywordCount: Int?
    public let language: String?
    public let processingCompletedAt: String?
    public let processingStartedAt: String?
}

public struct DocumentPage: Sendable, Codable, Equatable {
    public let documents: [Document]
    public let page: Int
    public let pageSize: Int
    public let total: Int
}

public struct DocumentKeyword: Sendable, Codable, Equatable {
    public let id: String
    public let normalised: String
    public let score: Double
    public let text: String
}

public struct DocumentKeywordsResponse: Sendable, Codable, Equatable {
    public let keywords: [DocumentKeyword]
}

public struct Keyword: Sendable, Codable, Equatable {
    public let documentCount: Int
    public let id: String
    public let normalised: String
    public let text: String
}

public struct KeywordPage: Sendable, Codable, Equatable {
    public let keywords: [Keyword]
    public let page: Int
    public let pageSize: Int
    public let total: Int
}

public struct KeywordDocument: Sendable, Codable, Equatable {
    public let id: String
    public let score: Double
    public let title: String
}

public struct KeywordDetail: Sendable, Codable, Equatable {
    public let documentCount: Int
    public let documents: [KeywordDocument]
    public let id: String
    public let normalised: String
    public let text: String
}

public struct KeywordSearchHit: Sendable, Codable, Equatable {
    public let documentCount: Int
    public let id: String
    public let normalised: String
    public let score: Double
    public let text: String
}

public struct KeywordSearchResponse: Sendable, Codable, Equatable {
    public let queryMs: Int
    public let results: [KeywordSearchHit]
}

public struct KnowledgeLinkTarget: Sendable, Codable, Equatable {
    public let kind: String
    public let slug: String

    public init(kind: String, slug: String) {
        self.kind = kind; self.slug = slug
    }
}

public struct KnowledgeLinkUpsert: Sendable, Codable, Equatable {
    public let label: String
    public let to: KnowledgeLinkTarget

    public init(label: String, to: KnowledgeLinkTarget) {
        self.label = label; self.to = to
    }
}

public struct KnowledgeNodeUpsertRow: Sendable, Codable, Equatable {
    public let kind: String
    public let slug: String
    public let title: String
    public let content: [String: JSONValue]?
    public let links: [KnowledgeLinkUpsert]?
    public let sourceDocument: String?

    public init(
        kind: String,
        slug: String,
        title: String,
        content: [String: JSONValue]? = nil,
        links: [KnowledgeLinkUpsert]? = nil,
        sourceDocument: String? = nil
    ) {
        self.kind = kind; self.slug = slug; self.title = title
        self.content = content; self.links = links; self.sourceDocument = sourceDocument
    }
}

public struct KnowledgeSummary: Sendable, Codable, Equatable {
    public let id: String
    public let kind: String
    public let title: String
}

public struct KnowledgeNodeListed: Sendable, Codable, Equatable {
    public let content: [String: JSONValue]
    public let createdAt: String
    public let id: String
    public let kind: String
    public let scope: [String]
    public let title: String
    public let updatedAt: String
    public let sourceDocument: String?
}

public struct KnowledgeNodeFull: Sendable, Codable, Equatable {
    public let content: [String: JSONValue]
    public let createdAt: String
    public let embedding: [Double]
    public let id: String
    public let kind: String
    public let scope: [String]
    public let title: String
    public let updatedAt: String
    public let sourceDocument: String?
}

public struct KnowledgeNodePage: Sendable, Codable, Equatable {
    public let nodes: [KnowledgeNodeListed]
    public let page: Int
    public let pageSize: Int
    public let total: Int
}

public struct KnowledgeNodeSearchHit: Sendable, Codable, Equatable {
    public let node: KnowledgeSummary
    public let score: Double
}

public struct KnowledgeNodeSearchResponse: Sendable, Codable, Equatable {
    public let queryMs: Int
    public let results: [KnowledgeNodeSearchHit]
}

public struct QueryFilter: Sendable, Codable, Equatable {
    public var documentIds: [String]?
    public var mimeType: [String]?
    public var scope: [String: String]?

    public init(documentIds: [String]? = nil, mimeType: [String]? = nil, scope: [String: String]? = nil) {
        self.documentIds = documentIds; self.mimeType = mimeType; self.scope = scope
    }
}

public struct QueryHitChunk: Sendable, Codable, Equatable {
    public let charEnd: Int
    public let charStart: Int
    public let document: String
    public let id: String
    public let position: Int
    public let text: String
    public let section: String?
}

public struct QueryHitDocument: Sendable, Codable, Equatable {
    public let id: String
    public let source: String
    public let title: String
}

public struct GraphEvidence: Sendable, Codable, Equatable {
    public let edgeKind: String
    public let neighbourLabel: String
    public let weight: Double
}

public struct QueryHit: Sendable, Codable, Equatable {
    public let chunk: QueryHitChunk
    public let document: QueryHitDocument
    public let score: Double
    public let graphEvidence: [GraphEvidence]?
    public let graphExpansion: [String: JSONValue]?
}

public struct QueryResponse: Sendable, Codable, Equatable {
    public let queryMs: Int
    public let results: [QueryHit]
}

public struct TraverseStart: Sendable, Codable, Equatable {
    public let type: String
    public let id: String?
    public let normalised: String?
    public let kind: String?
    public let slug: String?

    public init(type: String, id: String? = nil, normalised: String? = nil, kind: String? = nil, slug: String? = nil) {
        self.type = type; self.id = id; self.normalised = normalised; self.kind = kind; self.slug = slug
    }
}

public struct TraverseNode: Sendable, Codable, Equatable {
    public let depth: Int
    public let id: String
    public let type: String
    public let kind: String?
    public let normalised: String?
    public let title: String?
}

public struct TraverseEdge: Sendable, Codable, Equatable {
    public let kind: String
    public let label: String?
    public let score: Double?
    public let from: String
    public let to: String

    public init(kind: String, from: String, to: String, label: String? = nil, score: Double? = nil) {
        self.kind = kind; self.from = from; self.to = to; self.label = label; self.score = score
    }
}

public struct TraverseResponse: Sendable, Codable, Equatable {
    public let edges: [TraverseEdge]
    public let nodes: [TraverseNode]
}

public struct UploadResponse: Sendable, Codable, Equatable {
    public let contentHash: String
    public let deduplicated: Bool
    public let id: String
    public let status: String

    public init(contentHash: String, deduplicated: Bool, id: String, status: String) {
        self.contentHash = contentHash; self.deduplicated = deduplicated
        self.id = id; self.status = status
    }
}
