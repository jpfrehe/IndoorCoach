import Charts
import SwiftData
import SwiftUI
import TipKit

struct TodayView: View {
    @Binding var tab: AppTab
    @Environment(AppModel.self) private var model
    @Environment(\.scenePhase) private var scenePhase // ANCHOR-W3B
    @Query(sort: \StoredRide.startDate) private var storedRides: [StoredRide]
    @Query(sort: \StoredWorkout.date) private var workouts: [StoredWorkout]

    var body: some View {
        NavigationStack {
            ScrollView {
                TodayDashboard(rides: storedRides.map(\.summary), workouts: workouts, tab: $tab)
                    .refreshesOnNewDay()
                    .padding(.horizontal)
                    .padding(.bottom, 24)
            }
            .background(Theme.canvas)
            .navigationTitle("Heute")
            .navigationDestination(for: StoredWorkout.self) { WorkoutDetailView(workout: $0) }
            .refreshable {
                await model.refreshFromPull(includeHealth: true) // ANCHOR-W3B: Health mit abgleichen
            }
            // ANCHOR-W3B: Health abgleichen beim Start und wenn die App wieder in den Vordergrund kommt (nur mit aktiviertem Health).
            .task { await model.syncHealth() }
            .onChange(of: scenePhase) { _, phase in
                if phase == .active { Task { await model.syncHealth() } }
            }
            .toolbar {
                ToolbarItem(placement: .primaryAction) {
                    if model.isSyncing { ProgressView() }
                }
            }
        }
    }
}

/// Dashboard content (separate from navigation so it can be rendered standalone for snapshots).
struct TodayDashboard: View {
    var rides: [RideSummary]
    var workouts: [StoredWorkout]
    @Binding var tab: AppTab
    @Environment(AppModel.self) private var model

