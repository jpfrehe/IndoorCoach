import Charts
import SwiftData
import SwiftUI
import TipKit

enum RideFilter: String, CaseIterable, Identifiable {
    case all = "Alle", indoor = "Indoor", outdoor = "Outdoor"
    case strength = "Kraft", other = "Andere" // ANCHOR-STRENGTH
    var id: String { rawValue }

    func matches(_ ride: RideSummary) -> Bool {
        switch self {
        case .all: true
        case .indoor: ride.isIndoor
        case .outdoor: !ride.isIndoor && !ride.isForeignSport   // „Outdoor“ nur für echte Radfahrten
        case .strength, .other: false
        }
    }

    // ANCHOR-STRENGTH
    func matches(_ row: StoredStrengthSession) -> Bool {
        switch self {
        case .all: true
        case .indoor, .outdoor: false
        case .strength: !row.isOtherSport
        case .other: row.isOtherSport
        }
    }

    var showsRideCharts: Bool { self != .strength && self != .other }
}

struct HistoryView: View {
    @Environment(AppModel.self) private var model
    @Query(sort: \StoredRide.startDate, order: .reverse) private var storedRides: [StoredRide]
    @Query(sort: \StoredStrengthSession.start, order: .reverse) private var strengthRows: [StoredStrengthSession] // ANCHOR-STRENGTH
    @State private var filter: RideFilter = .all

    var body: some View {
        let rides = storedRides.map(\.summary).filter { filter.matches($0) }
        let strength = strengthRows.filter { filter.matches($0) }
        NavigationStack {
            List {
                Section {
                    NavigationLink { PerformanceView() } label: {
                        HStack(spacing: 12) {
                            Image(systemName: "bolt.fill").font(.title3).foregroundStyle(Theme.accent).frame(width: 28)
                            VStack(alignment: .leading, spacing: 2) {
                                Text("Leistung").font(.headline)
                                Text("Leistungskurve, Bestleistungen, VO₂max").font(.caption).foregroundStyle(Theme.rowSecondary)
                            }
                        }
                        .frame(minHeight: 44)
                    }
                    .popoverTip(PerformanceTip())
                    .accessibilityIdentifier("performance.open")
                }
                Section {
                    Picker("Filter", selection: $filter) {
                        ForEach(RideFilter.allCases) { Text($0.rawValue).tag($0) }
                    }
                    .pickerStyle(.segmented)
                    .listRowBackground(Color.clear)
                    .listRowInsets(EdgeInsets())
                }
                Section {
                    if filter.showsRideCharts {
                        HistoryChart(rides: rides, ftp: model.profile.ftp, thresholdHeartRate: model.profile.thresholdHeartRate)
                            .listRowInsets(EdgeInsets(top: 12, leading: 12, bottom: 12, trailing: 12))
                        EffortWeekCard(weeks: model.effortWeeks(rides: storedRides.map(\.summary)))
                            .listRowInsets(EdgeInsets(top: 12, leading: 12, bottom: 12, trailing: 12))
                    }
                }
                if rides.isEmpty && strength.isEmpty {
                    if filter.showsRideCharts {
                        EmptyStateView(title: "Keine Fahrten", systemImage: "bicycle",
                                       message: "Verbinde Strava unter Profil → Dienste & Geräte, um deine Fahrten zu sehen.")
                    } else {
                        EmptyStateView(title: "Keine Einheiten", systemImage: "dumbbell",
                                       message: "Trage Kraft oder andere Einheiten auf Heute nach.")
                    }
                }
                ForEach(groups(rides, strength: strength), id: \.start) { group in
                    Section {
                        // ANCHOR-STRENGTH
                        ForEach(group.strength) { row in
                            NavigationLink(value: row) { StrengthRow(row: row) }
                        }
                        ForEach(group.rides) { ride in
                            NavigationLink(value: ride) {
                                VStack(alignment: .leading, spacing: 4) {
                                    RideRow(ride: ride, ftp: model.profile.ftp, thresholdHeartRate: model.profile.thresholdHeartRate,
                                            heartRate: model.profile.heartRateProfile)
                                    if !(ride.powerCurve ?? [:]).isEmpty { SecondsDataBadge() }
                                    if ride.healthNote != nil {
                                        Label("Mit Health-Workout zusammengeführt", systemImage: "heart.text.square")
                                            .font(.caption2.weight(.semibold)).foregroundStyle(Theme.rowSecondary)
                                            .padding(.leading, 52)
                                            .accessibilityIdentifier("history.healthNote")
                                    }
                                }
                            }
                        }
                    } header: {
                        HStack {
                            Text("KW \(Calendar(identifier: .iso8601).component(.weekOfYear, from: group.start))")
                            Spacer()
                            Text(HistoryWeekSummary.text(rides: group.rides, strength: group.strength.map(\.session),
                                                         ftp: model.profile.ftp, thresholdHeartRate: model.profile.thresholdHeartRate))
                                .monospacedDigit()
                        }
                    }
                }
                if model.isStravaConnected {
                    Section {
                        PoweredByStrava()
                    }
                }
            }
            .scrollContentBackground(.hidden)
            .background(Theme.canvas)
            .navigationTitle("Verlauf")
            .navigationDestination(for: RideSummary.self) { RideDetailView(ride: $0) }
            .navigationDestination(for: StoredStrengthSession.self) { StrengthDetailView(row: $0) } // ANCHOR-STRENGTH
            .refreshable {
                await model.refreshFromPull()
            }
        }
    }

