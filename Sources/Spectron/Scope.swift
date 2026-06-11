import Foundation

/// A scope argument: an ordered set of slash-path strings (for example
/// `"team/eng"`) that identifies the memory region a write targets.
///
/// It accepts a single path, a list of paths, or key/value pairs (which become
/// `key/value` paths), and normalises to an ordered, de-duplicated list with
/// empty entries removed. Omitting scope uses the key's default write region.
///
/// ```swift
/// memory.remember("...", scope: "team/eng")
/// memory.remember("...", scope: ["team/eng", "org/acme"])
/// memory.remember("...", scope: ["org": "acme"])   // -> ["org/acme"]
/// ```
public struct Scope: Sendable, Equatable,
    ExpressibleByStringLiteral,
    ExpressibleByArrayLiteral,
    ExpressibleByDictionaryLiteral {

    private enum Entry: Sendable, Equatable {
        case path(String)
        case pair(key: String, value: String)
    }

    private let entries: [Entry]

    // MARK: Literals

    public init(stringLiteral value: String) {
        entries = [.path(value)]
    }

    public init(arrayLiteral elements: String...) {
        entries = elements.map { .path($0) }
    }

    public init(dictionaryLiteral elements: (String, String)...) {
        entries = elements.map { .pair(key: $0.0, value: $0.1) }
    }

    // MARK: Explicit constructors (for non-literal values)

    /// A single slash path.
    public init(_ path: String) {
        entries = [.path(path)]
    }

    /// A list of slash paths.
    public init(_ paths: [String]) {
        entries = paths.map { .path($0) }
    }

    /// Ordered key/value pairs, each serialised as a `key/value` path.
    public init(pairs: [(String, String)]) {
        entries = pairs.map { .pair(key: $0.0, value: $0.1) }
    }

    // MARK: Wire form

    /// The normalised wire representation: an ordered, de-duplicated list of
    /// slash paths with empty entries removed.
    public var paths: [String] {
        var out: [String] = []
        for entry in entries {
            let path: String
            switch entry {
            case .path(let value):
                path = value
            case .pair(let key, let value):
                path = "\(key)/\(value)"
            }
            if !path.isEmpty && !out.contains(path) {
                out.append(path)
            }
        }
        return out
    }
}
