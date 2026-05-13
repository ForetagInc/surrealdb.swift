import Foundation

public struct SessionInfo: Sendable, Codable, Equatable {
    public let id: String
    public let scope: [String: String]?
    public let metadata: [String: JSONValue]?
    public let createdAt: String?

    private enum CodingKeys: String, CodingKey {
        case id, scope, metadata, createdAt
    }

    public init(id: String, scope: [String: String]? = nil, metadata: [String: JSONValue]? = nil, createdAt: String? = nil) {
        self.id = id; self.scope = scope; self.metadata = metadata; self.createdAt = createdAt
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        self.id = try c.decode(String.self, forKey: .id)
        self.metadata = try c.decodeIfPresent([String: JSONValue].self, forKey: .metadata)
        self.createdAt = try c.decodeIfPresent(String.self, forKey: .createdAt)
        // Server may return scope as either [{key, value}] entries or a plain dict.
        if let entries = (try? c.decode([[String: String]].self, forKey: .scope)) {
            var out: [String: String] = [:]
            for e in entries {
                if let k = e["key"], let v = e["value"] { out[k] = v }
            }
            self.scope = out.isEmpty ? nil : out
        } else if let dict = try? c.decode([String: String].self, forKey: .scope) {
            self.scope = dict
        } else {
            self.scope = nil
        }
    }

    public func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(id, forKey: .id)
        try c.encodeIfPresent(metadata, forKey: .metadata)
        try c.encodeIfPresent(createdAt, forKey: .createdAt)
        if let scope = scope {
            let wire = scope.map { ["key": $0.key, "value": $0.value] }
            try c.encode(wire, forKey: .scope)
        }
    }
}

public struct Turn: Sendable, Codable, Equatable {
    public let role: TurnRole
    public let content: String
    public let id: String?
    public let createdAt: String?
    public let metadata: [String: JSONValue]?
}

public struct EntityRef: Sendable, Codable, Equatable, Hashable {
    public let type: String
    public let name: String

    public init(type: String, name: String) {
        self.type = type; self.name = name
    }
}

public struct AttributeUpdate: Sendable, Codable, Equatable {
    public let entity: EntityRef
    public let key: String
    public let value: JSONValue
    public let category: MemoryCategory?
    public let confidence: Double?
}

public struct RelationUpdate: Sendable, Codable, Equatable {
    public let label: String
    public let source: EntityRef
    public let target: EntityRef
    public let confidence: Double?
}

public struct ExtractionResult: Sendable, Codable, Equatable {
    public let entities: [EntityRef]?
    public let attributes: [AttributeUpdate]?
    public let relations: [RelationUpdate]?
    public let instructions: [String]?
    public let uncertainties: [String]?
    public let corrections: [[String: JSONValue]]?
    public let turnId: String?
}

public struct ChatReply: Sendable, Codable, Equatable {
    public let reply: String
    public let memoryUpdates: ExtractionResult?
    public let turnId: String?
}

public struct ContextResult: Sendable, Codable, Equatable {
    public let context: String
    public let tier: String?
    public let queryMs: Int?
}

public struct MemoryHit: Sendable, Codable, Equatable {
    public let source: String
    public let score: Double
    public let text: String?
    public let id: String?
    public let metadata: [String: JSONValue]?
}

public struct MemoryQueryResponse: Sendable, Codable, Equatable {
    public let hits: [MemoryHit]
    public let tier: String?
    public let queryMs: Int?
    public let trace: [String: JSONValue]?
}

public struct StructuredState: Sendable, Codable, Equatable {
    public let identity: [String: JSONValue]?
    public let knowledge: [String: JSONValue]?
    public let context: [String: JSONValue]?
    public let instructions: [String]?
    public let unknowns: [String]?
}

public struct ProfileResponse: Sendable, Codable, Equatable {
    public let `static`: [String: JSONValue]?
    public let dynamic: [String: JSONValue]?
    public let preferences: [String: JSONValue]?
    public let instructions: [String]?
}

public struct Entity: Sendable, Codable, Equatable {
    public let type: String
    public let name: String
    public let attributes: [String: JSONValue]?
    public let scope: [String: String]?
    public let createdAt: String?
    public let updatedAt: String?
}

public struct EntityHistoryEntry: Sendable, Codable, Equatable {
    public let value: JSONValue
    public let validFrom: String?
    public let validUntil: String?
    public let sourceTurn: String?
}

public struct ReflectionResult: Sendable, Codable, Equatable {
    public let reflection: String
    public let evidence: [[String: JSONValue]]?
    public let persistedAttributes: [AttributeUpdate]?
}

public struct ForgetResult: Sendable, Codable, Equatable {
    public let deleted: Int
}

public struct TraceRecord: Sendable, Codable, Equatable {
    public let id: String
    public let resolutionTier: String?
    public let latencyMs: Int?
    public let cached: Bool?
    public let retrievedCount: Int?
    public let topScores: [Double]?
    public let payload: [String: JSONValue]?
}

public struct TraceListResponse: Sendable, Codable, Equatable {
    public let traces: [TraceRecord]
}

public struct TraceStats: Sendable, Codable, Equatable {
    public let totalQueries: Int?
    public let cacheHits: Int?
    public let avgLatencyMs: Double?
    public let tierCounts: [String: Int]?
}
