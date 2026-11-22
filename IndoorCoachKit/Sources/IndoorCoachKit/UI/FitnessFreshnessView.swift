import Charts
import SwiftData
import SwiftUI

/// S11 – Fitness & Freshness: fitness, fatigue and form over a selectable range, tap a day for its values.
/// The expensive preparation (series, shadow, ticks, sentences) depends on rides and range only and lives here; the
/// selection lives in `FitnessFreshnessContent`, so tapping a day never recomputes it.
struct FitnessFreshnessView: View {
    @Environment(AppModel.self) private var model
    @Query(sort: \StoredRide.startDate) private var storedRides: [StoredRide]
    @State private var range: FitnessFreshness.Range = .days90

    var body: some View {
        let series = model.fitnessSeries(rides: storedRides.map(\.summary))
        let data = FitnessFreshnessData(series: series, range: range)
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                Picker("Zeitraum", selection: $range) {
                    ForEach(FitnessFreshness.Range.allCases) { Text($0.label).tag($0) }
                }
                .pickerStyle(.segmented)

                if data.points.last != nil {
                    // A new range starts without a selection (the old date may lie outside it).
                    FitnessFreshnessContent(data: data).id(range)
                } else {
                    EmptyStateView(title: "Noch keine Fahrten", systemImage: "chart.line.uptrend.xyaxis",
                                   message: "Sobald Fahrten da sind, siehst du hier, wie sich Fitness und Form entwickeln.")
                }
                explanation(series)
            }
            .padding()
        }
        .background(Theme.canvas)
        .navigationTitle("Fitness & Form")
        .inlineNavigationTitle()
    }

    private func explanation(_ series: FitnessFreshness.Series) -> some View {
        Card(title: "So wird gerechnet", systemImage: "info.circle") {
            Text("Fitness ist deine Trainingslast der letzten 42 Tage, Ermüdung die der letzten 7 Tage (Banister/Coggan). Form = Fitness − Ermüdung vom Vortag: positiv heißt erholt, deutlich negativ heißt du baust gerade auf.")
                .font(.subheadline)
            Text(series.effortFactor.map { "Fahrten ohne Leistungsmesser zählen über deinen Relative Effort mit (persönlicher Faktor \(Formatters.decimal($0, digits: 2)) TSS je Punkt, aus Fahrten mit beidem)." }
                 ?? "Fahrten ohne Leistungsmesser werden geschätzt, bis 10 Fahrten mit Leistung und Herzfrequenz einen persönlichen Faktor ergeben.")
                .font(.footnote)
                .foregroundStyle(Theme.rowSecondary)
        }
    }
}

/// Everything the charts need that does not depend on the selected day.
struct FitnessFreshnessData {
    let delta7: Double
    let points: [FitnessFreshness.Point]
    let shadow: [SeasonShadow.Point]?
    let loadTicks: [Double]
    let loadSentence: String
    let formTicks: [Double]
    let formSentence: String

    init(series: FitnessFreshness.Series, range: FitnessFreshness.Range) {
        let points = series.points(in: range)
        self.points = points
        delta7 = series.fitnessDelta7
        shadow = points.first.flatMap { first in
            points.last.flatMap { SeasonShadow.points(from: series.points, window: first.date...$0.date) }
        }
        let values = points.flatMap { [$0.fitness, $0.fatigue] } + (shadow ?? []).map(\.fitness)
        loadTicks = ChartMath.niceTicks(min: values.min() ?? 0, max: values.max() ?? 1, count: 4)
        loadSentence = ChartMath.seriesSentence(name: "Fitness", values: points.map(\.fitness), period: "\(points.count) Tagen")
        let forms = points.map(\.form)
        let band = ChartSeries.balancedFormBand
        formTicks = ChartMath.niceTicks(min: min(forms.min() ?? 0, band.lowerBound), max: max(forms.max() ?? 0, band.upperBound), count: 4)
        formSentence = ChartMath.seriesSentence(name: "Form", values: forms, period: "\(points.count) Tagen")
    }
}

