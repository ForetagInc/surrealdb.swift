import Foundation

/// RFC 3339 parsing and formatting for the embedded engine's datetime values.
///
/// surrealdb-core renders datetimes with `SecondsFormat::AutoSi`, which emits
/// 0, 3, 6 or 9 fractional digits depending on the value, and
/// `ISO8601DateFormatter` accepts at most milliseconds. Both shapes are handled
/// here so a datetime survives the round trip.
enum SurrealRFC3339 {
    static func date(from text: String) -> Date? {
        let formatter = ISO8601DateFormatter()

        if let normalized = normalizingFraction(text) {
            formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
            return formatter.date(from: normalized)
        }

        formatter.formatOptions = [.withInternetDateTime]
        return formatter.date(from: text)
    }

    static func string(from date: Date) -> String {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter.string(from: date)
    }

    /// Pads or truncates a fractional-seconds component to the three digits
    /// `ISO8601DateFormatter` accepts. Returns `nil` when there is no fraction.
    private static func normalizingFraction(_ text: String) -> String? {
        guard let dot = text.firstIndex(of: ".") else { return nil }
        let afterDot = text.index(after: dot)
        let digits = text[afterDot...].prefix(while: \.isNumber)
        guard !digits.isEmpty else { return nil }

        let padded = digits.count >= 3
            ? String(digits.prefix(3))
            : digits + String(repeating: "0", count: 3 - digits.count)

        return text[..<afterDot] + padded + text[text.index(afterDot, offsetBy: digits.count)...]
    }
}
