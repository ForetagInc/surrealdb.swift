import Foundation
import PotentCBOR
import Testing
@testable import SurrealDB

/// Unit tests for the typed server-error taxonomy (`ServerErrorKind`).
///
/// These construct fixture RPC error payloads (matching the wire shapes documented
/// against the SurrealDB server's `surrealdb_types::Error` snapshot tests) and assert
/// that parsing correctly discriminates between error categories/subcategories that
/// were previously only reachable via an undocumented, untyped `kind: String?`.
/// No live server is involved.

// MARK: - JSON envelope decoding (RPCErrorObject.typedKind)

@Test
func serverErrorKind_notAllowedAuthTokenExpired() throws {
    let json = """
    {
      "id": "1",
      "error": {
        "code": -32002,
        "message": "Token expired",
        "kind": "NotAllowed",
        "details": { "kind": "Auth", "details": { "kind": "TokenExpired" } }
      }
    }
    """
    let envelope = try JSONRPCCodec.decodeRPCEnvelope(Data(json.utf8))
    let kind = try #require(envelope.error?.typedKind)

    #expect(kind.isTokenExpired)
    #expect(!kind.isInvalidAuth)
    #expect(!kind.isSessionExpired)
    #expect(kind == .notAllowed(.auth(.tokenExpired)))
}

@Test
func serverErrorKind_notAllowedAuthInvalidAuth_isDistinctFromTokenExpired() throws {
    let json = """
    {
      "id": "1",
      "error": {
        "code": -32002,
        "message": "Invalid credentials",
        "kind": "NotAllowed",
        "details": { "kind": "Auth", "details": { "kind": "InvalidAuth" } }
      }
    }
    """
    let envelope = try JSONRPCCodec.decodeRPCEnvelope(Data(json.utf8))
    let kind = try #require(envelope.error?.typedKind)

    #expect(kind.isInvalidAuth)
    #expect(!kind.isTokenExpired)
}

@Test
func serverErrorKind_notAllowedAuthSessionExpired() throws {
    let json = """
    {
      "id": "1",
      "error": {
        "code": -32000,
        "message": "Session has expired",
        "kind": "NotAllowed",
        "details": { "kind": "Auth", "details": { "kind": "SessionExpired" } }
      }
    }
    """
    let envelope = try JSONRPCCodec.decodeRPCEnvelope(Data(json.utf8))
    let kind = try #require(envelope.error?.typedKind)

    #expect(kind.isSessionExpired)
    // SessionExpired is a distinct auth failure — not the generic invalid-auth bucket.
    #expect(!kind.isInvalidAuth)
    #expect(!kind.isTokenExpired)
}

@Test
func serverErrorKind_notAllowedScripting() throws {
    let json = """
    {
      "id": "1",
      "error": {
        "code": -32602,
        "message": "Scripting not allowed",
        "kind": "NotAllowed",
        "details": { "kind": "Scripting" }
      }
    }
    """
    let envelope = try JSONRPCCodec.decodeRPCEnvelope(Data(json.utf8))
    let kind = try #require(envelope.error?.typedKind)

    #expect(kind.isScriptingBlocked)
    #expect(kind == .notAllowed(.scripting))
}

@Test
func serverErrorKind_notAllowedMethod() throws {
    let json = """
    {
      "id": "1",
      "error": {
        "code": -32602,
        "message": "Method blocked",
        "kind": "NotAllowed",
        "details": { "kind": "Method", "details": { "name": "begin" } }
      }
    }
    """
    let envelope = try JSONRPCCodec.decodeRPCEnvelope(Data(json.utf8))
    let kind = try #require(envelope.error?.typedKind)

    #expect(kind == .notAllowed(.method(name: "begin")))
}

