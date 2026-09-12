import Dispatch

/// Runs blocking C calls off the Swift concurrency cooperative pool.
///
/// Every `sr_*` entry point blocks its thread for the whole operation
/// (surrealdb.c calls `Runtime::block_on` internally). Calling one directly from
/// an actor would occupy a cooperative thread, and enough concurrent queries
/// would starve unrelated async work. Here the calling actor *suspends* while a
/// dedicated queue does the blocking work.
///
/// The queue is serial. `EmbeddedRPCEngine` is an actor, but actors are
/// reentrant: while one `send` awaits its continuation another can run, so the
/// queue is what actually bounds concurrency. It also keeps session-mutating
/// calls (`sr_use_ns`, `sr_signin`) ordered against the queries that depend on
/// them, and caps thread use at one regardless of caller concurrency.
final class BlockingFFIExecutor: Sendable {
    private let queue: DispatchQueue

    init(label: String, qualityOfService: DispatchQoS) {
        self.queue = DispatchQueue(label: label, qos: qualityOfService)
    }

    func run<T>(_ body: sending @escaping () throws -> T) async throws -> sending T {
        let work = Transferred(body)
        let outcome: Transferred<Result<T, any Error>> = try await withCheckedThrowingContinuation { continuation in
            queue.async {
                continuation.resume(returning: Transferred(Result { try work.value() }))
            }
        }
        return try outcome.value.get()
    }

    func run<T>(_ body: sending @escaping () -> T) async -> sending T {
        let work = Transferred(body)
        let outcome: Transferred<T> = await withCheckedContinuation { continuation in
            queue.async {
                continuation.resume(returning: Transferred(work.value()))
            }
        }
        return outcome.value
    }
}

/// Hand-off box for values that cross onto the FFI queue and back.
///
/// Safe because each instance is created, moved across exactly one queue hop,
/// and read once, never shared. `sending` expresses that at the call site but
/// cannot be carried through `DispatchQueue.async`, which demands `@Sendable`.
private struct Transferred<Value>: @unchecked Sendable {
    let value: Value

    init(_ value: sending Value) {
        self.value = value
    }
}
