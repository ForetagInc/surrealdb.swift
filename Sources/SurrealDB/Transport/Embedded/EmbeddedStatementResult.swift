import Foundation

/// One statement's outcome as it comes back from `sr_query`, before it is
/// shaped into the `{status, time, result}` wire form the rest of the SDK
/// expects.
///
/// Deliberately free of C types so the whole response-synthesis path stays
/// testable without linking the native library.
struct EmbeddedStatementResult: Sendable, Equatable {
    /// The raw contents of the statement's `sr_array_t`, pre-unwrap.
    let values: [SurrealValue]
    /// `nil` when the statement succeeded (`sr_SurrealError.code == 0`).
    let errorMessage: String?

    init(values: [SurrealValue], errorMessage: String? = nil) {
        self.values = values
        self.errorMessage = errorMessage
    }
}
