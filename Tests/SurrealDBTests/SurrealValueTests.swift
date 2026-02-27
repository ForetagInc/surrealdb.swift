import Foundation
import Testing
@testable import SurrealDB

@Test
func surrealValue_JSONRoundTrip() throws {
    let original: SurrealValue = .object([
        "id": .string("user:1"),
        "age": .int(42),
        "tags": .array([.string("swift"), .string("cbor")]),
    ])

    let object = try original.jsonObject()
    let roundTrip = try SurrealValue(jsonObject: object)

    #expect(roundTrip == original)
}

@Test
func surrealPredicate_buildsExpectedSQL() {
    struct Model: SurrealModel {
        static let surrealTable = "person"
    }

    let predicate = (SurrealField<Model, Int>("age") >= 21) && (SurrealField<Model, String>("name") == "Alice")

    #expect(predicate.raw == "(age >= 21 AND name = \"Alice\")")
}
