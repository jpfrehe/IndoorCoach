import IndoorCoachKit
import Foundation

// Pure helpers of the bridge app (no UI, no I/O beyond what is injected) – unit-tested in Bridge/Tests.

/// Where the bridge reads the FIT files from.
enum BridgeFolderState: Equatable {
    /// Nothing chosen yet.
    case none
    /// Folder is readable.
    case ready
    /// Bookmark is stale/unresolvable or the folder vanished (e.g. after a MyWhoosh update).
    case needsReshare
}

struct BridgeStatusInput: Equatable {
    var folder: BridgeFolderState
    var pairedDeviceName: String?
    var rideCount: Int
    var lastFetch: Date?
    var serverError: String?
}

struct BridgeStatusLine: Equatable {
    enum Level: Equatable { case ok, info, warning }
    var text: String
    var level: Level
}

enum BridgeFormat {
    /// What a scanned FIT file contains, for the diagnostics log (no ride names or places).
    struct FileFacts: Equatable {
        var start: Date
        var seconds: Int
        var averageWatts: Double?
        var normalizedPower: Double?
        var powerSeconds: Int?
        var heartRateSeconds: Int?
        var hasCurve: Bool

        init(start: Date, seconds: Int, averageWatts: Double?, normalizedPower: Double?, powerSeconds: Int?,
             heartRateSeconds: Int?, hasCurve: Bool) {
            self.start = start
            self.seconds = seconds
            self.averageWatts = averageWatts
            self.normalizedPower = normalizedPower
            self.powerSeconds = powerSeconds
            self.heartRateSeconds = heartRateSeconds
            self.hasCurve = hasCurve
        }

        init(_ s: FITParser.Summary) {
            self.init(start: s.startDate, seconds: s.movingTime, averageWatts: s.averageWatts, normalizedPower: s.normalizedPower,
                      powerSeconds: s.seconds?.count, heartRateSeconds: s.seconds?.heartRate?.count,
                      hasCurve: s.powerCurve?.isEmpty == false)
        }
    }

    /// One diagnostics line per scanned file.
    static func fileDiagnostics(name: String, size: Int, facts: Result<FileFacts, Error>) -> String {
        let head = "Datei \(name) (\(size / 1024) KB)"
        switch facts {
        case .failure(let error):
            return "\(head): nicht lesbar (\(error))"
        case .success(let f):
            let iso = ISO8601DateFormatter().string(from: f.start)
            let duration = String(format: "%d:%02d", f.seconds / 60, f.seconds % 60)
            let avg = f.averageWatts.map { "Ø \(Int($0.rounded())) W" } ?? "Ø –"
            let np = f.normalizedPower.map { "NP \(Int($0.rounded())) W" } ?? "NP –"
            let power = f.powerSeconds.map { "Leistung \($0) s" } ?? "Leistung –"
            let heart = f.heartRateSeconds.map { "Puls \($0) s" } ?? "Puls –"
            return "\(head): Start \(iso), \(duration), \(avg), \(np), \(power), \(heart), Kurve \(f.hasCurve ? "ja" : "nein")"
        }
    }


    /// One-line status of the menu panel, e.g. "Gekoppelt mit iPhone · 23 Fahrten bereit · zuletzt abgeholt 18:42".
    static func statusLine(_ input: BridgeStatusInput, timeZone: TimeZone = .current) -> BridgeStatusLine {
        switch input.folder {
        case .needsReshare:
            return BridgeStatusLine(text: "Ordner neu freigeben", level: .warning)
        case .none:
            return BridgeStatusLine(text: "Noch kein Ordner freigegeben", level: .warning)
        case .ready:
            break
        }
        var parts: [String] = []
        if let device = input.pairedDeviceName {
            parts.append("Gekoppelt mit \(device)")
        } else {
            parts.append("Noch kein iPhone gekoppelt")
        }
        parts.append(rideCountText(input.rideCount))
        if input.pairedDeviceName != nil, let last = input.lastFetch {
            parts.append("zuletzt abgeholt \(clockTime(last, timeZone: timeZone))")
        }
        if input.serverError != nil {
            return BridgeStatusLine(text: parts.joined(separator: " · "), level: .warning)
        }
        return BridgeStatusLine(text: parts.joined(separator: " · "), level: input.pairedDeviceName == nil ? .info : .ok)
    }

    static func rideCountText(_ count: Int) -> String {
        count == 1 ? "1 Fahrt bereit" : "\(count) Fahrten bereit"
    }

