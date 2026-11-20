import Foundation

/// Kopfzeile einer Woche im Verlauf: Gesamtzeit aller Einheiten, TSS der Fahrten und Muskel-Last der Krafteinheiten.
/// Jede Spur erscheint nur, wenn sie Einheiten hat, damit der Filter „Kraft“ nicht „TSS 0“ zeigt.
public enum HistoryWeekSummary {
    public static func text(rides: [RideSummary], strength: [StrengthSession], ftp: Int, thresholdHeartRate: Int?) -> String {
        let seconds = rides.reduce(0) { $0 + $1.movingTime } + strength.reduce(0) { $0 + max(0, $1.durationSeconds) }
        var parts = [Formatters.duration(seconds)]
        if !rides.isEmpty {
            let tss = rides.reduce(0) { $0 + TrainingLoad.estimateTSS(for: $1, ftp: ftp, thresholdHeartRate: thresholdHeartRate).tss }
            parts.append("TSS \(Int(tss.rounded()))")
        }
        let loads = strength.compactMap(MuscleLoad.load(of:))
        if !loads.isEmpty {
            parts.append("Last \(Int(loads.reduce(0, +).rounded()))")
        }
        return parts.joined(separator: " · ")
    }
}
