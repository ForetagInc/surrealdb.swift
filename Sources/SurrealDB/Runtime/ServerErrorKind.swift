import Foundation

/// A typed view of the error taxonomy the SurrealDB server sends over the wire.
///
/// Every server error carries a `kind` string (e.g. `"NotAllowed"`, `"NotFound"`) and,
/// depending on the kind, a nested `{ kind, details? }` payload describing the specific
/// failure (e.g. which auth check failed, which record was missing). `RPCErrorObject`
/// and `RPCErrorCause` only exposed those as a raw `kind: String?` / `details: SurrealValue?`
/// pair, which forced callers into undocumented string comparisons.
///
/// `ServerErrorKind` parses that raw pair into a typed tree that mirrors the shape the
/// server actually produces (see `surrealdb_types::ErrorDetails` and its detail enums).
/// Unknown kinds — from a newer server this SDK doesn't yet know about — are preserved
/// via `.unknown(_:)` instead of being silently coerced, so callers can still inspect the
/// raw string.
///
/// Access it via `RPCErrorObject.typedKind`, `RPCErrorCause.typedKind`, or
/// `SurrealError.serverErrorKind`.
public enum ServerErrorKind: Sendable, Hashable {
    /// Parse error, invalid request/params, or bad input.
    case validation(Validation?)
    /// Feature or configuration not supported (live queries, GraphQL).
    case configuration(Configuration?)
    /// User-thrown error via `THROW` in SurrealQL.
    case thrown
    /// Query execution failure (timeout, cancelled, not executed, transaction conflict).
    case query(Query?)
    /// Serialization or deserialization failure.
    case serialization(Serialization?)
    /// Permission denied, method not allowed, or authentication/authorization failure.
    case notAllowed(NotAllowed?)
    /// Resource not found (table, record, namespace, RPC method, etc.).
    case notFound(NotFound?)
    /// Duplicate resource (record, table, namespace, etc.).
    case alreadyExists(AlreadyExists?)
    /// Client-side connection state error.
    case connection(Connection?)
    /// Unexpected or unknown internal error.
    case internalError
    /// Context wrapper used for error chaining. Rarely seen as the outermost kind.
    case context
    /// A kind string not recognized by this version of the SDK. Preserves the raw
    /// value so callers can still branch on it or report it upstream.
    case unknown(String)
}

// MARK: - Nested detail types

extension ServerErrorKind {
    /// Validation failure details.
    public enum Validation: Sendable, Hashable {
        case parse
        case invalidRequest
        case invalidParams
        case namespaceEmpty
        case databaseEmpty
        case invalidParameter(name: String)
        case invalidContent(value: String)
        case invalidMerge(value: String)
    }

    /// Configuration failure details.
    public enum Configuration: Sendable, Hashable {
        case liveQueryNotSupported
        case badLiveQueryConfig
        case badGraphqlConfig
    }

    /// Query execution failure details.
    public enum Query: Sendable, Hashable {
        case notExecuted
        case timedOut(duration: Duration)
        case cancelled
        /// A concurrent transaction wrote to the same data. Safe to retry.
        case transactionConflict

        /// Wire representation of a Rust `std::time::Duration` (`{ secs, nanos }`).
        public struct Duration: Sendable, Hashable {
            public let seconds: Int64
            public let nanoseconds: Int64

            public init(seconds: Int64, nanoseconds: Int64) {
                self.seconds = seconds
                self.nanoseconds = nanoseconds
            }

            public var timeInterval: TimeInterval {
                Double(seconds) + Double(nanoseconds) / 1_000_000_000
            }
        }
    }

    /// Serialization/deserialization failure details.
    public enum Serialization: Sendable, Hashable {
        case serialization
        case deserialization
    }

    /// Not-allowed failure details (permissions, blocked methods/functions/scripting).
    public enum NotAllowed: Sendable, Hashable {
        case scripting
        case auth(Auth?)
        case method(name: String)
        case function(name: String)
        case target(name: String)

        /// Authentication/authorization failure nested inside a `NotAllowed` error.
        public enum Auth: Sendable, Hashable {
            case tokenExpired
            case sessionExpired
            case invalidAuth
            case unexpectedAuth
            case missingUserOrPass
            case noSigninTarget
            case invalidPass
            case tokenMakingFailed
            case invalidSignup
            case invalidRole(name: String)
            case notAllowed(actor: String, action: String, resource: String)
        }
    }

