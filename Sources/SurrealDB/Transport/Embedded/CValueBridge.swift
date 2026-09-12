#if SURREALDB_EMBEDDED
import CSurrealDB
import Foundation

/// A `SurrealValue` the C value union cannot express.
struct EmbeddedMarshallingError: Error, Sendable, Equatable {
    let reason: String

    var asSurrealError: SurrealError {
        .unsupportedFeature("The embedded engine cannot send this value to the database: \(reason)")
    }
}

/// Converts between `SurrealValue` and `sr_value_t`.
///
/// Writes throw on anything the union cannot represent rather than coercing:
/// silently corrupting a bound value is worse than refusing it. Reads never
/// throw: an unrecognised tag degrades to `.null`, matching the tolerance the
/// CBOR decoder already has for unknown tags.
enum CValueBridge {
    // MARK: - Swift to C

    static func makeValue(_ value: SurrealValue, maximumArrayCount: Int) throws -> OwnedCValue {
        switch value {
        case .none:
            return try owned(sr_value_none(), "none")
        case .null:
            return try owned(sr_value_null(), "null")
        case .bool(let flag):
            return try owned(sr_value_bool(flag), "bool")
        case .int(let number):
            return try owned(sr_value_int(number), "int")
        case .double(let number):
            return try owned(sr_value_float(number), "double")
        case .string(let text):
            return try owned(text.withCString { sr_value_string($0) }, "string")
        case .decimal(let text):
            // `sr_value_decimal` falls back to a float, then to 0.0, without
            // reporting failure, so validate here and let a malformed decimal
            // be an error rather than a silent zero.
            guard Decimal(string: text) != nil else {
                throw EmbeddedMarshallingError(reason: "'\(text)' is not a valid decimal.")
            }
            return try owned(text.withCString { sr_value_decimal($0) }, "decimal")
        case .duration(let text):
            let parsed = try parseDuration(text)
            return try owned(sr_value_duration(parsed.seconds, parsed.nanoseconds), "duration")
        case .datetime(let date):
            return try owned(SurrealRFC3339.string(from: date).withCString { sr_value_datetime($0) }, "datetime")
        case .uuid(let uuid):
            return try makeUUID(uuid)
        case .bytes(let data):
            return try makeBytes(data)
        case .recordID(let recordID):
            return try makeRecordID(recordID, maximumArrayCount: maximumArrayCount)
        case .geometry(let geometry):
            return try makeGeometry(geometry)
        case .array(let elements), .set(let elements):
            // A set degrades to an array: the union has no set tag, so SurrealDB
            // will not deduplicate it.
            return try makeArray(elements, maximumArrayCount: maximumArrayCount)
        case .object(let fields):
            let object = try makeObject(fields, maximumArrayCount: maximumArrayCount)
            return try owned(sr_value_object(&object.object), "object")
        case .table:
            throw EmbeddedMarshallingError(reason: "table names have no embedded representation; inline it in the query instead.")
        case .range:
            throw EmbeddedMarshallingError(reason: "ranges have no embedded representation; inline the range in the query instead.")
        }
    }

    static func makeObject(_ fields: [String: SurrealValue], maximumArrayCount: Int) throws -> OwnedCObject {
        let object = OwnedCObject()
        for (key, value) in fields {
            object.insert(key, try makeValue(value, maximumArrayCount: maximumArrayCount))
        }
        return object
    }

    private static func makeArray(_ elements: [SurrealValue], maximumArrayCount: Int) throws -> OwnedCValue {
        guard elements.count <= maximumArrayCount else {
            throw EmbeddedMarshallingError(
                reason: """
                    an array of \(elements.count) elements exceeds the \(maximumArrayCount) bound-array limit. \
                    sr_array_push copies the whole array on every element, so large bindings are quadratic; \
                    raise SurrealEmbeddedOptions.maximumBoundArrayCount if you need this.
                    """
            )
        }

        let shell = try owned(sr_value_array(), "array")
        guard !elements.isEmpty else { return shell }

        let builder = OwnedCArray(seededBy: shell.pointer)
        for element in elements {
            builder.push(try makeValue(element, maximumArrayCount: maximumArrayCount))
        }

        guard let built = builder.take() else { return shell }
        let previous = shell.pointer.pointee.sr_value_array
        shell.pointer.pointee.sr_value_array = built
        if let previous, previous != built {
            sr_array_free(previous)
        }
        return shell
    }

    private static func makeUUID(_ uuid: UUID) throws -> OwnedCValue {
        var bytes = uuid.uuid
        let pointer = try withUnsafeBytes(of: &bytes) { raw -> UnsafeMutablePointer<sr_value_t>? in
            sr_value_uuid(raw.bindMemory(to: UInt8.self).baseAddress)
        }
        return try owned(pointer, "uuid")
    }

    private static func makeBytes(_ data: Data) throws -> OwnedCValue {
        guard data.count <= Int(Int32.max) else {
            throw EmbeddedMarshallingError(reason: "byte payloads above 2 GiB do not fit the C API's 32-bit length.")
        }
        let pointer = data.withUnsafeBytes { raw -> UnsafeMutablePointer<sr_value_t>? in
            sr_value_bytes(raw.bindMemory(to: UInt8.self).baseAddress, Int32(data.count))
        }
        return try owned(pointer, "bytes")
    }

