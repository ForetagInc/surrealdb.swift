import Foundation

/// Wire-protocol-neutral decoders. These operate on already-decoded
/// `SurrealValue` / `RPCResponseEnvelope` so they're identical regardless of
/// whether the bytes came from CBOR or JSON.
enum RPCWire {
    static func decodeQueryResults(from value: SurrealValue) throws -> [RPCQueryResult] {
        guard case .array(let rows) = value else {
            throw SurrealError.invalidResponse("Expected query result array.")
        }

        return try rows.enumerated().map { index, value in
            guard case .object(let object) = value else {
                throw SurrealError.invalidResponse("Expected query result object at index \(index).")
            }

            guard
                let statusRaw = object["status"],
                case .string(let statusString) = statusRaw,
                let status = QueryResultStatus(rawValue: statusString)
            else {
                throw SurrealError.invalidResponse("Missing query status at index \(index).")
            }

            guard let timeRaw = object["time"], case .string(let time) = timeRaw else {
                throw SurrealError.invalidResponse("Missing query time at index \(index).")
            }

            let result = object["result"] ?? .null
            let type = object["type"].flatMap(stringFromSurrealValue(_:))
            let kind = object["kind"].flatMap(stringFromSurrealValue(_:))
            let details = object["details"]

            return RPCQueryResult(
                status: status,
                time: time,
                result: result,
                type: type,
                kind: kind,
                details: details
            )
        }
    }

    static func decodeLiveEvent(from envelope: RPCResponseEnvelope) -> LiveWireEvent? {
        if
            let actionRaw = envelope.action,
            let action = LiveAction(rawValue: actionRaw),
            let id = envelope.id,
            let queryID = UUID(uuidString: id),
            let payloadValue = envelope.result
        {
            let recordValue = liveRecordValue(fromPayload: payloadValue)
            guard let recordValue, let recordID = recordIDFromSurrealValue(recordValue) else {
                return nil
            }

            return LiveWireEvent(
                queryID: queryID,
                action: action,
                recordID: recordID,
                payload: payloadValue
            )
        }

        guard let result = envelope.result else {
            return nil
        }
        return decodeLiveEvent(from: result)
    }

    static func decodeLiveEvent(from value: SurrealValue) -> LiveWireEvent? {
        guard case .object(let object) = value else {
            return nil
        }

        guard
            let idValue = object["id"],
            let actionValue = object["action"],
            let payloadValue = object["result"],
            case .string(let actionRaw) = actionValue,
            let action = LiveAction(rawValue: actionRaw)
        else {
            return nil
        }

        guard let queryID = uuidFromSurrealValue(idValue) else {
            return nil
        }

        let recordValue = object["record"] ?? liveRecordValue(fromPayload: payloadValue)
        guard let recordValue, let recordID = recordIDFromSurrealValue(recordValue) else {
            return nil
        }

        return LiveWireEvent(
            queryID: queryID,
            action: action,
            recordID: recordID,
            payload: payloadValue
        )
    }

    private static func stringFromSurrealValue(_ value: SurrealValue) -> String? {
        if case .string(let string) = value {
            return string
        }
        return nil
    }

    private static func uuidFromSurrealValue(_ value: SurrealValue) -> UUID? {
        switch value {
        case .uuid(let uuid):
            return uuid
        case .string(let raw):
            return UUID(uuidString: raw)
        default:
            return nil
        }
    }

    private static func recordIDFromSurrealValue(_ value: SurrealValue) -> String? {
        switch value {
        case .string(let raw):
            return raw
        case .recordID(let value):
            return value.rawValue
        default:
            return nil
        }
    }

    private static func liveRecordValue(fromPayload payload: SurrealValue) -> SurrealValue? {
        switch payload {
        case .object(let object):
            return object["id"] ?? object["record"]
        case .string, .recordID:
            return payload
        default:
            return nil
        }
    }
}