    /// Not-found failure details.
    public enum NotFound: Sendable, Hashable {
        case method(name: String)
        case session(id: String?)
        case table(name: String)
        case record(id: String)
        case namespace(name: String)
        case database(name: String)
        case transaction
    }

    /// Already-exists failure details.
    public enum AlreadyExists: Sendable, Hashable {
        case session(id: String)
        case table(name: String)
        case record(id: String)
        case namespace(name: String)
        case database(name: String)
    }

    /// Client-side connection state failure details.
    public enum Connection: Sendable, Hashable {
        case uninitialised
        case alreadyConnected
        case connectionFailed
    }
}

// MARK: - Convenience discriminators

extension ServerErrorKind {
    /// True if the auth token used for the request has expired.
    public var isTokenExpired: Bool {
        if case .notAllowed(.some(.auth(.some(.tokenExpired)))) = self { return true }
        return false
    }

    /// True if the session itself has expired (distinct from a plain token expiry).
    public var isSessionExpired: Bool {
        if case .notAllowed(.some(.auth(.some(.sessionExpired)))) = self { return true }
        return false
    }

    /// True if authentication failed for a reason other than an expired token/session
    /// (bad credentials, missing signin target, invalid role, etc.).
    public var isInvalidAuth: Bool {
        if case .notAllowed(.some(.auth(.some(let auth)))) = self {
            switch auth {
            case .tokenExpired, .sessionExpired:
                return false
            default:
                return true
            }
        }
        return false
    }

    /// True if scripting was blocked by server configuration.
    public var isScriptingBlocked: Bool {
        if case .notAllowed(.some(.scripting)) = self { return true }
        return false
    }

    /// True if a query failed due to a transaction conflict (safe to retry).
    public var isTransactionConflict: Bool {
        if case .query(.some(.transactionConflict)) = self { return true }
        return false
    }

    /// True if a query failed because it timed out.
    public var isQueryTimedOut: Bool {
        if case .query(.some(.timedOut)) = self { return true }
        return false
    }

    /// True if a query was cancelled before completing.
    public var isQueryCancelled: Bool {
        if case .query(.some(.cancelled)) = self { return true }
        return false
    }

    /// True if this is a deserialization failure (as opposed to serialization).
    public var isDeserializationFailure: Bool {
        if case .serialization(.some(.deserialization)) = self { return true }
        return false
    }

    /// True if this is a not-found error, regardless of the specific resource.
    public var isNotFound: Bool {
        if case .notFound = self { return true }
        return false
    }

    /// True if this is an already-exists error, regardless of the specific resource.
    public var isAlreadyExists: Bool {
        if case .alreadyExists = self { return true }
        return false
    }
}

// MARK: - Human-readable description

extension ServerErrorKind: CustomStringConvertible {
    public var description: String {
        switch self {
        case .validation(let detail): return "Validation" + describing(detail)
        case .configuration(let detail): return "Configuration" + describing(detail)
        case .thrown: return "Thrown"
        case .query(let detail): return "Query" + describing(detail)
        case .serialization(let detail): return "Serialization" + describing(detail)
        case .notAllowed(let detail): return "NotAllowed" + describing(detail)
        case .notFound(let detail): return "NotFound" + describing(detail)
        case .alreadyExists(let detail): return "AlreadyExists" + describing(detail)
        case .connection(let detail): return "Connection" + describing(detail)
        case .internalError: return "Internal"
        case .context: return "Context"
        case .unknown(let kind): return "Unknown(\(kind))"
        }
    }

    private func describing(_ detail: (any CustomStringConvertible)?) -> String {
        guard let detail else { return "" }
        return "(\(detail))"
    }
}

extension ServerErrorKind.Validation: CustomStringConvertible {
    public var description: String {
        switch self {
        case .parse: return "Parse"
        case .invalidRequest: return "InvalidRequest"
        case .invalidParams: return "InvalidParams"
        case .namespaceEmpty: return "NamespaceEmpty"
        case .databaseEmpty: return "DatabaseEmpty"
        case .invalidParameter(let name): return "InvalidParameter(name: \(name))"
        case .invalidContent(let value): return "InvalidContent(value: \(value))"
        case .invalidMerge(let value): return "InvalidMerge(value: \(value))"
        }
    }
}

extension ServerErrorKind.Configuration: CustomStringConvertible {
    public var description: String {
        switch self {
        case .liveQueryNotSupported: return "LiveQueryNotSupported"
        case .badLiveQueryConfig: return "BadLiveQueryConfig"
        case .badGraphqlConfig: return "BadGraphqlConfig"
        }
    }
}