    /// `sr_value_thing` only accepts a string key. String-like keys go straight
    /// through it; an integer key is retagged in place afterwards.
    ///
    /// The retag frees the placeholder with `sr_free_string` rather than writing
    /// a `strdup`'d replacement: the string would then be freed by Rust's
    /// allocator on `sr_value_free`, which is only incidentally the same
    /// allocator as libc's.
    private static func makeRecordID(_ recordID: SurrealRecordID, maximumArrayCount: Int) throws -> OwnedCValue {
        func thing(_ key: String) throws -> OwnedCValue {
            try owned(
                recordID.table.withCString { table in
                    key.withCString { id in sr_value_thing(table, id) }
                },
                "record id"
            )
        }

        switch recordID.id {
        case .string(let text):
            return try thing(text)
        case .uuid(let uuid):
            return try thing(uuid.uuidString.lowercased())
        case .int(let number):
            let value = try thing("")
            sr_free_string(value.pointer.pointee.sr_value_thing.id.sr_id_string)
            value.pointer.pointee.sr_value_thing.id.tag = SR_ID_NUMBER
            value.pointer.pointee.sr_value_thing.id.sr_id_number = number
            return value
        default:
            throw EmbeddedMarshallingError(
                reason: "record ids on the embedded engine must have a string, integer or UUID key."
            )
        }
    }

    private static func makeGeometry(_ geometry: SurrealGeometry) throws -> OwnedCValue {
        switch geometry {
        case .point(let coordinate):
            let point = try coordinatePair(coordinate)
            return try owned(sr_value_point(point.x, point.y), "point")

        case .line(let coordinates):
            var coords = try coordinates.map(coordinatePair)
            return try owned(sr_value_linestring(&coords, Int32(coords.count)), "line")

        case .polygon(let rings):
            guard rings.count <= 1 else {
                throw EmbeddedMarshallingError(
                    reason: "the embedded engine can only send single-ring polygons; sr_value_polygon takes no interior rings."
                )
            }
            var coords = try (rings.first ?? []).map(coordinatePair)
            return try owned(sr_value_polygon(&coords, Int32(coords.count)), "polygon")

        case .multiPoint(let coordinates):
            var coords = try coordinates.map(coordinatePair)
            return try owned(sr_value_multipoint(&coords, Int32(coords.count)), "multi-point")

        case .multiLine(let lines):
            return try withCoordinateGroups(lines) { pointers, lengths in
                sr_value_multilinestring(&pointers, &lengths, Int32(pointers.count))
            }

        case .multiPolygon(let polygons):
            let rings = try polygons.map { polygon -> [[Double]] in
                guard polygon.count <= 1 else {
                    throw EmbeddedMarshallingError(
                        reason: "the embedded engine can only send single-ring polygons; sr_value_multipolygon takes exterior rings only."
                    )
                }
                return polygon.first ?? []
            }
            return try withCoordinateGroups(rings) { pointers, lengths in
                sr_value_multipolygon(&pointers, &lengths, Int32(pointers.count))
            }

        case .collection:
            throw EmbeddedMarshallingError(
                reason: "geometry collections have no embedded constructor; send the members individually."
            )
        }
    }

    private static func withCoordinateGroups(
        _ groups: [[[Double]]],
        _ body: (inout [UnsafePointer<sr_sr_g_coord>?], inout [Int32]) -> UnsafeMutablePointer<sr_value_t>?
    ) throws -> OwnedCValue {
        var storage: [[sr_sr_g_coord]] = try groups.map { try $0.map(coordinatePair) }
        var lengths = storage.map { Int32($0.count) }

        var buffers: [UnsafeMutableBufferPointer<sr_sr_g_coord>] = []
        defer { buffers.forEach { $0.deallocate() } }

        var pointers: [UnsafePointer<sr_sr_g_coord>?] = []
        for index in storage.indices {
            let buffer = UnsafeMutableBufferPointer<sr_sr_g_coord>.allocate(capacity: storage[index].count)
            _ = buffer.initialize(fromContentsOf: storage[index])
            buffers.append(buffer)
            pointers.append(UnsafePointer(buffer.baseAddress))
        }

        return try owned(body(&pointers, &lengths), "geometry")
    }

    private static func coordinatePair(_ coordinate: [Double]) throws -> sr_sr_g_coord {
        guard coordinate.count >= 2 else {
            throw EmbeddedMarshallingError(reason: "a geometry coordinate needs both a longitude and a latitude.")
        }
        return sr_sr_g_coord(x: coordinate[0], y: coordinate[1])
    }

    private static func parseDuration(_ text: String) throws -> (seconds: UInt64, nanoseconds: UInt32) {
        do {
            return try SurrealDuration.parse(text)
        } catch {
            throw EmbeddedMarshallingError(reason: "'\(text)' is not a SurrealQL duration.")
        }
    }

    private static func owned(_ pointer: UnsafeMutablePointer<sr_value_t>?, _ what: String) throws -> OwnedCValue {
        guard let pointer else {
            throw EmbeddedMarshallingError(reason: "the embedded engine could not allocate a \(what) value.")
        }
        return OwnedCValue(pointer)
    }
}
#endif
