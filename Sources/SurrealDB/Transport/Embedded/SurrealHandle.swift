#if SURREALDB_EMBEDDED
import CSurrealDB
import Foundation

/// A call into the native library that failed.
struct EmbeddedCallError: Error, Sendable {
    let code: Int32
    let message: String
}

/// Thin, blocking wrapper around an `sr_surreal_t` connection.
///
/// Every method here blocks its thread, so all of them must be invoked from
/// `BlockingFFIExecutor`'s queue, never from the cooperative pool. The type is
/// `@unchecked Sendable` on exactly that invariant: `EmbeddedRPCEngine` holds the
/// only reference and never touches it outside an `executor.run { }` body.
final class SurrealHandle: @unchecked Sendable {
    private let database: OpaquePointer
    private let maximumArrayCount: Int
    private var isPoisoned = false

    private init(database: OpaquePointer, maximumArrayCount: Int) {
        self.database = database
        self.maximumArrayCount = maximumArrayCount
    }

    static func connect(endpoint: String, maximumArrayCount: Int) throws -> SurrealHandle {
        var error: sr_string_t?
        var database: OpaquePointer?

        let code = endpoint.withCString { sr_connect(&error, &database, $0) }
        guard code >= 0, let database else {
            throw failure(code: code, error: error)
        }
        return SurrealHandle(database: database, maximumArrayCount: maximumArrayCount)
    }

    func disconnect() {
        guard !isPoisoned else { return }
        sr_surreal_disconnect(database)
    }

    func use(namespace: String?, database databaseName: String?) throws {
        if let namespace {
            try call { error in namespace.withCString { sr_use_ns(self.database, error, $0) } }
        }
        if let databaseName {
            try call { error in databaseName.withCString { sr_use_db(self.database, error, $0) } }
        }
    }

    func authenticate(token: String) throws {
        try call { error in token.withCString { sr_authenticate(database, error, $0) } }
    }

    func invalidate() throws {
        try call { error in sr_invalidate(database, error) }
    }

    func kill(liveQueryID: UUID) throws {
        let id = liveQueryID.uuidString.lowercased()
        try call { error in id.withCString { sr_kill(database, error, $0) } }
    }

    func signIn(_ request: EmbeddedAuthRequest) throws -> String {
        try authenticateWith(request) { database, error, token, scope, credentials, details, params in
            sr_signin(database, error, token, scope, credentials, details, params)
        }
    }

    func signUp(_ request: EmbeddedAuthRequest) throws -> String {
        try authenticateWith(request) { database, error, token, scope, credentials, details, params in
            sr_signup(database, error, token, scope, credentials, details, params)
        }
    }

    func query(_ sql: String, bindings: [String: SurrealValue]) throws -> [EmbeddedStatementResult] {
        try guardPoison()

        let variables = try CValueBridge.makeObject(bindings, maximumArrayCount: maximumArrayCount)

        var error: sr_string_t?
        var results: UnsafeMutablePointer<sr_arr_res_t>?

        let count = sql.withCString { statement in
            sr_query(database, &error, &results, statement, &variables.object)
        }

        guard count >= 0, let results else {
            poisonIfFatal(count)
            throw Self.failure(code: count, error: error)
        }
        // One call frees the whole result set: each `sr_arr_res_t`'s Drop is
        // transitive over its array and its error string.
        defer { sr_free_arr_res_arr(results, count) }

        return (0..<Int(count)).map { index in
            let statement = results[index]
            if statement.err.code != 0 {
                let message = statement.err.msg.map { String(cString: $0) } ?? "Unknown embedded engine error"
                return EmbeddedStatementResult(values: [], errorMessage: message)
            }
            var ok = statement.ok
            return EmbeddedStatementResult(values: CValueBridge.readArray(&ok))
        }
    }

    // MARK: - Call plumbing

