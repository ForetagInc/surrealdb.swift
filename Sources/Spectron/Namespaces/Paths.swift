import Foundation

enum Paths {
    static func endUserBase(_ contextId: String) -> String {
        "/api/v1/\(SpectronTransport.quotePath(contextId))"
    }
}

enum QueryItems {
    static func from(_ items: [(String, Any?)]) -> [URLQueryItem]? {
        var out: [URLQueryItem] = []
        for (name, value) in items {
            guard let value = value else { continue }
            out.append(URLQueryItem(name: name, value: "\(value)"))
        }
        return out.isEmpty ? nil : out
    }
}

extension JSONValue {
    static func encodeObject(_ object: [String: JSONValue]) throws -> Data {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.withoutEscapingSlashes]
        return try encoder.encode(object)
    }
}
