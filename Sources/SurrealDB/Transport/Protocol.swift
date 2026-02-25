public protocol Transport {
    func query(query: String, params: [String: SurrealValue]) async
}
