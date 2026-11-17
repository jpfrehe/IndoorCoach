import Charts
import SwiftUI

/// "Aerobe Effizienz" in Leistung: weekly median EF (NP ÷ Ø-Puls) with the 6-vs-6-week trend and data coverage.
struct AerobicEfficiencyCard: View {
    var rides: [RideSummary]
    var ftp: Int
    var range: PerformanceRange
    var now: Date = .now

    var body: some View {
        let start = now.addingTimeInterval(-Double(range.days) * 86_400)
        let series = AerobicEfficiency.weeklySeries(rides: rides, ftp: ftp, from: start, to: now)
        let trend = AerobicEfficiency.trend(rides: rides, ftp: ftp, now: now)
        let coverage = AerobicEfficiency.coverage(rides: rides, ftp: ftp, from: start, to: now)
        Card(title: "Aerobe Effizienz", systemImage: "heart.text.square") {
            if let trend {
                HStack(alignment: .firstTextBaseline, spacing: 10) {
                    StatTile(title: "Veränderung (6 gegen 6 Wochen)", value: Self.percent(trend.changePercent))
                    Spacer(minLength: 8)
                    JellyChip(text: Self.directionLabel(trend.direction), systemImage: Self.symbol(trend.direction),
                              fill: trend.direction == .declining ? Theme.softFill : Theme.fill(.z2))
                        .fixedSize()
                }
                Text(trend.text).font(.subheadline.weight(.semibold))
                    .accessibilityIdentifier("efficiency.trend")
            } else {
                Text("Für einen Trend braucht es je mindestens 2 passende Fahrten in den letzten 6 Wochen und in den 6 Wochen davor.")
                    .font(.subheadline).foregroundStyle(Theme.rowSecondary)
            }

            if series.count >= 2 { chart(series) }

            Label(coverageText(coverage), systemImage: "info.circle")
                .font(.footnote).foregroundStyle(Theme.rowSecondary)
                .accessibilityIdentifier("efficiency.coverage")
            if coverage.isLow {
                Label("Trag einen Pulsgurt, damit die Effizienz berechnet werden kann.", systemImage: "heart.fill")
                    .font(.footnote.weight(.semibold)).foregroundStyle(.primary)
                    .accessibilityIdentifier("efficiency.hint")
            }

            Text("Effizienz = Leistung (NP, sonst Ø-Leistung) ÷ Ø-Puls. Steigt der Wert, leistest du mit dem gleichen Puls mehr. Es zählen nur Fahrten ab 20 Minuten mit Leistung und Puls und einer Intensität bis 0,85 (IF), also ruhige bis mittlere Ausdauerfahrten. Quelle: Wochenmedian deiner Fahrten.")
                .font(.footnote).foregroundStyle(Theme.rowSecondary)
        }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("efficiency.card")
    }

    private func chart(_ series: [AerobicEfficiency.WeekPoint]) -> some View {
        Chart(series) { p in
            LineMark(x: .value("Woche", p.weekStart), y: .value("Effizienz", p.ef))
                .foregroundStyle(Theme.fitnessLine)
                .lineStyle(StrokeStyle(lineWidth: 2.5, lineCap: .round))
                .interpolationMethod(.monotone)
            PointMark(x: .value("Woche", p.weekStart), y: .value("Effizienz", p.ef))
                .foregroundStyle(Theme.fitnessLine)
                .symbolSize(36)
        }
        .chartYScale(domain: .automatic(includesZero: false))
        .chartXAxis {
            AxisMarks(values: .automatic(desiredCount: 5)) { _ in
                AxisValueLabel(format: .dateTime.day().month(.defaultDigits).locale(Locale(identifier: "de_DE")))
                    .foregroundStyle(Theme.axisLabel)
            }
        }
        .chartYAxis {
            AxisMarks { _ in
                AxisGridLine()
                AxisValueLabel().foregroundStyle(Theme.axisLabel)
            }
        }
        .chartYAxisLabel("EF (W/bpm)")
        .frame(height: 160)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Aerobe Effizienz, Wochenmedian in Watt je Herzschlag")
        .accessibilityValue(Self.summary(series))
        .accessibilityIdentifier("efficiency.chart")
    }

