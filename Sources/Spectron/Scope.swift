import Foundation

public enum Scope {
    public static func serialise(_ scope: [String: String]?) -> [[String: String]]? {
        guard let scope else { return nil }
        return scope.map { ["key": $0.key, "value": $0.value] }
    }

    public static func deserialise(_ wire: [[String: String]]?) -> [String: String] {
        guard let wire else { return [:] }
        var out: [String: String] = [:]
        for entry in wire {
            if let k = entry["key"], let v = entry["value"] {
                out[k] = v
            }
        }
        return out
    }
}
