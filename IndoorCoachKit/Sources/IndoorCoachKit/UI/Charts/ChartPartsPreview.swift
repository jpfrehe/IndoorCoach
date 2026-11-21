#if DEBUG
import Charts
import SwiftUI

/// Reference composition of the shared chart parts (a typical line chart as AP5/AP6 will build it).
private struct ChartPartsDemo: View {
    struct Pt: Identifiable { let id: Int; let date: Date; let ctl: Double; let atl: Double }

    let count: Int
    @State private var selected: Date?
    @Environment(\.colorScheme) private var scheme

    private var points: [Pt] {
        let t0 = Date(timeIntervalSince1970: 1_760_000_000)
        return (0..<count).map { i in
            Pt(id: i, date: t0.addingTimeInterval(Double(i) * 86_400), ctl: 40 + Double(i) * 0.3 + 3 * sin(Double(i) / 5),
               atl: 38 + 8 * sin(Double(i) / 3))
        }
    }

    var body: some View {
        let pts = points
        let state = ChartDataState(count: pts.count)
        let sel = selected.flatMap { ChartMath.nearest(pts.map(\.date), to: $0) }.map { pts[$0] }
        let shown = sel ?? pts.last
        let domain = ChartMath.domain(values: pts.flatMap { [$0.ctl, $0.atl] }, includeZero: false)
        VStack(alignment: .leading, spacing: 10) {
            ChartCardHeader(items: [
                .init(label: "Fitness", value: shown.map { ChartMath.format($0.ctl) } ?? "–", color: ChartPalette.fitness),
                .init(label: "Ermüdung", value: shown.map { ChartMath.format($0.atl) } ?? "–", color: ChartPalette.fatigue),
                .init(label: "Vorjahr", value: "35", color: ChartPalette.reference, marker: .dotted),
            ], selectionTitle: sel.map { $0.date.formatted(.dateTime.day().month(.wide).locale(Locale.de)) },
                            onReset: { selected = nil })
            if state == .empty {
                ChartEmptyState(message: "Ab zwei Wochen mit Fahrten siehst du hier deinen Verlauf.")
            } else {
                Chart {
                    ForEach(pts) { p in
                        AreaMark(x: .value("Tag", p.date), yStart: .value("Basis", ChartMath.areaBase(in: domain)), yEnd: .value("Fitness", p.ctl))
                            .interpolationMethod(ChartStyle.interpolation(pointCount: pts.count))
                            .foregroundStyle(ChartStyle.area(ChartPalette.fitness, dark: scheme == .dark))
                        LineMark(x: .value("Tag", p.date), y: .value("Fitness", p.ctl), series: .value("Reihe", "Fitness"))
                            .interpolationMethod(ChartStyle.interpolation(pointCount: pts.count))
                            .lineStyle(ChartStyle.stroke(.main)).foregroundStyle(ChartPalette.fitness)
                        LineMark(x: .value("Tag", p.date), y: .value("Ermüdung", p.atl), series: .value("Reihe", "Ermüdung"))
                            .interpolationMethod(ChartStyle.interpolation(pointCount: pts.count))
                            .lineStyle(ChartStyle.stroke(.main)).foregroundStyle(ChartPalette.fatigue)
                    }
                    ChartRule(y: .value("Ziel", 48), kind: .target, label: "Ziel 48")
                    if let p = shown {
                        HighlightPoint(x: .value("Tag", p.date), y: .value("Fitness", p.ctl), color: ChartPalette.fitness,
                                       baseline: .value("Fitness", 0), dark: scheme == .dark)
                        HighlightPoint(x: .value("Tag", p.date), y: .value("Ermüdung", p.atl), color: ChartPalette.fatigue,
                                       dark: scheme == .dark)
                    }
                }
                .chartXSelection(value: $selected)
                .chartYScale(domain: domain)
                .chartStyleAxes()
                .chartStyleAnimation(value: selected)
                .chartStyleHeight()
                .chartAccessibility(
                    label: "Verlauf von Fitness und Ermüdung",
                    value: ChartMath.seriesSentence(name: "Fitness", values: pts.map(\.ctl), period: "\(pts.count) Tagen"))
            }
        }
        .padding(16)
        .background(Theme.card, in: RoundedRectangle(cornerRadius: 20))
        .padding()
    }
}

#Preview("Bausteine · viele Punkte") { ChartPartsDemo(count: 90).background(Theme.canvas) }
#Preview("Bausteine · 3 Punkte, dunkel") { ChartPartsDemo(count: 3).background(Theme.canvas).preferredColorScheme(.dark) }
#Preview("Bausteine · leer") { ChartPartsDemo(count: 0).background(Theme.canvas) }
#endif
