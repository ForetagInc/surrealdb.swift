import Foundation

enum Endpoint {
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
