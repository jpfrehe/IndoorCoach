import Charts
import SwiftUI

/// "Soll/Ist": planned vs. actual power per work interval of a finished workout. Renders nothing without a result.
public struct IntervalComplianceCard: View {
    let workout: StoredWorkout
    @Environment(AppModel.self) private var model
    @State private var selectedMinute: Double?

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
                    ComplianceChart(result: result, definition: workout.definition, ftp: model.profile.ftp,
                                    selectedMinute: $selectedMinute)
                    VStack(alignment: .leading, spacing: 8) {
                        ForEach(result.intervals) { interval in
                            ComplianceRow(interval: interval, baseline: result.isBaseline,
                                          isUnderFinger: selectedMinute.map { Self.contains(interval, minute: $0) } ?? false)
                        }
                    }
                }
            }
            .accessibilityElement(children: .contain)
            .accessibilityIdentifier("compliance.card")
        }
    }
}

extension IntervalComplianceCard {
    /// The interval whose plan time span contains `minute` (marks the row under the finger).
    static func contains(_ interval: IntervalCompliance.Interval, minute: Double) -> Bool {
        let t = minute * 60
        return t >= Double(interval.start) && t < Double(interval.start + interval.duration)
    }
}

private struct ComplianceChart: View {
    let result: IntervalCompliance.Result
    let definition: WorkoutDefinition
    let ftp: Int
    @Binding var selectedMinute: Double?
    @Environment(\.colorScheme) private var scheme
    @Environment(\.displayScale) private var displayScale

    private var scale: CGFloat { max(displayScale, 1) }

    /// Watts at a second of the plan timeline.
    private func value(_ series: [Double], at minute: Double) -> Double? {
        let i = Int(minute * 60)
        return series.indices.contains(i) ? series[i] : nil
    }

