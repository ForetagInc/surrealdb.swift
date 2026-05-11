import Foundation
import PotentCBOR
import Testing
@testable import SurrealDB

@Test
func cborCodec_encodesRequestAndDecodesResponse() throws {
    let request = RPCRequest(
        id: "1",
        method: "query",
        params: [.string("SELECT * FROM person;"), .object([:])],
        session: nil,
        txn: nil
    )

    let requestData = try CBORSurrealCodec.encode(request)
    #expect(!requestData.isEmpty)

    var responseMap = CBOR.Map()
    responseMap[.utf8String("id")] = .utf8String("1")
    responseMap[.utf8String("result")] = CBORSurrealCodec.toCBOR(.array([
        .object([
            "status": .string("OK"),
            "time": .string("1ms"),
            "result": .array([
                .object([
                    "name": .string("chiru"),
                ]),
            ]),
            "type": .string("other"),
        ]),
    ]))

    let responseData = try CBORSerialization.data(from: .map(responseMap))
    let envelope = try CBORSurrealCodec.decodeRPCEnvelope(responseData)

    #expect(envelope.id == "1")
    #expect(envelope.error == nil)

    let queryResults = try RPCWire.decodeQueryResults(from: envelope.result ?? .null)
    #expect(queryResults.count == 1)
    #expect(queryResults[0].status == .ok)
}

@Test
func cborCodec_roundTripsGeographyValues() throws {
    let point: SurrealValue = .geometry(.point([51.5074, -0.1278]))
    let line: SurrealValue = .geometry(.line([[0.0, 0.0], [1.0, 1.0]]))

    let pointCBOR = CBORSurrealCodec.toCBOR(point)
    let lineCBOR = CBORSurrealCodec.toCBOR(line)

    let decodedPoint = try CBORSurrealCodec.fromCBOR(pointCBOR)
    let decodedLine = try CBORSurrealCodec.fromCBOR(lineCBOR)

    #expect(decodedPoint == point)
    #expect(decodedLine == line)
}

@Test
func cborCodec_decodesTopLevelLiveNotificationEnvelope() throws {
    let queryID = UUID().uuidString.lowercased()

    var notificationMap = CBOR.Map()
    notificationMap[.utf8String("id")] = .utf8String(queryID)
    notificationMap[.utf8String("action")] = .utf8String("CREATE")
    notificationMap[.utf8String("result")] = CBORSurrealCodec.toCBOR(
        .object([
            "id": .string("live_person:test123"),
            "name": .string("Ada"),
            "age": .int(30),
        ])
    )

    let notificationData = try CBORSerialization.data(from: .map(notificationMap))
    let envelope = try CBORSurrealCodec.decodeRPCEnvelope(notificationData)
    let event = RPCWire.decodeLiveEvent(from: envelope)

    #expect(event != nil)
    #expect(event?.action == .create)
    #expect(event?.recordID == "live_person:test123")
    #expect(event?.queryID.uuidString.lowercased() == queryID)
}
