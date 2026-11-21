import Charts
import SwiftData
import SwiftUI

/// S11 – Fitness & Freshness: fitness, fatigue and form over a selectable range, tap a day for its values.
struct FitnessFreshnessView: View {
    @Environment(AppModel.self) private var model
    @Query(sort: \StoredRide.startDate) private var storedRides: [StoredRide]
    @State private var range: FitnessFreshness.Range = .days90
    @State private var selectedDate: Date?
    @Environment(\.colorScheme) private var scheme
    @Environment(\.displayScale) private var displayScale

    var body: some View {
        let series = model.fitnessSeries(rides: storedRides.map(\.summary))
        let points = series.points(in: range)
        let selected = selectedPoint(in: points)
        let shadow = points.first.flatMap { first in
            points.last.flatMap { SeasonShadow.points(from: series.points, window: first.date...$0.date) }
        }
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                Picker("Zeitraum", selection: $range) {
                    ForEach(FitnessFreshness.Range.allCases) { Text($0.label).tag($0) }
                }
                .pickerStyle(.segmented)

                if let shown = selected ?? points.last {
                    header(shown, isToday: selected == nil, delta: series.fitnessDelta7)
                    Card(title: "Fitness & Ermüdung", systemImage: "waveform.path.ecg") {
                        loadChart(points, selected: selected, shadow: shadow, shown: shown)
                        legend(showsShadow: shadow != nil)
                    }
                    Card(title: "Form (Fitness − Ermüdung)", systemImage: "gauge.with.dots.needle.33percent") {
                        formChart(points)
                        formLegend
                    }
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

    private func selectedPoint(in points: [FitnessFreshness.Point]) -> FitnessFreshness.Point? {
        guard let selectedDate else { return nil }
        return points.min { abs($0.date.timeIntervalSince(selectedDate)) < abs($1.date.timeIntervalSince(selectedDate)) }
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

    private func loadChart(_ points: [FitnessFreshness.Point], selected: FitnessFreshness.Point?,
                           shadow: [SeasonShadow.Point]?, shown: FitnessFreshness.Point) -> some View {
        let dark = scheme == .dark
        let values = points.flatMap { [$0.fitness, $0.fatigue] } + (shadow ?? []).map(\.fitness)
        let ticks = ChartMath.niceTicks(min: values.min() ?? 0, max: values.max() ?? 1, count: 4)
        let lower = ticks.first ?? 0, upper = ticks.last ?? 1
        let method = ChartStyle.interpolation(pointCount: points.count)
        let previous = shadow.flatMap { SeasonShadow.fitness(on: shown.date, in: $0) }
        let sentence = ChartMath.seriesSentence(name: "Fitness", values: points.map(\.fitness), period: "\(points.count) Tagen")
            + " Ermüdung \(ChartMath.format(shown.fatigue)). "
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

    private func formChart(_ points: [FitnessFreshness.Point]) -> some View {
        let forms = points.map(\.form)
        let band = ChartSeries.balancedFormBand
        let ticks = ChartMath.niceTicks(min: min(forms.min() ?? 0, band.lowerBound), max: max(forms.max() ?? 0, band.upperBound), count: 4)
        let lower = ticks.first ?? -10, upper = ticks.last ?? 10
        let selected = selectedPoint(in: points)
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
            value: ChartMath.seriesSentence(name: "Form", values: forms, period: "\(points.count) Tagen"))
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

/// Small legend for the form colours (same jelly scale as the zones).
struct FormZoneLegend: View {
    var body: some View {
        let zones: [(String, Double)] = [("Frisch", 10), ("Ausgewogen", 0), ("Produktiv", -20), ("Überlastet", -35)]
        LazyVGrid(columns: [GridItem(.adaptive(minimum: 96), alignment: .leading)], alignment: .leading, spacing: 6) {
            ForEach(zones, id: \.0) { name, tsb in
                JellyChip(text: name, fill: Theme.formColor(tsb))
            }
        }
    }
}

/// Legend entry for the Vorjahres-Schatten: a dashed muted swatch and "Vorjahr".
struct ShadowLegendItem: View {
    var body: some View {
        Label {
            Text("Vorjahr")
        } icon: {
            Capsule().stroke(Theme.shadowLine, style: StrokeStyle(lineWidth: 2, lineCap: .round, dash: [2, 3]))
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
        Label { Text("Fitness") } icon: { Circle().fill(Theme.fitnessLine).frame(width: 8, height: 8) }
        Label { Text("Kurs") } icon: {
            Capsule().stroke(Theme.accent, style: StrokeStyle(lineWidth: 2, lineCap: .round, dash: [4, 3]))
                .frame(width: 18, height: 2)
        }
        if showsShadow { ShadowLegendItem() }
    }
}

extension Theme {
    /// Vorjahres-Schatten (G6): a muted line that stays >= 3:1 against the card, never competing with the fitness curve.
    static let shadowLine = Color.primary.opacity(0.55)
}
