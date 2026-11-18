import Charts
import SwiftUI

/// "Soll/Ist": planned vs. actual power per work interval of a finished workout. Renders nothing without a result.
public struct IntervalComplianceCard: View {
    let workout: StoredWorkout
    @Environment(AppModel.self) private var model
    @Environment(\.dynamicTypeSize) private var typeSize

    public init(workout: StoredWorkout) {
        self.workout = workout
    }

    public var body: some View {
        if let result = model.intervalCompliance(for: workout) {
            Card(title: "Soll/Ist", systemImage: "scope") {
                VStack(alignment: .leading, spacing: 12) {
                    Text(result.summary)
                        .font(.headline)
                        .fixedSize(horizontal: false, vertical: true)
                        .accessibilityIdentifier("compliance.summary")
                    ComplianceChart(result: result)
                        .frame(minHeight: typeSize.isAccessibilitySize ? 220 : 170)
                    VStack(alignment: .leading, spacing: 8) {
                        ForEach(result.intervals) { interval in
                            ComplianceRow(interval: interval, baseline: result.isBaseline)
                        }
                    }
                }
            }
            .accessibilityElement(children: .contain)
            .accessibilityIdentifier("compliance.card")
        }
    }
}

private struct ComplianceChart: View {
    let result: IntervalCompliance.Result

    private struct Point: Identifiable {
        var id: String { "\(series)\(second)" }
        var series: String
        var second: Int
        var watts: Double
    }

    private var points: [Point] {
        let step = 10
        var out: [Point] = []
        for t in stride(from: 0, to: result.targetSeries.count, by: step) {
            out.append(Point(series: "Soll", second: t, watts: result.targetSeries[t]))
        }
        for t in stride(from: 0, to: result.actualSeries.count, by: step) {
            out.append(Point(series: "Ist", second: t, watts: result.actualSeries[t]))
        }
        return out
    }

    var body: some View {
        Chart(points) { p in
            LineMark(x: .value("Minuten", Double(p.second) / 60), y: .value("Watt", p.watts), series: .value("Reihe", p.series))
                .interpolationMethod(p.series == "Soll" ? .stepEnd : .monotone)
                .foregroundStyle(by: .value("Reihe", p.series))
                .lineStyle(StrokeStyle(lineWidth: p.series == "Soll" ? 2 : 2.5, dash: p.series == "Soll" ? [5, 3] : []))
        }
        .chartForegroundStyleScale(["Soll": Color.primary.opacity(0.75), "Ist": Theme.accent])
        .chartXAxis {
            AxisMarks { value in
                AxisGridLine()
                AxisValueLabel {
                    if let minutes = value.as(Double.self) { Text("\(Int(minutes)) min").foregroundStyle(Theme.axisLabel) }
                }
            }
        }
        .chartYAxis {
            AxisMarks(position: .leading) { value in
                AxisGridLine()
                AxisValueLabel {
                    if let watts = value.as(Double.self) { Text("\(Int(watts)) W").foregroundStyle(Theme.axisLabel) }
                }
            }
        }
        .chartLegend(position: .bottom, alignment: .leading)
        .transaction { $0.animation = nil }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Diagramm Soll und Ist")
        .accessibilityValue(result.summary)
        .accessibilityIdentifier("compliance.chart")
    }
}

private struct ComplianceRow: View {
    let interval: IntervalCompliance.Interval
    let baseline: Bool

    private var style: (symbol: String, color: Color, label: String) {
        switch interval.status {
        case .hit: ("checkmark.circle.fill", Theme.done, "getroffen")
        case .under: ("arrow.down.circle.fill", Theme.fatigueLine, "zu leicht")
        case .over: ("arrow.up.circle.fill", Theme.fatigueLine, "zu hart")
        case .missed: ("minus.circle.fill", Theme.rowSecondary, "nicht gefahren")
        }
    }

    private var title: String { baseline ? "Grundlage" : "\(interval.index)" }

    private var line: String {
        var parts = [title, Self.clock(interval.duration), "Soll \(interval.targetWatts) W"]
        if let actual = interval.actualWatts { parts.append("Ist \(Int(actual.rounded())) W") }
        parts.append(style.label)
        return parts.joined(separator: " · ")
    }

    private var spoken: String {
        let what = baseline ? "Grundlage" : "Intervall \(interval.index)"
        var text = "\(what), \(Formatters.duration(interval.duration)), Soll \(interval.targetWatts) Watt"
        if let actual = interval.actualWatts {
            text += ", Ist \(Int(actual.rounded())) Watt, \(Int((abs(interval.deviation) * 100).rounded())) Prozent \(interval.deviation < 0 ? "darunter" : "darüber")"
        }
        return text + ", \(style.label)"
    }

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            Image(systemName: style.symbol).foregroundStyle(style.color).accessibilityHidden(true)
            Text(line)
                .font(.subheadline)
                .foregroundStyle(.primary)
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 0)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(spoken)
        .accessibilityIdentifier("compliance.row.\(interval.index)")
    }

    static func clock(_ seconds: Int) -> String {
        String(format: "%d:%02d", seconds / 60, seconds % 60)
    }
}
