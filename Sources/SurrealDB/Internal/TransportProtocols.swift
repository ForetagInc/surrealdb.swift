import Foundation

protocol RPCEngine: Actor {
    /// Human-readable transport name, used in capability-gating error messages.
    /// Defaulted so conformers (including test doubles) need not implement it.
    nonisolated var transportDescription: String { get }

    func connect() async throws
    func close() async
    func send(_ request: RPCRequest, session: SessionContext) async throws -> RPCResponseEnvelope
}

extension RPCEngine {
    nonisolated var transportDescription: String { "this transport" }
}

protocol LiveRPCEngine: RPCEngine {
    func openLiveStream(for queryID: UUID) async -> AsyncStream<LiveWireEvent>
    func closeLiveStream(for queryID: UUID) async

    /// Fires each time the engine successfully re-establishes a connection
    /// after an unexpected drop (not on the initial `connect()`). Consumers
    /// use this to replay session state (namespace/database/auth) that the
    /// server loses when a connection is re-established.
    func reconnectEvents() -> AsyncStream<Void>
}

/// Marker for engines whose connections can multiplex more than one
/// server-side session (via `attach`/`detach`). Orthogonal to `LiveRPCEngine`
/// even though only `WebSocketRPCEngine` conforms to both today.
protocol SessionCapableRPCEngine: RPCEngine {}
