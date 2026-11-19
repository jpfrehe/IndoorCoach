import Foundation

/// Anzeige-Texte der Live Activity, abgeleitet aus `RecordingLiveState`. Reine Logik ohne ActivityKit/SwiftUI,
/// damit sie auf dem Mac getestet werden kann. Der Pulswert wird nie geloggt.
public struct RecordingLiveDisplay: Equatable, Sendable {
    public let state: RecordingLiveState

    public init(_ state: RecordingLiveState) { self.state = state }

    /// Ziffern für die große Pulsanzeige; „–“ ohne Messwert.
    public var heartRateText: String {
        guard let bpm = state.heartRate, bpm > 0 else { return "–" }
        return String(bpm)
    }

    public var hasHeartRate: Bool { (state.heartRate ?? 0) > 0 }

    /// Warnzeile, wenn der Gurt nicht verbunden ist.
    public var connectionWarning: String? { state.connected ? nil : "Gurt getrennt" }

    /// Block bzw. Übung; leere Titel zählen als nicht vorhanden.
    public var blockText: String? {
        guard let title = state.blockTitle?.trimmingCharacters(in: .whitespacesAndNewlines), !title.isEmpty else { return nil }
        return title
    }

    /// Ende des aktuellen Blocks, nur solange es noch in der Zukunft liegt (sonst läuft kein Countdown).
    public func blockEnd(at now: Date) -> Date? {
        guard let end = state.blockEndsAt, end > now else { return nil }
        return end
    }

    /// SF Symbol je Art der Aufzeichnung.
    public var kindSymbol: String {
        switch state.kind {
        case .ride: "bicycle"
        case .strength: "dumbbell.fill"
        case .other: "figure.indoor.cycle"
        }
    }

    /// VoiceOver-Satz für die ganze Aktivität.
    public func accessibilityLabel(at now: Date) -> String {
        var parts = [state.title]
        parts.append(hasHeartRate ? "Puls \(heartRateText) Schläge pro Minute" : "Kein Pulswert")
        if let warning = connectionWarning { parts.append(warning) }
        if let block = blockText {
            if let end = blockEnd(at: now) {
                parts.append("\(block), noch \(Formatters.duration(Int(end.timeIntervalSince(now).rounded())))")
            } else {
                parts.append(block)
            }
        }
        return parts.joined(separator: ", ")
    }

    /// Ohne neue Daten gilt die Anzeige nach dieser Zeit als veraltet.
    public static let staleInterval: TimeInterval = 120

    public static func staleDate(from now: Date) -> Date { now.addingTimeInterval(staleInterval) }
}
