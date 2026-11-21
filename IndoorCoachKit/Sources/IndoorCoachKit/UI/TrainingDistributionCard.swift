import SwiftUI

/// A8 – "Trainingsverteilung" in Leistung: stacked bar of riding time per intensity band (4 or 12 weeks).
struct TrainingDistributionCard: View {
    var rides: [RideSummary]
    var ftp: Int
    var now: Date = .now

    @State private var weeks = 4
    @Environment(AppModel.self) private var model

    static func color(_ band: TrainingDistribution.Band) -> Color {
        switch band {
        case .base: ChartPalette.zone(.z2)
        case .tempo: ChartPalette.zone(.z3)
        case .threshold: ChartPalette.zone(.z5)
        case .unknown: ChartPalette.band
        }
    }

    /// Text colour for the share inside a segment (white or ink on the zone mark, ink on the neutral band).
    static func labelColor(_ band: TrainingDistribution.Band) -> Color {
        switch band {
        case .base: ChartPalette.label(on: .z2)
        case .tempo: ChartPalette.label(on: .z3)
        case .threshold: ChartPalette.label(on: .z5)
        case .unknown: .primary
        }
    }

    var body: some View {
        let result = model.trainingDistribution(rides: rides, weeks: weeks, now: now)
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
            if result.rides > 0 {
                Text("\(result.measuredRides) von \(result.rides) Fahrten mit Sekundendaten gemessen")
                    .font(.footnote.weight(.medium)).foregroundStyle(Theme.rowSecondary)
                    .accessibilityIdentifier("distribution.measured")
            }
            Text("Intensität je Fahrt = NP ÷ FTP (\(ftp) W), ohne NP Ø-Leistung × 1,05. Grundlage unter 0,75, Tempo/Sweet Spot 0,75 bis 0,95, Schwelle und mehr ab 0,95. Gewichtet nach Fahrzeit, Quelle: deine Fahrten der letzten \(weeks) Wochen.")
                .font(.footnote).foregroundStyle(Theme.rowSecondary)
        }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("distribution.card")
    }

    private func bar(_ r: TrainingDistribution.Result) -> some View {
        GeometryReader { proxy in
            SegmentedBar(items: TrainingDistribution.Band.allCases.enumerated().compactMap { n, band in
                guard (r.seconds[band] ?? 0) > 0 else { return nil }
                return SegmentedBar.Item(
                    id: n, value: Double(r.seconds[band] ?? 0), color: Self.color(band),
                    label: TrainingDistribution.segmentLabel(percent: r.percent(band), barWidth: proxy.size.width, textWidth: 30),
                    labelColor: Self.labelColor(band))
            }, variant: .tall)
        }
        .frame(height: SegmentedBar.Variant.tall.height)
        .chartAccessibility(label: "Trainingsverteilung der letzten \(weeks) Wochen", value: summary(r))
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
