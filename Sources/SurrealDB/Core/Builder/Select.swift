enum SelectFields {
    case all
    case fields([String])
    
    func toSurql() -> String {
        switch self {
        case .all: return "*"
        case .fields(let f): return f.joined(separator: ", ")
        }
    }
}

struct SelectQuery {
    var fields: SelectFields
    var from: String
    var filter: Expr?
    var order: [OrderBy] = []
    var limit: Int?
    var start: Int?
    
    func build(params: [String: SurrealValue] = [:]) -> BuiltQuery {
        var parts: [String] = []
        
        parts.append("SELECT \(fields.toSurql()) FROM \(from)")
        if let filter { parts.append("WHERE \(filter.toSurql())") }
        
        if !order.isEmpty {
            parts.append("ORDER BY" + order.map {
                $0.toSurql()
            }.joined(separator: ", "))
        }
        
        if let limit { parts.append("LIMIT \(limit)") }
        if let start { parts.append("START \(start)") }
        
        return BuiltQuery(
            query: parts.joined(separator: "\n") + ";",
            vars: params
        )
    }
    
    func from(_ table: String) -> Self {
        var c = self
        c.from = table
        return c
    }
    
    func `where`(_ e: Expr) -> Self {
        var c = self
        c.filter = e
        return c
    }
    
    func orderBy(_ field: String, _ direction: OrderDirection) -> Self {
        var c = self
        c.order.append(.init(field: field, direction: direction))
        return c
    }
    
    
}
