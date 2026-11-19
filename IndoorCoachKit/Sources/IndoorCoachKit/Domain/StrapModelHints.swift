import Foundation

/// Knowledge about common chest straps (concept doc 17 §3.2). Hints only – nothing here blocks a connection.
public struct StrapModelHint: Equatable, Sendable {
    public var model: String
    /// Simultaneous BLE connections the strap supports; nil when unknown.
    public var bleConnections: Int?
    public var note: String
}

public enum StrapModelHints {
    private static let garmin = "Drei Verbindungen, RR-Intervalle evtl. nur auf einem Kanal."
    private static let wahoo = "Drei gleichzeitige Bluetooth-Verbindungen, RR-Intervalle werden gesendet."

    private static let table: [(needle: String, hint: StrapModelHint)] = [
        // Order matters: the more specific names come first (H9Z before H9, TICKR X before TICKR).
        ("h9z", StrapModelHint(model: "Coospo H9Z", bleConnections: 2, note: "Zwei gleichzeitige Bluetooth-Verbindungen.")),
        ("tickr x", StrapModelHint(model: "Wahoo TICKR X", bleConnections: 3, note: wahoo)),
        ("tickr", StrapModelHint(model: "Wahoo TICKR", bleConnections: 3, note: wahoo)),
        ("h10", StrapModelHint(model: "Polar H10", bleConnections: 2,
                               note: "Zwei Verbindungen, sobald die Mehrfachverbindung in der App Polar Beat aktiviert ist (Gurt dort einmal verbinden).")),
        ("h9", StrapModelHint(model: "Polar H9", bleConnections: 1,
                              note: "Nur eine Bluetooth-Verbindung. Läuft MyWhoosh am Mac mit demselben Gurt, bricht diese Verbindung ab.")),
        ("hrm-pro", StrapModelHint(model: "Garmin HRM-Pro Plus", bleConnections: 3, note: garmin)),
        ("hrm pro", StrapModelHint(model: "Garmin HRM-Pro Plus", bleConnections: 3, note: garmin)),
        ("hrm 600", StrapModelHint(model: "Garmin HRM 600", bleConnections: 3, note: garmin)),
        ("hrm600", StrapModelHint(model: "Garmin HRM 600", bleConnections: 3, note: garmin))
    ]

    public static let unknown = StrapModelHint(
        model: "Unbekanntes Modell", bleConnections: nil,
        note: "Wie viele Geräte gleichzeitig verbunden sein dürfen, steht in der Anleitung deines Gurts. Der Mehrfachverbindungs-Test zeigt es dir direkt.")

    public static func hint(forName name: String?) -> StrapModelHint {
        guard let lower = name?.lowercased() else { return unknown }
        return table.first { lower.contains($0.needle) }?.hint ?? unknown
    }
}
