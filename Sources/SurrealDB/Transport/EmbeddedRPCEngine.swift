#if SURREALDB_EMBEDDED
import CSurrealDB
import Foundation

/// An in-process SurrealDB engine backed by surrealdb.c.
///
/// It conforms to `RPCEngine` only. Declining `SessionCapableRPCEngine` and
/// `LiveRPCEngine` is how sessions and live queries are gated off: `ClientCore`
/// checks conformance and throws `unsupportedFeature` before a request is ever
/// built, exactly as it does for HTTP.
///
/// Live queries are absent because the C API exposes them only as
/// `sr_select_live(resource)`, which takes a bare table name and returns no
/// query id. There is no way to attach to the UUID that `LIVE SELECT` hands
/// back through `sr_query`, and bridging via the table name would silently drop
/// the query's `WHERE` clause.
actor EmbeddedRPCEngine: RPCEngine {
    nonisolated let transportDescription = "the embedded engine"

    private let target: EmbeddedTarget
    private let options: SurrealEmbeddedOptions
    private let executor: BlockingFFIExecutor
    private var handle: SurrealHandle?
    private var isPoisoned = false

    init(target: EmbeddedTarget, options: SurrealEmbeddedOptions) {
        self.target = target
        self.options = options
        self.executor = BlockingFFIExecutor(
            label: "com.surrealdb.embedded",
            qualityOfService: options.qualityOfService.dispatchQoS
        )
    }

    func connect() async throws {
        try guardPoison()
        guard handle == nil else { return }

        let endpoint = target.connectionString
        let maximumArrayCount = options.maximumBoundArrayCount

        do {
            handle = try await executor.run {
                try SurrealHandle.connect(endpoint: endpoint, maximumArrayCount: maximumArrayCount)
            }
        } catch let error as EmbeddedCallError {
            throw translate(error)
        }
    }

    func close() async {
        guard let handle else { return }
        self.handle = nil
        // `sr_surreal_disconnect` drops the embedded Tokio runtime, so it blocks.
        await executor.run { handle.disconnect() }
    }

    func send(_ request: RPCRequest, session: SessionContext) async throws -> RPCResponseEnvelope {
        try guardPoison()
        guard let handle else { throw SurrealError.notConnected }

        guard request.session == nil else {
            throw SurrealError.unsupportedFeature(
                "Sessions require a WebSocket endpoint (ws:// or wss://); \(transportDescription) does not multiplex sessions."
            )
        }

        do {
            switch request.method {
            case "use":
                return try await performUse(request, on: handle)
            case "signin":
                return try await performAuth(request, on: handle, signingUp: false)
            case "signup":
                return try await performAuth(request, on: handle, signingUp: true)
            case "authenticate":
                return try await performAuthenticate(request, on: handle)
            case "invalidate":
                try await executor.run { try handle.invalidate() }
                return EmbeddedEnvelope.ok(id: request.id, result: .null)
            case "query":
                return try await performQuery(request, on: handle)
            case "kill":
                return try await performKill(request, on: handle)
            case "attach", "detach", "sessions":
                throw SurrealError.unsupportedFeature(
                    "Sessions require a WebSocket endpoint (ws:// or wss://); \(transportDescription) does not multiplex sessions."
                )
            default:
                throw SurrealError.unsupportedFeature(
                    "\(transportDescription) does not implement the '\(request.method)' RPC method."
                )
            }
        } catch let error as EmbeddedMarshallingError {
            throw error.asSurrealError
        } catch let error as EmbeddedCallError {
            if error.code == sr_SR_FATAL {
                isPoisoned = true
                throw translate(error)
            }
            if error.code == sr_SR_CLOSED {
                throw translate(error)
            }
            // Database-level failures travel as an error envelope so
            // `ClientCore` turns them into `SurrealError.serverError` and the
            // `ServerErrorKind` taxonomy still applies.
            return EmbeddedEnvelope.failure(id: request.id, message: error.message, code: error.code)
        }
    }

    // MARK: - Methods

    private func performUse(_ request: RPCRequest, on handle: SurrealHandle) async throws -> RPCResponseEnvelope {
        let namespace = stringParameter(request, at: 0)
        let database = stringParameter(request, at: 1)

        try await executor.run { try handle.use(namespace: namespace, database: database) }
        return EmbeddedEnvelope.ok(id: request.id, result: .null)
    }

    private func performAuth(
        _ request: RPCRequest,
        on handle: SurrealHandle,
        signingUp: Bool
    ) async throws -> RPCResponseEnvelope {
        guard let payload = request.params?.first else {
            throw SurrealError.invalidCredentials("Missing credentials.")
        }

        let credentials = signingUp
            ? try EmbeddedCredentials.resolveSignUp(payload)
            : try EmbeddedCredentials.resolveSignIn(payload)

        let token = try await executor.run {
            signingUp ? try handle.signUp(credentials) : try handle.signIn(credentials)
        }
        return EmbeddedEnvelope.ok(id: request.id, result: .string(token))
    }

    private func performAuthenticate(_ request: RPCRequest, on handle: SurrealHandle) async throws -> RPCResponseEnvelope {
        guard let token = stringParameter(request, at: 0) else {
            throw SurrealError.invalidCredentials("Missing authentication token.")
        }
        try await executor.run { try handle.authenticate(token: token) }
        return EmbeddedEnvelope.ok(id: request.id, result: .null)
    }

    private func performQuery(_ request: RPCRequest, on handle: SurrealHandle) async throws -> RPCResponseEnvelope {
        guard let sql = stringParameter(request, at: 0) else {
            throw SurrealError.invalidResponse("A query request needs SQL.")
        }

        var bindings: [String: SurrealValue] = [:]
        if let params = request.params, params.count > 1, case .object(let values) = params[1] {
            bindings = values
        }

        let clock = ContinuousClock()
        let start = clock.now
        let statements = try await executor.run { try handle.query(sql, bindings: bindings) }
        let elapsed = clock.now - start

        return EmbeddedEnvelope.queryResponse(id: request.id, statements: statements, elapsed: elapsed)
    }

    private func performKill(_ request: RPCRequest, on handle: SurrealHandle) async throws -> RPCResponseEnvelope {
        guard let first = request.params?.first, case .uuid(let id) = first else {
            throw SurrealError.invalidResponse("A kill request needs a live query id.")
        }
        try await executor.run { try handle.kill(liveQueryID: id) }
        return EmbeddedEnvelope.ok(id: request.id, result: .null)
    }

    // MARK: - Helpers

    private func stringParameter(_ request: RPCRequest, at index: Int) -> String? {
        guard let params = request.params, params.indices.contains(index) else { return nil }
        guard case .string(let value) = params[index] else { return nil }
        return value
    }

    private func guardPoison() throws {
        guard !isPoisoned else {
            throw SurrealError.connectionLost(cause: EmbeddedEngineFatal())
        }
    }

    private func translate(_ error: EmbeddedCallError) -> SurrealError {
        switch error.code {
        case sr_SR_FATAL, sr_SR_CLOSED:
            return .connectionLost(cause: EmbeddedEngineFatal(message: error.message))
        default:
            return .serverError(EmbeddedErrorMapping.rpcError(message: error.message, code: error.code))
        }
    }
}

/// Cause attached to `SurrealError.connectionLost` when the embedded engine dies.
///
/// A new `SurrealError` case would be source-breaking for every exhaustive
/// switch in user code, and carries no information this does not.
struct EmbeddedEngineFatal: LocalizedError {
    var message: String = "The embedded engine panicked and is no longer usable."

    var errorDescription: String? { message }
}

private extension SurrealEmbeddedOptions.QualityOfService {
    var dispatchQoS: DispatchQoS {
        switch self {
        case .userInitiated: return .userInitiated
        case .utility: return .utility
        case .background: return .background
        }
    }
}
#endif
