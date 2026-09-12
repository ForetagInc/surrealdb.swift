import Foundation

/// Where a client endpoint points: out over the network, or at an in-process
/// store.
enum ResolvedEndpoint: Sendable {
    case remote(URL)
    case embedded(EmbeddedTarget)
}

enum Endpoint {
    /// Schemes served in-process rather than over the network.
    static let embeddedSchemes: Set<String> = ["mem"]

    /// Classifies an endpoint before any URL normalisation.
    ///
    /// The embedded branch has to run first: `normalizedRPCURL` rejects every
    /// scheme outside the remote allowlist and unconditionally appends `/rpc`,
    /// neither of which makes sense for a storage locator.
    static func resolve(_ value: String) throws -> ResolvedEndpoint {
        let scheme = String(value.prefix(while: { $0 != ":" })).lowercased()
        if embeddedSchemes.contains(scheme) {
            return .embedded(try EmbeddedTarget(endpoint: value))
        }
        return .remote(try normalizedRPCURL(from: value))
    }

    static func normalizedRPCURL(from value: String) throws -> URL {
        guard let original = URL(string: value), let scheme = original.scheme?.lowercased() else {
            throw SurrealError.invalidEndpoint(value)
        }

        guard ["ws", "wss", "http", "https"].contains(scheme) else {
            throw SurrealError.invalidEndpoint(value)
        }

        guard var components = URLComponents(url: original, resolvingAgainstBaseURL: false) else {
            throw SurrealError.invalidEndpoint(value)
        }

        var path = components.path
        if !path.hasSuffix("/rpc") {
            if path.isEmpty {
                path = "/rpc"
            } else if path.hasSuffix("/") {
                path += "rpc"
            } else {
                path += "/rpc"
            }
        }

        components.path = path
        guard let normalized = components.url else {
            throw SurrealError.invalidEndpoint(value)
        }

        return normalized
    }

    static func asHTTP(_ url: URL) -> URL {
        guard var components = URLComponents(url: url, resolvingAgainstBaseURL: false) else {
            return url
        }
        if components.scheme == "ws" {
            components.scheme = "http"
        } else if components.scheme == "wss" {
            components.scheme = "https"
        }
        return components.url ?? url
    }

    static func asWebSocket(_ url: URL) -> URL {
        guard var components = URLComponents(url: url, resolvingAgainstBaseURL: false) else {
            return url
        }
        if components.scheme == "http" {
            components.scheme = "ws"
        } else if components.scheme == "https" {
            components.scheme = "wss"
        }
        return components.url ?? url
    }
}
