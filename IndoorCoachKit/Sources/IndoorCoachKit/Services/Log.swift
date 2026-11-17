import Foundation
import OSLog

/// Thin facade over `os.Logger` for the pilot diagnostics (B05).
///
/// Rules for callers: log only counts, HTTP status codes, durations and type names – never tokens, API keys,
/// client secrets, OAuth codes, ride names, goals/notes or locations. As a second line of defence every message
/// runs through `Redactor.scrub` before it reaches the unified log.
public enum Log {
    public enum Category: String, CaseIterable, Sendable {
        case strava, claude, calendar, sync, plan
        /// User-visible banners and app-level events.
        case app
    }

    public static let subsystem: String = Bundle.main.bundleIdentifier ?? "app.indoorcoach.personal"

    static func logger(_ category: Category) -> Logger {
        Logger(subsystem: subsystem, category: category.rawValue)
    }

    /// Key event. Logged at `.notice` so it is persisted and shows up in the diagnostics export.
    public static func notice(_ category: Category, _ message: String) {
        let text = Redactor.scrub(message)
        logger(category).notice("\(text, privacy: .public)")
    }

    /// Failure that the user may report.
    public static func error(_ category: Category, _ message: String) {
        let text = Redactor.scrub(message)
        logger(category).error("\(text, privacy: .public)")
    }

    /// Reads this process's entries of our subsystem since `since` (oldest first, at most `limit` lines).
    /// Throws when the log store is unavailable – callers degrade gracefully.
    public static func storedEntries(since: Date, limit: Int = 2_000) throws -> [String] {
        let store = try OSLogStore(scope: .currentProcessIdentifier)
        let position = store.position(date: since)
        let predicate = NSPredicate(format: "subsystem == %@", subsystem)
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime]
        var lines: [String] = []
        for entry in try store.getEntries(at: position, matching: predicate) {
            guard let log = entry as? OSLogEntryLog, log.date >= since else { continue }
            lines.append("\(formatter.string(from: log.date)) [\(log.category)] \(levelName(log.level)): \(log.composedMessage)")
        }
        return Array(lines.suffix(limit))
    }

    private static func levelName(_ level: OSLogEntryLog.Level) -> String {
        switch level {
        case .debug: "debug"
        case .info: "info"
        case .notice: "notice"
        case .error: "error"
        case .fault: "fault"
        default: "log"
        }
    }
}

/// Removes secrets from free text (log lines, server error messages, the diagnostics export).
public enum Redactor {
    private static let rules: [(pattern: String, replacement: String)] = [
        // Anthropic API keys
        (#"sk-ant-[A-Za-z0-9_\-]+"#, "sk-ant-…"),
        // HTTP authorization headers
        (#"(?i)\b(Bearer|Basic)\s+[A-Za-z0-9._~+/=\-]+"#, "$1 …"),
        // key=value / "key": "value" pairs of OAuth and API credentials
        (#"(?i)("?\b(?:access_token|refresh_token|client_secret|code|api[_-]?key|x-api-key|password|secret|token)"?\s*[:=]\s*"?)[^\s&",}]+"#, "$1…"),
        // 32+ hex characters (Strava tokens, client secrets and OAuth codes are 40 hex)
        (#"\b[0-9a-fA-F]{32,}\b"#, "‹hex›"),
        // GPS coordinate pairs
        (#"-?\d{1,3}\.\d{4,}\s*,\s*-?\d{1,3}\.\d{4,}"#, "‹Koordinaten›")
    ]

    /// Pattern-based redaction plus literal replacement of known secrets (e.g. the stored key and tokens).
    public static func scrub(_ text: String, knownSecrets: [String] = []) -> String {
        var result = text
        for secret in knownSecrets where secret.count >= 6 {
            result = result.replacingOccurrences(of: secret, with: "‹entfernt›")
        }
        for rule in rules {
            result = result.replacingOccurrences(of: rule.pattern, with: rule.replacement, options: .regularExpression)
        }
        return result
    }
}
