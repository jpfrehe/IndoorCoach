import Charts
import SwiftData
import SwiftUI

/// Selectable analysis window for the power curve.
enum PerformanceRange: String, CaseIterable, Identifiable {
    case weeks6 = "6 Wochen", days90 = "90 Tage", year = "1 Jahr"
    var id: String { rawValue }
    var days: Int {
        switch self {
        case .weeks6: 42
        case .days90: 90
        case .year: 365
        }
    }
}

enum PerformanceFormat {
    /// "5 s", "1 min", "60 min".
    static func duration(_ seconds: Int) -> String {
        seconds < 60 ? "\(seconds) s" : "\(seconds / 60) min"
    }

    static func watts(_ w: Double) -> String { "\(Int(w.rounded())) W" }

    static func date(_ d: Date) -> String {
        d.formatted(.dateTime.day().month(.abbreviated).year().locale(Locale(identifier: "de_DE")))
    }
}

/// "Leistung": power curve, best efforts, eFTP and VO2max (opened from the Verlauf tab).
struct PerformanceView: View {
    @Environment(AppModel.self) private var model
    @Query(sort: \StoredRide.startDate) private var storedRides: [StoredRide]
    @State private var range: PerformanceRange = .days90

    var body: some View {
        let rides = storedRides.map(\.summary)
        let comparison = PowerCurve.comparison(rides: rides, days: range.days)
        let current = comparison.current
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                Picker("Zeitraum", selection: $range) {
                    ForEach(PerformanceRange.allCases) { Text($0.rawValue).tag($0) }
                }
                .pickerStyle(.segmented)

                if current.points.isEmpty {
                    EmptyStateView(title: "Noch keine Leistungsdaten", systemImage: "bolt.fill",
                                   message: "Sobald Fahrten mit Leistung da sind, siehst du hier deine Bestleistungen.")
                } else {
                    curveCard(comparison)
                    bestEffortsCard(current)
                }
                coverageNote(current)
                if current.estimatedFTP != nil { eftpCard(current) }
                VO2maxCard(rides: rides, showTrend: true, range: range)
                // ANCHOR-K4-LEISTUNG (Aerobe Effizienz)

                explanation
            }
            .padding()
        }
        .background(Theme.canvas)
        .navigationTitle("Leistung")
        .inlineNavigationTitle()
    }

    // MARK: Curve

    private func curveCard(_ comparison: PowerCurve.Comparison) -> some View {
        let cur = comparison.current.sortedPoints
        let prev = comparison.previous.sortedPoints
        let maxDuration = Double(max(cur.last?.duration ?? 60, 60))
        return Card(title: "Leistungskurve", systemImage: "bolt.fill") {
            Chart {
                ForEach(prev, id: \.duration) { p in
                    LineMark(x: .value("Dauer", Double(p.duration)), y: .value("Watt", p.watts),
                             series: .value("Zeitraum", "Vorher"))
                        .foregroundStyle(Theme.axisLabel)
                        .lineStyle(StrokeStyle(lineWidth: 2, lineCap: .round, dash: [5, 4]))
                        .interpolationMethod(.monotone)
                }
                ForEach(cur, id: \.duration) { p in
                    LineMark(x: .value("Dauer", Double(p.duration)), y: .value("Watt", p.watts),
                             series: .value("Zeitraum", "Aktuell"))
                        .foregroundStyle(Theme.cap(.z6))
                        .lineStyle(StrokeStyle(lineWidth: 3, lineCap: .round))
                        .interpolationMethod(.monotone)
                }
                ForEach(cur.filter { $0.source == .measured && PowerCurve.headlineDurations.contains($0.duration) }, id: \.duration) { p in
                    PointMark(x: .value("Dauer", Double(p.duration)), y: .value("Watt", p.watts))
                        .foregroundStyle(Theme.cap(.z6))
                        .symbolSize(40)
                }
            }
            .chartXScale(domain: 1...maxDuration, type: .log)
            .chartYScale(domain: .automatic(includesZero: false))
            .chartLegend(.hidden)
            .chartXAxis {
                // Log axis: 5/10/20/60 min sit too close for labels – keep one label per decade-ish step.
                AxisMarks(values: [5, 60, 300, 1200, 3600].map(Double.init).filter { $0 <= maxDuration }) { value in
                    AxisGridLine()
                    AxisValueLabel {
                        if let d = value.as(Double.self) { Text(PerformanceFormat.duration(Int(d))) }
                    }
                    .foregroundStyle(Theme.axisLabel)
                }
            }
            .chartYAxis {
                AxisMarks { _ in
                    AxisGridLine()
                    AxisValueLabel().foregroundStyle(Theme.axisLabel)
                }
            }
            .chartYAxisLabel("W")
            .frame(height: 220)
            .accessibilityElement(children: .ignore)
            .accessibilityLabel("Leistungskurve, beste Durchschnittsleistung je Dauer")
            .accessibilityValue(curveSummary(comparison.current))
            .accessibilityIdentifier("performance.curve")

            HStack(spacing: 14) {
                legendLine(Theme.cap(.z6), "Aktuell", dashed: false)
                if !prev.isEmpty { legendLine(Theme.axisLabel, "Vorperiode", dashed: true) }
            }
        }
    }

    private func curveSummary(_ agg: PowerCurve.Aggregate) -> String {
        PowerCurve.headlineDurations.compactMap { d in
            agg.points[d].map { "\(PerformanceFormat.duration(d)) \(Int($0.watts.rounded())) Watt" }
        }.joined(separator: ", ")
    }

    private func legendLine(_ color: Color, _ text: String, dashed: Bool) -> some View {
        HStack(spacing: 6) {
            Capsule().fill(color).frame(width: 18, height: dashed ? 2 : 3)
            Text(text).font(.caption).foregroundStyle(Theme.rowSecondary)
        }
        .accessibilityElement(children: .combine)
    }

    // MARK: Best efforts

    private func bestEffortsCard(_ agg: PowerCurve.Aggregate) -> some View {
        Card(title: "Bestleistungen", systemImage: "trophy") {
            VStack(spacing: 0) {
                ForEach(PowerCurve.headlineDurations, id: \.self) { d in
                    if let p = agg.points[d] { effortRow(p) }
                }
            }
        }
    }

    private func effortRow(_ p: PowerCurve.Point) -> some View {
        let perKg = model.profile.weightKg > 0 ? p.watts / model.profile.weightKg : nil
        let measured = p.source == .measured
        return HStack(alignment: .firstTextBaseline, spacing: 10) {
            Text(PerformanceFormat.duration(p.duration)).font(.headline).frame(minWidth: 56, alignment: .leading)
            VStack(alignment: .leading, spacing: 2) {
                Text(PerformanceFormat.watts(p.watts)).font(.title3.weight(.semibold)).monospacedDigit()
                Text([perKg.map { "\(Formatters.decimal($0, digits: 2)) W/kg" }, PerformanceFormat.date(p.date)]
                    .compactMap { $0 }.joined(separator: " · "))
                    .font(.caption).foregroundStyle(Theme.rowSecondary)
            }
            Spacer(minLength: 8)
            JellyChip(text: measured ? "gemessen" : "mindestens", fill: measured ? Theme.fill(.z2) : Theme.softFill)
                .fixedSize()                                            // audit: chip text was clipped
                .layoutPriority(1)
        }
        .padding(.vertical, 8)
        .frame(minHeight: 44)
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier("performance.best.\(p.duration)")
    }

    // MARK: Coverage

    @ViewBuilder
    private func coverageNote(_ agg: PowerCurve.Aggregate) -> some View {
        if agg.totalRides > 0 {
            let text = agg.measuredRides >= agg.totalRides
                ? "Alle \(agg.totalRides) Fahrten mit Sekundendaten."
                : "\(agg.measuredRides) von \(agg.totalRides) Fahrten mit Sekundendaten – importiere FIT-Dateien (Profil → MyWhoosh) für die volle Kurve."
            Label(text, systemImage: "info.circle")
                .font(.footnote).foregroundStyle(Theme.rowSecondary)
                .accessibilityIdentifier("performance.coverage")
        }
    }

    // MARK: eFTP

    private func eftpCard(_ agg: PowerCurve.Aggregate) -> some View {
        let eftp = agg.estimatedFTP ?? 0
        let ftp = model.profile.ftp
        let measured = agg.points[1200]?.source == .measured
        let differs = ftp > 0 && abs(Double(eftp - ftp)) / Double(ftp) >= 0.03
        return Card(title: "Geschätzte FTP", systemImage: "gauge.with.needle") {
            HStack {
                StatTile(title: "eFTP", value: "\(eftp)", unit: "W")
                StatTile(title: "Profil-FTP", value: "\(ftp)", unit: "W")
            }
            Text("95 % deiner besten 20 Minuten\(measured ? "" : " (nur ein Mindestwert aus einer Fahrt ohne Sekundendaten)").")
                .font(.footnote).foregroundStyle(Theme.rowSecondary)
            // A floor from an easy long ride would suggest lowering the FTP – only measured values can be applied.
            if differs && measured {
                Button {
                    model.profile.ftp = eftp
                    model.show("FTP auf \(eftp) W gesetzt.", error: false)
                } label: {
                    Label("Ins Profil übernehmen", systemImage: "arrow.down.to.line").frame(maxWidth: .infinity)
                }
                .buttonStyle(.jelly)
                .accessibilityIdentifier("performance.applyFTP")
            }
        }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("performance.eftp")
    }

    private var explanation: some View {
        Card(title: "So wird gerechnet", systemImage: "info.circle") {
            Text("Die Kurve zeigt, welche Durchschnittsleistung du je Dauer maximal gehalten hast. Fahrten ohne Sekundendaten (Strava, MyWhoosh-Liste) liefern nur Mindestwerte: eine 45-Minuten-Fahrt mit 205 W beweist, dass du 45 Minuten mindestens 205 W konntest.")
                .font(.footnote).foregroundStyle(Theme.rowSecondary)
        }
    }
}