    struct Group { let start: Date; let rides: [RideSummary]; var strength: [StoredStrengthSession] = [] }

    private func groups(_ rides: [RideSummary], strength: [StoredStrengthSession] = []) -> [Group] {
        var cal = Calendar.current
        cal.firstWeekday = 2
        func weekStart(_ d: Date) -> Date { cal.dateInterval(of: .weekOfYear, for: d)?.start ?? d }
        let grouped = Dictionary(grouping: rides) { weekStart($0.startDate) }
        let strengthGrouped = Dictionary(grouping: strength) { weekStart($0.start) }
        let keys = Set(grouped.keys).union(strengthGrouped.keys)
        return keys.sorted(by: >).map {
            Group(start: $0, rides: (grouped[$0] ?? []).sorted { $0.startDate > $1.startDate },
                  strength: (strengthGrouped[$0] ?? []).sorted { $0.start > $1.start })
        }
    }
}

/// "Sekundendaten": the ride has a measured 1 Hz power curve (FIT file, Mac bridge).
struct SecondsDataBadge: View {
    var body: some View {
        Label("Sekundendaten", systemImage: "waveform.path.ecg")
            .font(.caption2.weight(.semibold))
            .foregroundStyle(Theme.rowSecondary)
            .padding(.leading, 52)
            .accessibilityLabel("Mit Sekundendaten")
            .accessibilityIdentifier("history.secondsBadge")
    }
}

struct HistoryChart: View {
    var rides: [RideSummary]
    var ftp: Int
    var thresholdHeartRate: Int? = nil
    @State private var metric: Metric = .hours
    @State private var selectedWeek: Date?

    private func value(of week: TrainingLoad.WeekSummary) -> Double {
        metric == .hours ? Double(week.seconds) / 3600 : week.tss
    }

    private func text(_ value: Double) -> String {
        metric == .hours ? Formatters.duration(Int((value * 3600).rounded())) : "\(Int(value.rounded()))"
    }

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
            let bars = weeks.map { WeekBarsChart.Bar(weekStart: $0.weekStart, value: value(of: $0)) }
            if weeks.allSatisfy({ $0.rides == 0 }) {
                ChartEmptyState(symbol: "chart.bar", message: "Sobald du fährst, siehst du hier deine Wochen.")
            } else {
                let isHours = metric == .hours
                let picked = WeekBarsChart.selectedBar(in: bars, raw: selectedWeek)
                let shown = picked ?? bars.last
                let average = bars.isEmpty ? 0 : bars.map(\.value).reduce(0, +) / Double(bars.count)
                ChartCardHeader(items: [
                    .init(label: metric == .hours ? "Stunden" : "TSS", value: shown.map { text($0.value) } ?? "–", color: Theme.accent),
                    .init(label: "Ø", value: text(average), color: ChartPalette.reference, marker: .dashed),
                ], selectionTitle: picked.map { "Woche ab " + $0.weekStart.formatted(.dateTime.day().month(.defaultDigits).locale(Locale.de)) },
                                resetTitle: "Aufheben", onReset: { selectedWeek = nil })
                WeekBarsChart(
                    bars: bars,
                    valueLabel: { isHours ? Formatters.duration(Int(($0 * 3600).rounded())) : "\(Int($0.rounded()))" },
                    axisLabel: { v, top in ChartMath.format(v) + (top ? (isHours ? " h" : " TSS") : "") },
                    line: average > 0 ? (average, "Ø " + text(average)) : nil,
                    accessibilityLabel: "Verlauf der letzten 12 Wochen, \(metric.rawValue)",
                    accessibilityValue: ChartMath.seriesSentence(name: "Aktuelle Woche", values: bars.map(\.value),
                                                                 decimals: metric == .hours ? 1 : 0,
                                                                 unit: metric == .hours ? " Stunden" : " TSS", period: "12 Wochen")
                        + " Durchschnitt \(text(average)).",
                    selection: $selectedWeek,
                    xStrideCount: 3,
                    height: ChartStyle.heightNormal - 30)
            }
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

