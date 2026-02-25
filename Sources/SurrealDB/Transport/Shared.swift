import Foundation
import Network

@available(macOS 10.15, *)
public enum ConnectionState {
    case idle
    case connecting
    case connected
    case disconnecting
    case disconnected(code: URLSessionWebSocketTask.CloseCode?, reason: String?)
    case failed(Error)
    case reconnecting(attempt: Int)
}

public enum TransportKind {
    case websocket
    case http
}
