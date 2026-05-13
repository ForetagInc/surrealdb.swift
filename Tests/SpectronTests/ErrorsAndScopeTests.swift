import Foundation
import XCTest
@testable import Spectron

final class ErrorsAndScopeTests: XCTestCase {
    func testSerialiseScopeRoundTrip() {
        let payload = Scope.serialise(["org": "anneal", "user": "tobie"])
        XCTAssertNotNil(payload)
        let pairs = Set(payload!.map { Pair(key: $0["key"]!, value: $0["value"]!) })
        XCTAssertEqual(pairs, [Pair(key: "org", value: "anneal"), Pair(key: "user", value: "tobie")])
        XCTAssertEqual(Scope.deserialise(payload), ["org": "anneal", "user": "tobie"])
    }

    func testSerialiseScopeNonePassthrough() {
        XCTAssertNil(Scope.serialise(nil))
        XCTAssertEqual(Scope.deserialise(nil), [:])
    }

    func testErrorFromResponseStatusMapping() {
        let cases: [(Int, SpectronError.Kind)] = [
            (400, .validation),
            (401, .auth),
            (403, .scope),
            (404, .notFound),
            (422, .validation),
            (429, .rateLimit),
            (500, .server),
            (502, .server),
            (418, .base)
        ]
        for (status, expected) in cases {
            let body: JSONValue = .object([
                "title": .string("boom"),
                "detail": .string("kaboom"),
                "type": .string("https://example"),
                "extra": .string("ext")
            ])
            let err = SpectronErrorFactory.fromResponse(status: status, body: body, headers: [:])
            XCTAssertEqual(err.kind, expected, "status \(status)")
            XCTAssertEqual(err.status, status)
            XCTAssertEqual(err.title, "boom")
            XCTAssertEqual(err.detail, "kaboom")
            XCTAssertEqual(err.typeURI, "https://example")
            XCTAssertEqual(err.extensions["extra"], .string("ext"))
        }
    }

    func testRateLimitPicksUpRetryAfter() {
        let err = SpectronErrorFactory.fromResponse(
            status: 429,
            body: .object(["title": .string("slow down")]),
            headers: ["Retry-After": "12.5"]
        )
        XCTAssertEqual(err.kind, .rateLimit)
        XCTAssertEqual(err.retryAfter, 12.5)
    }

    func testErrorFromResponseFallsBackForNonDictBodies() {
        let err = SpectronErrorFactory.fromResponse(
            status: 500,
            body: .string("internal explosion"),
            headers: [:]
        )
        XCTAssertEqual(err.kind, .server)
        XCTAssertEqual(err.detail, "internal explosion")
    }

    func testBackoffScheduleCapped() {
        XCTAssertEqual(Retry.backoffSchedule(maxRetries: 0), [])
        XCTAssertEqual(Retry.backoffSchedule(maxRetries: 1), [0.25])
        XCTAssertEqual(Retry.backoffSchedule(maxRetries: 2), [0.25, 0.5])
        XCTAssertEqual(Retry.backoffSchedule(maxRetries: 3), [0.25, 0.5, 1.0])
        XCTAssertEqual(Retry.backoffSchedule(maxRetries: 10), [0.25, 0.5, 1.0])
    }

    func testShouldRetryRules() {
        XCTAssertTrue(Retry.shouldRetry(method: "GET", status: 503, attempt: 0, maxRetries: 3))
        XCTAssertTrue(Retry.shouldRetry(method: "GET", status: nil, attempt: 0, maxRetries: 3))
        XCTAssertFalse(Retry.shouldRetry(method: "POST", status: 503, attempt: 0, maxRetries: 3))
        XCTAssertFalse(Retry.shouldRetry(method: "GET", status: 400, attempt: 0, maxRetries: 3))
        XCTAssertFalse(Retry.shouldRetry(method: "GET", status: 503, attempt: 3, maxRetries: 3))
    }

    private struct Pair: Hashable {
        let key: String
        let value: String
    }
}
