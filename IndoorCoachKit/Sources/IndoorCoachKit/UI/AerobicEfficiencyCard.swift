import Charts
import SwiftUI

/// "Aerobe Effizienz" in Leistung: weekly median EF (NP ÷ Ø-Puls) with the 6-vs-6-week trend and data coverage.
struct AerobicEfficiencyCard: View {
    var rides: [RideSummary]
    var ftp: Int
    var range: PerformanceRange
    var now: Date = .now
    @Environment(\.colorScheme) private var scheme

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
        let dark = scheme == .dark
        let values = series.map(\.ef)
        let span = ChartMath.domain(values: values, includeZero: false)
        let ticks = ChartMath.niceTicks(min: span.lowerBound, max: span.upperBound, count: 4)
        let pieces = ChartMath.segments(series.map(\.weekStart), splitWhenGapExceeds: 15 * 86_400)
        let base = ChartMath.areaBase(in: (ticks.first ?? 0)...(ticks.last ?? 1))
        return Chart {
            ForEach(Array(pieces.enumerated()), id: \.offset) { n, range in
                if range.count == 1, let only = series[range].first {
                    // A lone week after a gap has no line to draw: show it as a dot.
                    PointMark(x: .value("Woche", only.weekStart), y: .value("Effizienz", only.ef))
                        .symbolSize(30).foregroundStyle(Theme.accent)
                } else {
                    ForEach(series[range]) { p in
                        if series.count >= 4 {
                            AreaMark(x: .value("Woche", p.weekStart), yStart: .value("Basis", base), yEnd: .value("Effizienz", p.ef), series: .value("Teil", "Fläche\(n)"))
                                .interpolationMethod(.monotone)
                                .foregroundStyle(ChartStyle.area(Theme.accent, dark: dark))
                        }
                        LineMark(x: .value("Woche", p.weekStart), y: .value("Effizienz", p.ef), series: .value("Teil", "Linie\(n)"))
                            .interpolationMethod(ChartStyle.interpolation(pointCount: range.count))
                            .lineStyle(ChartStyle.stroke(.main))
                            .foregroundStyle(Theme.accent)
                    }
                }
            }
            if series.count <= ChartStyle.maxMarkers {
                ForEach(series.dropLast()) { p in
                    OpenMarker(x: .value("Woche", p.weekStart), y: .value("Effizienz", p.ef), color: Theme.accent)
                }
            }
            if let last = series.last {
                HighlightPoint(x: .value("Woche", last.weekStart), y: .value("Effizienz", last.ef), color: Theme.accent, dark: dark)
                PointMark(x: .value("Woche", last.weekStart), y: .value("Effizienz", last.ef))
                    .symbolSize(1).foregroundStyle(.clear)
                    .annotation(position: .top, spacing: 8) {
                        Text(Formatters.decimal(last.ef, digits: 2)).font(ChartStyle.ruleLabelFont).foregroundStyle(Theme.axisLabel)
                    }
            }
        }
        .chartYScale(domain: (ticks.first ?? 0)...(ticks.last ?? 1))
        .chartStyleAxes(yTicks: ticks, yLabel: { ChartMath.format($0, decimals: 1) }, xCount: 3)
        .chartYAxisLabel(position: .topTrailing) {
            Text("W/bpm").font(ChartStyle.axisFont).foregroundStyle(Theme.axisLabel)
        }
        .chartStyleHeight()
        .chartAccessibility(label: "Aerobe Effizienz, Wochenmedian in Watt je Herzschlag", value: Self.summary(series))
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
        func day(_ date: Date) -> String { DayFormatters.shared.string(from: date, format: "d. MMMM", calendar: .current) }
        return "\(series.count) Wochen. Erste Woche ab \(day(first.weekStart)): \(Formatters.decimal(first.ef, digits: 2)). "
            + "Letzte Woche ab \(day(last.weekStart)): \(Formatters.decimal(last.ef, digits: 2))."
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
