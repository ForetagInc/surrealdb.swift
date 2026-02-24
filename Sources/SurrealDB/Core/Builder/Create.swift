struct CreateQuery {
    var table: String
    var content: [String: SurrealValue] = [:]
    
    func build(params: [String: SurrealValue] = [:]) -> BuiltQuery {
        let content = SurrealValue.object(content).toSurql()
        
        return BuiltQuery(
            query: "CREATE \(table) CONTENT \(content);",
            vars: params
        )
    }
}