extension ServerErrorKind.Query: CustomStringConvertible {
    public var description: String {
        switch self {
        case .notExecuted: return "NotExecuted"
        case .timedOut(let duration): return "TimedOut(\(duration.seconds)s)"
        case .cancelled: return "Cancelled"
        case .transactionConflict: return "TransactionConflict"
        }
    }
}

extension ServerErrorKind.Serialization: CustomStringConvertible {
    public var description: String {
        switch self {
        case .serialization: return "Serialization"
        case .deserialization: return "Deserialization"
        }
    }
}

extension ServerErrorKind.NotAllowed: CustomStringConvertible {
    public var description: String {
        switch self {
        case .scripting: return "Scripting"
        case .auth(let auth): return "Auth" + (auth.map { "(\($0))" } ?? "")
        case .method(let name): return "Method(name: \(name))"
        case .function(let name): return "Function(name: \(name))"
        case .target(let name): return "Target(name: \(name))"
        }
    }
}

extension ServerErrorKind.NotAllowed.Auth: CustomStringConvertible {
    public var description: String {
        switch self {
        case .tokenExpired: return "TokenExpired"
        case .sessionExpired: return "SessionExpired"
        case .invalidAuth: return "InvalidAuth"
        case .unexpectedAuth: return "UnexpectedAuth"
        case .missingUserOrPass: return "MissingUserOrPass"
        case .noSigninTarget: return "NoSigninTarget"
        case .invalidPass: return "InvalidPass"
        case .tokenMakingFailed: return "TokenMakingFailed"
        case .invalidSignup: return "InvalidSignup"
        case .invalidRole(let name): return "InvalidRole(name: \(name))"
        case .notAllowed(let actor, let action, let resource):
            return "NotAllowed(actor: \(actor), action: \(action), resource: \(resource))"
        }
    }
}

extension ServerErrorKind.NotFound: CustomStringConvertible {
    public var description: String {
        switch self {
        case .method(let name): return "Method(name: \(name))"
        case .session(let id): return "Session(id: \(id ?? "nil"))"
        case .table(let name): return "Table(name: \(name))"
        case .record(let id): return "Record(id: \(id))"
        case .namespace(let name): return "Namespace(name: \(name))"
        case .database(let name): return "Database(name: \(name))"
        case .transaction: return "Transaction"
        }
    }
}

extension ServerErrorKind.AlreadyExists: CustomStringConvertible {
    public var description: String {
        switch self {
        case .session(let id): return "Session(id: \(id))"
        case .table(let name): return "Table(name: \(name))"
        case .record(let id): return "Record(id: \(id))"
        case .namespace(let name): return "Namespace(name: \(name))"
        case .database(let name): return "Database(name: \(name))"
        }
    }
}

extension ServerErrorKind.Connection: CustomStringConvertible {
    public var description: String {
        switch self {
        case .uninitialised: return "Uninitialised"
        case .alreadyConnected: return "AlreadyConnected"
        case .connectionFailed: return "ConnectionFailed"
        }
    }
}

// MARK: - Parsing from the wire

extension ServerErrorKind {
    /// Parses the top-level `kind` / `details` pair from an RPC error object into a typed
    /// taxonomy. `code` is used as a fallback to derive the kind for older servers that
    /// predate the structured `kind` field (mirrors the legacy JSON-RPC error codes).
    static func parse(kind: String?, details: SurrealValue?, code: Int? = nil) -> ServerErrorKind {
        let resolvedKind = kind ?? legacyKind(forCode: code) ?? "Internal"
        let details = unwrapDoubleWrappedDetails(details, outerKind: resolvedKind)
        switch resolvedKind {
        case "Validation":
            return .validation(details.flatMap(Validation.init(wireValue:)))
        case "Configuration":
            return .configuration(details.flatMap(Configuration.init(wireValue:)))
        case "Thrown":
            return .thrown
        case "Query":
            return .query(details.flatMap(Query.init(wireValue:)))
        case "Serialization":
            return .serialization(details.flatMap(Serialization.init(wireValue:)))
        case "NotAllowed":
            return .notAllowed(details.flatMap(NotAllowed.init(wireValue:)))
        case "NotFound":
            return .notFound(details.flatMap(NotFound.init(wireValue:)))
        case "AlreadyExists":
            return .alreadyExists(details.flatMap(AlreadyExists.init(wireValue:)))
        case "Connection":
            return .connection(details.flatMap(Connection.init(wireValue:)))
        case "Internal":
            return .internalError
        case "Context":
            return .context
        default:
            return .unknown(resolvedKind)
        }
    }