@Test
func serverErrorKind_notFoundTable_isNotFoundNotAlreadyExists() throws {
    let json = """
    {
      "id": "1",
      "error": {
        "code": -32000,
        "message": "The table 'users' does not exist",
        "kind": "NotFound",
        "details": { "kind": "Table", "details": { "name": "users" } }
      }
    }
    """
    let envelope = try JSONRPCCodec.decodeRPCEnvelope(Data(json.utf8))
    let kind = try #require(envelope.error?.typedKind)

    #expect(kind.isNotFound)
    #expect(!kind.isAlreadyExists)
    #expect(kind == .notFound(.table(name: "users")))
}

@Test
func serverErrorKind_notFoundRecord() throws {
    let json = """
    {
      "id": "1",
      "error": {
        "code": -32000,
        "message": "Record not found",
        "kind": "NotFound",
        "details": { "kind": "Record", "details": { "id": "person:jane" } }
      }
    }
    """
    let envelope = try JSONRPCCodec.decodeRPCEnvelope(Data(json.utf8))
    let kind = try #require(envelope.error?.typedKind)

    #expect(kind == .notFound(.record(id: "person:jane")))
}

@Test
func serverErrorKind_notFoundSession_withoutId() throws {
    // NotFoundError::Session { id: Option<String> } — no id provided.
    let json = """
    {
      "id": "1",
      "error": {
        "code": -32000,
        "message": "Session not found",
        "kind": "NotFound",
        "details": { "kind": "Session" }
      }
    }
    """
    let envelope = try JSONRPCCodec.decodeRPCEnvelope(Data(json.utf8))
    let kind = try #require(envelope.error?.typedKind)

    #expect(kind == .notFound(.session(id: nil)))
}

@Test
func serverErrorKind_alreadyExistsRecord_isAlreadyExistsNotNotFound() throws {
    let json = """
    {
      "id": "1",
      "error": {
        "code": -32000,
        "message": "Record exists",
        "kind": "AlreadyExists",
        "details": { "kind": "Record", "details": { "id": "users:123" } }
      }
    }
    """
    let envelope = try JSONRPCCodec.decodeRPCEnvelope(Data(json.utf8))
    let kind = try #require(envelope.error?.typedKind)

    #expect(kind.isAlreadyExists)
    #expect(!kind.isNotFound)
    #expect(kind == .alreadyExists(.record(id: "users:123")))
}

@Test
func serverErrorKind_queryTransactionConflict_isDistinctFromOtherQueryFailures() throws {
    let json = """
    {
      "id": "1",
      "error": {
        "code": -32009,
        "message": "Transaction conflict",
        "kind": "Query",
        "details": { "kind": "TransactionConflict" }
      }
    }
    """
    let envelope = try JSONRPCCodec.decodeRPCEnvelope(Data(json.utf8))
    let kind = try #require(envelope.error?.typedKind)

    #expect(kind.isTransactionConflict)
    #expect(!kind.isQueryTimedOut)
    #expect(!kind.isQueryCancelled)
}

@Test
func serverErrorKind_queryTimedOut_carriesDuration() throws {
    let json = """
    {
      "id": "1",
      "error": {
        "code": -32004,
        "message": "Query timed out",
        "kind": "Query",
        "details": { "kind": "TimedOut", "details": { "duration": { "secs": 30, "nanos": 0 } } }
      }
    }
    """
    let envelope = try JSONRPCCodec.decodeRPCEnvelope(Data(json.utf8))
    let kind = try #require(envelope.error?.typedKind)

    #expect(kind.isQueryTimedOut)
    #expect(!kind.isTransactionConflict)

    guard case .query(.some(.timedOut(let duration))) = kind else {
        Issue.record("Expected .query(.timedOut), got \(kind)")
        return
    }
    #expect(duration.seconds == 30)
    #expect(duration.nanoseconds == 0)
    #expect(duration.timeInterval == 30)
}

