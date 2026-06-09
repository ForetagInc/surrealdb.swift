import Foundation

public enum Retry {
    static let backoffSeconds: [TimeInterval] = [0.25, 0.5, 1.0]

    public static func backoffSchedule(maxRetries: Int) -> [TimeInterval] {
        let capped = max(0, min(maxRetries, backoffSeconds.count))
        return Array(backoffSeconds.prefix(capped))
    }

    public static func shouldRetry(method: String, status: Int?, attempt: Int, maxRetries: Int, idempotent: Bool = false) -> Bool {
        if attempt >= maxRetries { return false }
        // GET is always safe to retry. Other verbs are retried only when the
        // caller marks the request idempotent (for example, a write carrying an
        // Idempotency-Key that the server deduplicates).
        if method.uppercased() != "GET" && !idempotent { return false }
        guard let status else { return true }
        return status >= 500
    }
}
