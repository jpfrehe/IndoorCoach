import Charts
import SwiftUI

/// A6 – "eFTP-Verlauf" in Leistung: 95 % of the best measured 20 minutes per 4-week window over 6 months,
/// with the profile FTP as reference line. Measured values only.
struct FTPHistoryCard: View {
    var rides: [RideSummary]
    var ftp: Int
    var now: Date = .now

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
                Text("Für den Verlauf braucht es gemessene 20-Minuten-Leistungen (Fahrten mit Sekundendaten, z. B. FIT-Import) in mindestens zwei 4-Wochen-Fenstern.")
                    .font(.subheadline).foregroundStyle(Theme.rowSecondary)
            }
            Text("eFTP = 95 % der besten gemessenen 20 Minuten in den 4 Wochen bis zum jeweiligen Datum, über 6 Monate. Fahrten ohne Sekundendaten zählen nicht. Die gestrichelte Linie ist deine Profil-FTP (\(ftp) W).")
                .font(.footnote).foregroundStyle(Theme.rowSecondary)
        }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("ftpHistory.card")
    }

    private func chart(_ series: [FTPHistory.Point]) -> some View {
        Chart {
            ForEach(series) { p in
                LineMark(x: .value("Fenster bis", p.date), y: .value("eFTP", p.eftp))
                    .foregroundStyle(Theme.fitnessLine)
                    .lineStyle(StrokeStyle(lineWidth: 2.5, lineCap: .round))
                    .interpolationMethod(.monotone)
                PointMark(x: .value("Fenster bis", p.date), y: .value("eFTP", p.eftp))
                    .foregroundStyle(Theme.fitnessLine)
                    .symbolSize(30)
            }
            if ftp > 0 {
                RuleMark(y: .value("Profil-FTP", ftp))
                    .foregroundStyle(Theme.accent.opacity(0.8))
                    .lineStyle(StrokeStyle(lineWidth: 1.5, dash: [5, 4]))
                    .annotation(position: .top, alignment: .leading) {
                        Text("Profil-FTP \(ftp) W").font(.caption2.weight(.semibold)).foregroundStyle(Theme.accent)
                    }
            }
        }
        .chartYScale(domain: .automatic(includesZero: false))
        .chartXAxis {
            AxisMarks(values: .stride(by: .month)) { _ in
                AxisGridLine()
                AxisValueLabel(format: .dateTime.month(.abbreviated).locale(Locale.de))
                    .foregroundStyle(Theme.axisLabel)
            }
        }
        .chartYAxis { AxisMarks { _ in AxisGridLine(); AxisValueLabel().foregroundStyle(Theme.axisLabel) } }
        .chartYAxisLabel("Watt")
        .frame(height: 170)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Verlauf der geschätzten FTP über 6 Monate")
        .accessibilityValue(Self.summary(series, ftp: ftp))
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
