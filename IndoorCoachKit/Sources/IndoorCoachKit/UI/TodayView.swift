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
                await model.syncRides(userInitiated: true)
                await model.syncHealth() // ANCHOR-W3B
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
            // ANCHOR-K2-HEUTE (Wochenrückblick)
            if let reviewWeek = model.weeklyReviewCardWeek() {
                WeeklyReviewCard(weekStart: reviewWeek, rides: rides, workouts: workouts)
            } else {
                // ANCHOR-K3-HEUTE (Saison-Challenge)
                ChallengeHighlightSlot(rides: rides)
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
                    PowerProfileChart(definition: d, ftp: model.profile.ftp, showAxes: false, height: 64)
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
            Chart(series) { day in
                // Soft jelly area under fitness, crisp lines in the deeper tones (≥ 3:1 on the card).
                AreaMark(x: .value("Tag", day.date), y: .value("Wert", day.ctl))
                    .foregroundStyle(LinearGradient(colors: [Theme.fitness.opacity(0.35), Theme.fitness.opacity(0)],
                                                    startPoint: .top, endPoint: .bottom))
                    .interpolationMethod(.monotone)
                LineMark(x: .value("Tag", day.date), y: .value("Wert", day.ctl), series: .value("Kurve", "Fitness"))
                    .foregroundStyle(Theme.fitnessLine)
                    .lineStyle(StrokeStyle(lineWidth: 2.5, lineCap: .round))
                    .interpolationMethod(.monotone)
                LineMark(x: .value("Tag", day.date), y: .value("Wert", day.atl), series: .value("Kurve", "Ermüdung"))
                    .foregroundStyle(Theme.fatigueLine)
                    .lineStyle(StrokeStyle(lineWidth: 2, lineCap: .round))
                    .interpolationMethod(.monotone)
                BarMark(x: .value("Tag", day.date, unit: .day), y: .value("TSS", day.tss / 3))
                    .foregroundStyle(Color(Palette.mangoPop).opacity(0.45))
            }
            .chartLegend(.hidden)
            .chartXAxis {
                AxisMarks(values: .stride(by: .month)) { _ in
                    AxisGridLine()
                    AxisValueLabel(format: .dateTime.month(.abbreviated).locale(Locale.de))
                        .foregroundStyle(Theme.axisLabel)
                }
            }
            .frame(height: 140)
            HStack(spacing: 14) {
                legendDot(Theme.fitnessLine, "Fitness (CTL)")
                legendDot(Theme.fatigueLine, "Ermüdung (ATL)")
                legendDot(Color(Palette.mangoPop), "Tages-TSS")
            }
        }
    }

    private func legendDot(_ color: Color, _ text: String) -> some View {
        HStack(spacing: 5) {
            Circle().fill(color).frame(width: 7, height: 7)
            Text(text).font(.caption2).foregroundStyle(.secondary)
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
        // Legend and bars only for kinds that occur in the 8 weeks (no empty "Andere" entry).
        // Never an empty scale (empty seed / no rides yet): Charts logs an invalid configuration otherwise.
        let present = VolumeKind.allCases.filter { kind in weeks.contains { kind.seconds(in: $0) > 0 } }
        let kinds = present.isEmpty ? [VolumeKind.indoor] : present
        return Card(title: "Wochenumfang · 8 Wochen", systemImage: "chart.bar") {
            Chart(weeks) { w in
                ForEach(kinds, id: \.self) { kind in
                    BarMark(x: .value("Woche", w.weekStart, unit: .weekOfYear),
                            y: .value("Stunden", Double(kind.seconds(in: w)) / 3600))
                        .foregroundStyle(by: .value("Art", kind.rawValue))
                        .cornerRadius(5)
                }
            }
            // Deeper tones so the bars keep ≥ 3:1 against the white card.
            .chartForegroundStyleScale(domain: kinds.map(\.rawValue), range: kinds.map(\.color))
            .chartYAxisLabel("h")
            .chartXAxis {
                AxisMarks(values: .stride(by: .weekOfYear, count: 2)) { _ in
                    AxisValueLabel(format: .dateTime.day().month(.defaultDigits).locale(Locale.de))
                        .foregroundStyle(Theme.axisLabel)
                }
            }
            .frame(height: 150)
        }
    }
}

/// Arten im Wochenumfang-Diagramm.
private enum VolumeKind: String, CaseIterable {
    case indoor = "Indoor", outdoor = "Outdoor", other = "Andere"

    func seconds(in week: TrainingLoad.WeekSummary) -> Int {
        switch self {
        case .indoor: week.indoorSeconds
        case .outdoor: max(0, week.seconds - week.indoorSeconds - week.otherSeconds)
        case .other: week.otherSeconds
        }
    }

    var color: Color {
        switch self {
        case .indoor: Theme.indoorMark
        case .outdoor: Theme.outdoorMark
        case .other: Theme.otherMark
        }
    }
}