    /// Maps legacy JSON-RPC error codes to their kind, for servers that don't send `kind`.
    private static func legacyKind(forCode code: Int?) -> String? {
        guard let code else { return nil }
        switch code {
        case -32700, -32600, -32603: return "Validation"
        case -32601: return "NotFound"
        case -32602, -32002: return "NotAllowed"
        case -32604, -32605, -32606: return "Configuration"
        case -32000: return "Internal"
        case -32001: return "Connection"
        case -32003, -32004, -32005, -32009: return "Query"
        case -32006: return "Thrown"
        case -32007, -32008: return "Serialization"
        default: return nil
        }
    }

    /// Some server code paths (notably per-statement query result errors) serialize the
    /// full inner detail object — including its own `kind` — into the outer `details`
    /// field, duplicating the outer kind at both levels
    /// (`{ kind: "Query", details: { kind: "Query", details: { kind: "TransactionConflict" } } }`).
    /// When that happens, unwrap one level so parsing sees the actual inner detail.
    ///
    /// The extra check that the (would-be) inner `details` is itself an object guards
    /// against false positives where a leaf variant's name legitimately matches its
    /// parent kind by coincidence (e.g. `Serialization`'s own `"Serialization"` case,
    /// which carries no further nested details).
    private static func unwrapDoubleWrappedDetails(_ details: SurrealValue?, outerKind: String) -> SurrealValue? {
        guard let details,
              case .object(let object) = details,
              case .string(let innerKind)? = object["kind"],
              innerKind == outerKind,
              case .object? = object["details"]
        else {
            return details
        }
        return object["details"]
    }
}

extension ServerErrorKind.Validation {
    fileprivate init?(wireValue value: SurrealValue) {
        guard let (kind, details) = value.wireKindDetails else { return nil }
        switch kind {
        case "Parse": self = .parse
        case "InvalidRequest": self = .invalidRequest
        case "InvalidParams": self = .invalidParams
        case "NamespaceEmpty": self = .namespaceEmpty
        case "DatabaseEmpty": self = .databaseEmpty
        case "InvalidParameter": self = .invalidParameter(name: details?.wireStringField("name") ?? "")
        case "InvalidContent": self = .invalidContent(value: details?.wireStringField("value") ?? "")
        case "InvalidMerge": self = .invalidMerge(value: details?.wireStringField("value") ?? "")
        default: return nil
        }
    }
}

extension ServerErrorKind.Configuration {
    fileprivate init?(wireValue value: SurrealValue) {
        guard let (kind, _) = value.wireKindDetails else { return nil }
        switch kind {
        case "LiveQueryNotSupported": self = .liveQueryNotSupported
        case "BadLiveQueryConfig": self = .badLiveQueryConfig
        case "BadGraphqlConfig": self = .badGraphqlConfig
        default: return nil
        }
    }
}

extension ServerErrorKind.Query {
    fileprivate init?(wireValue value: SurrealValue) {
        guard let (kind, details) = value.wireKindDetails else { return nil }
        switch kind {
        case "NotExecuted": self = .notExecuted
        case "Cancelled": self = .cancelled
        case "TransactionConflict": self = .transactionConflict
        case "TimedOut":
            let durationValue = details?.wireObjectField("duration")
            let seconds = durationValue?.wireIntField("secs") ?? 0
            let nanoseconds = durationValue?.wireIntField("nanos") ?? 0
            self = .timedOut(duration: Duration(seconds: seconds, nanoseconds: nanoseconds))
        default: return nil
        }
    }
}

extension ServerErrorKind.Serialization {
    fileprivate init?(wireValue value: SurrealValue) {
        guard let (kind, _) = value.wireKindDetails else { return nil }
        switch kind {
        case "Serialization": self = .serialization
        case "Deserialization": self = .deserialization
        default: return nil
        }
    }
}

extension ServerErrorKind.NotAllowed {
    fileprivate init?(wireValue value: SurrealValue) {
        guard let (kind, details) = value.wireKindDetails else { return nil }
        switch kind {
        case "Scripting": self = .scripting
        case "Auth": self = .auth(details.flatMap(Auth.init(wireValue:)))
        case "Method": self = .method(name: details?.wireStringField("name") ?? "")
        case "Function": self = .function(name: details?.wireStringField("name") ?? "")
        case "Target": self = .target(name: details?.wireStringField("name") ?? "")
        default: return nil
        }
    }
}