    // MARK: Text

    static func percent(_ value: Double) -> String {
        let rounded = Int(value.rounded())
        return rounded > 0 ? "+\(rounded) %" : rounded < 0 ? "−\(abs(rounded)) %" : "0 %"
    }

    static func directionLabel(_ d: AerobicEfficiency.Direction) -> String {
        switch d {
        case .improving: "besser"
        case .stable: "stabil"
        case .declining: "schwächer"
        }
    }

    static func symbol(_ d: AerobicEfficiency.Direction) -> String {
        switch d {
        case .improving: "arrow.up.right"
        case .stable: "arrow.right"
        case .declining: "arrow.down.right"
        }
    }

    private func coverageText(_ c: AerobicEfficiency.Coverage) -> String {
        c.total == 0
            ? "Noch keine Fahrten im Zeitraum."
            : "\(c.withData) von \(c.total) Fahrten mit Leistung und Puls"
    }

    static func summary(_ series: [AerobicEfficiency.WeekPoint]) -> String {
        guard let first = series.first, let last = series.last else { return "Keine Daten" }
        let day = DateFormatter()
        day.locale = Locale(identifier: "de_DE")
        day.dateFormat = "d. MMMM"
        return "\(series.count) Wochen. Erste Woche ab \(day.string(from: first.weekStart)): \(Formatters.decimal(first.ef, digits: 2)). "
            + "Letzte Woche ab \(day.string(from: last.weekStart)): \(Formatters.decimal(last.ef, digits: 2))."
    }
}

/// "Effizienz" and (with FIT data) "Entkopplung" tiles in the ride detail.
struct RideEfficiencyCard: View {
    var ride: RideSummary
    var ftp: Int

    /// Raw EF of this ride (needs power and heart rate), whether or not it counts for the trend.
    private var ef: Double? {
        guard let hr = ride.averageHeartrate, hr > 0, let w = ride.weightedAverageWatts ?? ride.averageWatts, w > 0 else { return nil }
        return w / hr
    }

    var body: some View {
        if let ef {
            let counts = AerobicEfficiency.factor(for: ride, ftp: ftp) != nil
            Card(title: "Aerobe Effizienz", systemImage: "heart.text.square") {
                HStack(alignment: .top, spacing: 12) {
                    StatTile(title: "Effizienz", value: Formatters.decimal(ef, digits: 2), unit: "W/bpm")
                    if let d = ride.decoupling {
                        let rating = AerobicEfficiency.rating(decoupling: d)
                        VStack(alignment: .leading, spacing: 6) {
                            StatTile(title: "Entkopplung", value: Formatters.decimal(d, digits: 1), unit: "%")
                            JellyChip(text: rating.label, fill: rating == .stable ? Theme.fill(.z2) : Theme.softFill).fixedSize()
                        }
                    }
                }
                Text(footnote(counts: counts))
                    .font(.caption).foregroundStyle(Theme.rowSecondary)
            }
            .accessibilityElement(children: .combine)
            .accessibilityIdentifier("ride.efficiency")
        }
    }

    private func footnote(counts: Bool) -> String {
        var parts = ["Effizienz = \(ride.weightedAverageWatts != nil ? "NP" : "Ø-Leistung") ÷ Ø-Puls."]
        if ride.decoupling != nil {
            parts.append("Entkopplung: Wie stark die Effizienz von der ersten zur zweiten Fahrthälfte abfällt. Unter 5 % ist stabil.")
        }
        if !counts { parts.append("Zählt nicht für den Trend (unter 20 Minuten oder sehr intensiv).") }
        return parts.joined(separator: " ")
    }
}
