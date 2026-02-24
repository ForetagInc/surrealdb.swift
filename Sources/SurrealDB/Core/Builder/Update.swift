struct UpdateQuery {
    var target: String
    var set: [String: SurrealValue] = [:]
    var filter: Expr?
    
    func build(params: [String: SurrealValue] = [:]) -> BuiltQuery {
        let setQL = set.map { "\($0) = \($1.toSurql())" }
            .sorted()
            .joined(separator: ", ")
        
        var query = "UPDATE \(target) SET \(setQL)";
        
        if let filter {
            query += "\n WHERE \(filter.toSurql())"
        }
        
        query += ";"
        
        return BuiltQuery(query: query, vars: params)
    }
    
    func set(_ s: [String: SurrealValue]) -> Self {
        var x = self
        x.set = s
        return x
    }
    
    func `where`(_ e: Expr) -> Self {
        var x = self
        x.filter = e;
        return x
    }
}