extension ServerErrorKind.NotAllowed.Auth {
    fileprivate init?(wireValue value: SurrealValue) {
        guard let (kind, details) = value.wireKindDetails else { return nil }
        switch kind {
        case "TokenExpired": self = .tokenExpired
        case "SessionExpired": self = .sessionExpired
        case "InvalidAuth": self = .invalidAuth
        case "UnexpectedAuth": self = .unexpectedAuth
        case "MissingUserOrPass": self = .missingUserOrPass
        case "NoSigninTarget": self = .noSigninTarget
        case "InvalidPass": self = .invalidPass
        case "TokenMakingFailed": self = .tokenMakingFailed
        case "InvalidSignup": self = .invalidSignup
        case "InvalidRole": self = .invalidRole(name: details?.wireStringField("name") ?? "")
        case "NotAllowed":
            self = .notAllowed(
                actor: details?.wireStringField("actor") ?? "",
                action: details?.wireStringField("action") ?? "",
                resource: details?.wireStringField("resource") ?? ""
            )
        default: return nil
        }
    }
}

extension ServerErrorKind.NotFound {
    fileprivate init?(wireValue value: SurrealValue) {
        guard let (kind, details) = value.wireKindDetails else { return nil }
        switch kind {
        case "Method": self = .method(name: details?.wireStringField("name") ?? "")
        case "Session": self = .session(id: details?.wireStringField("id"))
        case "Table": self = .table(name: details?.wireStringField("name") ?? "")
        case "Record": self = .record(id: details?.wireStringField("id") ?? "")
        case "Namespace": self = .namespace(name: details?.wireStringField("name") ?? "")
        case "Database": self = .database(name: details?.wireStringField("name") ?? "")
        case "Transaction": self = .transaction
        default: return nil
        }
    }
}

extension ServerErrorKind.AlreadyExists {
    fileprivate init?(wireValue value: SurrealValue) {
        guard let (kind, details) = value.wireKindDetails else { return nil }
        switch kind {
        case "Session": self = .session(id: details?.wireStringField("id") ?? "")
        case "Table": self = .table(name: details?.wireStringField("name") ?? "")
        case "Record": self = .record(id: details?.wireStringField("id") ?? "")
        case "Namespace": self = .namespace(name: details?.wireStringField("name") ?? "")
        case "Database": self = .database(name: details?.wireStringField("name") ?? "")
        default: return nil
        }
    }
}

extension ServerErrorKind.Connection {
    fileprivate init?(wireValue value: SurrealValue) {
        guard let (kind, _) = value.wireKindDetails else { return nil }
        switch kind {
        case "Uninitialised": self = .uninitialised
        case "AlreadyConnected": self = .alreadyConnected
        case "ConnectionFailed": self = .connectionFailed
        default: return nil
        }
    }
}

// MARK: - Wire value helpers

extension SurrealValue {
    /// Splits a `{ kind: String, details?: SurrealValue }` wire object into its parts.
    fileprivate var wireKindDetails: (kind: String, details: SurrealValue?)? {
        guard case .object(let object) = self,
              case .string(let kind)? = object["kind"] else {
            return nil
        }
        return (kind, object["details"])
    }

    /// Extracts a string field from an object-shaped detail payload.
    fileprivate func wireStringField(_ key: String) -> String? {
        guard case .object(let object) = self, case .string(let value)? = object[key] else {
            return nil
        }
        return value
    }

    /// Extracts an integer field from an object-shaped detail payload.
    fileprivate func wireIntField(_ key: String) -> Int64? {
        guard case .object(let object) = self, case .int(let value)? = object[key] else {
            return nil
        }
        return value
    }

    /// Extracts a nested object field from an object-shaped detail payload.
    fileprivate func wireObjectField(_ key: String) -> SurrealValue? {
        guard case .object(let object) = self else { return nil }
        return object[key]
    }
}

// MARK: - Attach typed accessors to the wire error types

extension RPCErrorObject {
    /// The typed error taxonomy parsed from `kind` and `details`. Prefer this over
    /// string-comparing `kind` directly. See ``ServerErrorKind``.
    public var typedKind: ServerErrorKind {
        ServerErrorKind.parse(kind: kind, details: details, code: code)
    }
}

extension RPCErrorCause {
    /// The typed error taxonomy parsed from `kind` and `details`. See ``ServerErrorKind``.
    public var typedKind: ServerErrorKind {
        ServerErrorKind.parse(kind: kind, details: details)
    }
}
