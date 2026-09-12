import Foundation

/// The authentication scope `sr_signin` / `sr_signup` take, mirrored in Swift
/// so credential resolution stays testable without the native library.
enum EmbeddedCredentialScope: Sendable, Equatable {
    case root
    case namespace
    case database
    case record
}

/// A `signin`/`signup` payload destructured into the arguments the C API wants.
struct EmbeddedAuthRequest: Sendable, Equatable {
    let scope: EmbeddedCredentialScope
    let username: String?
    let password: String?
    let namespace: String?
    let database: String?
    let access: String?
    let variables: [String: SurrealValue]
}

/// Turns the flat `.object` payload that `SignInCredentials`/`SignUpCredentials`
/// produce back into a scope plus its arguments.
///
/// The wire payload is deliberately shapeless, since the server infers the scope
/// from which keys are present, so this mirrors that inference.
enum EmbeddedCredentials {
    static func resolveSignIn(_ payload: SurrealValue) throws -> EmbeddedAuthRequest {
        var fields = try object(from: payload)

        let namespace = takeString(&fields, "ns")
        let database = takeString(&fields, "db")
        let access = takeString(&fields, "ac")
        let username = takeString(&fields, "user")
        let password = takeString(&fields, "pass")

        if let access {
            // `.accessBearer` produces exactly {ac, key} plus optional ns/db.
            // `sr_signin` only ever builds a record-access request, so there is
            // no way to express a bearer sign-in through the C API.
            if fields.count == 1, fields["key"] != nil {
                throw SurrealError.unsupportedFeature(
                    "The embedded engine cannot sign in with bearer access; surrealdb.c exposes record access only."
                )
            }
            return EmbeddedAuthRequest(
                scope: .record,
                username: username,
                password: password,
                namespace: namespace,
                database: database,
                access: access,
                variables: fields
            )
        }

        guard let username, let password else {
            throw SurrealError.invalidCredentials(
                "The embedded engine needs either a username and password, or an access method."
            )
        }

        let scope: EmbeddedCredentialScope
        if database != nil {
            scope = .database
        } else if namespace != nil {
            scope = .namespace
        } else {
            scope = .root
        }

        return EmbeddedAuthRequest(
            scope: scope,
            username: username,
            password: password,
            namespace: namespace,
            database: database,
            access: nil,
            variables: [:]
        )
    }

    /// `sr_signup` supports record access only, and the C layer errors on an
    /// empty namespace, database or access name, so catch that here and give the
    /// caller a message that names the missing field.
    static func resolveSignUp(_ payload: SurrealValue) throws -> EmbeddedAuthRequest {
        var fields = try object(from: payload)

        let namespace = takeString(&fields, "ns")
        let database = takeString(&fields, "db")
        let access = takeString(&fields, "ac")
        let username = takeString(&fields, "user")
        let password = takeString(&fields, "pass")

        guard let access else {
            throw SurrealError.invalidCredentials("Sign-up on the embedded engine requires an access method.")
        }
        guard let namespace else {
            throw SurrealError.invalidCredentials("Sign-up on the embedded engine requires a namespace.")
        }
        guard let database else {
            throw SurrealError.invalidCredentials("Sign-up on the embedded engine requires a database.")
        }

        return EmbeddedAuthRequest(
            scope: .record,
            username: username,
            password: password,
            namespace: namespace,
            database: database,
            access: access,
            variables: fields
        )
    }

    private static func object(from payload: SurrealValue) throws -> [String: SurrealValue] {
        guard case .object(let fields) = payload else {
            throw SurrealError.invalidCredentials("Expected a credentials object.")
        }
        return fields
    }

    private static func takeString(_ fields: inout [String: SurrealValue], _ key: String) -> String? {
        guard case .string(let value)? = fields[key] else { return nil }
        fields.removeValue(forKey: key)
        return value
    }
}