// MARK: - VO2max

/// VO2max estimate with method and (optionally) the 6-week trend. Used on Heute and in Leistung.
struct VO2maxCard: View {
    var rides: [RideSummary]
    var showTrend = false
    var range: PerformanceRange = .days90
    @Environment(AppModel.self) private var model

    var body: some View {
        let now = Date.now
        let agg = PowerCurve.aggregate(rides: rides, from: now.addingTimeInterval(-Double(range.days) * 86_400), to: now)
        let estimate = VO2max.estimate(curve: agg, profile: model.profile)
        Card(title: "VO₂max", systemImage: "lungs") {
            if let estimate {
                HStack(alignment: .firstTextBaseline) {
                    StatTile(title: "Geschätzt", value: Formatters.decimal(estimate.value, digits: 1), unit: "ml/kg/min")
                    Spacer()
                    JellyChip(text: Self.chipText(estimate.method),
                              systemImage: estimate.method == .heartRate ? "heart.fill" : "bolt.fill",
                              fill: Theme.fill(.z2))
                }
                Text(methodText(estimate)).font(.footnote).foregroundStyle(Theme.rowSecondary)
                if showTrend { trend }
            } else {
                Text("Noch nicht berechenbar: Dafür braucht es eine Fahrt mit mindestens 5 Minuten Leistung (oder im Profil Maximalpuls und Ruhepuls).")
                    .font(.subheadline).foregroundStyle(Theme.rowSecondary)
            }
            Text("Schätzung, kein Labortest").font(.caption.weight(.semibold)).foregroundStyle(Theme.rowSecondary)
        }
        .accessibilityElement(children: showTrend ? .contain : .combine)
        .accessibilityIdentifier("vo2max.card")
    }