@Test
func serverErrorKind_queryNotExecutedAndCancelled_areNotTransactionConflicts() throws {
    for (kindDetail, expectNotExecuted, expectCancelled) in [
        ("NotExecuted", true, false),
        ("Cancelled", false, true),
    ] {
        let json = """
        {
          "id": "1",
          "error": {
            "code": -32000,
            "message": "boom",
            "kind": "Query",
            "details": { "kind": "\(kindDetail)" }
          }
        }
        """
        let envelope = try JSONRPCCodec.decodeRPCEnvelope(Data(json.utf8))
        let kind = try #require(envelope.error?.typedKind)

        #expect(!kind.isTransactionConflict)
        #expect((kind == .query(.notExecuted)) == expectNotExecuted)
        #expect((kind == .query(.cancelled)) == expectCancelled)
    }
}

@Test
func serverErrorKind_serializationDeserialization_isDistinctFromSerialization() throws {
    let json = """
    {
      "id": "1",
      "error": {
        "code": -32008,
        "message": "Failed to deserialize",
        "kind": "Serialization",
        "details": { "kind": "Deserialization" }
      }
    }
    """
    let envelope = try JSONRPCCodec.decodeRPCEnvelope(Data(json.utf8))
    let kind = try #require(envelope.error?.typedKind)

    #expect(kind.isDeserializationFailure)
    #expect(kind == .serialization(.deserialization))
}

@Test
func serverErrorKind_serializationWithoutDeserialization_isNotFalselyDeserialization() throws {
    // Regression guard for the double-wrap unwrap: SerializationError's own "Serialization"
    // variant name collides with the outer "Serialization" kind, but carries no nested
    // details. Naively unwrapping here would wrongly discard the detail.
    let json = """
    {
      "id": "1",
      "error": {
        "code": -32007,
        "message": "Failed to serialize",
        "kind": "Serialization",
        "details": { "kind": "Serialization" }
      }
    }
    """
    let envelope = try JSONRPCCodec.decodeRPCEnvelope(Data(json.utf8))
    let kind = try #require(envelope.error?.typedKind)

    #expect(!kind.isDeserializationFailure)
    #expect(kind == .serialization(.serialization))
}

@Test
func serverErrorKind_validationInvalidParameter() throws {
    let json = """
    {
      "id": "1",
      "error": {
        "code": -32600,
        "message": "Invalid parameter 'limit'",
        "kind": "Validation",
        "details": { "kind": "InvalidParameter", "details": { "name": "limit" } }
      }
    }
    """
    let envelope = try JSONRPCCodec.decodeRPCEnvelope(Data(json.utf8))
    let kind = try #require(envelope.error?.typedKind)

    #expect(kind == .validation(.invalidParameter(name: "limit")))
}

@Test
func serverErrorKind_configurationLiveQueryNotSupported() throws {
    let json = """
    {
      "id": "1",
      "error": {
        "code": -32604,
        "message": "Live queries not supported",
        "kind": "Configuration",
        "details": { "kind": "LiveQueryNotSupported" }
      }
    }
    """
    let envelope = try JSONRPCCodec.decodeRPCEnvelope(Data(json.utf8))
    let kind = try #require(envelope.error?.typedKind)

    #expect(kind == .configuration(.liveQueryNotSupported))
}

@Test
func serverErrorKind_internalNoDetails() throws {
    let json = """
    {
      "id": "1",
      "error": { "code": -32000, "message": "Unexpected", "kind": "Internal" }
    }
    """
    let envelope = try JSONRPCCodec.decodeRPCEnvelope(Data(json.utf8))
    let kind = try #require(envelope.error?.typedKind)

    #expect(kind == .internalError)
}

@Test
func serverErrorKind_unknownKindIsPreservedNotCoerced() throws {
    // Forward compatibility: a kind string this SDK doesn't recognize (e.g. from a
    // newer server) must not be silently misreported as some other category.
    let json = """
    {
      "id": "1",
      "error": { "code": -32000, "message": "boom", "kind": "SomeFutureKind" }
    }
    """
    let envelope = try JSONRPCCodec.decodeRPCEnvelope(Data(json.utf8))
    let kind = try #require(envelope.error?.typedKind)

    #expect(kind == .unknown("SomeFutureKind"))
    #expect(!kind.isNotFound)
    #expect(!kind.isTransactionConflict)
}

