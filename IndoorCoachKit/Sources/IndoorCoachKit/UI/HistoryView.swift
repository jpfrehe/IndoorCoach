import Charts
import SwiftData
import SwiftUI

enum RideFilter: String, CaseIterable, Identifiable {
    case all = "Alle", indoor = "Indoor", outdoor = "Outdoor"
    var id: String { rawValue }

    func matches(_ ride: RideSummary) -> Bool {
        switch self {
        case .all: true
        case .indoor: ride.isIndoor
        case .outdoor: !ride.isIndoor
        }
    }
}

struct HistoryView: View {
    @Environment(AppModel.self) private var model
    @Query(sort: \StoredRide.startDate, order: .reverse) private var storedRides: [StoredRide]
    @State private var filter: RideFilter = .all

    var body: some View {
        let rides = storedRides.map(\.summary).filter(filter.matches)
        NavigationStack {
            List {
                Section {
                    Picker("Filter", selection: $filter) {
                        ForEach(RideFilter.allCases) { Text($0.rawValue).tag($0) }
                    }
                    .pickerStyle(.segmented)
                    .listRowBackground(Color.clear)
                    .listRowInsets(EdgeInsets())

                    HistoryChart(rides: rides, ftp: model.profile.ftp, thresholdHeartRate: model.profile.thresholdHeartRate)
                        .listRowInsets(EdgeInsets(top: 12, leading: 12, bottom: 12, trailing: 12))
                    EffortWeekCard(weeks: model.effortWeeks(rides: storedRides.map(\.summary)))
                        .listRowInsets(EdgeInsets(top: 12, leading: 12, bottom: 12, trailing: 12))
                }
                if rides.isEmpty {
                    EmptyStateView(title: "Keine Fahrten", systemImage: "bicycle",
                                   message: "Verbinde Strava im Profil, um deine Fahrten zu sehen.")
                }
                ForEach(groups(rides), id: \.start) { group in
                    Section {
                        ForEach(group.rides) { ride in
                            NavigationLink(value: ride) { RideRow(ride: ride, ftp: model.profile.ftp, thresholdHeartRate: model.profile.thresholdHeartRate,
                                                                    heartRate: model.profile.heartRateProfile) }
                        }
                    } header: {
                        HStack {
                            Text("KW \(Calendar(identifier: .iso8601).component(.weekOfYear, from: group.start))")
                            Spacer()
                            Text("\(Formatters.duration(group.rides.reduce(0) { $0 + $1.movingTime })) · TSS \(Int(group.rides.reduce(0) { $0 + TrainingLoad.estimateTSS(for: $1, ftp: model.profile.ftp, thresholdHeartRate: model.profile.thresholdHeartRate).tss }.rounded()))")
                                .monospacedDigit()
                        }
                    }
                }
                if !model.isDemoMode {
                    Section {
                        PoweredByStrava()
                    }
                }
            }
            .scrollContentBackground(.hidden)
            .background(Theme.canvas)
            .navigationTitle("Verlauf")
            .navigationDestination(for: RideSummary.self) { RideDetailView(ride: $0) }
            .refreshable {
                if model.isStravaConnected { await model.syncStrava() }
                else { model.show("Strava ist nicht verbunden – verbinde es im Profil.", error: false) }
            }
        }
    }

    struct Group { let start: Date; let rides: [RideSummary] }

    private func groups(_ rides: [RideSummary]) -> [Group] {
        var cal = Calendar.current
        cal.firstWeekday = 2
        let grouped = Dictionary(grouping: rides) { cal.dateInterval(of: .weekOfYear, for: $0.startDate)?.start ?? $0.startDate }
        return grouped.keys.sorted(by: >).map { Group(start: $0, rides: grouped[$0]!.sorted { $0.startDate > $1.startDate }) }
    }
}

struct HistoryChart: View {
    var rides: [RideSummary]
    var ftp: Int
    var thresholdHeartRate: Int? = nil
    @State private var metric: Metric = .hours

    enum Metric: String, CaseIterable, Identifiable {
        case hours = "Stunden", tss = "TSS"
        var id: String { rawValue }
    }