    /// "18:42"
    static func clockTime(_ date: Date, timeZone: TimeZone = .current) -> String {
        let f = DateFormatter()
        f.locale = Locale(identifier: "de_DE")
        f.timeZone = timeZone
        f.dateFormat = "HH:mm"
        return f.string(from: date)
    }

    /// "18.11. · 52 min" / "18.11. · 1 h 05 min"
    static func rideLabel(start: Date, durationSeconds: Int, timeZone: TimeZone = .current) -> String {
        let f = DateFormatter()
        f.locale = Locale(identifier: "de_DE")
        f.timeZone = timeZone
        f.dateFormat = "dd.MM."
        return "\(f.string(from: start)) · \(durationText(durationSeconds))"
    }

    static func durationText(_ seconds: Int) -> String {
        let minutes = max(0, seconds) / 60
        if minutes < 60 { return "\(minutes) min" }
        return String(format: "%d h %02d min", minutes / 60, minutes % 60)
    }

    /// "482913" -> "482 913"
    static func groupedCode(_ code: String) -> String {
        guard code.count == 6 else { return code }
        return "\(code.prefix(3)) \(code.suffix(3))"
    }

    /// "4:32"
    static func countdown(_ remaining: TimeInterval) -> String {
        let total = max(0, Int(remaining.rounded(.up)))
        return String(format: "%d:%02d", total / 60, total % 60)
    }

    static func foundRidesText(_ count: Int) -> String {
        count == 1 ? "✓ 1 Fahrt gefunden" : "✓ \(count) Fahrten gefunden"
    }
}

// MARK: - Real home directory

enum RealHome {
    /// In the sandbox `FileManager.homeDirectoryForCurrentUser` is the container; the account's real home comes from the passwd entry.
    static func url() -> URL {
        if let entry = getpwuid(getuid()), let dir = entry.pointee.pw_dir {
            return URL(fileURLWithPath: String(cString: dir), isDirectory: true)
        }
        return FileManager.default.homeDirectoryForCurrentUser
    }
}

// MARK: - Folder bookmark handling

protocol FolderBookmarkResolving {
    func resolve(bookmark: Data) throws -> (url: URL, isStale: Bool)
    func makeBookmark(for url: URL) throws -> Data
}

enum FolderResolution: Equatable {
    case none
    /// `refreshedBookmark` is set when the stored bookmark was stale but could be renewed.
    case accessible(URL, refreshedBookmark: Data?)
    case needsReshare
}

enum FolderBookmark {
    static func resolve(bookmark: Data?, using resolver: some FolderBookmarkResolving) -> FolderResolution {
        guard let bookmark else { return .none }
        guard let resolved = try? resolver.resolve(bookmark: bookmark) else { return .needsReshare }
        guard resolved.isStale else { return .accessible(resolved.url, refreshedBookmark: nil) }
        guard let fresh = try? resolver.makeBookmark(for: resolved.url) else { return .needsReshare }
        return .accessible(resolved.url, refreshedBookmark: fresh)
    }
}

struct SecurityScopedBookmarks: FolderBookmarkResolving {
    func resolve(bookmark: Data) throws -> (url: URL, isStale: Bool) {
        var stale = false
        let url = try URL(resolvingBookmarkData: bookmark, options: .withSecurityScope, relativeTo: nil, bookmarkDataIsStale: &stale)
        return (url, stale)
    }

    func makeBookmark(for url: URL) throws -> Data {
        let started = url.startAccessingSecurityScopedResource()
        defer { if started { url.stopAccessingSecurityScopedResource() } }
        return try url.bookmarkData(options: .withSecurityScope, includingResourceValuesForKeys: nil, relativeTo: nil)
    }
}

// MARK: - Debug launch arguments

struct BridgeLaunchOptions: Equatable {
    var folder: URL?
    var pairingCode: String?
    var skipSetup = false

    /// Reads `-bridgeFolder`, `-bridgePairingCode`, `-bridgeSkipSetup` (only meaningful in DEBUG builds).
    static func parse(_ defaults: UserDefaults) -> BridgeLaunchOptions {
        var options = BridgeLaunchOptions()
        if let path = defaults.string(forKey: "bridgeFolder"), path.hasPrefix("/") {
            options.folder = URL(fileURLWithPath: path, isDirectory: true)
        }
        if let code = defaults.string(forKey: "bridgePairingCode"), code.count == 6, code.allSatisfy(\.isNumber) {
            options.pairingCode = code
        }
        options.skipSetup = defaults.bool(forKey: "bridgeSkipSetup")
        return options
    }
}
