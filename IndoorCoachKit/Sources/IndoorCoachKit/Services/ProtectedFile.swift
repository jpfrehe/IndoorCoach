import Foundation

/// Gesundheitsnahe JSON-Dateien in Application Support (Erholungswerte, Morgen-HRV, laufende und wartende Aufzeichnung):
/// atomar schreiben, mit Dateischutz und vom iCloud-/Geräte-Backup ausgenommen. Application Support wird sonst gesichert.
public enum ProtectedFile {
    /// Vollschutz für Dateien, die nur bei entsperrtem Gerät geschrieben werden. Dateien, die auch bei gesperrtem Bildschirm
    /// entstehen (Aufzeichnung läuft, Hintergrund-Abgleich), brauchen `untilFirstUnlock`, sonst schlägt das Schreiben fehl.
    public enum Protection: Sendable {
        case complete
        case untilFirstUnlock

        var option: Data.WritingOptions {
            #if os(iOS)
            switch self {
            case .complete: .completeFileProtection
            case .untilFirstUnlock: .completeFileProtectionUntilFirstUserAuthentication
            }
            #else
            []
            #endif
        }
    }

    /// Schreibt `data` atomar nach `url` (legt den Ordner an) und schließt die Datei vom Backup aus.
    public static func write(_ data: Data, to url: URL, protection: Protection = .complete) throws {
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try data.write(to: url, options: [.atomic, protection.option])
        try excludeFromBackup(url)
    }

    /// Setzt `isExcludedFromBackup`; die Datei muss existieren.
    public static func excludeFromBackup(_ url: URL) throws {
        var values = URLResourceValues()
        values.isExcludedFromBackup = true
        var target = url
        try target.setResourceValues(values)
    }

    public static func isExcludedFromBackup(_ url: URL) -> Bool {
        (try? url.resourceValues(forKeys: [.isExcludedFromBackupKey]).isExcludedFromBackup) ?? false
    }
}