    static func chipText(_ method: VO2max.Method) -> String {
        switch method {
        case .power: "aus 5-min-Leistung"
        case .ftp: "aus deiner FTP"
        case .heartRate: "aus Herzfrequenz"
        }
    }

    private func methodText(_ e: VO2max.Estimate) -> String {
        switch e.method {
        case .power:
            let watts = e.inputWatts.map { "\(Int($0.rounded())) W" } ?? "–"
            return "ACSM-Formel: 10,8 × (\(watts) ÷ \(Formatters.decimal(model.profile.weightKg, digits: 1)) kg) + 7"
                + (e.isLowerBound ? ". Die 5-Minuten-Leistung ist nur ein Mindestwert, der Wert kann höher liegen." : ".")
        case .ftp:
            let watts = e.inputWatts.map { "\(Int($0.rounded())) W" } ?? "–"
            return "Aus deiner FTP (\(model.profile.ftp) W): 5-Minuten-Leistung ≈ 120 % FTP = \(watts), ACSM-Formel "
                + "10,8 × W/kg + 7. Mit FIT-Dateien (Sekundenwerte) wird der Wert genauer."
        case .heartRate:
            return "Uth-Sørensen: 15,3 × Maximalpuls \(e.inputMaxHR ?? 0) ÷ Ruhepuls \(e.inputRestingHR ?? 0)"
                + (e.maxHRIsEstimated ? " (Maximalpuls geschätzt)." : ".")
        }
    }

    @ViewBuilder
    private var trend: some View {
        let points = VO2max.trend(rides: rides, profile: model.profile)
        if points.count >= 2 {
            Chart(points) { p in
                LineMark(x: .value("Zeitraum bis", p.windowEnd), y: .value("VO₂max", p.value))
                    .foregroundStyle(Theme.fitnessLine)
                    .lineStyle(StrokeStyle(lineWidth: 2.5, lineCap: .round))
                PointMark(x: .value("Zeitraum bis", p.windowEnd), y: .value("VO₂max", p.value))
                    .foregroundStyle(Theme.fitnessLine)
                    .annotation(position: .top) {
                        Text(Formatters.decimal(p.value, digits: 1)).font(.caption2).foregroundStyle(Theme.axisLabel)
                    }
            }
            .chartYScale(domain: .automatic(includesZero: false))
            .chartXAxis {
                AxisMarks(values: points.map(\.windowEnd)) { _ in
                    AxisValueLabel(format: .dateTime.day().month(.defaultDigits).locale(Locale(identifier: "de_DE")))
                        .foregroundStyle(Theme.axisLabel)
                }
            }
            .chartYAxis { AxisMarks { _ in AxisGridLine(); AxisValueLabel().foregroundStyle(Theme.axisLabel) } }
            .frame(height: 130)
            .accessibilityElement(children: .ignore)
            .accessibilityLabel("VO₂max-Verlauf in 6-Wochen-Fenstern")
            .accessibilityValue(points.map { Formatters.decimal($0.value, digits: 1) }.joined(separator: ", "))
            Text("Verlauf: ein Wert je 6-Wochen-Fenster aus der besten 5-Minuten-Leistung.")
                .font(.caption).foregroundStyle(Theme.rowSecondary)
        }
    }
}
