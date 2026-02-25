import Foundation

public struct SurrealOptions {
    public var database: String?
    public var namespace: String?
    public let renewAccess: Bool?
    
    public init(namespace: String? = nil, database: String? = nil, renewAccess: Bool? = true) {
        self.namespace = namespace
        self.database = database
        self.renewAccess = renewAccess
    }
}

@available(macOS 10.15, *)
public final class Surreal {
    private var transport: Transport

    public let state: ConnectionState?
    public var options: SurrealOptions
    
    public init?(host: String, public options: SurrealOptions = .init()) {
        guard
            let url = URL(string: host),
            let scheme = url.scheme,
            scheme == "ws" || scheme == "wss"
        else { return nil }
        
        self.options = options
        
        let transport = SurrealWS()
        self.transport = transport
        
        self.state = nil
    }
    
    public func use(namespace: String? = nil, database: String? = nil) async {
        if ((namespace) != nil) { self.options.namespace = namespace}
        if ((database) != nil) { self.options.database = database}
    }
    
    public func query(query: String, params: [String: SurrealValue] = [:]) async {
        await self.transport.query(query: query, params: params)
    }
    
    public func close() {
        
    }
}
