import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

public protocol HTTPClient: Sendable {
    func data(for request: URLRequest) async throws -> (Data, URLResponse)
}

extension URLSession: HTTPClient {}

public actor SpectronTransport {
    public static let defaultTimeout: TimeInterval = 30
    public static let defaultMaxRetries: Int = 3
    public static let userAgent = "surrealdb-swift-spectron/1.0"

    public let endpoint: String
    public let apiKey: String
    public let timeout: TimeInterval
    public let maxRetries: Int

    private let client: any HTTPClient
    private let sleeper: @Sendable (TimeInterval) async -> Void

    public init(
        endpoint: String,
        apiKey: String,
        timeout: TimeInterval = SpectronTransport.defaultTimeout,
        maxRetries: Int = SpectronTransport.defaultMaxRetries,
        client: (any HTTPClient)? = nil,
        sleeper: (@Sendable (TimeInterval) async -> Void)? = nil
    ) throws {
        guard !endpoint.isEmpty else {
            throw SpectronError(kind: .base, status: 0, title: "Spectron endpoint is required.")
        }
        guard !apiKey.isEmpty else {
            throw SpectronError(kind: .base, status: 0, title: "Spectron API key is required.")
        }
        var ep = endpoint
        while ep.hasSuffix("/") { ep.removeLast() }
        self.endpoint = ep
        self.apiKey = apiKey
        self.timeout = timeout
        self.maxRetries = maxRetries
        if let client = client {
            self.client = client
        } else {
            let config = URLSessionConfiguration.ephemeral
            config.timeoutIntervalForRequest = timeout
            self.client = URLSession(configuration: config)
        }
        if let sleeper = sleeper {
            self.sleeper = sleeper
        } else {
            self.sleeper = { seconds in
                try? await Task.sleep(nanoseconds: UInt64(seconds * 1_000_000_000))
            }
        }
    }

    // MARK: - URL building / encoding

    public static func quotePath(_ value: String) -> String {
        var allowed = CharacterSet.alphanumerics
        allowed.insert(charactersIn: "-._~")
        return value.addingPercentEncoding(withAllowedCharacters: allowed) ?? value
    }

    private func buildURL(path: String, query: [URLQueryItem]?) throws -> URL {
        let urlString: String
        if path.hasPrefix("http://") || path.hasPrefix("https://") {
            urlString = path
        } else {
            let suffix = path.hasPrefix("/") ? path : "/" + path
            urlString = endpoint + suffix
        }
        guard var components = URLComponents(string: urlString) else {
            throw SpectronError(kind: .base, status: 0, title: "Invalid URL", detail: urlString)
        }
        if let query = query, !query.isEmpty {
            components.queryItems = query
        }
        guard let url = components.url else {
            throw SpectronError(kind: .base, status: 0, title: "Invalid URL", detail: urlString)
        }
        return url
    }

    private func headers(contentType: String?, extra: [String: String]?) -> [String: String] {
        var headers: [String: String] = [
            "Authorization": "Bearer \(apiKey)",
            "Accept": "application/json",
            "User-Agent": SpectronTransport.userAgent
        ]
        if let contentType { headers["Content-Type"] = contentType }
        if let extra {
            for (k, v) in extra { headers[k] = v }
        }
        return headers
    }

    // MARK: - Core request

    @discardableResult
    public func request(
        method: String,
        path: String,
        query: [URLQueryItem]? = nil,
        jsonBody: Data? = nil,
        rawBody: Data? = nil,
        contentType: String? = nil,
        extraHeaders: [String: String]? = nil,
        timeoutOverride: TimeInterval? = nil
    ) async throws -> (Data, JSONValue?) {
        let url = try buildURL(path: path, query: query)
        let methodUpper = method.uppercased()
        var resolvedContentType: String? = contentType
        if jsonBody != nil, resolvedContentType == nil {
            resolvedContentType = "application/json"
        }
        if rawBody != nil, contentType == nil, jsonBody == nil {
            resolvedContentType = nil // multipart caller should pass explicit content type
        }
        let allHeaders = headers(contentType: resolvedContentType, extra: extraHeaders)

        var attempt = 0
        let schedule = Retry.backoffSchedule(maxRetries: maxRetries)

        while true {
            var req = URLRequest(url: url, timeoutInterval: timeoutOverride ?? timeout)
            req.httpMethod = methodUpper
            for (k, v) in allHeaders {
                req.setValue(v, forHTTPHeaderField: k)
            }
            if let jsonBody = jsonBody {
                req.httpBody = jsonBody
            } else if let rawBody = rawBody {
                req.httpBody = rawBody
            }

            let data: Data
            let response: URLResponse
            do {
                (data, response) = try await client.data(for: req)
            } catch {
                if Retry.shouldRetry(method: methodUpper, status: nil, attempt: attempt, maxRetries: maxRetries) {
                    await sleeper(schedule[attempt])
                    attempt += 1
                    continue
                }
                throw SpectronErrorFactory.connectionFailed(error)
            }

            guard let http = response as? HTTPURLResponse else {
                throw SpectronError(kind: .base, status: 0, title: "Invalid response", detail: "Expected HTTPURLResponse")
            }
            let status = http.statusCode

            if status >= 400 && Retry.shouldRetry(method: methodUpper, status: status, attempt: attempt, maxRetries: maxRetries) {
                await sleeper(schedule[attempt])
                attempt += 1
                continue
            }

            if status >= 400 {
                let body = decodeJSON(data)
                var headerDict: [String: String] = [:]
                for (k, v) in http.allHeaderFields {
                    if let ks = k as? String, let vs = v as? String {
                        headerDict[ks] = vs
                    }
                }
                throw SpectronErrorFactory.fromResponse(status: status, body: body, headers: headerDict)
            }

            if status == 204 || data.isEmpty {
                return (data, nil)
            }
            return (data, decodeJSON(data))
        }
    }

    // MARK: - Convenience verbs (decoded)

    public func get<T: Decodable>(_ path: String, query: [URLQueryItem]? = nil, as: T.Type) async throws -> T {
        let (data, _) = try await request(method: "GET", path: path, query: query)
        return try decode(T.self, from: data)
    }

    public func getOptional<T: Decodable>(_ path: String, query: [URLQueryItem]? = nil, as: T.Type) async throws -> T? {
        let (data, _) = try await request(method: "GET", path: path, query: query)
        if data.isEmpty { return nil }
        return try decode(T.self, from: data)
    }

    public func postJSON<Body: Encodable, T: Decodable>(_ path: String, body: Body, as: T.Type) async throws -> T {
        let data = try encode(body)
        let (resp, _) = try await request(method: "POST", path: path, jsonBody: data)
        return try decode(T.self, from: resp)
    }

    public func postJSON<Body: Encodable>(_ path: String, body: Body) async throws {
        let data = try encode(body)
        _ = try await request(method: "POST", path: path, jsonBody: data)
    }

    public func postRawJSON(_ path: String, jsonData: Data) async throws -> JSONValue? {
        let (_, json) = try await request(method: "POST", path: path, jsonBody: jsonData)
        return json
    }

    public func putRawJSON(_ path: String, jsonData: Data) async throws -> JSONValue? {
        let (_, json) = try await request(method: "PUT", path: path, jsonBody: jsonData)
        return json
    }

    public func delete(_ path: String) async throws {
        _ = try await request(method: "DELETE", path: path)
    }

    public func uploadMultipart(_ path: String, method: String = "POST", body: Data, contentType: String) async throws -> (Data, JSONValue?) {
        try await request(method: method, path: path, rawBody: body, contentType: contentType)
    }

    public func rawBytes(_ path: String) async throws -> Data {
        let (data, _) = try await request(method: "GET", path: path)
        return data
    }

    // MARK: - Codec helpers

    public func encode<T: Encodable>(_ value: T) throws -> Data {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.withoutEscapingSlashes]
        return try encoder.encode(value)
    }

    /// Encodes any `Encodable` value into a `JSONValue` so it can be embedded
    /// in a manually-assembled request payload.
    public func jsonValue<T: Encodable>(_ value: T) throws -> JSONValue {
        let data = try encode(value)
        return try JSONDecoder().decode(JSONValue.self, from: data)
    }

    public func decode<T: Decodable>(_ type: T.Type, from data: Data) throws -> T {
        let decoder = JSONDecoder()
        do {
            return try decoder.decode(T.self, from: data)
        } catch {
            throw SpectronError(
                kind: .base,
                status: 0,
                title: "Failed to decode response",
                detail: String(describing: error)
            )
        }
    }

    private func decodeJSON(_ data: Data) -> JSONValue? {
        if data.isEmpty { return nil }
        let decoder = JSONDecoder()
        if let value = try? decoder.decode(JSONValue.self, from: data) {
            return value
        }
        if let s = String(data: data, encoding: .utf8) {
            return .string(s)
        }
        return nil
    }
}

