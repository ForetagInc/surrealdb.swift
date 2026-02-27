import Foundation

public enum SurrealError: Error, Sendable {
    case invalidEndpoint(String)
    case notConnected
    case unsupportedFeature(String)
    case invalidCredentials(String)
    case invalidResponse(String)
    case serverError(RPCErrorObject)
    case queryError(index: Int, message: String, details: SurrealValue?)
    case timeout

    public var message: String {
        switch self {
        case .invalidEndpoint(let value):
            return "Invalid endpoint: \(value)"
        case .notConnected:
            return "The client is not connected."
        case .unsupportedFeature(let feature):
            return "Unsupported feature: \(feature)"
        case .invalidCredentials(let message):
            return "Invalid credentials: \(message)"
        case .invalidResponse(let message):
            return "Invalid response: \(message)"
        case .serverError(let payload):
            return payload.message
        case .queryError(let index, let message, _):
            return "Query statement #\(index) failed: \(message)"
        case .timeout:
            return "The request timed out."
        }
    }
}
