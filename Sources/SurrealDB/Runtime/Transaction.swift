import Foundation

/// Builds a single client-side transaction by accumulating statements that
/// are flushed atomically through a single `query` RPC wrapped in
/// `BEGIN; ... COMMIT;`. If any statement fails, SurrealDB cancels the
/// transaction server-side.
///
/// Construct a transaction via the client's `transaction { tx in ... }`
/// closure rather than instantiating this type directly.
public final class SurrealTransaction: @unchecked Sendable {
    private var statements: [String] = []
    private var bindings: [String: SurrealValue] = [:]
    private var bindingCounter = 0

    public init() {}

    /// Appends a raw SurrealQL statement with optional bindings. Bindings
    /// whose names collide with previously appended ones are automatically
    /// renamed; the SQL is rewritten to match.
    @discardableResult
    public func append(_ sql: String, bindings: [String: SurrealValue] = [:]) -> SurrealTransaction {
        var rewritten = sql
        var mapping: [String: String] = [:]

        for (key, value) in bindings {
            let finalKey: String
            if let existing = self.bindings[key], existing != value {
                finalKey = nextUniqueKey(preferred: key)
                mapping[key] = finalKey
            } else {
                finalKey = key
            }
            self.bindings[finalKey] = value
        }

        for (oldKey, newKey) in mapping {
            rewritten = renameBinding(in: rewritten, from: oldKey, to: newKey)
        }

        statements.append(rewritten)
        return self
    }

    /// Appends a typed `SurrealQuery`. The query's bindings are merged into
    /// the transaction with automatic renaming on conflict.
    @discardableResult
    public func append<T>(_ query: SurrealQuery<T>) -> SurrealTransaction {
        append(query.sql, bindings: query.bindings)
    }

    func build() -> (sql: String, bindings: [String: SurrealValue]) {
        var sql = "BEGIN;\n"
        for statement in statements {
            let trimmed = statement.trimmingCharacters(in: .whitespacesAndNewlines)
            if trimmed.isEmpty { continue }
            sql += trimmed.hasSuffix(";") ? trimmed : trimmed + ";"
            sql += "\n"
        }
        sql += "COMMIT;"
        return (sql, bindings)
    }

    private func nextUniqueKey(preferred: String) -> String {
        repeat {
            bindingCounter += 1
            let candidate = "\(preferred)_tx\(bindingCounter)"
            if bindings[candidate] == nil {
                return candidate
            }
        } while true
    }

    private func renameBinding(in sql: String, from oldKey: String, to newKey: String) -> String {
        // Replace `$oldKey` occurrences that aren't part of a longer identifier.
        var result = ""
        let chars = Array(sql)
        let oldPattern = Array("$\(oldKey)")
        var i = 0

        while i < chars.count {
            if matches(chars: chars, at: i, pattern: oldPattern),
               isBindingBoundary(chars: chars, after: i + oldPattern.count)
            {
                result += "$" + newKey
                i += oldPattern.count
            } else {
                result.append(chars[i])
                i += 1
            }
        }
        return result
    }

    private func matches(chars: [Character], at index: Int, pattern: [Character]) -> Bool {
        guard index + pattern.count <= chars.count else { return false }
        for offset in 0..<pattern.count where chars[index + offset] != pattern[offset] {
            return false
        }
        return true
    }

    private func isBindingBoundary(chars: [Character], after index: Int) -> Bool {
        guard index < chars.count else { return true }
        let next = chars[index]
        return !(next.isLetter || next.isNumber || next == "_")
    }
}