    var body: some View {
        let today = Calendar.current.startOfDay(for: .now)
        let weeks = TrainingLoad.weeks(rides: rides, ftp: ftp, thresholdHeartRate: thresholdHeartRate,
                                       from: Calendar.current.date(byAdding: .weekOfYear, value: -11, to: today)!, to: today)
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("12 Wochen").font(.subheadline.weight(.semibold)).foregroundStyle(.secondary)
                Spacer()
                // Segmented instead of a menu: one tap, and the menu stayed open after choosing (UX audit F06).
                Picker("Metrik", selection: $metric) {
                    ForEach(Metric.allCases) { Text($0.rawValue).tag($0) }
                }
                .pickerStyle(.segmented)
                .labelsHidden()
                .fixedSize()
            }
            Chart(weeks) { w in
                BarMark(x: .value("Woche", w.weekStart, unit: .weekOfYear),
                        y: .value(metric.rawValue, metric == .hours ? Double(w.seconds) / 3600 : w.tss))
                    // Hot jelly → berry: ≥ 4.5:1 against the card over the whole bar (audit measures marks like text).
                    .foregroundStyle(LinearGradient(colors: [Theme.cap(.z6), Color(Palette.accentTextLight)],
                                                    startPoint: .top, endPoint: .bottom))
                    .cornerRadius(5)
            }
            .chartXAxis {
                AxisMarks(values: .stride(by: .weekOfYear, count: 3)) { _ in
                    AxisValueLabel(format: .dateTime.day().month(.defaultDigits).locale(Locale(identifier: "de_DE")))
                        .foregroundStyle(Theme.axisLabel)
                }
            }
            .chartYAxis {
                AxisMarks { _ in
                    AxisGridLine()
                    AxisValueLabel().foregroundStyle(Theme.axisLabel)
                }
            }
            .frame(height: 140)
            let total = weeks.reduce(0) { $0 + $1.seconds }
            HStack {
                StatTile(title: "Ø pro Woche", value: Formatters.duration(total / max(1, weeks.count) / 60 * 60))
                StatTile(title: "Fahrten", value: "\(weeks.reduce(0) { $0 + $1.rides })")
                StatTile(title: "TSS gesamt", value: "\(Int(weeks.reduce(0) { $0 + $1.tss }.rounded()))")
            }
        }
    }
}

struct RideDetailView: View {
    var ride: RideSummary
    @Environment(AppModel.self) private var model

    var body: some View {
        let est = TrainingLoad.estimateTSS(for: ride, ftp: model.profile.ftp, thresholdHeartRate: model.profile.thresholdHeartRate)
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                VStack(alignment: .leading, spacing: 6) {
                    JellyChip(text: ride.isIndoor ? "Indoor" : "Outdoor",
                              systemImage: ride.isIndoor ? "figure.indoor.cycle" : "figure.outdoor.cycle",
                              fill: ride.isIndoor ? Theme.indoor : Theme.outdoor)
                    Text(ride.name).font(.largeTitle.weight(.bold))
                    Text(ride.startDate.formatted(.dateTime.weekday(.wide).day().month(.wide).year().hour().minute().locale(Locale(identifier: "de_DE"))))
                        .foregroundStyle(.secondary)
                }
                Card {
                    Grid(alignment: .leading, horizontalSpacing: 12, verticalSpacing: 14) {
                        GridRow {
                            StatTile(title: "Zeit", value: Formatters.duration(ride.movingTime))
                            StatTile(title: "Distanz", value: Formatters.distanceKm(ride.distance))
                            StatTile(title: "TSS", value: "\(Int(est.tss.rounded()))")
                        }
                        GridRow {
                            StatTile(title: "NP", value: ride.weightedAverageWatts.map { "\(Int($0))" } ?? "–", unit: "W")
                            StatTile(title: "Ø Leistung", value: ride.averageWatts.map { "\(Int($0))" } ?? "–", unit: "W")
                            StatTile(title: "IF", value: est.intensityFactor.map { Formatters.decimal($0, digits: 2) } ?? "–")
                        }
                        GridRow {
                            StatTile(title: "Ø HF", value: ride.averageHeartrate.map { "\(Int($0))" } ?? "–", unit: "bpm")
                            StatTile(title: "Max HF", value: ride.maxHeartrate.map { "\(Int($0))" } ?? "–", unit: "bpm")
                            StatTile(title: "Arbeit", value: ride.kilojoules.map { "\(Int($0))" } ?? "–", unit: "kJ")
                        }
                    }
                }
                RelativeEffortCard(ride: ride)
                if est.source != .power {
                    Label(est.source == .heartRate ? "TSS aus Herzfrequenz geschätzt." : "TSS aus der Dauer geschätzt (keine Leistungsdaten).",
                          systemImage: "info.circle")
                        .font(.caption).foregroundStyle(.secondary)
                }
                if !model.isDemoMode, let url = URL(string: "https://www.strava.com/activities/\(ride.id)") {
                    Link(destination: url) {
                        Label("Auf Strava ansehen", systemImage: "arrow.up.right.square")
                            .font(.headline)
                            .foregroundStyle(Theme.strava)
                    }
                    PoweredByStrava()
                }
            }
            .padding()
        }
        .background(Theme.canvas)
        .navigationTitle(ride.name)
        .inlineNavigationTitle()
    }
}
