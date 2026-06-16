import Foundation

// MARK: - Sessions

public struct SessionInfo: Sendable, Codable, Equatable {
    public let id: String
    /// Scope selector in disjunctive normal form (an OR of AND-clauses), echoed
    /// back from the requested selector.
    public let scopes: [[String]]
    public let createdAt: String

    public init(id: String, scopes: [[String]] = [], createdAt: String = "") {
        self.id = id
        self.scopes = scopes
        self.createdAt = createdAt
    }
}

public struct Turn: Sendable, Codable, Equatable {
    public let id: String
    public let session: String
    public let seq: Int
    public let role: TurnRole
    public let content: String
    public let createdAt: String
}

struct TurnListResponse: Codable {
    let turns: [Turn]
}

// MARK: - Extraction (memory diff returned by ingestion)

public struct EntitySummary: Sendable, Codable, Equatable {
    public let id: String
    public let entityType: String
    public let name: String
    public let memoryCategory: MemoryCategory
    public let isNew: Bool
}

public struct AttributeSummary: Sendable, Codable, Equatable {
    public let id: String
    public let entityId: String
    public let key: String
    public let value: String
    public let memoryCategory: MemoryCategory
}

public struct RelationSummary: Sendable, Codable, Equatable {
    public let subject: String
    public let label: String
    public let object: String
    public let memoryCategory: MemoryCategory
}

public struct CorrectionSummary: Sendable, Codable, Equatable {
    public let entityId: String
    public let key: String
    public let oldValue: String
    public let newValue: String
}

public struct InstructionSummary: Sendable, Codable, Equatable {
    public let id: String
    public let label: String
    public let description: String
}

public struct UncertaintySummary: Sendable, Codable, Equatable {
    public let about: String
    public let reason: String
}

public struct ExtractionResult: Sendable, Codable, Equatable {
    public let turnId: String
    public let entities: [EntitySummary]
    public let attributes: [AttributeSummary]
    public let relations: [RelationSummary]
    public let corrections: [CorrectionSummary]
    public let instructions: [InstructionSummary]
    public let uncertainties: [UncertaintySummary]
}

// MARK: - Chat and context

public struct ChatReply: Sendable, Codable, Equatable {
    public let reply: String
    public let sessionId: String
    public let traceId: String
    public let memoryUpdates: ExtractionResult
}

public struct ContextResult: Sendable, Codable, Equatable {
    public let context: String
    public let tier: String
    public let queryMs: Int
}

public struct SessionContextResult: Sendable, Codable, Equatable {
    public let context: String
}

// MARK: - Memory query

public struct MemoryHit: Sendable, Codable, Equatable {
    public let id: String
    public let source: ResultKind
    public let score: Double
    public let text: String
}

public struct QueryTrace: Sendable, Codable, Equatable {
    public let traceId: String
    public let resolutionTier: String
    public let tierReason: String
    public let latencyMs: Int
    public let retrievedCount: Int
    public let topScores: [Double]
}

public struct MemoryQueryResponse: Sendable, Codable, Equatable {
    public let hits: [MemoryHit]
    public let tier: Tier
    public let classificationKind: QueryKind
    public let seedEntities: [String]
    public let queryMs: Int
    public let trace: QueryTrace
}

/// Geospatial filter for a memory query.
public struct GeoNear: Sendable, Codable, Equatable {
    public let lat: Double
    public let lng: Double
    public let radiusKm: Double

    public init(lat: Double, lng: Double, radiusKm: Double) {
        self.lat = lat; self.lng = lng; self.radiusKm = radiusKm
    }
}

public struct GeoFilter: Sendable, Codable, Equatable {
    public let near: GeoNear?
    public let within: String?

    public init(near: GeoNear? = nil, within: String? = nil) {
        self.near = near; self.within = within
    }
}

// MARK: - Entities, attributes, relations (detailed views)

public struct EntityDetail: Sendable, Codable, Equatable {
    public let id: String
    public let entityType: String
    public let name: String
    public let memoryCategory: MemoryCategory
    public let importance: Double
    public let createdAt: String
    public let updatedAt: String
}

public struct AttributeDetail: Sendable, Codable, Equatable {
    public let id: String
    public let entity: String
    public let key: String
    public let value: String
    public let memoryCategory: MemoryCategory
    public let importance: Double
    public let supersedes: String?
    public let supersededBy: String?
    public let validFrom: String?
    public let validUntil: String?
    public let createdAt: String
}

public struct RelationDetail: Sendable, Codable, Equatable {
    public let id: String
    public let subject: String
    public let label: String
    public let object: String
    public let memoryCategory: MemoryCategory
    public let validFrom: String?
    public let validUntil: String?
    public let createdAt: String
}