    /// Longest headline duration at which this ride holds the best measured value of the last 90 days.
    private var prRecord: PowerCurve.Point? {
        guard ride.powerCurve != nil else { return nil }
        return PowerCurve.records(for: ride, among: model.allRides()).last
    }

    var body: some View {
        let est = TrainingLoad.estimateTSS(for: ride, ftp: model.profile.ftp, thresholdHeartRate: model.profile.thresholdHeartRate)
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                VStack(alignment: .leading, spacing: 6) {
                    if let sport = ride.foreignSport {
                        JellyChip(text: HealthImport.germanName(for: sport), systemImage: SportClassification.symbol(for: sport),
                                  fill: Theme.softFill)
                    } else {
                        JellyChip(text: ride.isIndoor ? "Indoor" : "Outdoor",
                                  systemImage: ride.isIndoor ? "figure.indoor.cycle" : "figure.outdoor.cycle",
                                  fill: ride.isIndoor ? Theme.indoor : Theme.outdoor)
                    }
                    Text(ride.name).font(.largeTitle.weight(.bold))
                    Text(ride.startDate.formatted(.dateTime.weekday(.wide).day().month(.wide).year().hour().minute().locale(Locale.de)))
                        .foregroundStyle(.secondary)
                }
                Card {
                    Grid(alignment: .leading, horizontalSpacing: 12, verticalSpacing: 14) {
                        GridRow {
                            StatTile(title: "Zeit", value: Formatters.duration(ride.movingTime))
                            StatTile(title: "Distanz", value: Formatters.distanceKm(ride.distance))
                            StatTile(title: ride.isForeignSport ? "TSS (geschätzt)" : "TSS", value: "\(Int(est.tss.rounded()))")
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
                if let record = prRecord {
                    Label("Neue Bestleistung: \(PerformanceFormat.duration(record.duration)) · \(PerformanceFormat.watts(record.watts))",
                          systemImage: "trophy.fill")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(Theme.ink)
                        .padding(.horizontal, 14).padding(.vertical, 10)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(Theme.sunset, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
                        .accessibilityElement(children: .combine)
                        .accessibilityIdentifier("ride.pr")
                }
                // ANCHOR-B1-RIDE: Zeile „Gipfelmoment dieser Fahrt ansehen“, wenn zur Fahrt ein Moment gehört – Agent A
                MomentRideRow(ride: ride)
                // ANCHOR-K3-FAHRT (Challenge-Fortschritt/Trophäe)
                RideChallengeNote(ride: ride)

                RelativeEffortCard(ride: ride)

                RideZonesCard(ride: ride)

                // ANCHOR-WARMUP (Aufwärm-Check)
                WarmupCheckCard(ride: ride)

                // ANCHOR-K4-FAHRT (Effizienz & Entkopplung)
                RideEfficiencyCard(ride: ride, ftp: model.profile.ftp)

                // ANCHOR-P2-FAHRT (Ermüdungsresistenz)
                RideDurabilityRow(ride: ride)

                if ride.isForeignSport {
                    Label("TSS geschätzt aus Dauer und Puls. Zählt nur in der Belastung, nie in Leistungsanalysen.", systemImage: "info.circle")
                        .font(.caption).foregroundStyle(.secondary)
                        .accessibilityIdentifier("ride.foreignNote")
                }
                if let note = ride.healthNote {
                    Label(note, systemImage: "heart.text.square")
                        .font(.caption).foregroundStyle(.secondary)
                        .accessibilityIdentifier("ride.healthNote")
                }
                if est.source != .power, !ride.isForeignSport {
                    Label(est.source == .heartRate ? "TSS aus Herzfrequenz geschätzt." : "TSS aus der Dauer geschätzt (keine Leistungsdaten).",
                          systemImage: "info.circle")
                        .font(.caption).foregroundStyle(.secondary)
                }
                if model.isStravaConnected, ride.isFromStrava, let url = URL(string: "https://www.strava.com/activities/\(ride.id)") {
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