    var body: some View {
        let series = model.loadSeries(rides: rides)
        let today = Calendar.current.startOfDay(for: .now)
        let next = workouts.first { $0.status == .planned && $0.date >= today }
        let weeks = TrainingLoad.weeks(rides: rides, ftp: model.profile.ftp, thresholdHeartRate: model.profile.thresholdHeartRate,
                                       from: Calendar.current.date(byAdding: .weekOfYear, value: -7, to: today)!, to: today)

        VStack(spacing: 16) {
            Text(Date.now.formatted(.dateTime.weekday(.wide).day().month(.wide).locale(Locale.de)))
                .font(.subheadline.weight(.medium))
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity, alignment: .leading)

            if model.isDemoMode && !Self.showcase { demoHint }
            nextWorkoutCard(next)
            MorningMeasurementRow() // ANCHOR-W4B (Morgenmessung HRV, nur aktiviert, vor 11 Uhr)
            CheckInCard() // ANCHOR-CHECKIN
            TrendHintCard(rides: rides) // ANCHOR-W4A (Trend-Wächter: ruhige Karte vor harter Einheit)
            StrengthQuickStartRow() // ANCHOR-STRENGTH (Schnellstart Kraft / Andere Einheit)
            HealthAnnotationCard() // ANCHOR-W3B (Kraft aus Apple Health: wie hart? Beine?)
            // ── Highlight-Slot (Konstanz-Paket, docs/10): zeitlich relevante Hinweise direkt unter der Einheit ──
            // At most one highlight (docs/10, U1): the weekly review (Sun 16:00 – Tue) wins over the challenge.
            // ANCHOR-B4-HEUTE: „Willkommen zurück“ (ComebackCard) und einmalige Warum-Frage, höchste Priorität im Slot – Agent B
            WinterHighlightSlot(rides: rides, workouts: workouts, fallbackFirst: model.weeklyReviewCardWeek() != nil) {
                // ANCHOR-K2-HEUTE (Wochenrückblick)
                if let reviewWeek = model.weeklyReviewCardWeek() {
                    WeeklyReviewCard(weekStart: reviewWeek, rides: rides, workouts: workouts)
                } else {
                    // ANCHOR-K3-HEUTE (Saison-Challenge)
                    ChallengeHighlightSlot(rides: rides)
                }
            }

            // ── Ende Highlight-Slot ──
            if let arc = model.winterArc(rides: rides) {
                NavigationLink { WinterArcView() } label: { WinterArcCard(status: arc) }
                    .buttonStyle(.plain)
                    .popoverTip(WinterArcTip())
            }
            // Without rides the 0/0/0 "Ausgewogen" card would look like a real assessment.
            if !rides.isEmpty, let current = series.last {
                NavigationLink { FitnessFreshnessView() } label: { formCard(series: series, current: current) }
                    .buttonStyle(.plain)
            }
            if let week = weeks.last { weekCard(week) }
            volumeCard(weeks)
            if !rides.isEmpty {
                NavigationLink { PerformanceView() } label: { VO2maxCard(rides: rides) }
                    .buttonStyle(.plain)
            }
        }
    }

    /// Debug-only launch argument for README screenshots: `-uiShowcase YES` hides the demo banner.
    static var showcase: Bool {
        #if DEBUG
        UserDefaults.standard.bool(forKey: "uiShowcase")
        #else
        false
        #endif
    }

    private var demoHint: some View {
        Card {
            HStack(alignment: .top, spacing: 12) {
                Image(systemName: "sparkles").font(.title2).foregroundStyle(Theme.sunset)
                VStack(alignment: .leading, spacing: 6) {
                    Text("Demo-Modus").font(.headline)
                    Text.protectingBrands("Du siehst Beispieldaten. Verbinde unter Profil → Dienste & Geräte Strava, MyWhoosh, intervals.icu oder FIT-Dateien, dazu unter Profil → Coach · Claude deinen Claude-Key, dann plant der Coach mit deinen echten Fahrten.")
                        .font(.subheadline).foregroundStyle(.secondary)
                    Button {
                        model.pendingProfileRoute = [.connections]
                        tab = .profile
                    } label: {
                        Text("Zum Profil").frame(minHeight: 44).contentShape(Rectangle())
                    }
                    .font(.subheadline.weight(.semibold))
                }
            }
        }
    }

    @ViewBuilder
    private func nextWorkoutCard(_ next: StoredWorkout?) -> some View {
        if let next {
            let d = next.definition
            NavigationLink(value: next) {
                Card(title: "Nächste Einheit", systemImage: "bicycle") {
                    HStack(alignment: .top) {
                        VStack(alignment: .leading, spacing: 4) {
                            Text(WorkoutRow.dayLabel(next.date) + ", " + model.startDate(for: next).formatted(date: .omitted, time: .shortened))
                                .font(.subheadline).foregroundStyle(.secondary)
                            Text(next.title).font(.title3.weight(.bold)).foregroundStyle(.primary)
                        }
                        Spacer()
                        TypeBadge(type: d.type)
                    }
                    WorkoutProfileView(definition: d, ftp: model.profile.ftp, variant: .card, height: 64).equatable()
                    HStack {
                        StatTile(title: "Dauer", value: Formatters.duration(d.totalDuration))
                        StatTile(title: "TSS", value: "\(Int(d.estimatedTSS.rounded()))")
                        StatTile(title: "IF", value: Formatters.decimal(d.intensityFactor, digits: 2))
                    }
                    Text(d.summary).font(.subheadline).foregroundStyle(.secondary).multilineTextAlignment(.leading)
                }
            }
            .buttonStyle(.plain)
        } else {
            Card(title: "Nächste Einheit", systemImage: "bicycle") {
                EmptyStateView(title: "Nichts geplant", systemImage: "calendar.badge.plus",
                               message: "Lass deinen Coach die nächsten Tage planen.")
                Button {
                    model.plannerRequested = true // PlanView opens the planner sheet on arrival
                    tab = .plan
                } label: {
                    Label("Plan erstellen", systemImage: "sparkles").frame(maxWidth: .infinity)
                }
                .buttonStyle(.jelly)
            }
        }
    }

    private func formCard(series: [TrainingLoad.DayLoad], current: TrainingLoad.DayLoad) -> some View {
        Card(title: "Fitness & Form · 90 Tage", systemImage: "waveform.path.ecg") {
            HStack {
                StatTile(title: "Fitness", value: Formatters.decimal(current.ctl), dot: Theme.fitness)
                StatTile(title: "Ermüdung", value: Formatters.decimal(current.atl), dot: Theme.fatigue)
                StatTile(title: "Form", value: (current.tsb > 0 ? "+" : "") + Formatters.decimal(current.tsb),
                         dot: Theme.formColor(current.tsb))
            }
            JellyChip(text: Theme.formLabel(current.tsb), fill: Theme.formColor(current.tsb))
            FitnessFormChart(series: series, current: current)
        }
    }

    private func weekCard(_ week: TrainingLoad.WeekSummary) -> some View {
        let target = model.profile.weeklyHours * 3600
        let progress = target > 0 ? min(1, Double(week.seconds) / target) : 0
        return Card(title: "Diese Woche", systemImage: "chart.pie") {
            HStack(spacing: 18) {
                ZStack {
                    Circle().stroke(Theme.softFill, lineWidth: 11)
                    Circle().trim(from: 0, to: progress)
                        .stroke(Theme.sunsetAngular, style: StrokeStyle(lineWidth: 11, lineCap: .round))
                        .rotationEffect(.degrees(-90))
                    Text("\(Int(progress * 100)) %").font(.callout.weight(.bold)).monospacedDigit()
                }
                .frame(width: 76, height: 76)
                VStack(alignment: .leading, spacing: 10) {
                    HStack {
                        StatTile(title: "Zeit", value: Formatters.duration(week.seconds))
                        StatTile(title: "Ziel", value: Formatters.duration(Int((model.profile.weeklyHours * 3600).rounded())))
                    }
                    HStack {
                        StatTile(title: "TSS", value: "\(Int(week.tss.rounded()))")
                        StatTile(title: "Fahrten", value: "\(week.rides)")
                    }
                }
            }
        }
    }

    private func volumeCard(_ weeks: [TrainingLoad.WeekSummary]) -> some View {
        // One series (total hours); the Indoor/Outdoor split lives in the spoken value and in Verlauf (concept 21, E2).
        let bars = weeks.map { WeekBarsChart.Bar(weekStart: $0.weekStart, value: Double($0.seconds) / 3600) }
        let target = model.profile.weeklyHours
        let current = weeks.last
        let split = current.map { w -> String in
            let other = w.otherSeconds, indoor = w.indoorSeconds
            let outdoor = max(0, w.seconds - indoor - other)
            return "Diese Woche \(Formatters.duration(w.seconds)), davon Indoor \(Formatters.duration(indoor)), Outdoor \(Formatters.duration(outdoor))"
                + (other > 0 ? ", Andere \(Formatters.duration(other))" : "") + "."
        } ?? ""
        return Card(title: "Wochenumfang · 8 Wochen", systemImage: "chart.bar") {
            if bars.allSatisfy({ $0.value == 0 }) {
                ChartEmptyState(symbol: "chart.bar", message: "Sobald du fährst, siehst du hier deine Wochenstunden.")
            } else {
                ChartCardHeader(items: [
                    .init(label: "Diese Woche", value: Formatters.duration(current?.seconds ?? 0), color: Theme.accent),
                    .init(label: "Ziel", value: Formatters.duration(Int((target * 3600).rounded())), color: ChartPalette.reference, marker: .dashed),
                ])
                WeekBarsChart(
                    bars: bars,
                    valueLabel: { Formatters.duration(Int(($0 * 3600).rounded())) },
                    axisLabel: { v, top in ChartMath.format(v) + (top ? " h" : "") },
                    line: target > 0 ? (target, "Ziel") : nil,
                    accessibilityLabel: "Wochenumfang der letzten 8 Wochen",
                    accessibilityValue: split + " Ziel \(Formatters.duration(Int((target * 3600).rounded()))).",
                    height: 150)
            }
        }
    }
}

