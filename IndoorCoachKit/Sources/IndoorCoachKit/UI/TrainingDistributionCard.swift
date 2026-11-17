import Charts
import SwiftUI

/// A8 – "Trainingsverteilung" in Leistung: stacked bar of riding time per intensity band (4 or 12 weeks).
struct TrainingDistributionCard: View {
    var rides: [RideSummary]
    var ftp: Int
    var now: Date = .now

    @State private var weeks = 4

    static func color(_ band: TrainingDistribution.Band) -> Color {
        switch band {
        case .base: Theme.fill(.z2)
        case .tempo: Theme.fill(.z3)
        case .threshold: Theme.fill(.z5)
        case .unknown: Color.gray.opacity(0.35)
        }
    }

    var body: some View {
        let result = TrainingDistribution.distribution(rides: rides, ftp: ftp, weeks: weeks, now: now)
        Card(title: "Trainingsverteilung", systemImage: "chart.bar.doc.horizontal") {
            Picker("Zeitraum", selection: $weeks) {
                Text("4 Wochen").tag(4)
                Text("12 Wochen").tag(12)
            }
            .pickerStyle(.segmented)
            .accessibilityIdentifier("distribution.range")

            if result.totalSeconds == 0 {
                Text(TrainingDistribution.advice(result)).font(.subheadline).foregroundStyle(Theme.rowSecondary)
            } else {
                Text(TrainingDistribution.advice(result)).font(.subheadline.weight(.semibold))
                    .fixedSize(horizontal: false, vertical: true)
                    .accessibilityIdentifier("distribution.advice")
                bar(result)
                VStack(alignment: .leading, spacing: 6) {
                    ForEach(TrainingDistribution.Band.allCases) { band in
                        if (result.seconds[band] ?? 0) > 0 || band != .unknown { row(band, result) }
                    }
                }
            }
            Text("Intensität je Fahrt = NP ÷ FTP (\(ftp) W), ohne NP Ø-Leistung × 1,05. Grundlage unter 0,75, Tempo/Sweet Spot 0,75 bis 0,95, Schwelle und mehr ab 0,95. Gewichtet nach Fahrzeit, Quelle: deine Fahrten der letzten \(weeks) Wochen.")
                .font(.footnote).foregroundStyle(Theme.rowSecondary)
        }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("distribution.card")
    }

    private func bar(_ r: TrainingDistribution.Result) -> some View {
        Chart(TrainingDistribution.Band.allCases) { band in
            BarMark(x: .value("Anteil", r.seconds[band] ?? 0), y: .value("Zeitraum", "Verteilung"), stacking: .normalized)
                .foregroundStyle(Self.color(band))
        }
        .chartXAxis(.hidden)
        .chartYAxis(.hidden)
        .chartLegend(.hidden)
        .frame(height: 36)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Trainingsverteilung der letzten \(weeks) Wochen")
        .accessibilityValue(summary(r))
        .accessibilityIdentifier("distribution.chart")
    }

    private func row(_ band: TrainingDistribution.Band, _ r: TrainingDistribution.Result) -> some View {
        HStack(spacing: 8) {
            Circle().fill(Self.color(band)).frame(width: 12, height: 12).accessibilityHidden(true)
            Text(band.label).font(.subheadline)
            Spacer(minLength: 8)
            Text("\(r.percent(band)) %").font(.subheadline.weight(.semibold)).monospacedDigit()
        }
        .accessibilityElement(children: .combine)
    }

    private func summary(_ r: TrainingDistribution.Result) -> String {
        TrainingDistribution.Band.allCases
            .filter { (r.seconds[$0] ?? 0) > 0 }
            .map { "\($0.shortLabel) \(r.percent($0)) Prozent" }
            .joined(separator: ", ")
    }
}
