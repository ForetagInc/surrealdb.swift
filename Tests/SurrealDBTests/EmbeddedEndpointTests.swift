import Foundation
import Testing
@testable import SurrealDB

@Test
func endpoint_resolvesMemSchemeAsEmbedded() throws {
    guard case .embedded(let target) = try Endpoint.resolve("mem://") else {
        Issue.record("Expected mem:// to resolve as embedded.")
        return
    }
    #expect(target.kind == .memory)
    #expect(target.connectionString == "mem://")
}

@Test
func endpoint_acceptsBareMemColonForm() throws {
    guard case .embedded(let target) = try Endpoint.resolve("mem:") else {
        Issue.record("Expected mem: to resolve as embedded.")
        return
    }
    #expect(target.connectionString == "mem://")
}

@Test
func endpoint_isCaseInsensitiveForMem() throws {
    guard case .embedded = try Endpoint.resolve("MEM://") else {
        Issue.record("Expected MEM:// to resolve as embedded.")
        return
    }
}

@Test
func endpoint_doesNotAppendRPCPathToMemScheme() throws {
    guard case .embedded(let target) = try Endpoint.resolve("mem://") else {
        Issue.record("Expected mem:// to resolve as embedded.")
        return
    }
    // sr_connect wants the literal locator, not an HTTP route.
    #expect(!target.connectionString.contains("/rpc"))
}

@Test
func endpoint_rejectsMemWithHostOrPath() {
    for endpoint in ["mem://foo", "mem:///tmp/store", "mem://localhost:8000"] {
        #expect(throws: SurrealError.self, "\(endpoint) should be rejected") {
            _ = try Endpoint.resolve(endpoint)
        }
    }
}

@Test
func endpoint_stillResolvesRemoteSchemesUnchanged() throws {
    for endpoint in ["ws://localhost:8000", "wss://example.com", "http://localhost:8000", "https://example.com"] {
        guard case .remote(let url) = try Endpoint.resolve(endpoint) else {
            Issue.record("Expected \(endpoint) to resolve as remote.")
            continue
        }
        #expect(url.path == "/rpc")
    }
}

@Test
func endpoint_stillRejectsUnknownSchemes() {
    for endpoint in ["ftp://localhost:8000", "not a url", "surrealkv://store.skv"] {
        #expect(throws: SurrealError.self, "\(endpoint) should be rejected") {
            _ = try Endpoint.resolve(endpoint)
        }
    }
}
