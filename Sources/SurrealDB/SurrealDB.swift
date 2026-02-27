@_exported import SurrealDBMacros

@attached(member, names: named(surrealTable), named(Fields))
@attached(extension, conformances: SurrealModel)
public macro SurrealModel(_ table: String) = #externalMacro(module: "SurrealDBMacroPlugin", type: "SurrealModelMacro")

@freestanding(expression)
public macro `where`(_ predicate: SurrealPredicate) -> SurrealPredicate = #externalMacro(module: "SurrealDBMacroPlugin", type: "WhereMacro")

@freestanding(expression)
public macro select<Model: SurrealModel & Decodable & Sendable>(
    _ model: Model.Type,
    where predicate: SurrealPredicate? = nil,
    limit: Int? = nil,
    start: Int? = nil
) -> SurrealQuery<Model> = #externalMacro(module: "SurrealDBMacroPlugin", type: "SelectMacro")

@freestanding(expression)
public macro create<Model: SurrealModel & Codable & Sendable>(
    _ model: Model.Type,
    contentBinding: String = "content"
) -> SurrealQuery<Model> = #externalMacro(module: "SurrealDBMacroPlugin", type: "CreateMacro")

@freestanding(expression)
public macro update<Model: SurrealModel & Decodable & Sendable>(
    _ model: Model.Type,
    where predicate: SurrealPredicate? = nil,
    contentBinding: String = "content"
) -> SurrealQuery<Model> = #externalMacro(module: "SurrealDBMacroPlugin", type: "UpdateMacro")

@freestanding(expression)
public macro upsert<Model: SurrealModel & Decodable & Sendable>(
    _ model: Model.Type,
    where predicate: SurrealPredicate? = nil,
    contentBinding: String = "content"
) -> SurrealQuery<Model> = #externalMacro(module: "SurrealDBMacroPlugin", type: "UpsertMacro")

@freestanding(expression)
public macro delete<Model: SurrealModel & Decodable & Sendable>(
    _ model: Model.Type,
    where predicate: SurrealPredicate? = nil
) -> SurrealQuery<Model> = #externalMacro(module: "SurrealDBMacroPlugin", type: "DeleteMacro")

@freestanding(expression)
public macro live<Model: SurrealModel & Decodable & Sendable>(
    _ model: Model.Type,
    where predicate: SurrealPredicate? = nil
) -> LiveQuery<Model> = #externalMacro(module: "SurrealDBMacroPlugin", type: "LiveMacro")
