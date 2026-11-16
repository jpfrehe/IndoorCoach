import Charts
import SwiftData
import SwiftUI

struct TodayView: View {
    @Binding var tab: AppTab
    @Environment(AppModel.self) private var model
    @Query(sort: \StoredRide.startDate) private var storedRides: [StoredRide]
    @Query(sort: \StoredWorkout.date) private var workouts: [StoredWorkout]

    var body: some View {
        NavigationStack {
            ScrollView {
                TodayDashboard(rides: storedRides.map(\.summary), workouts: workouts, tab: $tab)
                    .padding(.horizontal)
                    .padding(.bottom, 24)
            }
            .navigationTitle("Heute")
            .navigationDestination(for: StoredWorkout.self) { WorkoutDetailView(workout: $0) }
            .refreshable { await model.syncStrava() }
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
            Text(Date.now.formatted(.dateTime.weekday(.wide).day().month(.wide).locale(Locale(identifier: "de_DE"))))
                .font(.subheadline.weight(.medium))
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity, alignment: .leading)

            if model.isDemoMode { demoHint }
            nextWorkoutCard(next)
            if let current = series.last { formCard(series: series, current: current) }
            if let week = weeks.last { weekCard(week) }
            volumeCard(weeks)
        }
    }

    private var demoHint: some View {
        Card {
            HStack(alignment: .top, spacing: 12) {
                Image(systemName: "sparkles").font(.title2).foregroundStyle(Theme.accent)
                VStack(alignment: .leading, spacing: 6) {
                    Text("Demo-Modus").font(.headline)
                    Text("Du siehst Beispieldaten. Verbinde Strava und hinterlege deinen Claude-API-Key im Profil, um mit deinen echten Fahrten zu planen.")
                        .font(.subheadline).foregroundStyle(.secondary)
                    Button("Zum Profil") { tab = .profile }
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
                Button { tab = .plan } label: {
                    Label("Plan erstellen", systemImage: "sparkles").frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
            }
        }
    }

    private func formCard(series: [TrainingLoad.DayLoad], current: TrainingLoad.DayLoad) -> some View {
        Card(title: "Form · letzte 90 Tage", systemImage: "waveform.path.ecg") {
            HStack {
                StatTile(title: "Fitness", value: Formatters.decimal(current.ctl), tint: Theme.fitness)
                StatTile(title: "Ermüdung", value: Formatters.decimal(current.atl), tint: Theme.fatigue)
                StatTile(title: "Form", value: (current.tsb > 0 ? "+" : "") + Formatters.decimal(current.tsb),
                         tint: Theme.formColor(current.tsb))
            }
            Text(Theme.formLabel(current.tsb))
                .font(.caption.weight(.semibold))
                .padding(.horizontal, 8).padding(.vertical, 3)
                .background(Theme.formColor(current.tsb).opacity(0.15), in: Capsule())
                .foregroundStyle(Theme.formColor(current.tsb))
            Chart(series) { day in
                LineMark(x: .value("Tag", day.date), y: .value("Wert", day.ctl), series: .value("Kurve", "Fitness"))
                    .foregroundStyle(Theme.fitness)
                    .interpolationMethod(.monotone)
                LineMark(x: .value("Tag", day.date), y: .value("Wert", day.atl), series: .value("Kurve", "Ermüdung"))
                    .foregroundStyle(Theme.fatigue.opacity(0.8))
                    .interpolationMethod(.monotone)
                BarMark(x: .value("Tag", day.date, unit: .day), y: .value("TSS", day.tss / 3))
                    .foregroundStyle(.gray.opacity(0.25))
            }
            .chartLegend(.hidden)
            .chartXAxis {
                AxisMarks(values: .stride(by: .month)) { _ in
                    AxisGridLine()
                    AxisValueLabel(format: .dateTime.month(.abbreviated).locale(Locale(identifier: "de_DE")))
                }
            }
            .frame(height: 140)
            HStack(spacing: 14) {
                legendDot(Theme.fitness, "Fitness (CTL)")
                legendDot(Theme.fatigue, "Ermüdung (ATL)")
                legendDot(.gray.opacity(0.5), "Tages-TSS")
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
                    Circle().stroke(Theme.accent.opacity(0.18), lineWidth: 10)
                    Circle().trim(from: 0, to: progress)
                        .stroke(Theme.accent.gradient, style: StrokeStyle(lineWidth: 10, lineCap: .round))
                        .rotationEffect(.degrees(-90))
                    Text("\(Int(progress * 100)) %").font(.callout.weight(.bold)).monospacedDigit()
                }
                .frame(width: 76, height: 76)
                VStack(alignment: .leading, spacing: 10) {
                    HStack {
                        StatTile(title: "Zeit", value: Formatters.duration(week.seconds))
                        StatTile(title: "Ziel", value: Formatters.decimal(model.profile.weeklyHours, digits: 1), unit: "h")
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
        Card(title: "Wochenumfang · 8 Wochen", systemImage: "chart.bar") {
            Chart(weeks) { w in
                BarMark(x: .value("Woche", w.weekStart, unit: .weekOfYear),
                        y: .value("Stunden", Double(w.indoorSeconds) / 3600))
                    .foregroundStyle(by: .value("Art", "Indoor"))
                BarMark(x: .value("Woche", w.weekStart, unit: .weekOfYear),
                        y: .value("Stunden", Double(w.seconds - w.indoorSeconds) / 3600))
                    .foregroundStyle(by: .value("Art", "Outdoor"))
            }
            .chartForegroundStyleScale(["Indoor": Theme.indoor, "Outdoor": Theme.outdoor])
            .chartYAxisLabel("h")
            .chartXAxis {
                AxisMarks(values: .stride(by: .weekOfYear, count: 2)) { _ in
                    AxisValueLabel(format: .dateTime.day().month(.defaultDigits).locale(Locale(identifier: "de_DE")))
                }
            }
            .frame(height: 150)
        }
    }
}
