import Foundation

/// Header names used by the Agent Memory API beyond the standard set.
enum AgentMemoryHeader {
    /// Delegation header: perform the request on behalf of another principal.
    static let onBehalfOf = "X-Spectron-On-Behalf-Of"
    /// Idempotency token for safely retrying write requests.
    static let idempotencyKey = "Idempotency-Key"
}

/// Builds the delegation header dictionary for an optional principal, or `nil`
/// when no delegation was requested.
func delegationHeaders(_ onBehalfOf: String?) -> [String: String]? {
    guard let onBehalfOf, !onBehalfOf.isEmpty else { return nil }
    return [AgentMemoryHeader.onBehalfOf: onBehalfOf]
}