/// Header, both charts and legends for one prepared range; owns the day selection.
private struct FitnessFreshnessContent: View {
    let data: FitnessFreshnessData
    @State private var selectedDate: Date?
    @Environment(\.colorScheme) private var scheme
    @Environment(\.displayScale) private var displayScale

    var body: some View {
        let selected = selectedPoint
        if let shown = selected ?? data.points.last {
            VStack(alignment: .leading, spacing: 16) {
                header(shown, isToday: selected == nil, delta: data.delta7)
                Card(title: "Fitness & Ermüdung", systemImage: "waveform.path.ecg") {
                    loadChart(selected: selected, shown: shown)
                    legend(showsShadow: data.shadow != nil)
                }
                Card(title: "Form (Fitness − Ermüdung)", systemImage: "gauge.with.dots.needle.33percent") {
                    formChart(selected: selected)
                    formLegend
                }
            }
        }
    }

    /// The day a selection falls on: the last day at or before the raw x value (bars span their whole day).
    private var selectedPoint: FitnessFreshness.Point? {
        guard let selectedDate, let i = ChartMath.floorIndex(data.points.map(\.date), at: selectedDate) else { return nil }
        return data.points[i]
    }

    private func header(_ p: FitnessFreshness.Point, isToday: Bool, delta: Double) -> some View {
        Card {
            Text(isToday ? "Heute" : p.date.formatted(.dateTime.weekday(.wide).day().month(.wide).locale(Locale.de)))
                .font(.subheadline.weight(.semibold)).foregroundStyle(.secondary)
            HStack {
                StatTile(title: "Fitness", value: Formatters.decimal(p.fitness), dot: ChartPalette.fitness)
                StatTile(title: "Ermüdung", value: Formatters.decimal(p.fatigue), dot: ChartPalette.fatigue)
                StatTile(title: "Form", value: (p.form > 0 ? "+" : "") + Formatters.decimal(p.form), dot: Theme.formColor(p.form))
            }
            HStack(spacing: 8) {
                JellyChip(text: Theme.formLabel(p.form), fill: Theme.formColor(p.form))
                if !isToday {
                    Button { selectedDate = nil } label: {
                        Text("Zurück zu heute").frame(minHeight: 44).contentShape(Rectangle())
                    }
                    .font(.caption.weight(.semibold))
                }
                if isToday {
                    Label("\(delta >= 0 ? "+" : "")\(Formatters.decimal(delta)) Fitness in 7 Tagen",
                          systemImage: delta >= 0 ? "arrow.up.right" : "arrow.down.right")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(Theme.rowSecondary)
                }
            }
        }
        // .contain (not .combine) so VoiceOver can still reach "Zurück zu heute".
        .accessibilityElement(children: .contain)
    }

