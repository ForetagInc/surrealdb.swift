import Foundation

protocol RPCEngine: Actor {
    func connect() async throws
    func close() async
    func send(_ request: RPCRequest, session: SessionContext) async throws -> RPCResponseEnvelope
}

protocol LiveRPCEngine: RPCEngine {
    func openLiveStream(for queryID: UUID) async -> AsyncStream<LiveWireEvent>
    func closeLiveStream(for queryID: UUID) async
}
