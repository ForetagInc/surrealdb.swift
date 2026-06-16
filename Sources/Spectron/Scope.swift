import Foundation

/// One AND-clause of a scope selector: a set of slash-path strings that must all
/// hold together. A bare string is a single-path clause; an array is an AND of
/// its paths.
public struct ScopeClause: Sendable, Equatable,
    ExpressibleByStringLiteral,
    ExpressibleByArrayLiteral {

    let paths: [String]

    public init(stringLiteral value: String) {
        paths = [value]
    }

    public init(arrayLiteral elements: String...) {
        paths = elements
    }

    public init(_ paths: [String]) {
        self.paths = paths
    }
}

/// A scope selector in disjunctive normal form (an OR of AND-clauses) that
/// identifies the memory region a write targets, or the region a read is
/// narrowed to.
///
/// The outer level is an OR of clauses; each clause is an AND of slash-path
/// strings (for example `"team/eng"`). A bare string is a single-path clause,
/// and a nested array is an AND-clause, so the two mix freely:
///
/// ```swift
/// memory.remember("...", scope: "team/eng")              // -> [["team/eng"]]
/// memory.remember("...", scope: ["team/eng", "org/acme"]) // a OR b
/// memory.remember("...", scope: [["team/eng", "org/acme"]]) // a AND b
/// memory.remember("...", scope: ["team/eng", ["org/acme", "tier/gold"]])
/// //                                a OR (b AND c)
/// ```
///
/// Note that a flat list of two or more paths means OR, not AND. To require
/// several paths together, nest them in their own clause.
///
/// Selectors normalise to an ordered, de-duplicated list of clauses with empty
/// paths and empty clauses dropped. Omitting scope uses the key's default write
/// region.
public struct Scope: Sendable, Equatable,
    ExpressibleByStringLiteral,
    ExpressibleByArrayLiteral {

    private let rawClauses: [[String]]

    // MARK: Literals

    public init(stringLiteral value: String) {
        rawClauses = [[value]]
    }

    public init(arrayLiteral elements: ScopeClause...) {
        rawClauses = elements.map(\.paths)
    }

    // MARK: Explicit constructors (for non-literal values)

    /// A single slash path.
    public init(_ path: String) {
        rawClauses = [[path]]
    }

    /// A list of clauses, each an AND of slash paths.
    public init(_ clauses: [[String]]) {
        rawClauses = clauses
    }

    // MARK: Wire form

    /// The normalised wire representation: an ordered, de-duplicated OR of
    /// AND-clauses with empty paths and empty clauses removed.
    public var clauses: [[String]] {
        var out: [[String]] = []
        for clause in rawClauses {
            var paths: [String] = []
            for path in clause where !path.isEmpty && !paths.contains(path) {
                paths.append(path)
            }
            if !paths.isEmpty && !out.contains(paths) {
                out.append(paths)
            }
        }
        return out
    }
}

/// Encodes normalised scope clauses as the canonical `array<array<string>>`
/// wire shape shared by the `scopes` (write) and `lens` (read) fields.
func scopeSetsJSON(_ clauses: [[String]]) -> JSONValue {
    .array(clauses.map { clause in .array(clause.map { .string($0) }) })
}
