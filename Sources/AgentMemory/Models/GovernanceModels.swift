import Foundation

// MARK: - Scopes

public struct ScopeNode: Sendable, Codable, Equatable {
    public let path: String
    public let createdAt: String
    public let tombstonedAt: String?
}

public struct ForgetScopeResult: Sendable, Codable, Equatable {
    public let forgotten: Int
}

// MARK: - Principals and grants

public struct Principal: Sendable, Codable, Equatable {
    public let id: String
    public let kind: String
    public let displayName: String
    /// Map of scope path to the verbs granted on it.
    public let grants: [String: [String]]
}

public struct EffectiveGrants: Sendable, Codable, Equatable {
    public let path: String
    public let verbs: [String]
    public let asOf: String?
}

// MARK: - Audit

public struct AuditRow: Sendable, Codable, Equatable {
    public let traceId: String
    public let kind: String
    public let principal: String?
    public let model: String?
    public let cost: Double
    public let latencyMs: Int
    public let rowsTouched: Int
    public let createdAt: String
}

struct AuditResponse: Codable {
    let rows: [AuditRow]
}

// MARK: - fsck (integrity report)

public struct ContradictionFinding: Sendable, Codable, Equatable {
    public let entity: String
    public let key: String
    public let values: [String]
}

public struct DuplicateFinding: Sendable, Codable, Equatable {
    public let entityA: String
    public let entityB: String
    public let similarity: Double
}

public struct InjectionFinding: Sendable, Codable, Equatable {
    public let rowId: String
    public let kind: String
    public let snippet: String
}

public struct FsckReport: Sendable, Codable, Equatable {
    public let total: Int
    public let contradictions: [ContradictionFinding]
    public let duplicates: [DuplicateFinding]
    public let injection: [InjectionFinding]
}

// MARK: - Consolidate

public struct ConsolidateOutcome: Sendable, Codable, Equatable {
    public let kind: String
    public let entityName: String
    public let key: String
    public let value: String
    public let proofCount: Int
    public let observationId: String?
    public let rationale: String?
}

public struct ConsolidateResponse: Sendable, Codable, Equatable {
    public let dryRun: Bool
    public let created: Int
    public let updated: Int
    public let superseded: Int
    public let outcomes: [ConsolidateOutcome]
    public let traceId: String
}

// MARK: - Elaborate

public struct ElaborateProposedRelation: Sendable, Codable, Equatable {
    public let subject: String
    public let label: String
    public let object: String
}

public struct ElaborateOutcome: Sendable, Codable, Equatable {
    public let dryRun: Bool
    public let entityType: String
    public let entityName: String
    public let proposedRelations: [ElaborateProposedRelation]
    public let relationsEmitted: Int
    public let traceId: String
}

public struct ElaborateResponse: Sendable, Codable, Equatable {
    public let outcomes: [ElaborateOutcome]
    public let relationsEmitted: Int
}

// MARK: - Inspect (discriminated by `kind`)

public enum InspectResponse: Sendable, Equatable {
    case entity(entity: EntityDetail, attributes: [AttributeDetail], relations: [RelationDetail])
    case attribute(current: AttributeDetail?, history: [AttributeDetail])
    case relation(matches: [RelationDetail])
    case trace(TraceRecord)
}

extension InspectResponse: Decodable {
    private enum CodingKeys: String, CodingKey {
        case kind, entity, attributes, relations, current, history, matches, trace
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let kind = try c.decode(String.self, forKey: .kind)
        switch kind {
        case "entity":
            self = .entity(
                entity: try c.decode(EntityDetail.self, forKey: .entity),
                attributes: try c.decode([AttributeDetail].self, forKey: .attributes),
                relations: try c.decode([RelationDetail].self, forKey: .relations)
            )
        case "attribute":
            self = .attribute(
                current: try c.decodeIfPresent(AttributeDetail.self, forKey: .current),
                history: try c.decode([AttributeDetail].self, forKey: .history)
            )
        case "relation":
            self = .relation(matches: try c.decode([RelationDetail].self, forKey: .matches))
        case "trace":
            self = .trace(try c.decode(TraceRecord.self, forKey: .trace))
        default:
            throw DecodingError.dataCorruptedError(
                forKey: .kind,
                in: c,
                debugDescription: "Unknown inspect result kind: \(kind)"
            )
        }
    }
}
