import Foundation

/// Builds the `RPCResponseEnvelope`s the embedded engine hands back, matching
/// the shape the server would have sent over the wire.
enum EmbeddedEnvelope {
    static func ok(id: String, result: SurrealValue) -> RPCResponseEnvelope {
        RPCResponseEnvelope(id: id, action: nil, result: result, error: nil)
    }

    static func failure(id: String, message: String, code: Int32) -> RPCResponseEnvelope {
        RPCResponseEnvelope(
            id: id,
            action: nil,
            result: nil,
            error: EmbeddedErrorMapping.rpcError(message: message, code: code)
        )
    }

    /// Assembles a `query` response. `RPCWire.decodeQueryResults` requires both
    /// `status` and `time` on every row, so both are always present.
    ///
    /// `elapsed` is the wall time of the whole `sr_query` call and is reported
    /// identically on every row: the C API exposes no per-statement timing, and
    /// a fabricated per-statement split would be worse than an honest total.
    static func queryResponse(
        id: String,
        statements: [EmbeddedStatementResult],
        elapsed: Duration
    ) -> RPCResponseEnvelope {
        let time = formatDuration(elapsed)

        let rows: [SurrealValue] = statements.map { statement in
            guard let message = statement.errorMessage else {
                return .object([
                    "status": .string(QueryResultStatus.ok.rawValue),
                    "time": .string(time),
                    "result": unwrapSingleUnit(statement.values),
                ])
            }

            var row: [String: SurrealValue] = [
                "status": .string(QueryResultStatus.err.rawValue),
                "time": .string(time),
                "result": .string(message),
            ]

            let classified = EmbeddedErrorMapping.classify(message)
            if let kind = classified.kind {
                row["kind"] = .string(kind)
            }
            if let details = classified.details {
                row["details"] = details
            }
            return .object(row)
        }

        return ok(id: id, result: .array(rows))
    }

    /// `sr_query` wraps every non-array statement result in a one-element array,
    /// so a `DEFINE`/`REMOVE` statement arrives as `[NONE]` rather than `NONE`.
    ///
    /// `SurrealClientCore.decodeQueryResults` skips a bare `.none`/`.null` but
    /// *iterates* an array, so the wrapped form would try to decode `NONE` into
    /// the caller's model and throw. Unwrapping the single-unit case is safe
    /// because `RETURN NONE` and `RETURN [NONE]` are indistinguishable at the C
    /// boundary and both are skipped identically downstream.
    ///
    /// Everything else stays wrapped: `RETURN 1` yields `.array([.int(1)])`
    /// here where WebSocket yields `.int(1)`. That divergence is invisible to
    /// the typed APIs, which flatten arrays anyway.
    static func unwrapSingleUnit(_ values: [SurrealValue]) -> SurrealValue {
        if values.count == 1 {
            switch values[0] {
            case .none, .null:
                return values[0]
            default:
                break
            }
        }
        return .array(values)
    }

    /// Formats a duration the way SurrealDB reports query times (`"412ns"`,
    /// `"87.3µs"`, `"1.24ms"`, `"2.01s"`).
    static func formatDuration(_ duration: Duration) -> String {
        let components = duration.components
        let nanoseconds =
            Double(components.seconds) * 1_000_000_000
            + Double(components.attoseconds) / 1_000_000_000

        switch nanoseconds {
        case ..<1_000:
            return "\(Int(nanoseconds.rounded()))ns"
        case ..<1_000_000:
            return "\(trimmed(nanoseconds / 1_000))µs"
        case ..<1_000_000_000:
            return "\(trimmed(nanoseconds / 1_000_000))ms"
        default:
            return "\(trimmed(nanoseconds / 1_000_000_000))s"
        }
    }

    private static func trimmed(_ value: Double) -> String {
        var text = String(format: "%.3f", value)
        while text.hasSuffix("0") {
            text.removeLast()
        }
        if text.hasSuffix(".") {
            text.removeLast()
        }
        return text
    }
}
