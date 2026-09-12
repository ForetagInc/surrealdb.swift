#if SURREALDB_EMBEDDED
import CSurrealDB
import Foundation

extension CValueBridge {
    /// Reads a borrowed `sr_value_t` into Swift. The caller keeps ownership of
    /// the input; nothing here frees it.
    ///
    /// Note that surrealdb.c's own `From<Value>` conversion maps every value
    /// kind outside its thirteen tags (ranges, tables, files, regexes,
    /// closures) to `NONE` before it ever reaches Swift. Those are lost inside
    /// the Rust layer, not here.
    static func readValue(_ pointer: UnsafePointer<sr_value_t>) -> SurrealValue {
        let value = pointer.pointee

        switch value.tag {
        case SR_VALUE_NONE:
            return .none
        case SR_VALUE_NULL:
            return .null
        case SR_VALUE_BOOL:
            return .bool(value.sr_value_bool)
        case SR_VALUE_NUMBER:
            return readNumber(value.sr_value_number)
        case SR_VALUE_STRAND:
            return .string(string(value.sr_value_strand))
        case SR_VALUE_DURATION:
            let duration = value.sr_value_duration
            return .duration(SurrealDuration.format(seconds: duration.secs, nanoseconds: duration.nanos))
        case SR_VALUE_DATETIME:
            let text = string(value.sr_value_datetime)
            return SurrealRFC3339.date(from: text).map(SurrealValue.datetime) ?? .string(text)
        case SR_VALUE_UUID:
            return .uuid(readUUID(value.sr_value_uuid))
        case SR_VALUE_ARRAY:
            guard let array = value.sr_value_array else { return .array([]) }
            return .array(readArray(array))
        case SR_VALUE_OBJECT:
            return .object(readObject(value.sr_value_object))
        case SR_GEOMETRY_OBJECT:
            return readGeometry(value.sr_geometry_object).map(SurrealValue.geometry) ?? .null
        case SR_VALUE_BYTES:
            return .bytes(readBytes(value.sr_value_bytes))
        case SR_VALUE_THING:
            return .recordID(readThing(value.sr_value_thing))
        default:
            return .null
        }
    }

    static func readArray(_ pointer: UnsafePointer<sr_array_t>) -> [SurrealValue] {
        let array = pointer.pointee
        guard let elements = array.arr, array.len > 0 else { return [] }
        return (0..<Int(array.len)).map { readValue(elements.advanced(by: $0)) }
    }

    static func readObject(_ object: sr_object_t) -> [String: SurrealValue] {
        var object = object
        var keys: UnsafeMutablePointer<UnsafeMutablePointer<CChar>?>?
        let count = sr_object_keys(&object, &keys)
        guard count > 0, let keys else { return [:] }
        defer { sr_free_string_arr(keys, count) }

        var fields: [String: SurrealValue] = [:]
        for index in 0..<Int(count) {
            guard let rawKey = keys[index] else { continue }
            let key = String(cString: rawKey)
            // Borrowed; freeing it would double-free the object's storage.
            guard let element = sr_object_get(&object, rawKey) else { continue }
            fields[key] = readValue(element)
        }
        return fields
    }

    static func readThing(_ thing: sr_thing_t) -> SurrealRecordID {
        let table = string(thing.table)
        let id = thing.id

        switch id.tag {
        case SR_ID_NUMBER:
            return SurrealRecordID(table: table, id: .int(id.sr_id_number))
        case SR_ID_STRING:
            return SurrealRecordID(table: table, id: .string(string(id.sr_id_string)))
        case SR_ID_ARRAY:
            guard let array = id.sr_id_array else { return SurrealRecordID(table: table, id: .array([])) }
            return SurrealRecordID(table: table, id: .array(readArray(array)))
        case SR_ID_OBJECT:
            return SurrealRecordID(table: table, id: .object(readObject(id.sr_id_object)))
        default:
            return SurrealRecordID(table: table, id: .null)
        }
    }

    static func readNumber(_ number: sr_number_t) -> SurrealValue {
        switch number.tag {
        case SR_NUMBER_INT:
            return .int(number.sr_number_int)
        case SR_NUMBER_FLOAT:
            return .double(number.sr_number_float)
        case SR_NUMBER_DECIMAL:
            return .decimal(string(number.sr_number_decimal))
        default:
            return .null
        }
    }

    static func readBytes(_ bytes: sr_bytes_t) -> Data {
        guard let pointer = bytes.arr, bytes.len > 0 else { return Data() }
        return Data(bytes: pointer, count: Int(bytes.len))
    }

    static func readGeometry(_ geometry: sr_sr_geometry) -> SurrealGeometry? {
        switch geometry.tag {
        case sr_g_point:
            return .point(coordinate(geometry.sr_g_point._0))
        case sr_g_linestring:
            return .line(coordinates(geometry.sr_g_linestring._0))
        case sr_g_polygon:
            let polygon = geometry.sr_g_polygon
            var rings = [coordinates(polygon._0._0)]
            rings.append(contentsOf: lineStrings(polygon._1))
            return .polygon(rings)
        case sr_g_multipoint:
            let points = geometry.sr_g_multipoint._0
            guard let pointer = points.ptr, points.len > 0 else { return .multiPoint([]) }
            return .multiPoint((0..<Int(points.len)).map { coordinate(pointer[$0]._0) })
        case sr_g_multiline:
            return .multiLine(lineStrings(geometry.sr_g_multiline._0))
        case sr_g_multipolygon:
            let polygons = geometry.sr_g_multipolygon._0
            guard let pointer = polygons.ptr, polygons.len > 0 else { return .multiPolygon([]) }
            return .multiPolygon((0..<Int(polygons.len)).map { index in
                let polygon = pointer[index]
                var rings = [coordinates(polygon._0._0)]
                rings.append(contentsOf: lineStrings(polygon._1))
                return rings
            })
        case sr_g_collection:
            let members = geometry.sr_g_collection
            guard let pointer = members.ptr, members.len > 0 else { return .collection([]) }
            return .collection((0..<Int(members.len)).compactMap { readGeometry(pointer[$0]) })
        default:
            return nil
        }
    }

    private static func lineStrings(_ group: sr_ArrayGen_sr_g_linestring) -> [[[Double]]] {
        guard let pointer = group.ptr, group.len > 0 else { return [] }
        return (0..<Int(group.len)).map { coordinates(pointer[$0]._0) }
    }

    private static func coordinates(_ group: sr_ArrayGen_sr_g_coord) -> [[Double]] {
        guard let pointer = group.ptr, group.len > 0 else { return [] }
        return (0..<Int(group.len)).map { coordinate(pointer[$0]) }
    }

    private static func coordinate(_ value: sr_sr_g_coord) -> [Double] {
        [value.x, value.y]
    }

    private static func readUUID(_ uuid: sr_uuid_t) -> UUID {
        var bytes = uuid._0
        return withUnsafeBytes(of: &bytes) { raw in
            UUID(uuid: raw.load(as: uuid_t.self))
        }
    }

    private static func string(_ pointer: UnsafeMutablePointer<CChar>?) -> String {
        pointer.map { String(cString: $0) } ?? ""
    }
}
#endif
