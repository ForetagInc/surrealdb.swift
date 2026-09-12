import Foundation
import Testing
@testable import SurrealDB

@Test
func embeddedEnvelope_queryResponseIsAcceptedByRPCWireDecoder() throws {
    let response = EmbeddedEnvelope.queryResponse(
        id: "1",
        statements: [
            EmbeddedStatementResult(values: [.int(1)]),
            EmbeddedStatementResult(values: [], errorMessage: "boom"),
        ],
        elapsed: .milliseconds(3)
    )

    let decoded = try RPCWire.decodeQueryResults(from: try #require(response.result))
    #expect(decoded.count == 2)
    #expect(decoded[0].status == .ok)
    #expect(decoded[1].status == .err)
    #expect(decoded.allSatisfy { !$0.time.isEmpty })
}

@Test
func embeddedEnvelope_errorStatementBecomesERRRowWithStringResult() throws {
    let response = EmbeddedEnvelope.queryResponse(
        id: "1",
        statements: [EmbeddedStatementResult(values: [], errorMessage: "read or write conflict")],
        elapsed: .milliseconds(1)
    )

    let decoded = try RPCWire.decodeQueryResults(from: try #require(response.result))
    #expect(decoded[0].result == .string("read or write conflict"))

    let detail = QueryErrorDetail(
        index: 0,
        message: "read or write conflict",
        kind: decoded[0].kind,
        details: decoded[0].details
    )
    #expect(detail.typedKind.isTransactionConflict)
}

@Test
func embeddedEnvelope_unwrapsSingleUnitResults() {
    // `sr_query` wraps a unit statement result as `[NONE]`; leaving it wrapped
    // makes ClientCore try to decode NONE into the caller's model.
    #expect(EmbeddedEnvelope.unwrapSingleUnit([.none]) == .none)
    #expect(EmbeddedEnvelope.unwrapSingleUnit([.null]) == .null)
}

@Test
func embeddedEnvelope_keepsEverythingElseWrapped() {
    #expect(EmbeddedEnvelope.unwrapSingleUnit([]) == .array([]))
    #expect(EmbeddedEnvelope.unwrapSingleUnit([.int(1)]) == .array([.int(1)]))
    #expect(EmbeddedEnvelope.unwrapSingleUnit([.none, .none]) == .array([.none, .none]))
}

@Test
func embeddedEnvelope_echoesRequestID() {
    #expect(EmbeddedEnvelope.ok(id: "abc", result: .null).id == "abc")
    #expect(EmbeddedEnvelope.failure(id: "abc", message: "x", code: -2).id == "abc")
    #expect(EmbeddedEnvelope.queryResponse(id: "abc", statements: [], elapsed: .zero).id == "abc")
}

@Test
func embeddedEnvelope_formatsDurationLikeSurrealDB() {
    #expect(EmbeddedEnvelope.formatDuration(.nanoseconds(412)) == "412ns")
    #expect(EmbeddedEnvelope.formatDuration(.microseconds(87)) == "87µs")
    #expect(EmbeddedEnvelope.formatDuration(.milliseconds(2)) == "2ms")
    #expect(EmbeddedEnvelope.formatDuration(.seconds(3)) == "3s")
}

@Test
func surrealDuration_parsesSimpleAndCompoundForms() throws {
    #expect(try SurrealDuration.parse("500ms") == (0, 500_000_000))
    #expect(try SurrealDuration.parse("100ns") == (0, 100))
    #expect(try SurrealDuration.parse("2µs") == (0, 2_000))
    #expect(try SurrealDuration.parse("2us") == (0, 2_000))
    #expect(try SurrealDuration.parse("1h30m").seconds == 5_400)
    #expect(try SurrealDuration.parse("1y2w3d").seconds == (365 + 14 + 3) * 24 * 60 * 60)
}

@Test
func surrealDuration_formatRoundTrips() throws {
    for text in ["1h30m", "500ms", "100ns", "1y2w3d", "45s", "2ms500µs"] {
        let parsed = try SurrealDuration.parse(text)
        let rendered = SurrealDuration.format(seconds: parsed.seconds, nanoseconds: parsed.nanoseconds)
        let reparsed = try SurrealDuration.parse(rendered)
        #expect(reparsed == parsed, "\(text) rendered as \(rendered)")
    }
}

@Test
func surrealDuration_rejectsUnparseableInput() {
    for text in ["", "abc", "10", "10x", "1h30"] {
        #expect(throws: SurrealDuration.ParseError.self, "\(text) should not parse") {
            _ = try SurrealDuration.parse(text)
        }
    }
}

@Test
func surrealRFC3339_parsesWithAndWithoutFractionalSeconds() {
    // surrealdb-core uses SecondsFormat::AutoSi, so 0/3/6/9 digits all occur.
    let expected = Date(timeIntervalSince1970: 1_705_314_600)
    for text in ["2024-01-15T10:30:00Z", "2024-01-15T10:30:00.000Z",
                 "2024-01-15T10:30:00.000000Z", "2024-01-15T10:30:00.000000000Z"] {
        let parsed = SurrealRFC3339.date(from: text)
        #expect(parsed != nil, "\(text) should parse")
        #expect(abs((parsed ?? .distantPast).timeIntervalSince(expected)) < 0.001, "\(text)")
    }
}

@Test
func surrealRFC3339_roundTripsDate() {
    let date = Date(timeIntervalSince1970: 1_700_000_000.25)
    let parsed = SurrealRFC3339.date(from: SurrealRFC3339.string(from: date))
    #expect(abs((parsed ?? .distantPast).timeIntervalSince(date)) < 0.001)
}
