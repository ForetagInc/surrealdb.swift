import SwiftSyntaxMacros
import SwiftSyntaxMacrosTestSupport
import XCTest

@testable import SurrealDBMacroPlugin

final class MacroExpansionTests: XCTestCase {
    private let testMacros: [String: Macro.Type] = [
        "SurrealModel": SurrealModelMacro.self,
        "where": WhereMacro.self,
        "select": SelectMacro.self,
    ]

    func testSurrealModelExpansion() {
        assertMacroExpansion(
            """
            @SurrealModel("person")
            struct Person {
                let id: String
                let age: Int
            }
            """,
            expandedSource: """
            struct Person {
                let id: String
                let age: Int
            
                public static let surrealTable: String = "person"

                public enum Fields {
                    public static let id = SurrealField<Person, String>("id")
                    public static let age = SurrealField<Person, Int>("age")
                }
            }

            extension Person: SurrealModel {
            }
            """,
            macros: testMacros
        )
    }

    func testSelectExpansion() {
        assertMacroExpansion(
            "#select(Person.self)",
            expandedSource: "SurrealDSL.select(Person.self)",
            macros: testMacros
        )
    }
}
