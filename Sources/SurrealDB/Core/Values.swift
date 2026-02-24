import Foundation

enum SurrealValue {
    case null
    case bool(Bool)
    case int(Int)
    case double(Double)
    case string(String)
    case datetime(Date)
    case record(String)
    case param(String)
    case object([String: SurrealValue])
    case array([SurrealValue])
    
    func toSurql() -> String {
        switch self {
        case .null: return "NONE"
        case .bool(let v): return v ? "true" : "false"
        case .int(let v): return "\(v)"
        case .double(let v): return "\(v)"
        case .string(let s): return "\"\(s.replacingOccurrences(of: "\"", with: "\\\""))\""
        case .datetime: return "$__date"
        case .record(let r): return r
        case .param(let name): return "$\(name)"
        case .object(let o):
            return "{ " + o.map { "\($0): \($1.toSurql())" }.sorted().joined(separator: ", ") + " }"
        case .array(let a):
            return "[" + a.map { $0.toSurql() }.joined(separator: ", ") + "]"
        }
    }
}

indirect enum Expr {
    case raw(String)
    case eq(String, SurrealValue)
    case ne(String, SurrealValue)
    case gt(String, SurrealValue)
    case lt(String, SurrealValue)
    case gte(String, SurrealValue)
    case lte(String, SurrealValue)
    case isNull(String)
    case isNotNull(String)
    case and(Expr, Expr)
    case or(Expr, Expr)
    case not(Expr)
    
    func toSurql() -> String {
        switch self {
        case .raw(let s): return s
        case .eq(let k, let v): return "\(k) = \(v.toSurql())"
        case .ne(let k, let v): return "\(k) != \(v.toSurql())"
        case .gt(let k, let v): return "\(k) > \(v.toSurql())"
        case .gte(let k, let v): return "\(k) >= \(v.toSurql())"
        case .lt(let k, let v): return "\(k) < \(v.toSurql())"
        case .lte(let k, let v): return "\(k) <= \(v.toSurql())"
        case .isNull(let k): return "\(k) IS NULL"
        case .isNotNull(let k): return "\(k) IS NOT NULL"
        case .and(let a, let b): return "(\(a.toSurql()) AND \(b.toSurql()))"
        case .or(let a, let b): return "(\(a.toSurql()) OR \(b.toSurql()))"
        case .not(let e): return "NOT (\(e.toSurql()))"
        }
    }
}

struct OrderBy {
    let field: String
    let direction: OrderDirection
    
    func toSurql() -> String {
        "\(field) \(direction == .asc ? "ASC" : "DESC")"
    }
}

struct BuiltQuery {
    let query: String
    let vars: [String: SurrealValue]
}