    private func authenticateWith(
        _ request: EmbeddedAuthRequest,
        _ perform: (
            OpaquePointer,
            UnsafeMutablePointer<sr_string_t?>,
            UnsafeMutablePointer<sr_string_t?>,
            UnsafePointer<sr_credentials_scope>,
            UnsafePointer<sr_credentials>?,
            UnsafePointer<sr_credentials_access>?,
            UnsafePointer<sr_object_t>?
        ) -> Int32
    ) throws -> String {
        try guardPoison()

        var scope = request.scope.native
        var error: sr_string_t?
        var token: sr_string_t?

        let variables = request.variables.isEmpty
            ? nil
            : try CValueBridge.makeObject(request.variables, maximumArrayCount: maximumArrayCount)

        let code = withOptionalCString(request.username) { username in
            withOptionalCString(request.password) { password in
                withOptionalCString(request.namespace) { namespace in
                    withOptionalCString(request.database) { databaseName in
                        withOptionalCString(request.access) { access in
                            var credentials = sr_credentials(
                                username: UnsafeMutablePointer(mutating: username),
                                password: UnsafeMutablePointer(mutating: password)
                            )
                            var details = sr_credentials_access(
                                namespace_: UnsafeMutablePointer(mutating: namespace),
                                database: UnsafeMutablePointer(mutating: databaseName),
                                access: UnsafeMutablePointer(mutating: access)
                            )
                            let hasCredentials = username != nil && password != nil
                            let hasDetails = namespace != nil || databaseName != nil || access != nil

                            return withUnsafePointer(to: &scope) { scopePointer in
                                withUnsafePointer(to: &credentials) { credentialsPointer in
                                    withUnsafePointer(to: &details) { detailsPointer in
                                        let credentialsArgument = hasCredentials ? credentialsPointer : nil
                                        let detailsArgument = hasDetails ? detailsPointer : nil

                                        guard let variables else {
                                            return perform(
                                                self.database, &error, &token, scopePointer,
                                                credentialsArgument, detailsArgument, nil
                                            )
                                        }
                                        return withUnsafePointer(to: &variables.object) { params in
                                            perform(
                                                self.database, &error, &token, scopePointer,
                                                credentialsArgument, detailsArgument, params
                                            )
                                        }
                                    }
                                }
                            }
                        }
                    }
                }
            }
        }

        guard code >= 0 else {
            poisonIfFatal(code)
            throw Self.failure(code: code, error: error)
        }

        defer { if let token { sr_free_string(token) } }
        return token.map { String(cString: $0) } ?? ""
    }

    private func call(_ body: (UnsafeMutablePointer<sr_string_t?>) -> Int32) throws {
        try guardPoison()

        var error: sr_string_t?
        let code = body(&error)
        guard code >= 0 else {
            poisonIfFatal(code)
            throw Self.failure(code: code, error: error)
        }
    }

    /// `SR_FATAL` means the Rust side panicked. The documented contract is that
    /// any further call aborts the host process, so latch it and never touch the
    /// handle again.
    private func poisonIfFatal(_ code: Int32) {
        if code == sr_SR_FATAL {
            isPoisoned = true
        }
    }

    private func guardPoison() throws {
        guard !isPoisoned else {
            throw EmbeddedCallError(
                code: sr_SR_FATAL,
                message: "The embedded engine panicked and is no longer usable; open a new client."
            )
        }
    }

    private static func failure(code: Int32, error: sr_string_t?) -> EmbeddedCallError {
        defer { if let error { sr_free_string(error) } }
        let message = error.map { String(cString: $0) } ?? "Unknown embedded engine error"
        return EmbeddedCallError(code: code, message: message)
    }
}

private func withOptionalCString<T>(_ value: String?, _ body: (UnsafePointer<CChar>?) throws -> T) rethrows -> T {
    guard let value else { return try body(nil) }
    return try value.withCString { try body($0) }
}

private extension EmbeddedCredentialScope {
    var native: sr_credentials_scope {
        switch self {
        case .root: return ROOT
        case .namespace: return NAMESPACE
        case .database: return DATABASE
        case .record: return RECORD
        }
    }
}
#endif
