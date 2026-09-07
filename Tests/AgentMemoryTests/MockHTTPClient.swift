import Foundation
@testable import AgentMemory

#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

final class MockHTTPClient: HTTPClient, @unchecked Sendable {
    struct Recorded: Sendable {
        let method: String
        let url: URL
        let headers: [String: String]
        let body: Data?
    }

    struct Response {
        let status: Int
        let body: Data
        let headers: [String: String]

        init(status: Int = 200, body: Data = Data(), headers: [String: String] = [:]) {
            self.status = status; self.body = body; self.headers = headers
        }

        static func json(_ object: Any, status: Int = 200, headers: [String: String] = [:]) -> Response {
            let data = try! JSONSerialization.data(withJSONObject: object, options: [])
            return Response(status: status, body: data, headers: headers)
        }

        static func text(_ s: String, status: Int = 200, headers: [String: String] = [:]) -> Response {
            Response(status: status, body: s.data(using: .utf8) ?? Data(), headers: headers)
        }
    }

    private let lock = NSRecursiveLock()
    private var responses: [Response] = []
    private var _recorded: [Recorded] = []

    private func withLock<T>(_ body: () -> T) -> T {
        lock.lock()
        defer { lock.unlock() }
        return body()
    }

    func enqueue(_ response: Response) {
        withLock { responses.append(response) }
    }

    func enqueueMany(_ rs: [Response]) {
        withLock { responses.append(contentsOf: rs) }
    }

    var recorded: [Recorded] {
        withLock { _recorded }
    }

    var callCount: Int {
        withLock { _recorded.count }
    }

    func data(for request: URLRequest) async throws -> (Data, URLResponse) {
        let record = Recorded(
            method: request.httpMethod ?? "GET",
            url: request.url!,
            headers: request.allHTTPHeaderFields ?? [:],
            body: request.httpBody
        )
        let next: Response? = withLock {
            _recorded.append(record)
            if responses.isEmpty { return nil }
            return responses.removeFirst()
        }
        guard let next = next else {
            throw URLError(.cannotFindHost)
        }
        let http = HTTPURLResponse(
            url: request.url!,
            statusCode: next.status,
            httpVersion: "HTTP/1.1",
            headerFields: next.headers
        )!
        return (next.body, http)
    }
}
