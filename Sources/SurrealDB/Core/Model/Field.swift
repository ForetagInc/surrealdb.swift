public struct Field<T: SurrealTable, X>: Sendable {
    public let name: String
    public init(_ name: String) { self.name = name }
}

