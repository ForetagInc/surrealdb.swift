import Foundation

// MARK: - Identity

/// The effective identity for the current request, as resolved by the server
/// from the API key and any delegation header.
public struct WhoamiResponse: Sendable, Codable, Equatable {
    public let principalId: String
    public let displayName: String
    public let kind: String
    public let enforce: Bool
    public let grants: [String: JSONValue]
    public let effectiveGrants: [String: JSONValue]
    public let delegatedPrincipalId: String?
    public let tokenGrants: [String: JSONValue]?

    public init(
        principalId: String = "",
        displayName: String = "",
        kind: String = "",
        enforce: Bool = false,
        grants: [String: JSONValue] = [:],
        effectiveGrants: [String: JSONValue] = [:],
        delegatedPrincipalId: String? = nil,
        tokenGrants: [String: JSONValue]? = nil
    ) {
        self.principalId = principalId
        self.displayName = displayName
        self.kind = kind
        self.enforce = enforce
        self.grants = grants
        self.effectiveGrants = effectiveGrants
        self.delegatedPrincipalId = delegatedPrincipalId
        self.tokenGrants = tokenGrants
    }

    private enum CodingKeys: String, CodingKey {
        case principalId, displayName, kind, enforce, grants, effectiveGrants, delegatedPrincipalId, tokenGrants
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        self.principalId = try c.decodeIfPresent(String.self, forKey: .principalId) ?? ""
        self.displayName = try c.decodeIfPresent(String.self, forKey: .displayName) ?? ""
        self.kind = try c.decodeIfPresent(String.self, forKey: .kind) ?? ""
        self.enforce = try c.decodeIfPresent(Bool.self, forKey: .enforce) ?? false
        self.grants = try c.decodeIfPresent([String: JSONValue].self, forKey: .grants) ?? [:]
        self.effectiveGrants = try c.decodeIfPresent([String: JSONValue].self, forKey: .effectiveGrants) ?? [:]
        self.delegatedPrincipalId = try c.decodeIfPresent(String.self, forKey: .delegatedPrincipalId)
        self.tokenGrants = try c.decodeIfPresent([String: JSONValue].self, forKey: .tokenGrants)
    }
}

// MARK: - Self-service API keys

/// A freshly minted or rotated key. `key` is the full bearer secret
/// (`sp-{id}-{secret}`) and is only ever returned once.
public struct MintedKey: Sendable, Codable, Equatable {
    public let id: String
    public let key: String
    public let validUntil: String?
}

public struct KeyDetail: Sendable, Codable, Equatable {
    public let id: String
    public let name: String
    public let createdAt: String
    public let grants: [String: JSONValue]?
    public let lastUsedAt: String?
    public let validUntil: String?

    private enum CodingKeys: String, CodingKey {
        case id, name, createdAt, grants, lastUsedAt, validUntil
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        self.id = try c.decode(String.self, forKey: .id)
        self.name = try c.decodeIfPresent(String.self, forKey: .name) ?? ""
        self.createdAt = try c.decodeIfPresent(String.self, forKey: .createdAt) ?? ""
        self.grants = try c.decodeIfPresent([String: JSONValue].self, forKey: .grants)
        self.lastUsedAt = try c.decodeIfPresent(String.self, forKey: .lastUsedAt)
        self.validUntil = try c.decodeIfPresent(String.self, forKey: .validUntil)
    }
}
