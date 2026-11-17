import Charts
import SwiftData
import SwiftUI

/// S11 – Fitness & Freshness: fitness, fatigue and form over a selectable range, tap a day for its values.
struct FitnessFreshnessView: View {
    @Environment(AppModel.self) private var model
    @Query(sort: \StoredRide.startDate) private var storedRides: [StoredRide]
    @State private var range: FitnessFreshness.Range = .days90
    @State private var selectedDate: Date?

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
                        FormZoneLegend()
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
            Text(isToday ? "Heute" : p.date.formatted(.dateTime.weekday(.wide).day().month(.wide).locale(Locale(identifier: "de_DE"))))
                .font(.subheadline.weight(.semibold)).foregroundStyle(.secondary)
            HStack {
                StatTile(title: "Fitness", value: Formatters.decimal(p.fitness), dot: Theme.fitness)
                StatTile(title: "Ermüdung", value: Formatters.decimal(p.fatigue), dot: Theme.fatigue)
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
        Chart {
            ForEach(points) { p in
                AreaMark(x: .value("Tag", p.date), y: .value("Fitness", p.fitness))
                    .foregroundStyle(LinearGradient(colors: [Theme.fitness.opacity(0.35), Theme.fitness.opacity(0)],
                                                    startPoint: .top, endPoint: .bottom))
                    .interpolationMethod(.monotone)
                LineMark(x: .value("Tag", p.date), y: .value("Wert", p.fitness), series: .value("Kurve", "Fitness"))
                    .foregroundStyle(Theme.fitnessLine)
                    .lineStyle(StrokeStyle(lineWidth: 2.5, lineCap: .round))
                    .interpolationMethod(.monotone)
                LineMark(x: .value("Tag", p.date), y: .value("Wert", p.fatigue), series: .value("Kurve", "Ermüdung"))
                    .foregroundStyle(Theme.fatigueLine)
                    .lineStyle(StrokeStyle(lineWidth: 2, lineCap: .round))
                    .interpolationMethod(.monotone)
            }
            // G6: last year's fitness over the same days (dashed, muted).
            ForEach(shadow ?? []) { p in
                LineMark(x: .value("Tag", p.date), y: .value("Wert", p.fitness), series: .value("Kurve", "Vorjahr"))
                    .foregroundStyle(Theme.shadowLine)
                    .lineStyle(StrokeStyle(lineWidth: 2, lineCap: .round, dash: [2, 4]))
                    .interpolationMethod(.monotone)
            }
            if let selected {
                RuleMark(x: .value("Auswahl", selected.date))
                    .foregroundStyle(Theme.ink.opacity(0.35))
                    .lineStyle(StrokeStyle(lineWidth: 1, dash: [3, 3]))
            }
        }
        .chartXSelection(value: $selectedDate)
        .chartGesture { proxy in SpatialTapGesture().onEnded { proxy.selectXValue(at: $0.location.x) } }
        .chartLegend(.hidden)
        .chartXAxis {
            AxisMarks(values: .automatic(desiredCount: 4)) { _ in
                AxisGridLine()
                AxisValueLabel(format: .dateTime.day().month(.abbreviated).locale(Locale(identifier: "de_DE")))
                    .foregroundStyle(Theme.axisLabel)
            }
        }
        .chartYAxis { AxisMarks { _ in AxisGridLine(); AxisValueLabel().foregroundStyle(Theme.axisLabel) } }
        .frame(height: 200)
        .accessibilityLabel("Verlauf von Fitness und Ermüdung")
        .accessibilityValue(SeasonShadow.comparisonText(
            today: shown.fitness, previous: shadow.flatMap { SeasonShadow.fitness(on: shown.date, in: $0) }))
    }

    private func formChart(_ points: [FitnessFreshness.Point]) -> some View {
        Chart(points) { p in
            BarMark(x: .value("Tag", p.date, unit: .day), y: .value("Form", p.form))
                .foregroundStyle(Theme.formColor(p.form))
            RuleMark(y: .value("Null", 0)).foregroundStyle(Theme.axisLabel.opacity(0.6))
        }
        .chartXSelection(value: $selectedDate)
        .chartGesture { proxy in SpatialTapGesture().onEnded { proxy.selectXValue(at: $0.location.x) } }
        .chartXAxis(.hidden)
        .chartYAxis { AxisMarks { _ in AxisGridLine(); AxisValueLabel().foregroundStyle(Theme.axisLabel) } }
        .frame(height: 110)
        .accessibilityLabel("Form pro Tag")
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
        Label { Text("Fitness (42 Tage)") } icon: { Circle().fill(Theme.fitnessLine).frame(width: 8, height: 8) }
        Label { Text("Ermüdung (7 Tage)") } icon: { Circle().fill(Theme.fatigueLine).frame(width: 8, height: 8) }
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
