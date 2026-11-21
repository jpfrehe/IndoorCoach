import Charts
import SwiftUI

/// Week-by-week bars (concept 21 §5, D9/D10): one series, the current week in the accent colour, earlier weeks muted
/// (opaque, ≥ 3:1). Optional dashed target/average line, optional selection of a week.
struct WeekBarsChart: View {
    struct Bar: Identifiable, Equatable {
        var weekStart: Date
        var value: Double
        var id: Date { weekStart }
    }

    var bars: [Bar]
    /// Text for the value shown above the current week and used on the axis top.
    var valueLabel: @Sendable (Double) -> String
    /// y axis label for a tick; the unit appears once, on the top value.
    var axisLabel: @Sendable (Double, Bool) -> String
    var line: (value: Double, label: String)?
    var accessibilityLabel: String
    var accessibilityValue: String
    /// Raw x selection from `chartXSelection`; nil disables selection.
    var selection: Binding<Date?>?
    var xStrideCount = 2
    var height: CGFloat = ChartStyle.heightNormal

    /// The bar a selection resolves to.
    static func selectedBar(in bars: [Bar], raw: Date?) -> Bar? {
        guard let raw, let i = ChartMath.nearest(bars.map(\.weekStart), to: raw) else { return nil }
        return bars[i]
    }

    var body: some View {
        let flags = ChartSeries.currentWeekFlags(weekStarts: bars.map(\.weekStart), now: .now)
        let selectedBar = Self.selectedBar(in: bars, raw: selection?.wrappedValue)
        let top = max(bars.map(\.value).max() ?? 0, line?.value ?? 0)
        let ticks = ChartMath.niceTicks(min: 0, max: top, count: 4)
        let upper = ticks.last ?? 1
        let chart = Chart {
            ForEach(Array(bars.enumerated()), id: \.element.id) { index, bar in
                let highlighted = selectedBar.map { $0.weekStart == bar.weekStart } ?? flags[index]
                BarMark(x: .value("Woche", bar.weekStart, unit: .weekOfYear), y: .value("Wert", bar.value), width: .ratio(0.6))
                    .foregroundStyle(highlighted ? Theme.accent : ChartPalette.accentMuted)
                    .cornerRadius(ChartStyle.barCornerRadius)
                    .annotation(position: .top, spacing: 2) {
                        if highlighted && bar.value > 0 {
                            Text(valueLabel(bar.value)).font(ChartStyle.ruleLabelFont).foregroundStyle(Theme.axisLabel)
                        }
                    }
            }
            if let line {
                ChartRule(y: .value("Linie", line.value), kind: .target, label: line.label)
            }
        }
        .chartYScale(domain: 0...upper)
        .chartStyleAxes(yTicks: ticks, yLabel: { [axisLabel, upper] v in axisLabel(v, v == upper) }, showsX: false)
        .chartXAxis {
            AxisMarks(values: .stride(by: .weekOfYear, count: xStrideCount)) { _ in
                AxisValueLabel(format: .dateTime.day().month(.defaultDigits).locale(Locale.de))
                    .font(ChartStyle.axisFont).foregroundStyle(ChartStyle.axisColor)
            }
        }
        .environment(\.locale, Locale.de)
        .chartStyleAnimation(value: selectedBar?.weekStart)
        .chartStyleHeight(height)
        .chartAccessibility(label: accessibilityLabel, value: accessibilityValue)
        if let selection {
            chart
                .chartXSelection(value: selection)
                .chartGesture { proxy in SpatialTapGesture().onEnded { proxy.selectXValue(at: $0.location.x) } }
        } else {
            chart
        }
    }
}
