public struct RecordId<T: SurrealTable>: Codable, Hashable, Sendable {
    public let raw: String
    public init(_ raw: String) { self.raw = raw }
}
