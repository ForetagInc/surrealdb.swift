public protocol SurrealTable: Codable, Sendable {
    static var name: String { get }
}


public enum ValueExpr<T: SurrealTable>: Sendable {
    case value(T)
    case param(String)
}