/// D4: fitness (line + faint area) and fatigue (line) over the series; current values as highlight points.
/// No daily-load bars (they sat on a hidden second axis), form stays a key figure and a chip (concept 21, E3).
private struct FitnessFormChart: View {
    var series: [TrainingLoad.DayLoad]
    var current: TrainingLoad.DayLoad
    @Environment(\.colorScheme) private var scheme

    var body: some View {
        let dark = scheme == .dark
        let values = series.flatMap { [$0.ctl, $0.atl] }
        let ticks = ChartMath.niceTicks(min: values.min() ?? 0, max: values.max() ?? 1, count: 4)
        let lower = ticks.first ?? 0, upper = ticks.last ?? 1
        let method = ChartStyle.interpolation(pointCount: series.count)
        Chart {
            ForEach(series) { day in
                AreaMark(x: .value("Tag", day.date), yStart: .value("Basis", lower), yEnd: .value("Fitness", day.ctl))
                    .interpolationMethod(method)
                    .foregroundStyle(ChartStyle.area(ChartPalette.fitness, dark: dark))
                LineMark(x: .value("Tag", day.date), y: .value("Wert", day.ctl), series: .value("Kurve", "Fitness"))
                    .interpolationMethod(method).lineStyle(ChartStyle.stroke(.main)).foregroundStyle(ChartPalette.fitness)
                LineMark(x: .value("Tag", day.date), y: .value("Wert", day.atl), series: .value("Kurve", "Ermüdung"))
                    .interpolationMethod(method).lineStyle(ChartStyle.stroke(.main)).foregroundStyle(ChartPalette.fatigue)
            }
            HighlightPoint(x: .value("Tag", current.date), y: .value("Fitness", current.ctl), color: ChartPalette.fitness, dark: dark)
            HighlightPoint(x: .value("Tag", current.date), y: .value("Ermüdung", current.atl), color: ChartPalette.fatigue, dark: dark)
        }
        .chartYScale(domain: lower...upper)
        .chartStyleAxes(yTicks: ticks, showsX: false)
        .chartXAxis {
            AxisMarks(values: .stride(by: .month)) { _ in
                AxisValueLabel(format: .dateTime.month(.abbreviated).locale(Locale.de))
                    .font(ChartStyle.axisFont).foregroundStyle(ChartStyle.axisColor)
            }
        }
        .environment(\.locale, Locale.de)
        .chartStyleHeight(140)
        .chartAccessibility(
            label: "Fitness und Ermüdung, Verlauf",
            value: ChartMath.seriesSentence(name: "Fitness", values: series.map(\.ctl), period: "\(series.count) Tagen")
                + " Ermüdung \(ChartMath.format(current.atl)). Form \(ChartMath.format(current.tsb)), \(Theme.formLabel(current.tsb)).")
    }
}
