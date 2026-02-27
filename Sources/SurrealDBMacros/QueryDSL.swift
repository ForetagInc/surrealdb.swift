import Foundation

public protocol SurrealModel: Codable, Sendable {
    static var surrealTable: String { get }
}

public struct SurrealField<Model, Value>: Sendable, Hashable {
    public let name: String

    public init(_ name: String) {
        self.name = name
    }
}

public struct SurrealBinding<Value: Encodable & Sendable>: Sendable, Hashable {
    public let name: String

    public init(_ name: String) {
        self.name = name
    }
}

public func bind<T: Encodable & Sendable>(_ name: String, as: T.Type = T.self) -> SurrealBinding<T> {
    _ = `as`
    return SurrealBinding<T>(name)
}

public struct SurrealPredicate: Sendable, Hashable, ExpressibleByStringLiteral, CustomStringConvertible {
    public let raw: String

    public init(raw: String) {
        self.raw = raw
    }

    public init(stringLiteral value: String) {
        self.init(raw: value)
    }

    public var description: String { raw }
}

public func && (lhs: SurrealPredicate, rhs: @autoclosure () -> SurrealPredicate) -> SurrealPredicate {
    .init(raw: "(\(lhs.raw) AND \(rhs().raw))")
}

public func || (lhs: SurrealPredicate, rhs: @autoclosure () -> SurrealPredicate) -> SurrealPredicate {
    .init(raw: "(\(lhs.raw) OR \(rhs().raw))")
}

prefix public func ! (predicate: SurrealPredicate) -> SurrealPredicate {
    .init(raw: "NOT (\(predicate.raw))")
}

public protocol SurrealPredicateValue {
    var surrealPredicateSQL: String { get }
}

extension SurrealBinding: SurrealPredicateValue {
    public var surrealPredicateSQL: String { "$\(name)" }
}

extension String: SurrealPredicateValue {
    public var surrealPredicateSQL: String {
        "\"\(self.replacingOccurrences(of: "\"", with: "\\\""))\""
    }
}

extension Int: SurrealPredicateValue {
    public var surrealPredicateSQL: String { "\(self)" }
}

extension Int64: SurrealPredicateValue {
    public var surrealPredicateSQL: String { "\(self)" }
}

extension Double: SurrealPredicateValue {
    public var surrealPredicateSQL: String { "\(self)" }
}

extension Bool: SurrealPredicateValue {
    public var surrealPredicateSQL: String { self ? "true" : "false" }
}

extension UUID: SurrealPredicateValue {
    public var surrealPredicateSQL: String { "u\"\(uuidString.lowercased())\"" }
}

extension Date: SurrealPredicateValue {
    public var surrealPredicateSQL: String {
        "d\"\(ISO8601DateFormatter().string(from: self))\""
    }
}

extension SurrealValue: SurrealPredicateValue {
    public var surrealPredicateSQL: String { sqlLiteral }
}

private func binaryPredicate<Model, Value: SurrealPredicateValue>(
    _ lhs: SurrealField<Model, Value>,
    _ op: String,
    _ rhs: Value
) -> SurrealPredicate {
    .init(raw: "\(lhs.name) \(op) \(rhs.surrealPredicateSQL)")
}

private func binaryPredicate<Model, Value: Encodable & Sendable>(
    _ lhs: SurrealField<Model, Value>,
    _ op: String,
    _ rhs: SurrealBinding<Value>
) -> SurrealPredicate {
    .init(raw: "\(lhs.name) \(op) \(rhs.surrealPredicateSQL)")
}

public func == <Model, Value: SurrealPredicateValue>(lhs: SurrealField<Model, Value>, rhs: Value) -> SurrealPredicate {
    binaryPredicate(lhs, "=", rhs)
}

public func != <Model, Value: SurrealPredicateValue>(lhs: SurrealField<Model, Value>, rhs: Value) -> SurrealPredicate {
    binaryPredicate(lhs, "!=", rhs)
}

public func > <Model, Value: SurrealPredicateValue>(lhs: SurrealField<Model, Value>, rhs: Value) -> SurrealPredicate {
    binaryPredicate(lhs, ">", rhs)
}

public func >= <Model, Value: SurrealPredicateValue>(lhs: SurrealField<Model, Value>, rhs: Value) -> SurrealPredicate {
    binaryPredicate(lhs, ">=", rhs)
}

public func < <Model, Value: SurrealPredicateValue>(lhs: SurrealField<Model, Value>, rhs: Value) -> SurrealPredicate {
    binaryPredicate(lhs, "<", rhs)
}

public func <= <Model, Value: SurrealPredicateValue>(lhs: SurrealField<Model, Value>, rhs: Value) -> SurrealPredicate {
    binaryPredicate(lhs, "<=", rhs)
}

public func == <Model, Value: Encodable & Sendable>(lhs: SurrealField<Model, Value>, rhs: SurrealBinding<Value>) -> SurrealPredicate {
    binaryPredicate(lhs, "=", rhs)
}

