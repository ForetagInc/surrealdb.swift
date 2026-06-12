import Foundation

/// One incremental frame of a streamed chat response.
public struct ChatChunk: Sendable, Equatable {
    /// Newly generated text for this frame. Empty on the terminal frame.
    public let delta: String
    public let traceId: String?
    public let sessionId: String?
    /// `true` on the final frame of the stream.
    public let done: Bool
    /// The raw decoded frame payload, when it was JSON.
    public let raw: JSONValue?

    public init(delta: String = "", traceId: String? = nil, sessionId: String? = nil, done: Bool = false, raw: JSONValue? = nil) {
        self.delta = delta
        self.traceId = traceId
        self.sessionId = sessionId
        self.done = done
        self.raw = raw
    }
}

/// Incremental Server-Sent Events parser that turns a line stream into
/// `ChatChunk` values. Mirrors the framing used by the Spectron chat endpoint:
/// `event:` and `data:` fields accumulate until a blank line dispatches a frame.
struct SSEParser {
    private var event: String?
    private var dataLines: [String] = []

    /// Feeds one line (without its trailing newline) and returns a chunk when a
    /// complete frame has been seen.
    mutating func consume(_ rawLine: String) -> ChatChunk? {
        let line = rawLine.hasSuffix("\r") ? String(rawLine.dropLast()) : rawLine

        if line.isEmpty {
            guard !dataLines.isEmpty else {
                event = nil
                return nil
            }
            let chunk = Self.frame(event: event, payload: dataLines.joined(separator: "\n"))
            event = nil
            dataLines = []
            return chunk
        }

        if line.hasPrefix(":") {
            return nil
        }
        if line.hasPrefix("event:") {
            event = String(line.dropFirst("event:".count)).trimmingCharacters(in: .whitespaces)
        } else if line.hasPrefix("data:") {
            var value = String(line.dropFirst("data:".count))
            if value.hasPrefix(" ") { value.removeFirst() }
            dataLines.append(value)
        }
        return nil
    }

    /// Dispatches any buffered frame at end of stream.
    mutating func flush() -> ChatChunk? {
        guard !dataLines.isEmpty else { return nil }
        let chunk = Self.frame(event: event, payload: dataLines.joined(separator: "\n"))
        event = nil
        dataLines = []
        return chunk
    }

    private static func frame(event: String?, payload: String) -> ChatChunk {
        if payload == "[DONE]" {
            return ChatChunk(done: true)
        }
        guard
            let data = payload.data(using: .utf8),
            let json = try? JSONDecoder().decode(JSONValue.self, from: data),
            case .object(let obj) = json
        else {
            return ChatChunk(delta: payload)
        }

        let traceId = obj["traceId"]?.asString ?? obj["trace_id"]?.asString
        let sessionId = obj["sessionId"]?.asString ?? obj["session_id"]?.asString
        let isDone = event == "done" || (obj["done"]?.asBool ?? false)
        if isDone {
            return ChatChunk(delta: "", traceId: traceId, sessionId: sessionId, done: true, raw: json)
        }
        let delta = obj["delta"]?.asString ?? obj["token"]?.asString ?? ""
        return ChatChunk(delta: delta, traceId: traceId, sessionId: sessionId, done: false, raw: json)
    }
}
