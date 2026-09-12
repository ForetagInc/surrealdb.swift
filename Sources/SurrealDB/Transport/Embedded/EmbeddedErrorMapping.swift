import Foundation

/// Recovers the server's `kind`/`details` taxonomy from the free-text messages
/// the embedded engine produces.
///
/// surrealdb.c discards the structured error: every per-statement failure comes
/// back with `code == SR_ERROR` and nothing but `e.to_string()`. Without this,
/// every embedded failure would classify as `ServerErrorKind.internalError` and
/// `isTransactionConflict` / `isInvalidAuth` / `isNotFound` would all be false,
/// silently breaking retry logic written against `SurrealError.serverErrorKind`.
///
/// This is a heuristic over surrealdb-core's message strings, so it is
/// deliberately narrow: it covers only the cases where a wrong classification
/// changes program behaviour, and returns `nil` rather than guessing. Delete it
/// wholesale once the C layer carries structured errors.
enum EmbeddedErrorMapping {
    static func classify(_ message: String) -> (kind: String?, details: SurrealValue?) {
        let text = message.lowercased()

        if text.contains("read or write conflict") || text.contains("transaction conflict") {
            return ("Query", nested("TransactionConflict"))
        }
        if text.contains("query was cancelled") || text.contains("query was canceled") {
            return ("Query", nested("Cancelled"))
        }
        if text.contains("query was not executed") {
            return ("Query", nested("NotExecuted"))
        }
        if text.contains("not enough permissions")
            || text.contains("iam error")
            || text.contains("problem with authentication") {
            return ("NotAllowed", .object([
                "kind": .string("Auth"),
                "details": nested("InvalidAuth")!,
            ]))
        }
        if text.contains("already exists") || text.contains("already contains") {
            return ("AlreadyExists", nil)
        }
        if text.contains("does not exist") || text.contains("not found") {
            return ("NotFound", nil)
        }
        if text.contains("parse error") {
            return ("Validation", nested("Parse"))
        }

        return (nil, nil)
    }

    static func rpcError(message: String, code: Int32) -> RPCErrorObject {
        let classified = classify(message)
        return RPCErrorObject(
            code: Int(code),
            kind: classified.kind,
            message: message,
            details: classified.details,
            cause: nil
        )
    }

    private static func nested(_ kind: String) -> SurrealValue? {
        .object(["kind": .string(kind)])
    }
}