    var body: some View {
        let dark = scheme == .dark
        let soll = ChartSeries.targetSteps(result.targetSeries)
        let ist = ChartSeries.smoothedActual(result.actualSeries)
        let totalMinutes = max(Double(max(definition.totalDuration, result.targetSeries.count)) / 60, 1.0 / 60)
        let top = WorkoutProfileGeometry.domainTop(for: definition, variant: .detail) * Double(ftp)
        let ticks = ChartMath.niceTicks(min: 0, max: top, count: 4).filter { $0 <= top + 1e-6 }
        let minute = selectedMinute.map { min(max($0, 0), totalMinutes) }
        let shownSoll = minute.flatMap { value(result.targetSeries, at: $0) }
        let shownIst = minute.flatMap { value(result.actualSeries, at: $0) }
        let meanSoll = result.targetSeries.isEmpty ? 0 : result.targetSeries.reduce(0, +) / Double(result.targetSeries.count)
        let running = result.actualSeries.filter { $0 > 0 }
        let meanIst = running.isEmpty ? 0 : running.reduce(0, +) / Double(running.count)
        let sentence = result.summary
        VStack(alignment: .leading, spacing: 8) {
            ChartCardHeader(items: [
                .init(label: minute == nil ? "Soll Ø" : "Soll", value: watts(minute == nil ? meanSoll : shownSoll),
                      color: ChartPalette.reference, marker: .dashed),
                .init(label: minute == nil ? "Ist Ø" : "Ist", value: watts(minute == nil ? meanIst : shownIst), color: Theme.accent),
            ], selectionTitle: minute.map { IntervalComplianceCard.clock(Int($0 * 60)) }, resetTitle: "Aufheben",
                            onReset: { selectedMinute = nil })
            Chart {
                ForEach(Array(soll.enumerated()), id: \.offset) { _, p in
                    LineMark(x: .value("Minuten", p.minute), y: .value("Watt", min(p.watts, top)), series: .value("Reihe", "Soll"))
                        .interpolationMethod(.stepEnd)
                        .foregroundStyle(ChartPalette.reference).lineStyle(ChartStyle.stroke(.target))
                }
                ForEach(Array(ist.enumerated()), id: \.offset) { _, p in
                    LineMark(x: .value("Minuten", p.minute), y: .value("Watt", min(p.watts, top)), series: .value("Reihe", "Ist"))
                        .interpolationMethod(.monotone)
                        .foregroundStyle(Theme.accent).lineStyle(ChartStyle.stroke(.main))
                }
                if let minute, let shownIst {
                    HighlightPoint(x: .value("Minuten", minute), y: .value("Watt", min(shownIst, top)), color: Theme.accent,
                                   baseline: .value("Basis", 0), dark: dark)
                }
            }
            .chartXScale(domain: 0...totalMinutes)
            .chartYScale(domain: 0...top)
            .chartXSelection(value: $selectedMinute)
            .chartGesture { proxy in SpatialTapGesture().onEnded { proxy.selectXValue(at: $0.location.x) } }
            .chartStyleAxes(yTicks: ticks, yLabel: { v in ChartMath.format(v) + (v == ticks.last ? " W" : "") }, showsX: false)
            .chartXAxis {
                AxisMarks(values: ChartMath.minuteTicks(total: totalMinutes * 60)) { value in
                    AxisValueLabel {
                        if let m = value.as(Double.self) { Text("\(Int(m)) min") }
                    }
                    .font(ChartStyle.axisFont).foregroundStyle(ChartStyle.axisColor)
                }
            }
            // The plan as a faint backdrop: the same blocks as the workout profile, decorative only.
            .chartBackground { proxy in
                GeometryReader { geo in
                    if let anchor = proxy.plotFrame {
                        let frame = geo[anchor]
                        let origin = CGPoint(x: (frame.minX * scale).rounded() / scale, y: (frame.minY * scale).rounded() / scale)
                        let size = CGSize(width: (frame.width * scale).rounded() / scale, height: (frame.height * scale).rounded() / scale)
                        Canvas { context, canvasSize in
                            let blocks = WorkoutProfileGeometry.make(definition: definition, size: canvasSize, scale: scale, variant: .detail)
                            context.opacity = 0.2
                            WorkoutProfileRenderer.draw(blocks, in: &context, size: canvasSize, scale: scale,
                                                        style: WorkoutProfileRenderer.Style())
                        }
                        .frame(width: size.width, height: size.height)
                        .offset(x: origin.x, y: origin.y)
                        .allowsHitTesting(false)
                    }
                }
            }
            .transaction { $0.animation = nil }
            .chartStyleHeight(ChartStyle.heightNormal)
            .chartAccessibility(
                label: "Diagramm Soll und Ist", value: sentence,
                descriptor: ChartDescriptor(
                    title: "Soll und Ist", summary: sentence, xTitle: "Minuten", yTitle: "Watt",
                    series: [.init(name: "Soll", points: soll.map { ($0.minute, $0.watts) }, isContinuous: false),
                             .init(name: "Ist", points: ist.map { ($0.minute, $0.watts) })]))
            .accessibilityIdentifier("compliance.chart")
        }
    }

    private func watts(_ value: Double?) -> String { value.map { "\(Int($0.rounded())) W" } ?? "–" }
}

private struct ComplianceRow: View {
    let interval: IntervalCompliance.Interval
    let baseline: Bool
    var isUnderFinger = false

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
        .padding(.vertical, 2)
        .background(isUnderFinger ? Theme.softFill : Color.clear, in: RoundedRectangle(cornerRadius: 8))
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(spoken)
        .accessibilityIdentifier("compliance.row.\(interval.index)")
    }

    static func clock(_ seconds: Int) -> String { IntervalComplianceCard.clock(seconds) }
}

extension IntervalComplianceCard {
    static func clock(_ seconds: Int) -> String {
        String(format: "%d:%02d", seconds / 60, seconds % 60)
    }
}