public func != <Model, Value: Encodable & Sendable>(lhs: SurrealField<Model, Value>, rhs: SurrealBinding<Value>) -> SurrealPredicate {
    binaryPredicate(lhs, "!=", rhs)
}

public func > <Model, Value: Encodable & Sendable>(lhs: SurrealField<Model, Value>, rhs: SurrealBinding<Value>) -> SurrealPredicate {
    binaryPredicate(lhs, ">", rhs)
}

public func >= <Model, Value: Encodable & Sendable>(lhs: SurrealField<Model, Value>, rhs: SurrealBinding<Value>) -> SurrealPredicate {
    binaryPredicate(lhs, ">=", rhs)
}

public func < <Model, Value: Encodable & Sendable>(lhs: SurrealField<Model, Value>, rhs: SurrealBinding<Value>) -> SurrealPredicate {
    binaryPredicate(lhs, "<", rhs)
}

public func <= <Model, Value: Encodable & Sendable>(lhs: SurrealField<Model, Value>, rhs: SurrealBinding<Value>) -> SurrealPredicate {
    binaryPredicate(lhs, "<=", rhs)
}

public struct SurrealQuery<Result: Decodable & Sendable>: Sendable {
    public let sql: String
    public let bindings: [String: SurrealValue]

    public init(sql: String, bindings: [String: SurrealValue] = [:]) {
        self.sql = sql
        self.bindings = bindings
    }
}

public struct LiveQuery<Result: Decodable & Sendable>: Sendable {
    public let sql: String
    public let bindings: [String: SurrealValue]

    public init(sql: String, bindings: [String: SurrealValue] = [:]) {
        self.sql = sql
        self.bindings = bindings
    }
}

public enum SurrealDSL {
    public static func select<Model: SurrealModel & Decodable & Sendable>(
        _ model: Model.Type,
        where predicate: SurrealPredicate? = nil,
        limit: Int? = nil,
        start: Int? = nil,
        bindings: [String: SurrealValue] = [:]
    ) -> SurrealQuery<Model> {
        var sql = "SELECT * FROM \(model.surrealTable)"
        if let predicate {
            sql += " WHERE \(predicate.raw)"
        }
        if let limit {
            sql += " LIMIT \(limit)"
        }
        if let start {
            sql += " START \(start)"
        }
        return .init(sql: sql + ";", bindings: bindings)
    }

    public static func create<Model: SurrealModel & Codable & Sendable>(
        _ model: Model.Type,
        contentBinding: String = "content",
        bindings: [String: SurrealValue] = [:]
    ) -> SurrealQuery<Model> {
        .init(sql: "CREATE \(model.surrealTable) CONTENT $\(contentBinding);", bindings: bindings)
    }

    public static func update<Model: SurrealModel & Decodable & Sendable>(
        _ model: Model.Type,
        where predicate: SurrealPredicate? = nil,
        contentBinding: String = "content",
        bindings: [String: SurrealValue] = [:]
    ) -> SurrealQuery<Model> {
        var sql = "UPDATE \(model.surrealTable) CONTENT $\(contentBinding)"
        if let predicate {
            sql += " WHERE \(predicate.raw)"
        }
        return .init(sql: sql + ";", bindings: bindings)
    }

    public static func upsert<Model: SurrealModel & Decodable & Sendable>(
        _ model: Model.Type,
        where predicate: SurrealPredicate? = nil,
        contentBinding: String = "content",
        bindings: [String: SurrealValue] = [:]
    ) -> SurrealQuery<Model> {
        var sql = "UPSERT \(model.surrealTable) CONTENT $\(contentBinding)"
        if let predicate {
            sql += " WHERE \(predicate.raw)"
        }
        return .init(sql: sql + ";", bindings: bindings)
    }

    public static func delete<Model: SurrealModel & Decodable & Sendable>(
        _ model: Model.Type,
        where predicate: SurrealPredicate? = nil,
        bindings: [String: SurrealValue] = [:]
    ) -> SurrealQuery<Model> {
        var sql = "DELETE \(model.surrealTable)"
        if let predicate {
            sql += " WHERE \(predicate.raw)"
        }
        return .init(sql: sql + ";", bindings: bindings)
    }

    public static func live<Model: SurrealModel & Decodable & Sendable>(
        _ model: Model.Type,
        where predicate: SurrealPredicate? = nil,
        fetch: [String] = [],
        bindings: [String: SurrealValue] = [:]
    ) -> LiveQuery<Model> {
        var sql = "LIVE SELECT * FROM \(model.surrealTable)"
        if let predicate {
            sql += " WHERE \(predicate.raw)"
        }
        if !fetch.isEmpty {
            sql += " FETCH " + fetch.joined(separator: ", ")
        }
        return .init(sql: sql + ";", bindings: bindings)
    }
}
