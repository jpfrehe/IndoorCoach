import Charts
import SwiftUI

// MARK: - Marks

/// Current or selected value: halo (series colour 18 %), filled dot, card-coloured ring, optional hairline from the
/// baseline up to the dot (concept 21 §3.3). Use inside a `Chart { … }` after the series marks.
struct HighlightPoint<X: Plottable, Y: Plottable>: ChartContent {
    var x: PlottableValue<X>
    var y: PlottableValue<Y>
    var color: Color
    /// y value of the baseline (e.g. 0); when set a hairline connects it to the dot.
    var baseline: PlottableValue<Y>?
    var dark = false

    init(x: PlottableValue<X>, y: PlottableValue<Y>, color: Color, baseline: PlottableValue<Y>? = nil, dark: Bool = false) {
        self.x = x; self.y = y; self.color = color; self.baseline = baseline; self.dark = dark
    }

    private func dot(_ diameter: CGFloat) -> CGSize { CGSize(width: diameter, height: diameter) }

    var body: some ChartContent {
        if let baseline {
            RuleMark(x: x, yStart: baseline, yEnd: y)
                .lineStyle(StrokeStyle(lineWidth: 1))
                .foregroundStyle(ChartPalette.reference.opacity(0.4))
        }
        PointMark(x: x, y: y)
            .symbol(.circle).symbolSize(dot(ChartStyle.haloSize))
            .foregroundStyle(color.opacity(dark ? ChartStyle.haloOpacityDark : ChartStyle.haloOpacityLight))
        PointMark(x: x, y: y)
            .symbol(.circle).symbolSize(dot(ChartStyle.pointSize + 2 * ChartStyle.pointRing))
            .foregroundStyle(Theme.card)
        PointMark(x: x, y: y)
            .symbol(.circle).symbolSize(dot(ChartStyle.pointSize))
            .foregroundStyle(color)
    }
}

/// Open marker for a data point (card fill, 2 pt ring in the series colour). Only for ≤ `ChartStyle.maxMarkers` points.
struct OpenMarker<X: Plottable, Y: Plottable>: ChartContent {
    var x: PlottableValue<X>
    var y: PlottableValue<Y>
    var color: Color

    var body: some ChartContent {
        PointMark(x: x, y: y)
            .symbol(.circle).symbolSize(CGSize(width: ChartStyle.markerSize + ChartStyle.markerRing,
                                               height: ChartStyle.markerSize + ChartStyle.markerRing))
            .foregroundStyle(color)
        PointMark(x: x, y: y)
            .symbol(.circle).symbolSize(CGSize(width: ChartStyle.markerSize - ChartStyle.markerRing,
                                               height: ChartStyle.markerSize - ChartStyle.markerRing))
            .foregroundStyle(Theme.card)
    }
}

/// Horizontal reference line. `.target` = dashed `[4, 3]` for plan, goal, FTP; `.previous` = dotted for a comparison
/// level. Optional caption sits at the left end above the line.
struct ChartRule<Y: Plottable>: ChartContent {
    enum Kind { case target, previous }
    var y: PlottableValue<Y>
    var kind: Kind = .target
    var label: String?

    var body: some ChartContent {
        if let label {
            RuleMark(y: y)
                .lineStyle(ChartStyle.stroke(kind == .target ? .target : .previous))
                .foregroundStyle(ChartPalette.reference)
                .annotation(position: .top, alignment: .leading, spacing: 2) {
                    Text(label).font(ChartStyle.ruleLabelFont).foregroundStyle(Theme.axisLabel)
                }
        } else {
            RuleMark(y: y)
                .lineStyle(ChartStyle.stroke(kind == .target ? .target : .previous))
                .foregroundStyle(ChartPalette.reference)
        }
    }
}

// MARK: - Card header (key figures as legend)

/// Key-figure header that doubles as the legend: big value, below it a marker + series name. Shows the selected
/// day's values when `selectionTitle` is set, with a reset button ("Heute").
struct ChartCardHeader: View {
    struct Item: Identifiable {
        enum Marker { case dot, dashed, dotted, none }
        let id: String
        var label: String
        var value: String
        var color: Color = Theme.axisLabel
        var marker: Marker = .dot
        init(label: String, value: String, color: Color = Theme.axisLabel, marker: Marker = .dot) {
            self.id = label; self.label = label; self.value = value; self.color = color; self.marker = marker
        }
    }

    var items: [Item]
    /// Title of the current selection (e.g. "Mi., 12. November"); nil shows the live state.
    var selectionTitle: String?
    var resetTitle = "Heute"
    var onReset: (() -> Void)?
    @Environment(\.dynamicTypeSize) private var typeSize

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            if let selectionTitle {
                HStack {
                    Text(selectionTitle).font(.footnote.weight(.semibold)).foregroundStyle(Theme.axisLabel)
                    Spacer(minLength: 8)
                    if let onReset {
                        Button(resetTitle, action: onReset).font(.footnote.weight(.semibold)).buttonStyle(.borderless)
                    }
                }
            }
            let layout = typeSize.isAccessibilitySize ? AnyLayout(VStackLayout(alignment: .leading, spacing: 8))
                                                      : AnyLayout(HStackLayout(alignment: .top, spacing: 18))
            layout {
                ForEach(items) { item in
                    VStack(alignment: .leading, spacing: 2) {
                        Text(item.value).font(.title3.weight(.semibold).monospacedDigit()).foregroundStyle(.primary)
                        HStack(spacing: 5) {
                            markerView(item).accessibilityHidden(true)
                            Text(item.label).font(.caption2).foregroundStyle(Theme.axisLabel)
                        }
                    }
                }
            }
        }
        .accessibilityElement(children: .combine)
    }

    @ViewBuilder private func markerView(_ item: Item) -> some View {
        switch item.marker {
        case .dot: Circle().fill(item.color).frame(width: 8, height: 8)
        case .dashed: Capsule().fill(item.color).frame(width: 12, height: 2)
        case .dotted:
            HStack(spacing: 2) { ForEach(0..<3, id: \.self) { _ in Circle().fill(item.color).frame(width: 2.5, height: 2.5) } }
                .frame(width: 12)
        case .none: EmptyView()
        }
    }
}

// MARK: - Empty and sparse data

/// What to draw for a series, by number of values (concept 21 §3.4).
enum ChartDataState: Equatable {
    case empty, single, few, enough

    init(count: Int) {
        switch count {
        case ...0: self = .empty
        case 1: self = .single
        case 2...3: self = .few
        default: self = .enough
        }
    }
}

/// Replaces the whole chart when there is nothing to plot: symbol and one sentence, no empty axes.
struct ChartEmptyState: View {
    var symbol = "chart.line.uptrend.xyaxis"
    var message: String
    @Environment(\.dynamicTypeSize) private var typeSize

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: symbol).font(.title3).foregroundStyle(Theme.axisLabel).accessibilityHidden(true)
            Text(message).font(.subheadline).foregroundStyle(Theme.rowSecondary).fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 0)
        }
        .padding(.vertical, 14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .combine)
    }
}
