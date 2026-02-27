import Foundation

public struct SurrealRecordID: Sendable, Hashable, Codable {
    public let table: String
    public let id: SurrealValue

    public init(table: String, id: SurrealValue) {
        self.table = table
        self.id = id
    }

    public var rawValue: String {
        "\(table):\(id.sqlLiteral)"
    }
}

public enum SurrealRangeBound: Sendable, Hashable, Codable {
    case included(SurrealValue)
    case excluded(SurrealValue)
    case unbounded
}

public struct SurrealRange: Sendable, Hashable, Codable {
    public let begin: SurrealRangeBound
    public let end: SurrealRangeBound

    public init(begin: SurrealRangeBound, end: SurrealRangeBound) {
        self.begin = begin
        self.end = end
    }
}

public enum SurrealGeometry: Sendable, Hashable, Codable {
    case point([Double])
    case line([[Double]])
    case polygon([[[Double]]])
    case multiPoint([[Double]])
    case multiLine([[[Double]]])
    case multiPolygon([[[[Double]]]])
    case collection([SurrealGeometry])
}

public indirect enum SurrealValue: Sendable, Hashable, Codable {
    case none
    case null
    case bool(Bool)
    case int(Int64)
    case double(Double)
    case string(String)
    case bytes(Data)

    case datetime(Date)
    case uuid(UUID)
    case decimal(String)
    case duration(String)

    case table(String)
    case recordID(SurrealRecordID)
    case range(SurrealRange)
    case set([SurrealValue])
    case geometry(SurrealGeometry)

    case array([SurrealValue])
    case object([String: SurrealValue])

    public init(from decoder: any Decoder) throws {
        let container = try decoder.singleValueContainer()

        if container.decodeNil() {
            self = .null
            return
        }
        if let value = try? container.decode(Bool.self) {
            self = .bool(value)
            return
        }
        if let value = try? container.decode(Int64.self) {
            self = .int(value)
            return
        }
        if let value = try? container.decode(Double.self) {
            self = .double(value)
            return
        }
        if let value = try? container.decode(String.self) {
            self = .string(value)
            return
        }
        if let value = try? container.decode([SurrealValue].self) {
            self = .array(value)
            return
        }
        if let value = try? container.decode([String: SurrealValue].self) {
            self = .object(value)
            return
        }

        throw DecodingError.typeMismatch(
            SurrealValue.self,
            .init(codingPath: decoder.codingPath, debugDescription: "Unsupported SurrealValue payload.")
        )
    }

    public func encode(to encoder: any Encoder) throws {
        var container = encoder.singleValueContainer()
        switch self {
        case .none:
            try container.encodeNil()
        case .null:
            try container.encodeNil()
        case .bool(let value):
            try container.encode(value)
        case .int(let value):
            try container.encode(value)
        case .double(let value):
            try container.encode(value)
        case .string(let value):
            try container.encode(value)
        case .bytes(let value):
            try container.encode(value.base64EncodedString())
        case .datetime(let value):
            try container.encode(ISO8601DateFormatter().string(from: value))
        case .uuid(let value):
            try container.encode(value.uuidString)
        case .decimal(let value):
            try container.encode(value)
        case .duration(let value):
            try container.encode(value)
        case .table(let value):
            try container.encode(value)
        case .recordID(let value):
            try container.encode(value.rawValue)
        case .range(let value):
            try container.encode(String(describing: value))
        case .set(let value):
            try container.encode(value)
        case .geometry(let value):
            try container.encode(String(describing: value))
        case .array(let value):
            try container.encode(value)
        case .object(let value):
            try container.encode(value)
        }
    }

    public static func fromEncodable<T: Encodable>(_ value: T, encoder: JSONEncoder = .surrealDefault) throws -> SurrealValue {
        let data = try encoder.encode(value)
        let object = try JSONSerialization.jsonObject(with: data, options: [.fragmentsAllowed])
        return try SurrealValue(jsonObject: object)
    }

    public func decode<T: Decodable>(_ type: T.Type, decoder: JSONDecoder = .surrealDefault) throws -> T {
        let object = try jsonObject()
        let data = try JSONSerialization.data(withJSONObject: object, options: [.fragmentsAllowed])
        return try decoder.decode(T.self, from: data)
    }

    public init(jsonObject: Any) throws {
        switch jsonObject {
        case is NSNull:
            self = .null
        case let value as Bool:
            self = .bool(value)
        case let value as Int:
            self = .int(Int64(value))
        case let value as Int64:
            self = .int(value)
        case let value as UInt64:
            if value <= UInt64(Int64.max) {
                self = .int(Int64(value))
            } else {
                self = .double(Double(value))
            }
        case let value as Double:
            self = .double(value)
        case let value as String:
            self = .string(value)
        case let value as [Any]:
            self = .array(try value.map(SurrealValue.init(jsonObject:)))
        case let value as [String: Any]:
            self = .object(try value.mapValues(SurrealValue.init(jsonObject:)))
        default:
            throw SurrealValueError.unsupportedJSONType(String(describing: type(of: jsonObject)))
        }
    }

    public func jsonObject() throws -> Any {
        switch self {
        case .none:
            return NSNull()
        case .null:
            return NSNull()
        case .bool(let value):
            return value
        case .int(let value):
            return value
        case .double(let value):
            return value
        case .string(let value):
            return value
        case .bytes(let value):
            return value.base64EncodedString()
        case .datetime(let value):
            return ISO8601DateFormatter().string(from: value)
        case .uuid(let value):
            return value.uuidString
        case .decimal(let value):
            return value
        case .duration(let value):
            return value
        case .table(let value):
            return value
        case .recordID(let value):
            return value.rawValue
        case .range(let range):
            return [
                "begin": try range.begin.jsonObject(),
                "end": try range.end.jsonObject(),
            ]
        case .set(let value):
            return try value.map { try $0.jsonObject() }
        case .geometry(let value):
            return ["geometry": String(describing: value)]
        case .array(let value):
            return try value.map { try $0.jsonObject() }
        case .object(let value):
            return try value.mapValues { try $0.jsonObject() }
        }
    }

    public var sqlLiteral: String {
        switch self {
        case .none:
            return "NONE"
        case .null:
            return "NULL"
        case .bool(let value):
            return value ? "true" : "false"
        case .int(let value):
            return "\(value)"
        case .double(let value):
            return "\(value)"
        case .string(let value):
            return "\"\(value.replacingOccurrences(of: "\"", with: "\\\""))\""
        case .bytes(let value):
            return "<bytes>\"\(value.base64EncodedString())\""
        case .datetime(let value):
            return "d\"\(ISO8601DateFormatter().string(from: value))\""
        case .uuid(let value):
            return "u\"\(value.uuidString.lowercased())\""
        case .decimal(let value):
            return "\(value)dec"
        case .duration(let value):
            return value
        case .table(let value):
            return value
        case .recordID(let value):
            return value.rawValue
        case .range:
            return "<range>"
        case .set(let value):
            return "[" + value.map(\.sqlLiteral).joined(separator: ", ") + "]"
        case .geometry:
            return "<geometry>"
        case .array(let value):
            return "[" + value.map(\.sqlLiteral).joined(separator: ", ") + "]"
        case .object(let value):
            let entries = value.map { key, value in
                "\(key): \(value.sqlLiteral)"
            }.sorted()
            return "{" + entries.joined(separator: ", ") + "}"
        }
    }
}

public enum SurrealValueError: Error, Sendable {
    case unsupportedJSONType(String)
}

public extension SurrealRangeBound {
    func jsonObject() throws -> Any {
        switch self {
        case .included(let value):
            return ["included": try value.jsonObject()]
        case .excluded(let value):
            return ["excluded": try value.jsonObject()]
        case .unbounded:
            return ["unbounded": true]
        }
    }
}

public extension JSONEncoder {
    static var surrealDefault: JSONEncoder {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.withoutEscapingSlashes]
        return encoder
    }
}

public extension JSONDecoder {
    static var surrealDefault: JSONDecoder {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return decoder
    }
}
