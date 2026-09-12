import Foundation

/// Converts between SurrealQL's textual duration form (which `SurrealValue`
/// stores) and the `{seconds, nanoseconds}` pair the C API takes.
enum SurrealDuration {
    struct ParseError: Error, Sendable, Equatable {
        let text: String
    }

    /// Nanoseconds per unit, longest suffix first so `"ms"` is never matched as
    /// `"m"` and `"µs"`/`"us"` never as `"s"`.
    private static let units: [(suffix: String, nanoseconds: UInt64)] = [
        ("ns", 1),
        ("µs", 1_000),
        ("us", 1_000),
        ("ms", 1_000_000),
        ("y", 365 * 24 * 60 * 60 * 1_000_000_000),
        ("w", 7 * 24 * 60 * 60 * 1_000_000_000),
        ("d", 24 * 60 * 60 * 1_000_000_000),
        ("h", 60 * 60 * 1_000_000_000),
        ("m", 60 * 1_000_000_000),
        ("s", 1_000_000_000),
    ]

    /// Parses simple (`"500ms"`) and compound (`"1h30m"`, `"1y2w3d"`) forms.
    static func parse(_ text: String) throws -> (seconds: UInt64, nanoseconds: UInt32) {
        let trimmed = text.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else { throw ParseError(text: text) }

        var remainder = Substring(trimmed)
        var total: UInt64 = 0
        var matchedAnything = false

        while !remainder.isEmpty {
            let digits = remainder.prefix(while: \.isNumber)
            guard !digits.isEmpty, let amount = UInt64(digits) else {
                throw ParseError(text: text)
            }
            remainder = remainder.dropFirst(digits.count)

            guard let unit = units.first(where: { remainder.hasPrefix($0.suffix) }) else {
                throw ParseError(text: text)
            }
            remainder = remainder.dropFirst(unit.suffix.count)

            let (scaled, scaleOverflow) = amount.multipliedReportingOverflow(by: unit.nanoseconds)
            guard !scaleOverflow else { throw ParseError(text: text) }
            let (sum, sumOverflow) = total.addingReportingOverflow(scaled)
            guard !sumOverflow else { throw ParseError(text: text) }

            total = sum
            matchedAnything = true
        }

        guard matchedAnything else { throw ParseError(text: text) }
        return (seconds: total / 1_000_000_000, nanoseconds: UInt32(total % 1_000_000_000))
    }

    /// Renders the canonical compound form, so `parse(format(x)) == x`.
    static func format(seconds: UInt64, nanoseconds: UInt32) -> String {
        var remaining = seconds
        var parts: [String] = []

        // Largest unit first; years and weeks match SurrealQL's own rendering.
        for (suffix, divisor) in [("y", 365 * 24 * 60 * 60), ("w", 7 * 24 * 60 * 60),
                                  ("d", 24 * 60 * 60), ("h", 60 * 60), ("m", 60), ("s", 1)] as [(String, UInt64)] {
            let count = remaining / divisor
            if count > 0 {
                parts.append("\(count)\(suffix)")
                remaining -= count * divisor
            }
        }

        var subsecond = nanoseconds
        for (suffix, divisor) in [("ms", UInt32(1_000_000)), ("µs", 1_000), ("ns", 1)] {
            let count = subsecond / divisor
            if count > 0 {
                parts.append("\(count)\(suffix)")
                subsecond -= count * divisor
            }
        }

        return parts.isEmpty ? "0ns" : parts.joined()
    }
}
