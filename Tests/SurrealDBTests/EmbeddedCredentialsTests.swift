import Foundation
import Testing
@testable import SurrealDB

private func payload(_ credentials: SignInCredentials, context: SessionContext = .init()) throws -> SurrealValue {
    try credentials.payload(using: context)
}

@Test
func embeddedCredentials_resolvesRootScope() throws {
    let resolved = try EmbeddedCredentials.resolveSignIn(
        payload(.root(username: "root", password: "root"))
    )
    #expect(resolved.scope == .root)
    #expect(resolved.username == "root")
    #expect(resolved.password == "root")
    #expect(resolved.namespace == nil)
    #expect(resolved.database == nil)
}

@Test
func embeddedCredentials_resolvesNamespaceScope() throws {
    let resolved = try EmbeddedCredentials.resolveSignIn(
        payload(.namespace(namespace: "test", username: "u", password: "p"))
    )
    #expect(resolved.scope == .namespace)
    #expect(resolved.namespace == "test")
    #expect(resolved.database == nil)
}

@Test
func embeddedCredentials_resolvesDatabaseScope() throws {
    let resolved = try EmbeddedCredentials.resolveSignIn(
        payload(.database(namespace: "ns", database: "db", username: "u", password: "p"))
    )
    #expect(resolved.scope == .database)
    #expect(resolved.namespace == "ns")
    #expect(resolved.database == "db")
}

@Test
func embeddedCredentials_resolvesRecordScopeFromAccessVariables() throws {
    let resolved = try EmbeddedCredentials.resolveSignIn(
        payload(.accessVariables(
            namespace: "ns",
            database: "db",
            access: "user",
            variables: ["email": .string("ada@example.com")]
        ))
    )
    #expect(resolved.scope == .record)
    #expect(resolved.access == "user")
    #expect(resolved.namespace == "ns")
    #expect(resolved.database == "db")
    #expect(resolved.variables == ["email": .string("ada@example.com")])
}

@Test
func embeddedCredentials_rejectsBearerAccess() throws {
    // sr_signin only ever builds a record-access request, so bearer sign-in has
    // no embedded representation.
    #expect(throws: SurrealError.self) {
        _ = try EmbeddedCredentials.resolveSignIn(
            payload(.accessBearer(namespace: "ns", database: "db", access: "api", key: "secret"))
        )
    }
}

@Test
func embeddedCredentials_rejectsNonObjectPayload() {
    #expect(throws: SurrealError.self) {
        _ = try EmbeddedCredentials.resolveSignIn(.string("nope"))
    }
}

@Test
func embeddedCredentials_rejectsPayloadWithoutCredentialsOrAccess() {
    #expect(throws: SurrealError.self) {
        _ = try EmbeddedCredentials.resolveSignIn(.object(["user": .string("only")]))
    }
}

@Test
func embeddedCredentials_signUpAlwaysResolvesRecordScope() throws {
    let resolved = try EmbeddedCredentials.resolveSignUp(
        try SignUpCredentials
            .accessRecord(namespace: "ns", database: "db", access: "user", variables: ["email": .string("a@b.c")])
            .payload(using: .init())
    )
    #expect(resolved.scope == .record)
    #expect(resolved.access == "user")
    #expect(resolved.variables == ["email": .string("a@b.c")])
}

@Test
func embeddedCredentials_signUpRequiresNamespaceDatabaseAndAccess() {
    for incomplete: [String: SurrealValue] in [
        ["ns": .string("ns"), "db": .string("db")],
        ["ac": .string("user"), "db": .string("db")],
        ["ac": .string("user"), "ns": .string("ns")],
    ] {
        #expect(throws: SurrealError.self) {
            _ = try EmbeddedCredentials.resolveSignUp(.object(incomplete))
        }
    }
}

@Test
func embeddedError_classifiesTheCasesThatChangeBehaviour() {
    func kind(_ message: String) -> ServerErrorKind {
        let error = EmbeddedErrorMapping.rpcError(message: message, code: -2)
        return ServerErrorKind.parse(kind: error.kind, details: error.details, code: error.code)
    }

    #expect(kind("There was a read or write conflict").isTransactionConflict)
    #expect(kind("IAM error: Not enough permissions").isInvalidAuth)
    #expect(kind("The table 'x' does not exist").isNotFound)
    #expect(kind("The database 'x' already exists").isAlreadyExists)
}

@Test
func embeddedError_fallsBackToInternalForUnrecognisedMessages() {
    let error = EmbeddedErrorMapping.rpcError(message: "something entirely new", code: -2)
    #expect(error.kind == nil)
    #expect(error.details == nil)
    #expect(ServerErrorKind.parse(kind: error.kind, details: error.details, code: error.code) == .internalError)
}