// MARK: - Multipart form helpers

public struct MultipartForm: Sendable {
    public let boundary: String
    public private(set) var body: Data

    public init(boundary: String = "spectron-\(UUID().uuidString)") {
        self.boundary = boundary
        self.body = Data()
    }

    public var contentType: String {
        "multipart/form-data; boundary=\(boundary)"
    }

    public mutating func appendField(_ name: String, value: String) {
        appendBoundary()
        appendLine("Content-Disposition: form-data; name=\"\(name)\"")
        appendLine("")
        appendLine(value)
    }

    public mutating func appendJSONField(_ name: String, jsonData: Data) {
        appendBoundary()
        appendLine("Content-Disposition: form-data; name=\"\(name)\"")
        appendLine("Content-Type: application/json")
        appendLine("")
        body.append(jsonData)
        appendLine("")
    }

    public mutating func appendFile(_ name: String, filename: String?, mimeType: String?, data: Data) {
        appendBoundary()
        let fname = filename ?? "upload"
        appendLine("Content-Disposition: form-data; name=\"\(name)\"; filename=\"\(fname)\"")
        appendLine("Content-Type: \(mimeType ?? "application/octet-stream")")
        appendLine("")
        body.append(data)
        appendLine("")
    }

    public mutating func finalize() -> Data {
        body.append("--\(boundary)--\r\n".data(using: .utf8)!)
        return body
    }

    private mutating func appendBoundary() {
        body.append("--\(boundary)\r\n".data(using: .utf8)!)
    }

    private mutating func appendLine(_ line: String) {
        body.append((line + "\r\n").data(using: .utf8)!)
    }
}

// MARK: - File payload

public enum SpectronFile: Sendable {
    case data(Data, filename: String?, mimeType: String?)
    case fileURL(URL, filename: String?, mimeType: String?)

    public func read() throws -> (Data, String?, String?) {
        switch self {
        case .data(let d, let f, let m):
            return (d, f, m)
        case .fileURL(let url, let f, let m):
            let data = try Data(contentsOf: url)
            return (data, f ?? url.lastPathComponent, m)
        }
    }
}