@Test
func serverErrorKind_missingKindDefaultsToInternal() throws {
    // Backwards compatibility: an old wire format with no "kind" field at all
    // (and no legacy code to derive one from) defaults to Internal.
    let json = """
    {
      "id": "1",
      "error": { "code": 0, "message": "Something went wrong" }
    }
    """
    let envelope = try JSONRPCCodec.decodeRPCEnvelope(Data(json.utf8))
    let kind = try #require(envelope.error?.typedKind)

    #expect(kind == .internalError)
}

@Test
func serverErrorKind_missingKindFallsBackToLegacyCode() throws {
    // A pre-taxonomy server might send only the legacy numeric code. -32004 was the
    // wire code for QUERY_TIMEDOUT before "kind" existed.
    let json = """
    {
      "id": "1",
      "error": { "code": -32004, "message": "Query timed out" }
    }
    """
    let envelope = try JSONRPCCodec.decodeRPCEnvelope(Data(json.utf8))
    let kind = try #require(envelope.error?.typedKind)

    #expect(kind == .query(nil))
}

@Test
func serverErrorKind_cause_isTypedIndependently() throws {
    let json = """
    {
      "id": "1",
      "error": {
        "code": -32000,
        "message": "Wrapped failure",
        "kind": "Internal",
        "cause": {
          "message": "Record not found",
          "kind": "NotFound",
          "details": { "kind": "Record", "details": { "id": "person:jane" } }
        }
      }
    }
    """
    let envelope = try JSONRPCCodec.decodeRPCEnvelope(Data(json.utf8))
    let error = try #require(envelope.error)
    let cause = try #require(error.cause)

    #expect(error.typedKind == .internalError)
    #expect(cause.typedKind == .notFound(.record(id: "person:jane")))
}

// MARK: - Double-wrap defensive unwrap (older server compatibility)

@Test
func serverErrorKind_unwrapsDoubleWrappedDetails() {
    // Older server versions (pre error-serialization fix) duplicated the outer kind
    // into the details payload for per-statement query result errors, e.g.
    // { kind: "Query", details: { kind: "Query", details: { kind: "TransactionConflict" } } }.
    // Current servers no longer produce this, but the SDK should still parse it
    // correctly for compatibility with older self-hosted instances.
    let doubleWrapped = SurrealValue.object([
        "kind": .string("Query"),
        "details": .object(["kind": .string("TransactionConflict")]),
    ])

    let kind = ServerErrorKind.parse(kind: "Query", details: doubleWrapped)
    #expect(kind.isTransactionConflict)
}

// MARK: - QueryErrorDetail (per-statement query result errors)

@Test
func queryErrorDetail_typedKind_discriminatesTransactionConflict() {
    let conflict = QueryErrorDetail(
        index: 0,
        message: "Resource busy",
        kind: "Query",
        details: .object(["kind": .string("TransactionConflict")])
    )
    let notExecuted = QueryErrorDetail(
        index: 1,
        message: "Not executed",
        kind: "Query",
        details: .object(["kind": .string("NotExecuted")])
    )

    #expect(conflict.typedKind.isTransactionConflict)
    #expect(!notExecuted.typedKind.isTransactionConflict)
}

@Test
func queryErrorDetail_defaultsKindToNilForBackwardCompatibility() {
    // The memberwise init still allows omitting `kind` so existing call sites that
    // only had `details` keep compiling.
    let detail = QueryErrorDetail(index: 0, message: "boom", details: nil)
    #expect(detail.kind == nil)
    #expect(detail.typedKind == .internalError)
}

