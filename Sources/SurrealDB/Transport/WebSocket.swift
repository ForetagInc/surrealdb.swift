import Foundation

public protocol WebSocketClientDelegate: AnyObject {
    
}

@available(macOS 10.15, *)
public final class SurrealWS: NSObject {
    private let url: URL
    private let session: URLSession
    
    public init(
        url: URL,
        configuration: URLSessionConfiguration = .default,
        delegate: WebSocketClientDelegate? = nil
    ) {
        self.url = url
        self.session = URLSession(configuration: configuration)
        
        super.init()
    }
    
    deinit {
        disconnect()
    }
}

public enum WebSocketClientError: Error, LocalizedError {
    case notConnected
    case closed
    case invalidResponse
    case timeout
    
    public var errorDescription: String? {
        switch self {
        case .notConnected: return "WebSocket is not connected."
        case .closed: return "WebSocket is closed."
        case .invalidResponse: return "Received an invalid response."
        case .timeout: return "Request timeed out."
        }
    }
}
