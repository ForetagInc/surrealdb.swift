import Foundation
import Network

@available(macOS 10.15, *)
public final class SurrealWS: NSObject, Transport {
    private let url: URL
    private var options: Options
    private let session: URLSession
    private var task: URLSessionWebSocketTask?
    
    private var reconnectAttempt = 0
    
    private let queue = DispatchQueue(label: "surreal.ws.client.queue", qos: .userInitiated)
    
    private let encoder: JSONEncoder = {
        let e = JSONEncoder()
        e.outputFormatting = [.withoutEscapingSlashes]
        return e
    }()
    
    private let decoder = JSONDecoder()
    
    private var state: ConnectionState = .idle {
        didSet { onStateChange?(state) }
    }
    
    public enum ClientError: Error, LocalizedError {
        case notConnected
        case requestTimeout
        case invalidResponse
        case serverError(code: Int?, message: String)
        case decodeError(String)
        
        public var errorDescription: String? {
            switch self {
            case .notConnected: return "WebSocket is not connected."
            case .invalidResponse: return "Received an invalid response."
            case .requestTimeout: return "Request timeed out."
            case .serverError(let code, let message): return "Server error\(code.map { " (\($0))" } ?? ""): \(message)"
            case .decodeError(let msg): return "Decode error: \(msg)"
            }
        }
    }
    
    public struct Options {
        public var connectTimeout: TimeInterval = 10
        public var requestTimeout: TimeInterval = 20
        public var reconnect: Bool = true
        public var reconnectBaseDelay: TimeInterval = 0.5
        public var reconnectMaxDelay: TimeInterval = 8
        public var maxReconnectAttempts: Int = 10
        public var pingInterval: TimeInterval = 25
        
        public init() {}
    }
    
    public enum JSONValue: Codable, Equatable {
        case null
        case bool(Bool)
        case number(Double)
        case string(String)
        case array([JSONValue])
        case object([String: JSONValue])
        
        public init(from decoder: Decoder) throws {
            let c = try decoder.singleValueContainer()
            if c.decodeNil() { self = .null; return }
            if let b = try? c.decode(Bool.self) { self = .bool(b); return }
            if let n = try? c.decode(Double.self) { self = .number(n); return }
            if let s = try? c.decode(String.self) { self = .string(s); return }
            if let a = try? c.decode([JSONValue].self) { self = .array(a); return }
            if let o = try? c.decode([String: JSONValue].self) { self = .object(o); return }
            throw ClientError.decodeError("Unsupported JSON type")
        }
        
        public func encode(to encoder: Encoder) throws {
            var c = encoder.singleValueContainer()
            switch self {
            case .null: try c.encodeNil()
            case .bool(let b): try c.encode(b)
            case .number(let n): try c.encode(n)
            case .string(let s): try c.encode(s)
            case .array(let a): try c.encode(a)
            case .object(let o): try c.encode(o)
            }
        }
        
        public var stringValue: String? { if case .string(let s) = self { return s } else { return nil } }
        public var objectValue: [String: JSONValue]? { if case .object(let o) = self { return o } else { return nil } }
        public var arrayValue: [JSONValue]? { if case .array(let a) = self { return a } else { return nil } }
    }
    
    public struct NotificationMessage: Codable {
        public let id: String?
        public let method: String?
        public let params: [JSONValue]?
        public let result: JSONValue?
    }
    
    public var onStateChange: ((ConnectionState) -> Void)?
    public var onTextMessage: ((String) -> Void)?
    public var onBinaryMessage: ((Data) -> Void)?
    public var onNotification: ((NotificationMessage) -> Void)?
    public var onError: ((Error) -> Void)?
    
    public func connect(headers: [String: String] = [:]) {
        queue.async {
            guard self.task == nil else { return }
            
            self.state = .connecting
            var request = URLRequest(url: self.url, timeoutInterval: self.options.connectTimeout)
            
            headers.forEach {
                request.setValue($0.value, forHTTPHeaderField: $0.key)
            }
            
            let task = self.session.webSocketTask(with: request)
            self.task = task
            task.resume()
            
            self.reconnectAttempt = 0
            self.state = .connected
        }
    }
}