    private func loadChart(selected: FitnessFreshness.Point?, shown: FitnessFreshness.Point) -> some View {
        let dark = scheme == .dark
        let points = data.points, shadow = data.shadow
        let ticks = data.loadTicks
        let lower = ticks.first ?? 0, upper = ticks.last ?? 1
        let method = ChartStyle.interpolation(pointCount: points.count)
        let previous = shadow.flatMap { SeasonShadow.fitness(on: shown.date, in: $0) }
        let sentence = data.loadSentence + " Ermüdung \(ChartMath.format(shown.fatigue)). "
            + SeasonShadow.comparisonText(today: shown.fitness, previous: previous)
        return Chart {
            ForEach(points) { p in
                AreaMark(x: .value("Tag", p.date), yStart: .value("Basis", lower), yEnd: .value("Fitness", p.fitness))
                    .interpolationMethod(method)
                    .foregroundStyle(ChartStyle.area(ChartPalette.fitness, dark: dark))
            }
            // G6: last year's fitness over the same days (dotted, muted), above the area, below the main lines.
            ForEach(shadow ?? []) { p in
                LineMark(x: .value("Tag", p.date), y: .value("Wert", p.fitness), series: .value("Kurve", "Vorjahr"))
                    .interpolationMethod(method)
                    .foregroundStyle(ChartPalette.reference)
                    .lineStyle(ChartStyle.stroke(.previous))
            }
            ForEach(points) { p in
                LineMark(x: .value("Tag", p.date), y: .value("Wert", p.fitness), series: .value("Kurve", "Fitness"))
                    .interpolationMethod(method).lineStyle(ChartStyle.stroke(.main)).foregroundStyle(ChartPalette.fitness)
                LineMark(x: .value("Tag", p.date), y: .value("Wert", p.fatigue), series: .value("Kurve", "Ermüdung"))
                    .interpolationMethod(method).lineStyle(ChartStyle.stroke(.main)).foregroundStyle(ChartPalette.fatigue)
            }
            HighlightPoint(x: .value("Tag", shown.date), y: .value("Fitness", shown.fitness), color: ChartPalette.fitness,
                           baseline: selected == nil ? nil : .value("Basis", lower), dark: dark)
            HighlightPoint(x: .value("Tag", shown.date), y: .value("Ermüdung", shown.fatigue), color: ChartPalette.fatigue, dark: dark)
        }
        .chartYScale(domain: lower...upper)
        .chartXSelection(value: $selectedDate)
        .chartGesture { proxy in SpatialTapGesture().onEnded { proxy.selectXValue(at: $0.location.x) } }
        .chartStyleAxes(yTicks: ticks, xCount: 4)
        .environment(\.locale, Locale.de)
        .chartStyleAnimation(value: selected?.date)
        .chartStyleHeight(ChartStyle.heightLarge - 10)
        .chartAccessibility(
            label: "Verlauf von Fitness und Ermüdung", value: sentence,
            descriptor: ChartAccessibility.timeSeries(
                title: "Verlauf von Fitness und Ermüdung", summary: sentence, yTitle: "Punkte",
                series: [("Fitness", points.map { ($0.date, $0.fitness) }), ("Ermüdung", points.map { ($0.date, $0.fatigue) })]))
    }

    private func formChart(selected: FitnessFreshness.Point?) -> some View {
        let points = data.points
        let band = ChartSeries.balancedFormBand
        let ticks = data.formTicks
        let lower = ticks.first ?? -10, upper = ticks.last ?? 10
        return Chart {
            RectangleMark(yStart: .value("Band unten", band.lowerBound), yEnd: .value("Band oben", band.upperBound))
                .foregroundStyle(ChartPalette.band)
                .annotation(position: .overlay, alignment: .trailing, spacing: 2) {
                    Text("ausgewogen").font(ChartStyle.ruleLabelFont).foregroundStyle(Theme.axisLabel)
                }
            ForEach(points) { p in
                BarMark(x: .value("Tag", p.date, unit: .day), y: .value("Form", p.form))
                    .foregroundStyle(ChartSeries.formSide(p.form) == .recovered ? ChartPalette.fitness : ChartPalette.fatigue)
            }
            RuleMark(y: .value("Null", 0))
                .lineStyle(StrokeStyle(lineWidth: ChartStyle.hairline(displayScale: displayScale)))
                .foregroundStyle(ChartStyle.baselineColor)
            if let selected {
                RuleMark(x: .value("Auswahl", selected.date))
                    .lineStyle(StrokeStyle(lineWidth: ChartStyle.hairline(displayScale: displayScale)))
                    .foregroundStyle(ChartPalette.reference.opacity(0.4))
            }
        }
        .chartYScale(domain: lower...upper)
        .chartXSelection(value: $selectedDate)
        .chartGesture { proxy in SpatialTapGesture().onEnded { proxy.selectXValue(at: $0.location.x) } }
        .chartStyleAxes(yTicks: ticks, showsX: false)
        .chartStyleHeight(ChartStyle.heightSmall)
        .chartAccessibility(
            label: "Form pro Tag",
            value: data.formSentence)
    }