// MARK: - SurrealError.serverErrorKind

@Test
func surrealError_serverErrorKind_extractsTypedKindFromServerError() {
    let error = SurrealError.serverError(
        RPCErrorObject(
            code: -32002,
            kind: "NotAllowed",
            message: "Token expired",
            details: .object(["kind": .string("Auth"), "details": .object(["kind": .string("TokenExpired")])]),
            cause: nil
        )
    )

    #expect(error.serverErrorKind?.isTokenExpired == true)
    #expect(error.recoverySuggestion == "Re-authenticate and retry.")
}

@Test
func surrealError_serverErrorKind_isNilForNonServerErrors() {
    #expect(SurrealError.timeout.serverErrorKind == nil)
    #expect(SurrealError.notConnected.serverErrorKind == nil)
}

@Test
func surrealError_recoverySuggestion_flagsTransactionConflictAsRetryable() {
    let error = SurrealError.serverError(
        RPCErrorObject(
            code: -32009,
            kind: "Query",
            message: "Transaction conflict",
            details: .object(["kind": .string("TransactionConflict")]),
            cause: nil
        )
    )

    #expect(error.serverErrorKind?.isTransactionConflict == true)
    #expect(error.recoverySuggestion == "Safe to retry: a concurrent transaction modified the same data.")
}

// MARK: - CBOR wire path (hand-written decoder, exercised independently of JSON's Codable synthesis)

@Test
func cborCodec_decodesNotAllowedAuthTokenExpiredError() throws {
    var authDetails = CBOR.Map()
    authDetails[.utf8String("kind")] = .utf8String("TokenExpired")

    var notAllowedDetails = CBOR.Map()
    notAllowedDetails[.utf8String("kind")] = .utf8String("Auth")
    notAllowedDetails[.utf8String("details")] = .map(authDetails)

    var errorMap = CBOR.Map()
    errorMap[.utf8String("code")] = CBORSurrealCodec.toCBOR(.int(-32002))
    errorMap[.utf8String("message")] = .utf8String("Token expired")
    errorMap[.utf8String("kind")] = .utf8String("NotAllowed")
    errorMap[.utf8String("details")] = .map(notAllowedDetails)

    var responseMap = CBOR.Map()
    responseMap[.utf8String("id")] = .utf8String("1")
    responseMap[.utf8String("error")] = .map(errorMap)

    let data = try CBORSerialization.data(from: .map(responseMap))
    let envelope = try CBORSurrealCodec.decodeRPCEnvelope(data)

    let kind = try #require(envelope.error?.typedKind)
    #expect(kind.isTokenExpired)
    #expect(envelope.error?.message == "Token expired")
}

@Test
func cborCodec_decodesAlreadyExistsTableError() throws {
    var tableDetails = CBOR.Map()
    tableDetails[.utf8String("name")] = .utf8String("users")

    var alreadyExistsDetails = CBOR.Map()
    alreadyExistsDetails[.utf8String("kind")] = .utf8String("Table")
    alreadyExistsDetails[.utf8String("details")] = .map(tableDetails)

    var errorMap = CBOR.Map()
    errorMap[.utf8String("code")] = CBORSurrealCodec.toCBOR(.int(-32000))
    errorMap[.utf8String("message")] = .utf8String("Table already exists")
    errorMap[.utf8String("kind")] = .utf8String("AlreadyExists")
    errorMap[.utf8String("details")] = .map(alreadyExistsDetails)

    var responseMap = CBOR.Map()
    responseMap[.utf8String("id")] = .utf8String("1")
    responseMap[.utf8String("error")] = .map(errorMap)

    let data = try CBORSerialization.data(from: .map(responseMap))
    let envelope = try CBORSurrealCodec.decodeRPCEnvelope(data)

    let kind = try #require(envelope.error?.typedKind)
    #expect(kind == .alreadyExists(.table(name: "users")))
    #expect(!kind.isNotFound)
}