public struct EntityView: Sendable, Codable, Equatable {
    public let entity: EntityDetail
    public let attributes: [AttributeDetail]
    public let relations: [RelationDetail]
}

struct EntityListResponse: Codable {
    let entities: [EntityDetail]
}

struct EntityHistoryResponse: Codable {
    let history: [AttributeDetail]
}

// MARK: - State and profile

public struct CategoryState: Sendable, Codable, Equatable {
    public let entities: [EntityDetail]
    public let attributes: [AttributeDetail]
    public let relations: [RelationDetail]
}

public struct StructuredState: Sendable, Codable, Equatable {
    public let identity: CategoryState
    public let knowledge: CategoryState
    public let context: CategoryState
    public let instructions: [InstructionSummary]
    public let unknowns: [UncertaintySummary]
}

public struct ProfileEntry: Sendable, Codable, Equatable {
    public let key: String
    public let value: String
}

public struct ProfileResponse: Sendable, Codable, Equatable {
    public let `static`: [ProfileEntry]
    public let dynamic: [ProfileEntry]
    public let preferences: [ProfileEntry]
    public let instructions: [InstructionSummary]
}

// MARK: - Reflect and forget

public struct ReflectionResult: Sendable, Codable, Equatable {
    public let reflection: String
    public let evidence: [String]
    public let persistedAttributes: [AttributeSummary]
    public let traceId: String
}

public struct ForgetResult: Sendable, Codable, Equatable {
    public let deleted: Int
}

// MARK: - Lifecycle

public struct LifecycleResult: Sendable, Codable, Equatable {
    public let affected: Int
}

// MARK: - Traces

public struct TraceRecord: Sendable, Codable, Equatable {
    public let id: String
    public let queryText: String
    public let resolutionTier: String
    public let tierReason: String
    public let latencyMs: Int
    public let cached: Bool
    public let createdAt: String
}

struct TraceListResponse: Codable {
    let traces: [TraceRecord]
}

public struct ContradictionStats: Sendable, Codable, Equatable {
    public let contradictions: Int
    public let reconciliations: Int
    public let contradictionRate: Double
}

public struct SupersessionStats: Sendable, Codable, Equatable {
    public let supersessionEvents: Int
    public let entitiesChurned: Int
    public let churnPerEntity: Double
}

public struct RetrievalStats: Sendable, Codable, Equatable {
    public let traces: Int
    public let avgCandidateSet: Double
    public let maxCandidateSet: Int
}

public struct TierCounts: Sendable, Codable, Equatable {
    public let direct: Int
    public let hybrid: Int
    public let fullContext: Int
}

public struct SourceKindCount: Sendable, Codable, Equatable {
    public let kind: String
    public let count: Int
}

public struct TraceStats: Sendable, Codable, Equatable {
    public let totalQueries: Int
    public let cacheHits: Int
    public let cacheHitRate: Double
    public let avgLatencyMs: Double
    public let windowHours: Int
    public let responseTracesTotal: Int
    public let responseTracesCached: Int
    public let tierCounts: TierCounts
    public let sourceKindDistribution: [SourceKindCount]
    public let retrieval: RetrievalStats
    public let contradiction: ContradictionStats
    public let supersession: SupersessionStats
}

// MARK: - Facts

public struct TripleEntity: Sendable, Codable, Equatable {
    public let type: String
    public let name: String

    public init(type: String, name: String) {
        self.type = type; self.name = name
    }
}

/// A single structured fact: `entity.key = value` or `entity -[label]-> target`.
public struct Triple: Sendable, Codable, Equatable {
    public let entity: TripleEntity
    public let key: String
    public let value: String?
    public let target: TripleEntity?
    public let memoryCategory: MemoryCategory?

    public init(
        entity: TripleEntity,
        key: String,
        value: String? = nil,
        target: TripleEntity? = nil,
        memoryCategory: MemoryCategory? = nil
    ) {
        self.entity = entity
        self.key = key
        self.value = value
        self.target = target
        self.memoryCategory = memoryCategory
    }

    private enum CodingKeys: String, CodingKey {
        case entity, key, value, target
        case memoryCategory = "memory_category"
    }
}

/// One message in a batch fact ingestion request.
public struct BatchMessage: Sendable, Codable, Equatable {
    public let role: TurnRole
    public let content: String
    public let ts: String?

    public init(role: TurnRole, content: String, ts: String? = nil) {
        self.role = role; self.content = content; self.ts = ts
    }
}

public struct FactsResponse: Sendable, Codable, Equatable {
    public let sessionId: String
    public let mode: InferMode
    public let turnId: String?
    public let chunkId: String?
    public let preview: Bool?
    public let extraction: ExtractionResult?
}

public struct FactsBatchResponse: Sendable, Codable, Equatable {
    public let sessionId: String
    public let turnIds: [String]
    public let extractions: [ExtractionResult]
}
