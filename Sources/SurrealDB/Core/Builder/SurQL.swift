enum Surql {
    static func select (_ fields: SelectFields, _ table: String) ->
        SelectQuery { .init(fields: fields, from: table) }
   
    static func create (_ table: String) ->
        CreateQuery { .init(table: table) }
    
    static func update (_ target: String) ->
        UpdateQuery { .init(target: target) }
}
