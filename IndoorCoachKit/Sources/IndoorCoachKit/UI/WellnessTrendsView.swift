import Charts
import SwiftUI

/// „Erholung“ (docs/17 §2.1, §2.2; B52, B53): Ruhepuls, HRV, Schlafdauer und Atemfrequenz als Trendlinie mit Basisband
/// (Median ± MAD der letzten 28 Tage), Quelle sichtbar. Trend statt Tageswert; vor 21 Tagen mit Werten nur ein Hinweis.
struct WellnessTrendsView: View {
    @Environment(AppModel.self) private var model
    @State private var refreshed = 0

    private struct Kind: Identifiable {
        var metric: HealthMetric
        var title: String
        var unit: String
        var digits: Int
        var id: String { metric.rawValue }
    }

    private static let kinds = [
        Kind(metric: .restingHR, title: "Ruhepuls", unit: "bpm", digits: 0),
        Kind(metric: .hrvSDNN, title: "HRV (SDNN)", unit: "ms", digits: 0),
        Kind(metric: .sleepHours, title: "Schlafdauer", unit: "h", digits: 1),
        Kind(metric: .respiratoryRate, title: "Atemfrequenz", unit: "/min", digits: 1),
    ]

    var body: some View {
        ScrollView {
            VStack(spacing: 16) {
                if !model.healthEnabled {
                    Card(title: "Apple Health ist aus", systemImage: "heart.text.square") {
                        Text("Schalte Apple Health unter Profil → Dienste & Geräte → Apple Health ein, dann zeigt IndoorCoach hier deine Erholungswerte als Trend.")
                            .font(.subheadline).foregroundStyle(Theme.rowSecondary)
                    }
                } else {
                    ForEach(Self.kinds) { kind in
                        card(kind, trend: model.wellnessTrend(kind.metric))
                    }
                    Text("Ein Trend zeigt, wie deine Werte zu deiner eigenen Basis stehen (Median der letzten 28 Tage). Einzelne Tage sagen wenig: "
                         + "Schlaf, Hitze, Alkohol und Stress verschieben sie. Das ist keine medizinische Aussage.")
                        .font(.footnote).foregroundStyle(Theme.rowSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            .padding(.horizontal)
            .padding(.bottom, 24)
        }
        .background(Theme.canvas)
        .navigationTitle("Erholung")
        .inlineNavigationTitle()
        .task {
            await model.refreshWellness()
            refreshed += 1
        }
        .id(refreshed)
    }

    private func card(_ kind: Kind, trend: WellnessTrend) -> some View {
        Card(title: kind.title, systemImage: "waveform.path.ecg") {
            if trend.isReady, let baseline = trend.baseline {
                headline(kind, trend: trend, baseline: baseline)
                chart(kind, trend: trend, baseline: baseline)
            } else {
                Text(trend.dayCount == 0 ? "Noch keine Werte." : "Noch zu wenige Werte: \(trend.dayCount) von \(WellnessTrend.minDays) Tagen.")
                    .font(.subheadline).foregroundStyle(Theme.rowSecondary)
                    .accessibilityIdentifier("wellness.\(kind.metric.rawValue).notEnough")
            }
            if let source = trend.source {
                Text("Quelle: \(source.name)")
                    .font(.caption.weight(.semibold))
                    .padding(.horizontal, 8).padding(.vertical, 3)
                    .background(Capsule().fill(Color.primary.opacity(0.08)))
                    .accessibilityIdentifier("wellness.\(kind.metric.rawValue).source")
            }
        }
        .accessibilityElement(children: .contain)
    }

    private func headline(_ kind: Kind, trend: WellnessTrend, baseline: Double) -> some View {
        let recent = trend.mean3 ?? trend.points.last?.value ?? baseline
        return VStack(alignment: .leading, spacing: 2) {
            Text("Basis \(Formatters.decimal(baseline, digits: kind.digits)) \(kind.unit)").font(.headline)
            Text("Letzte 3 Tage \(Formatters.decimal(recent, digits: kind.digits)) \(kind.unit)")
                .font(.subheadline).foregroundStyle(Theme.rowSecondary)
        }
    }

    private func chart(_ kind: Kind, trend: WellnessTrend, baseline: Double) -> some View {
        let spread = trend.mad ?? 0
        let first = trend.points.first?.date ?? .now, last = trend.points.last?.date ?? .now
        return Chart {
            ForEach([first, last], id: \.self) { day in
                AreaMark(x: .value("Tag", day), yStart: .value("Basis −", baseline - spread), yEnd: .value("Basis +", baseline + spread))
                    .foregroundStyle(Color.primary.opacity(0.08))
            }
            RuleMark(y: .value("Basis", baseline))
                .lineStyle(StrokeStyle(lineWidth: 1, dash: [4, 3]))
                .foregroundStyle(Theme.rowSecondary)
            ForEach(trend.points, id: \.date) { point in
                LineMark(x: .value("Tag", point.date), y: .value(kind.title, point.value))
                    .foregroundStyle(Theme.accent)
                    .interpolationMethod(.monotone)
            }
        }
        .chartYScale(domain: .automatic(includesZero: false))
        .frame(height: 140)
        .accessibilityElement()
        .accessibilityLabel("\(kind.title): Verlauf der letzten 28 Tage mit Basisband")
        .accessibilityIdentifier("wellness.\(kind.metric.rawValue).chart")
    }
}
