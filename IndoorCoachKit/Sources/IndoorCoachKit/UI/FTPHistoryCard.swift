import Charts
import SwiftUI

/// A6 – "eFTP-Verlauf" in Leistung: 95 % of the best measured 20 minutes per 4-week window over 6 months,
/// with the profile FTP as reference line. Measured values only.
struct FTPHistoryCard: View {
    var rides: [RideSummary]
    var ftp: Int
    var now: Date = .now
    @Environment(\.colorScheme) private var scheme

    var body: some View {
        let series = FTPHistory.series(rides: rides, now: now)
        Card(title: "eFTP-Verlauf", systemImage: "chart.xyaxis.line") {
            if series.count >= 2 {
                chart(series)
                if let last = series.last, let first = series.first {
                    Text("Zuletzt \(last.eftp) W, vor \(Self.span(first.date, last.date)) waren es \(first.eftp) W.")
                        .font(.subheadline.weight(.semibold))
                }
            } else {
                ChartEmptyState(message: "Für den Verlauf braucht es gemessene 20-Minuten-Leistungen (Fahrten mit Sekundendaten, z. B. FIT-Import) in mindestens zwei 4-Wochen-Fenstern.")
            }
            Text("eFTP = 95 % der besten gemessenen 20 Minuten in den 4 Wochen bis zum jeweiligen Datum, über 6 Monate. Fahrten ohne Sekundendaten zählen nicht. Die gestrichelte Linie ist deine Profil-FTP (\(ftp) W).")
                .font(.footnote).foregroundStyle(Theme.rowSecondary)
        }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("ftpHistory.card")
    }

    private func chart(_ series: [FTPHistory.Point]) -> some View {
        let dark = scheme == .dark
        let values = series.map { Double($0.eftp) } + (ftp > 0 ? [Double(ftp)] : [])
        let ticks = ChartMath.niceTicks(min: values.min() ?? 0, max: values.max() ?? 1, count: 4)
        let base = ChartMath.areaBase(in: (ticks.first ?? 0)...(ticks.last ?? 1))
        let few = series.count <= ChartStyle.maxMarkers
        return Chart {
            ForEach(series) { p in
                AreaMark(x: .value("Fenster bis", p.date), yStart: .value("Basis", base), yEnd: .value("eFTP", Double(p.eftp)))
                    .interpolationMethod(ChartStyle.interpolation(pointCount: series.count))
                    .foregroundStyle(ChartStyle.area(Theme.accent, dark: dark))
                LineMark(x: .value("Fenster bis", p.date), y: .value("eFTP", p.eftp))
                    .interpolationMethod(ChartStyle.interpolation(pointCount: series.count))
                    .lineStyle(ChartStyle.stroke(.main))
                    .foregroundStyle(Theme.accent)
            }
            if few {
                ForEach(series.dropLast()) { p in
                    OpenMarker(x: .value("Fenster bis", p.date), y: .value("eFTP", p.eftp), color: Theme.accent)
                }
            }
            if ftp > 0 {
                ChartRule(y: .value("Profil-FTP", ftp), kind: .target, label: "Profil-FTP \(ftp) W")
            }
            if let last = series.last {
                HighlightPoint(x: .value("Fenster bis", last.date), y: .value("eFTP", last.eftp), color: Theme.accent, dark: dark)
                PointMark(x: .value("Fenster bis", last.date), y: .value("eFTP", last.eftp))
                    .symbolSize(1).foregroundStyle(.clear)
                    .annotation(position: .top, spacing: 8) {
                        Text("\(last.eftp) W").font(ChartStyle.ruleLabelFont).foregroundStyle(Theme.axisLabel)
                    }
            }
        }
        .chartYScale(domain: (ticks.first ?? 0)...(ticks.last ?? 1))
        .chartStyleAxes(yTicks: ticks, yLabel: { ChartMath.format($0) })
        .chartStyleHeight()
        .chartAccessibility(label: "Verlauf der geschätzten FTP über 6 Monate", value: Self.summary(series, ftp: ftp))
        .accessibilityIdentifier("ftpHistory.chart")
    }

    static func span(_ from: Date, _ to: Date) -> String {
        let weeks = max(1, Int((to.timeIntervalSince(from) / (7 * 86_400)).rounded()))
        return weeks == 1 ? "1 Woche" : "\(weeks) Wochen"
    }

    static func summary(_ series: [FTPHistory.Point], ftp: Int) -> String {
        guard let first = series.first, let last = series.last else { return "Keine Daten" }
        let low = series.map(\.eftp).min() ?? last.eftp, high = series.map(\.eftp).max() ?? last.eftp
        return "\(series.count) Werte. Zuerst \(first.eftp) Watt, zuletzt \(last.eftp) Watt, niedrigster \(low), höchster \(high). Profil-FTP \(ftp) Watt."
    }
}
