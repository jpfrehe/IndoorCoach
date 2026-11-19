import Foundation

extension DemoData {
    /// Demo-Ruhepuls für „Dein Herz im Winter Arc“: ein Tageswert je Tag der letzten 110 Tage, sinkt von 58 auf 53 bpm.
    /// Deterministisch, synthetisch; nur im Demo-Modus gezeigt.
    static func heartRestingDailies(now: Date = .now, calendar: Calendar = .current) -> [HealthDaily] {
        let today = calendar.startOfDay(for: now)
        let source = HealthSourceRef(name: "Demo", bundleID: "demo")
        var rng = SeededGenerator(seed: 58)
        return (0..<110).compactMap { back in
            guard let day = calendar.date(byAdding: .day, value: -back, to: today) else { return nil }
            let progress = 1 - Double(back) / 109
            let value = 58 - 5 * progress + Double.random(in: -0.8...0.8, using: &rng)
            return HealthDaily(date: day, metric: .restingHR, value: value.rounded(), source: source)
        }.reversed()
    }

    /// Demo-Krafteinheiten über die letzten gut drei Monate (ein bis zwei je Woche), nur für die Karte.
    static func heartStrengthStarts(now: Date = .now, calendar: Calendar = .current) -> [Date] {
        let today = calendar.startOfDay(for: now)
        return stride(from: 3, through: 95, by: 5).compactMap { calendar.date(byAdding: .day, value: -$0, to: today) }
    }

    /// Beginn des Demo-Fensters: der Demo-Winter ist schon einige Monate alt, damit die Karte Monate vergleichen kann.
    static func heartWindowStart(now: Date = .now, calendar: Calendar = .current) -> Date {
        let back = calendar.date(byAdding: .day, value: -75, to: now) ?? now
        return calendar.dateInterval(of: .month, for: back)?.start ?? back
    }
}
