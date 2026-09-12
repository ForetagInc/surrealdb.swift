import Foundation

/// An embedded storage target, parsed from an endpoint string such as `mem://`.
///
/// Only in-memory storage ships today. The `kind` enum is the seam for the
/// on-disk backends (`surrealkv://`, `rocksdb://`, `indxdb://`).
public struct EmbeddedTarget: Sendable, Equatable {
    public enum Kind: String, Sendable, Equatable {
        case memory = "mem"
    }

    public let kind: Kind

    /// The exact string handed to `sr_connect`. Kept verbatim rather than
    /// rebuilt from `URLComponents`, which would normalise `mem://` away.
    public let connectionString: String

    init(endpoint: String) throws {
        let lowercased = endpoint.lowercased()
        guard lowercased == "mem://" || lowercased == "mem:" else {
            // An in-memory store has no location. Silently ignoring one would
            // become a trap the moment `surrealkv://<path>` lands and does use it.
            throw SurrealError.invalidEndpoint(endpoint)
        }
        self.kind = .memory
        self.connectionString = "mem://"
    }
}

/// Tuning for the in-process `mem://` engine.
///
/// `sr_option_t`'s `strict` / `query_timeout` / `transaction_timeout` are
/// deliberately absent: surrealdb.c exposes them only through
/// `sr_surreal_rpc_new`, whose CBOR RPC path drops type tags and errors on query
/// results. They will be added here if `sr_connect` ever accepts options.
///
/// There is deliberately no request timeout either: a blocking C call cannot be
/// cancelled, so a caller-side timeout would resume while the call kept running
/// and, on a serial queue, block every request behind it.
public struct SurrealEmbeddedOptions: Sendable, Equatable {
    /// Priority of the thread that runs the blocking FFI calls.
    public var qualityOfService: QualityOfService

    /// Largest array accepted as a bound value. `sr_array_push` deep-clones the
    /// whole prefix on every push, so building an array is quadratic; above this
    /// bound the marshaller throws rather than stalling with no explanation.
    public var maximumBoundArrayCount: Int

    public init(
        qualityOfService: QualityOfService = .userInitiated,
        maximumBoundArrayCount: Int = 4_096
    ) {
        self.qualityOfService = qualityOfService
        self.maximumBoundArrayCount = maximumBoundArrayCount
    }

    public enum QualityOfService: Sendable, Equatable {
        case userInitiated
        case utility
        case background
    }
}
