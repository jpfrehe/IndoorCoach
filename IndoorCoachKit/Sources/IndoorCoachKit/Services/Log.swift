import Foundation
import OSLog

/// Thin facade over `os.Logger` for the pilot diagnostics (B05).
///
/// Rules for callers: log only counts, HTTP status codes, durations and type names – never tokens, API keys,
/// client secrets, OAuth codes, ride names, goals/notes or locations. As a second line of defence every message
/// runs through `Redactor.scrub` before it reaches the unified log.
public enum Log {
    public enum Category: String, CaseIterable, Sendable {
        case strava, claude, calendar, sync, plan, mywhoosh, intervals, bridge
        /// User-visible banners and app-level events.
        case app
        // ANCHOR-STRAP: Brustgurt-Verbindung und Gerätetest (nur Zähler/Status, keine Pulswerte)
        case strap
    }

    public static let subsystem: String = Bundle.main.bundleIdentifier ?? "app.indoorcoach.personal"

    static func logger(_ category: Category) -> Logger {
        Logger(subsystem: subsystem, category: category.rawValue)
    }

    /// Key event. Logged at `.notice` so it is persisted and shows up in the diagnostics export.
    public static func notice(_ category: Category, _ message: String) {
        let text = Redactor.scrub(message)
        logger(category).notice("\(text, privacy: .public)")
        LogFile.shared?.append(category: category.rawValue, level: "notice", text)
    }

    /// Failure that the user may report.
    public static func error(_ category: Category, _ message: String) {
        let text = Redactor.scrub(message)
        logger(category).error("\(text, privacy: .public)")
        LogFile.shared?.append(category: category.rawValue, level: "error", text)
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

/// Persistent copy of the (already redacted) log lines in Application Support, so diagnostics survive app
/// restarts – the unified log only returns the current process. Capped at 512 KB (older half dropped).
/// Only active in the app itself, never in unit tests.
final class LogFile: @unchecked Sendable {
    static let shared: LogFile? = Bundle.main.bundleIdentifier == "app.indoorcoach.personal" ? LogFile(url: defaultURL) : nil
    static var defaultURL: URL { URL.applicationSupportDirectory.appendingPathComponent("diagnostics-log.txt") }

    let url: URL
    private let lock = NSLock()
    private let maxBytes = 512 * 1024
    private let formatter: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter(); f.formatOptions = [.withInternetDateTime]; return f
    }()

    init(url: URL) { self.url = url }

    func append(category: String, level: String, _ text: String, date: Date = .now) {
        let line = "\(formatter.string(from: date)) [\(category)] \(level): \(text.replacingOccurrences(of: "\n", with: " "))\n"
        lock.withLock {
            let fm = FileManager.default
            try? fm.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
            if !fm.fileExists(atPath: url.path) { fm.createFile(atPath: url.path, contents: nil) }
            guard let handle = try? FileHandle(forWritingTo: url) else { return }
            defer { try? handle.close() }
            _ = try? handle.seekToEnd()
            try? handle.write(contentsOf: Data(line.utf8))
            if let size = try? handle.offset(), size > UInt64(maxBytes), let data = try? Data(contentsOf: url) {
                try? Data(data.suffix(maxBytes / 2)).write(to: url, options: .atomic)
            }
        }
    }

    /// Lines written at or after `since` (oldest first).
    func entries(since: Date) -> [String] {
        let text = lock.withLock { (try? String(contentsOf: url, encoding: .utf8)) ?? "" }
        return text.split(separator: "\n").compactMap { line -> String? in
            guard let stamp = line.split(separator: " ", maxSplits: 1).first,
                  let date = formatter.date(from: String(stamp)), date >= since else { return nil }
            return String(line)
        }
    }

    func clear() { lock.withLock { try? FileManager.default.removeItem(at: url) } }
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
        // JWTs (MyWhoosh access tokens)
        (#"eyJ[A-Za-z0-9_\-]+\.[A-Za-z0-9_\-]+\.?[A-Za-z0-9_\-]*"#, "‹JWT›"),
        // e-mail addresses (e.g. echoed back in a server message)
        (#"[A-Za-z0-9._%+\-]+@[A-Za-z0-9.\-]+\.[A-Za-z]{2,}"#, "‹E-Mail›"),
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
