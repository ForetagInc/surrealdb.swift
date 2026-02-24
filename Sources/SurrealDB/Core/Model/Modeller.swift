import Foundation

public protocol Table: Codable, Sendable {
    static var name: String { get }
}

public enum Param: Sendable, Equatable {
    case null
    case bool(Bool)
    case int(Int)
    case double(Double)
    case string(String)
    case datetime(Date)
    case record(String)
    case array([Param])
    case object([String: Param])
    
    func toSurqlLiteral() -> String {
        switch self {
        case .null: return "NONE"
        case .bool(let v): return v ? "true" : "false"
        case .int(let v): return "\(v)"
        case .double(let v): return "\(v)"
        case .string(let s):
        return "\"\(s.replacingOccurrences(of: "\"", with: "\\\""))\""
        case .datetime: return "$__datetime"
        case .record(let r): return r
        case .array(let a): return "[" + a.map { $0.toSurqlLiteral() }.joined(separator: ", ") + "]"
        case .object(let o):
            let body = o.map { "\($0): \($1.toSurqlLiteral())" }.sorted().joined(separator: ", ")
            return "{ \(body) }"
        }
    }
}

enum OrderDirection {
    case asc, desc
}

public enum ValueExpr<T: Sendable>: Sendable {
    case value(T)
    case param(String)
}

public extension ValueExpr {
    static func value(_ v: T) -> Self {
        .value(v)
    }
    
    static func param(_ name: String) -> Self {
        .param(name)
    }
}

public indirect enum Predicate<T: Table>: Sendable {
    case raw(String)
    case cmp(String)
    case and(Predicate, Predicate)
    case or(Predicate, Predicate)
    case not(Predicate)
    
    func toSurql() -> String {
        switch self {
        case .raw(let s): return s
        case .cmp(let s): return s
        case .and(let a, let b): return "(\(a.toSurql()) AND \(b.toSurql()))"
        case .or(let a, let b): return "(\(a.toSurql()) OR \(b.toSurql()))"
        case .not(let e): return "NOT (\(e.toSurql()))"
        }
    }
    
    public static func and(_ a: Predicate, _ b: Predicate) -> Predicate { .and(a, b) }
    public static func or(_ a: Predicate, _ b: Predicate) -> Predicate { .or(a, b) }
}
