import Charts
import SwiftUI

/// Shared chart tokens and axis styling (concept 21 §3.3, §3.5). Charts never hard-code widths, radii or fonts.
enum ChartStyle {
    // MARK: Lines
    /// Main series line.
    static let lineWidth: CGFloat = 2
    /// Previous period / previous year: dotted.
    static let previousWidth: CGFloat = 1.5
    /// Target / goal / FTP rule: dashed.
    static let ruleWidth: CGFloat = 1

    enum LineKind { case main, previous, target }

    /// Stroke for a line kind: solid round (main), dotted `[2, 3]` (previous), dashed `[4, 3]` (target).
    /// Dashes are reserved for these two meanings only.
    static func stroke(_ kind: LineKind) -> StrokeStyle {
        switch kind {
        case .main: StrokeStyle(lineWidth: lineWidth, lineCap: .round, lineJoin: .round)
        case .previous: StrokeStyle(lineWidth: previousWidth, lineCap: .round, lineJoin: .round, dash: [2, 3])
        case .target: StrokeStyle(lineWidth: ruleWidth, lineCap: .butt, lineJoin: .round, dash: [4, 3])
        }
    }

    /// `.monotone` never over- or undershoots a data point (`.catmullRom` is banned); with ≤ 3 points a straight line
    /// avoids implying a curve.
    static func interpolation(pointCount: Int) -> InterpolationMethod {
        pointCount <= 3 ? .linear : .monotone
    }

    // MARK: Markers
    /// Open marker (card-coloured fill, 2 pt ring in series colour); only for ≤ 16 points.
    static let markerSize: CGFloat = 8
    static let markerRing: CGFloat = 2
    static let maxMarkers = 16
    /// Current/selected value: halo, dot, card-coloured ring.
    static let haloSize: CGFloat = 22
    static let pointSize: CGFloat = 10
    static let pointRing: CGFloat = 2
    static let haloOpacityLight = 0.18, haloOpacityDark = 0.26

    // MARK: Bars and blocks
    static let barMaxWidth: CGFloat = 16
    static let barCornerRadius: CGFloat = 4
    static let segmentGap: CGFloat = 2

    // MARK: Grid and axes
    /// Hairline = one device pixel; never a dashed grid (dashes flicker at @2x/@3x).
    static func hairline(displayScale: CGFloat) -> CGFloat { 1 / Swift.max(displayScale, 1) }
    static let axisFont = Font.caption2.monospacedDigit()
    static let ruleLabelFont = Font.caption2.weight(.semibold)
    static var axisColor: Color { Theme.axisLabel }
    static var gridColor: Color { ChartPalette.grid }
    static var baselineColor: Color { ChartPalette.baseline }

    // MARK: Heights
    static let heightSmall: CGFloat = 120, heightNormal: CGFloat = 170, heightLarge: CGFloat = 210
    /// Dynamic Type growth is capped so charts do not explode at AX sizes.
    static let maxScale: CGFloat = 1.35

    // MARK: Fill and animation
    /// Faint area under a line: series colour 18 % (dark 26 %) fading to clear.
    static func area(_ color: Color, dark: Bool) -> LinearGradient {
        LinearGradient(colors: [color.opacity(dark ? haloOpacityDark : haloOpacityLight), color.opacity(0)],
                       startPoint: .top, endPoint: .bottom)
    }

    /// Range or selection change. Nil under "Reduce Motion". Not for first appearance and never in lists.
    static func animation(reduceMotion: Bool) -> Animation? {
        reduceMotion ? nil : .smooth(duration: 0.25)
    }
}

// MARK: - Modifiers

/// Standard axes: y on the right with 3–4 round values, hairline grid (horizontal only), x without grid,
/// text in `Theme.axisLabel`, no Swift Charts legend.
struct ChartAxesModifier: ViewModifier {
    var yTicks: [Double]?
    var yLabel: (@Sendable (Double) -> String)?
    var showsX: Bool
    var xCount: Int
    var xValues: [Double]?
    var xLabel: (@Sendable (Double) -> String)?
    @Environment(\.displayScale) private var displayScale