    /// Two poles by sign plus the neutral band (no zone rainbow); the chip in the header carries the form state.
    private var formLegend: some View {
        ViewThatFits(in: .horizontal) {
            HStack(spacing: 14) { formLegendItems }
            VStack(alignment: .leading, spacing: 6) { formLegendItems }
        }
        .font(.caption)
        .foregroundStyle(Theme.rowSecondary)
    }

    @ViewBuilder
    private var formLegendItems: some View {
        Label { Text("Erholt (über 0)") } icon: { Circle().fill(ChartPalette.fitness).frame(width: 8, height: 8) }
        Label { Text("Belastet (0 und darunter)") } icon: { Circle().fill(ChartPalette.fatigue).frame(width: 8, height: 8) }
        Label { Text("ausgewogen (−10 bis +5)") } icon: {
            RoundedRectangle(cornerRadius: 2).fill(ChartPalette.band).frame(width: 12, height: 8)
        }
    }

    private func legend(showsShadow: Bool) -> some View {
        // Side by side when they fit, otherwise stacked (Dynamic Type).
        ViewThatFits(in: .horizontal) {
            HStack(spacing: 14) { legendItems(showsShadow: showsShadow) }
            VStack(alignment: .leading, spacing: 6) { legendItems(showsShadow: showsShadow) }
        }
        .font(.caption)
        .foregroundStyle(Theme.rowSecondary)
    }

    @ViewBuilder
    private func legendItems(showsShadow: Bool) -> some View {
        Label { Text("Fitness (42 Tage)") } icon: { Circle().fill(ChartPalette.fitness).frame(width: 8, height: 8) }
        Label { Text("Ermüdung (7 Tage)") } icon: { Circle().fill(ChartPalette.fatigue).frame(width: 8, height: 8) }
        if showsShadow { ShadowLegendItem() }
    }

    private func explanation(_ series: FitnessFreshness.Series) -> some View {
        Card(title: "So wird gerechnet", systemImage: "info.circle") {
            Text("Fitness ist deine Trainingslast der letzten 42 Tage, Ermüdung die der letzten 7 Tage (Banister/Coggan). Form = Fitness − Ermüdung vom Vortag: positiv heißt erholt, deutlich negativ heißt du baust gerade auf.")
                .font(.subheadline)
            Text(series.effortFactor.map { "Fahrten ohne Leistungsmesser zählen über deinen Relative Effort mit (persönlicher Faktor \(Formatters.decimal($0, digits: 2)) TSS je Punkt, aus Fahrten mit beidem)." }
                 ?? "Fahrten ohne Leistungsmesser werden geschätzt, bis 10 Fahrten mit Leistung und Herzfrequenz einen persönlichen Faktor ergeben.")
                .font(.footnote)
                .foregroundStyle(Theme.rowSecondary)
        }
    }
}

/// Legend entry for the Vorjahres-Schatten: a dashed muted swatch and "Vorjahr".
struct ShadowLegendItem: View {
    var body: some View {
        Label {
            Text("Vorjahr")
        } icon: {
            // Same stroke as the chart's previous-year line: reference colour, dotted.
            Capsule().stroke(ChartPalette.reference, style: ChartStyle.stroke(.previous))
                .frame(width: 18, height: 2)
        }
        .accessibilityIdentifier("shadow.legend")
    }
}

/// Legend under the Winter-Arc course chart.
struct ShadowLegend: View {
    var showsShadow: Bool

    var body: some View {
        ViewThatFits(in: .horizontal) {
            HStack(spacing: 14) { items }
            VStack(alignment: .leading, spacing: 6) { items }
        }
        .font(.caption)
        .foregroundStyle(Theme.rowSecondary)
    }

    @ViewBuilder
    private var items: some View {
        Label { Text("Fitness") } icon: { Circle().fill(ChartPalette.fitness).frame(width: 8, height: 8) }
        Label { Text("Kurs") } icon: {
            // The course is a target line: reference colour, dashed (as in the chart).
            Capsule().stroke(ChartPalette.reference, style: ChartStyle.stroke(.target))
                .frame(width: 18, height: 2)
        }
        if showsShadow { ShadowLegendItem() }
    }
}
