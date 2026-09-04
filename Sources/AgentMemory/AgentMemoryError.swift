import Foundation

public struct AgentMemoryError: Error, Sendable, Equatable {
    public enum Kind: Sendable, Equatable {
        case base
        case auth
        case scope
        case notFound
        case validation
        case rateLimit
        case server
    }

    public let kind: Kind
    public let status: Int
    public let title: String
    public let detail: String?
    public let typeURI: String?
    public let instance: String?
    public let extensions: [String: JSONValue]
    public let retryAfter: TimeInterval?

    public init(
        kind: Kind,
        status: Int,
        title: String,
        detail: String? = nil,
        typeURI: String? = nil,
        instance: String? = nil,
        extensions: [String: JSONValue] = [:],
        retryAfter: TimeInterval? = nil
    ) {
        self.kind = kind
        self.status = status
        self.title = title
        self.detail = detail
        self.typeURI = typeURI
        self.instance = instance
        self.extensions = extensions
        self.retryAfter = retryAfter
    }

    public var isAuth: Bool { kind == .auth }
    public var isScope: Bool { kind == .scope }
    public var isNotFound: Bool { kind == .notFound }
    public var isValidation: Bool { kind == .validation }
    public var isRateLimit: Bool { kind == .rateLimit }
    public var isServer: Bool { kind == .server }
}

extension AgentMemoryError: LocalizedError {
    public var errorDescription: String? {
        if let detail = detail, !detail.isEmpty {
            return "[\(status)] \(title): \(detail)"
        }
        return "[\(status)] \(title)"
    }
}

enum AgentMemoryErrorFactory {
    static func fromResponse(status: Int, body: JSONValue?, headers: [String: String]) -> AgentMemoryError {
        var title = "Agent Memory request failed"
        var detail: String? = nil
        var typeURI: String? = nil
        var instance: String? = nil
        var extensions: [String: JSONValue] = [:]

        if case .object(let dict)? = body {
            if let t = dict["title"]?.asString { title = t }
            else if let t = dict["message"]?.asString { title = t }
            if let d = dict["detail"]?.asString { detail = d }
            if let t = dict["type"]?.asString { typeURI = t }
            if let i = dict["instance"]?.asString { instance = i }
            for (k, v) in dict {
                if !["status", "title", "detail", "type", "instance", "message"].contains(k) {
                    extensions[k] = v
                }
            }
        } else if case .string(let s)? = body, !s.isEmpty {
            detail = s
        }

        let kind: AgentMemoryError.Kind = {
            if status >= 500 { return .server }
            switch status {
            case 400, 422: return .validation
            case 401: return .auth
            case 403: return .scope
            case 404: return .notFound
            case 429: return .rateLimit
            default: return .base
            }
        }()

        var retryAfter: TimeInterval? = nil
        if kind == .rateLimit {
            let raw = headers["Retry-After"] ?? headers["retry-after"]
            if let raw, let d = Double(raw) {
                retryAfter = d
            }
        }

        return AgentMemoryError(
            kind: kind,
            status: status,
            title: title,
            detail: detail,
            typeURI: typeURI,
            instance: instance,
            extensions: extensions,
            retryAfter: retryAfter
        )
    }

    static func connectionFailed(_ underlying: any Error) -> AgentMemoryError {
        AgentMemoryError(
            kind: .base,
            status: 0,
            title: "Connection failed",
            detail: String(describing: underlying)
        )
    }
}