    func body(content: Content) -> some View {
        content
            .chartLegend(.hidden)
            // Areas and lines never leave the plot, whatever the domain.
            .chartPlotStyle { $0.clipped() }
            .chartYAxis {
                if let yTicks {
                    AxisMarks(position: .trailing, values: yTicks) { value in yMarks(value) }
                } else {
                    AxisMarks(position: .trailing, values: .automatic(desiredCount: 4)) { value in yMarks(value) }
                }
            }
            .chartXAxis {
                if let xValues {
                    AxisMarks(values: xValues) { value in
                        AxisTick(stroke: StrokeStyle(lineWidth: ChartStyle.hairline(displayScale: displayScale)))
                            .foregroundStyle(ChartStyle.baselineColor)
                        AxisValueLabel {
                            if let v = value.as(Double.self) { Text(xLabel?(v) ?? ChartMath.format(v)) }
                        }
                        .font(ChartStyle.axisFont).foregroundStyle(ChartStyle.axisColor)
                    }
                } else if showsX {
                    AxisMarks(values: .automatic(desiredCount: xCount)) { _ in
                        AxisTick(stroke: StrokeStyle(lineWidth: ChartStyle.hairline(displayScale: displayScale)))
                            .foregroundStyle(ChartStyle.baselineColor)
                        AxisValueLabel().font(ChartStyle.axisFont).foregroundStyle(ChartStyle.axisColor)
                    }
                }
            }
    }

    @AxisMarkBuilder
    private func yMarks(_ value: AxisValue) -> some AxisMark {
        AxisGridLine(stroke: StrokeStyle(lineWidth: ChartStyle.hairline(displayScale: displayScale)))
            .foregroundStyle(ChartStyle.gridColor)
        AxisValueLabel {
            if let v = value.as(Double.self) {
                Text(yLabel?(v) ?? ChartMath.format(v, decimals: abs(v) < 10 && v != v.rounded() ? 1 : 0))
            }
        }
        .font(ChartStyle.axisFont)
        .foregroundStyle(ChartStyle.axisColor)
    }
}

/// Animates `value` changes unless Reduce Motion is on.
struct ChartAnimationModifier<V: Equatable>: ViewModifier {
    var value: V
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    func body(content: Content) -> some View {
        content.animation(ChartStyle.animation(reduceMotion: reduceMotion), value: value)
    }
}

/// Plot height that scales with Dynamic Type (relative to caption2), capped at `ChartStyle.maxScale`.
struct ChartHeightModifier: ViewModifier {
    @ScaledMetric(relativeTo: .caption2) private var scale: CGFloat = 1
    var base: CGFloat

    func body(content: Content) -> some View {
        content.frame(height: base * Swift.min(scale, ChartStyle.maxScale))
    }
}

extension View {
    /// Concept 21 standard axes (right-hand y, hairline grid, no legend). Pass `yTicks` from `ChartMath.niceTicks`.
    func chartStyleAxes(yTicks: [Double]? = nil, yLabel: (@Sendable (Double) -> String)? = nil,
                        showsX: Bool = true, xCount: Int = 4, xValues: [Double]? = nil,
                        xLabel: (@Sendable (Double) -> String)? = nil) -> some View {
        modifier(ChartAxesModifier(yTicks: yTicks, yLabel: yLabel, showsX: showsX, xCount: xCount, xValues: xValues, xLabel: xLabel))
    }

    /// Smooth range/selection animation that respects "Reduce Motion".
    func chartStyleAnimation<V: Equatable>(value: V) -> some View {
        modifier(ChartAnimationModifier(value: value))
    }

    /// Chart height with capped Dynamic Type scaling (`ChartStyle.heightNormal` etc.).
    func chartStyleHeight(_ base: CGFloat = ChartStyle.heightNormal) -> some View {
        modifier(ChartHeightModifier(base: base))
    }
}
