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
        d.formatted(.dateTime.day().month(.abbreviated).year().locale(Locale.de))
    }
}

/// "Leistung": power curve, best efforts, eFTP and VO2max (opened from the Verlauf tab).
struct PerformanceView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
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
                bridgeCallToAction(rides: rides)
                if current.estimatedFTP != nil { eftpCard(current) }
                VO2maxCard(rides: rides, showTrend: true, range: range)
                // ANCHOR-WARMUP (Aufwärm-Check)
                WarmupCheckCard(rides: rides)
                // ANCHOR-K4-LEISTUNG (Aerobe Effizienz)
                AerobicEfficiencyCard(rides: rides, ftp: model.profile.ftp, range: range)
                // ANCHOR-P1-LEISTUNG (Trainingsverteilung, eFTP-Verlauf)
                TrainingDistributionCard(rides: rides, ftp: model.profile.ftp)
                FTPHistoryCard(rides: rides, ftp: model.profile.ftp)

                // ANCHOR-P2-LEISTUNG (Fähigkeitslevel, Ermüdungsresistenz)
                AbilityLevelsCard(rides: rides, weightKg: model.effectiveWeightKg)
                DurabilityCard(rides: rides)


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
        PowerCurveCard(comparison: comparison, weightKg: model.effectiveWeightKg)
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
        let perKg = model.effectiveWeightKg > 0 ? p.watts / model.effectiveWeightKg : nil
        let measured = p.source == .measured
        let duration = Text(PerformanceFormat.duration(p.duration)).font(.headline).lineLimit(1).fixedSize()
        let watts = Text(PerformanceFormat.watts(p.watts)).font(.title3.weight(.semibold)).monospacedDigit().lineLimit(1)
        let detail = Text([perKg.map { "\(Formatters.decimal($0, digits: 2)) W/kg" }, PerformanceFormat.date(p.date)]
            .compactMap { $0 }.joined(separator: " · "))
            .font(.caption).foregroundStyle(Theme.rowSecondary)
        let chip = JellyChip(text: measured ? "gemessen" : "mindestens", fill: measured ? Theme.fill(.z2) : Theme.softFill)
            .fixedSize()                                                // audit: chip text was clipped
        // Audit 2, A2-02: at accessibility sizes the columns collapsed ("10 / min", W/kg word by word) – stack instead.
        return Group {
            if dynamicTypeSize.isAccessibilitySize {
                VStack(alignment: .leading, spacing: 4) {
                    HStack(alignment: .firstTextBaseline, spacing: 10) { duration; watts }
                    detail
                    chip
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            } else {
                HStack(alignment: .firstTextBaseline, spacing: 10) {
                    duration.frame(minWidth: 56, alignment: .leading)
                    VStack(alignment: .leading, spacing: 2) { watts; detail }
                    Spacer(minLength: 8)
                    chip.layoutPriority(1)
                }
            }
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
                : "\(agg.measuredRides) von \(agg.totalRides) Fahrten mit Sekundendaten\(model.isBridgePaired ? " – neue Fahrten kommen automatisch vom Mac." : ".")"
            Label(text, systemImage: "info.circle")
                .font(.footnote).foregroundStyle(Theme.rowSecondary)
                .accessibilityIdentifier("performance.coverage")
        }
    }

    /// Entry to the Mac bridge (docs/14): only when rides without seconds data exist and no Mac is paired.
    @ViewBuilder
    private func bridgeCallToAction(rides: [RideSummary]) -> some View {
        if !model.isBridgePaired, rides.contains(where: { ($0.powerCurve ?? [:]).isEmpty }) {
            NavigationLink { MacBridgeView() } label: {
                Card(title: "Sekundendaten vom Mac", systemImage: "macbook.and.iphone") {
                    Text("Volle Leistungskurve für jede Fahrt: Fährst du MyWhoosh auf dem Mac? IndoorCoach Brücke holt die Daten automatisch.")
                        .font(.subheadline)
                        .foregroundStyle(.primary)
                        .multilineTextAlignment(.leading)
                        .fixedSize(horizontal: false, vertical: true)
                    Text("Einrichten")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(Theme.ink)
                        .padding(.horizontal, 16).padding(.vertical, 10)
                        .frame(minHeight: 44)
                        .background(Theme.sunset, in: Capsule())
                }
            }
            .buttonStyle(.plain)
            .accessibilityHint("Öffnet die Einrichtung der Mac-Brücke")
            .accessibilityIdentifier("performance.bridgeCTA")
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
        let estimate = VO2max.estimate(curve: agg, profile: model.calculationProfile)
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
            return "ACSM-Formel: 10,8 × (\(watts) ÷ \(Formatters.decimal(model.effectiveWeightKg, digits: 1)) kg) + 7"
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
        let points = VO2max.trend(rides: rides, profile: model.calculationProfile)
        if points.count >= 2 {
            VO2TrendChart(points: points)
            Text("Verlauf: ein Wert je 6-Wochen-Fenster aus der besten 5-Minuten-Leistung.")
                .font(.caption).foregroundStyle(Theme.rowSecondary)
        }
    }
}

// MARK: - Charts

/// D7: power curve on a log duration axis. Accent line + faint area, previous period dotted underneath the main line,
/// open markers on the headline durations, selection snaps to measured points and drives the header.
private struct PowerCurveCard: View {
    var comparison: PowerCurve.Comparison
    var weightKg: Double
    @State private var selected: Double?
    @Environment(\.colorScheme) private var scheme

    var body: some View {
        let cur = comparison.current.sortedPoints
        let prev = comparison.previous.sortedPoints
        let maxDuration = Double(max(cur.last?.duration ?? 60, 60))
        let dark = scheme == .dark
        let ticks = ChartMath.niceTicks(min: (cur + prev).map(\.watts).min() ?? 0, max: (cur + prev).map(\.watts).max() ?? 1, count: 4)
        let lower = ticks.first ?? 0, upper = ticks.last ?? 1
        let method = ChartStyle.interpolation(pointCount: cur.count)
        let logs = cur.map { log10(Double($0.duration)) }
        let picked: PowerCurve.Point? = selected.flatMap { $0 > 0 ? ChartMath.nearest(logs, to: log10($0)) : nil }.map { cur[$0] }
        let shown = picked ?? cur.first { $0.duration == 300 } ?? cur.last
        let measuredHeadlines = cur.filter { $0.source == .measured && PowerCurve.headlineDurations.contains($0.duration) }
        Card(title: "Leistungskurve", systemImage: "bolt.fill") {
            header(shown: shown, picked: picked)
            Chart {
                ForEach(cur, id: \.duration) { p in
                    AreaMark(x: .value("Dauer", Double(p.duration)), yStart: .value("Basis", lower), yEnd: .value("Watt", p.watts))
                        .interpolationMethod(method)
                        .foregroundStyle(ChartStyle.area(Theme.accent, dark: dark))
                }
                ForEach(prev, id: \.duration) { p in
                    LineMark(x: .value("Dauer", Double(p.duration)), y: .value("Watt", p.watts), series: .value("Zeitraum", "Vorher"))
                        .interpolationMethod(ChartStyle.interpolation(pointCount: prev.count))
                        .foregroundStyle(ChartPalette.reference).lineStyle(ChartStyle.stroke(.previous))
                }
                ForEach(cur, id: \.duration) { p in
                    LineMark(x: .value("Dauer", Double(p.duration)), y: .value("Watt", p.watts), series: .value("Zeitraum", "Aktuell"))
                        .interpolationMethod(method)
                        .foregroundStyle(Theme.accent).lineStyle(ChartStyle.stroke(.main))
                }
                ForEach(measuredHeadlines, id: \.duration) { p in
                    OpenMarker(x: .value("Dauer", Double(p.duration)), y: .value("Watt", p.watts), color: Theme.accent)
                }
                if let shown {
                    HighlightPoint(x: .value("Dauer", Double(shown.duration)), y: .value("Watt", shown.watts), color: Theme.accent,
                                   baseline: .value("Basis", lower), dark: dark)
                }
            }
            .chartXScale(domain: 1...maxDuration, type: .log)
            .chartYScale(domain: lower...upper)
            .chartXSelection(value: $selected)
            .chartGesture { proxy in SpatialTapGesture().onEnded { proxy.selectXValue(at: $0.location.x) } }
            .chartStyleAxes(yTicks: ticks, yLabel: { v in ChartMath.format(v) + (v == ticks.last ? " W" : "") }, showsX: false)
            .chartXAxis {
                // Log axis: 5 s / 1 / 5 / 20 min, 60 min only with enough data (it crowds 20 min).
                AxisMarks(values: ChartMath.powerCurveTicks(maxDuration: maxDuration)) { value in
                    AxisTick(stroke: StrokeStyle(lineWidth: 1)).foregroundStyle(ChartStyle.baselineColor)
                    AxisValueLabel {
                        if let d = value.as(Double.self) { Text(PerformanceFormat.duration(Int(d))) }
                    }
                    .font(ChartStyle.axisFont).foregroundStyle(ChartStyle.axisColor)
                }
            }
            .chartStyleAnimation(value: picked?.duration)
            .chartStyleHeight(ChartStyle.heightLarge)
            .chartAccessibility(
                label: "Leistungskurve, beste Durchschnittsleistung je Dauer", value: Self.summary(comparison.current),
                descriptor: ChartDescriptor(
                    title: "Leistungskurve", summary: Self.summary(comparison.current), xTitle: "Dauer", yTitle: "Watt",
                    series: [.init(name: "Aktuell", points: cur.map { (Double($0.duration), $0.watts) })],
                    xLabel: { PerformanceFormat.duration(Int($0)) }))
            .accessibilityIdentifier("performance.curve")
        }
    }

    @ViewBuilder
    private func header(shown: PowerCurve.Point?, picked: PowerCurve.Point?) -> some View {
        if let shown {
            let previous = comparison.previous.points[shown.duration]
            let name = PerformanceFormat.duration(shown.duration)
            let items: [ChartCardHeader.Item] = [
                .init(label: "Aktuell · \(name)", value: PerformanceFormat.watts(shown.watts), color: Theme.accent),
            ] + (weightKg > 0 ? [.init(label: "W/kg", value: Formatters.decimal(shown.watts / weightKg, digits: 2), marker: .none)] : [])
              + (previous.map { [.init(label: "Vorperiode", value: PerformanceFormat.watts($0.watts), color: ChartPalette.reference, marker: .dotted)] } ?? [])
            ChartCardHeader(items: items, selectionTitle: picked.map { _ in name }, resetTitle: "Aufheben", onReset: { selected = nil })
        }
    }

    static func summary(_ agg: PowerCurve.Aggregate) -> String {
        PowerCurve.headlineDurations.compactMap { d in
            agg.points[d].map { "\(PerformanceFormat.duration(d)) \(Int($0.watts.rounded())) Watt" }
        }.joined(separator: ", ")
    }
}

/// D16: VO₂max per 6-week window. Direct value only at the last (or selected) point.
private struct VO2TrendChart: View {
    var points: [VO2max.TrendPoint]
    @State private var selected: Date?
    @Environment(\.colorScheme) private var scheme

    var body: some View {
        let dark = scheme == .dark
        let values = points.map(\.value)
        let ticks = ChartMath.niceTicks(min: values.min() ?? 0, max: values.max() ?? 1, count: 3)
        let lower = ticks.first ?? 0, upper = ticks.last ?? 1
        let decimals = ticks.count > 1 && ticks[1] - ticks[0] < 1 ? 1 : 0
        let method = ChartStyle.interpolation(pointCount: points.count)
        let shownIndex = selected.flatMap { ChartMath.nearest(points.map(\.windowEnd), to: $0) } ?? points.count - 1
        let shown = points[shownIndex]
        let sentence = ChartMath.seriesSentence(name: "VO₂max", values: values, decimals: 1, unit: " ml/kg/min", period: "\(points.count) Fenstern")
        Chart {
            if ChartDataState(count: points.count) == .enough {
                ForEach(points) { p in
                    AreaMark(x: .value("Zeitraum bis", p.windowEnd), yStart: .value("Basis", lower), yEnd: .value("VO₂max", p.value))
                        .interpolationMethod(method).foregroundStyle(ChartStyle.area(Theme.accent, dark: dark))
                }
            }
            ForEach(points) { p in
                LineMark(x: .value("Zeitraum bis", p.windowEnd), y: .value("VO₂max", p.value))
                    .interpolationMethod(method).lineStyle(ChartStyle.stroke(.main)).foregroundStyle(Theme.accent)
            }
            ForEach(points.indices.filter { $0 != shownIndex }, id: \.self) { i in
                OpenMarker(x: .value("Zeitraum bis", points[i].windowEnd), y: .value("VO₂max", points[i].value), color: Theme.accent)
            }
            HighlightPoint(x: .value("Zeitraum bis", shown.windowEnd), y: .value("VO₂max", shown.value), color: Theme.accent, dark: dark)
            PointMark(x: .value("Zeitraum bis", shown.windowEnd), y: .value("VO₂max", shown.value))
                .opacity(0)
                .annotation(position: .top, spacing: 8) {
                    Text(Formatters.decimal(shown.value, digits: 1)).font(ChartStyle.ruleLabelFont).foregroundStyle(Theme.axisLabel)
                }
        }
        .chartYScale(domain: lower...upper)
        .chartXSelection(value: $selected)
        .chartGesture { proxy in SpatialTapGesture().onEnded { proxy.selectXValue(at: $0.location.x) } }
        .chartStyleAxes(yTicks: ticks, yLabel: { ChartMath.format($0, decimals: decimals) }, showsX: false)
        .chartXAxis {
            AxisMarks(values: points.map(\.windowEnd)) { _ in
                AxisValueLabel(format: .dateTime.day().month(.defaultDigits).locale(Locale.de))
                    .font(ChartStyle.axisFont).foregroundStyle(ChartStyle.axisColor)
            }
        }
        .chartStyleAnimation(value: shownIndex)
        .chartStyleHeight(ChartStyle.heightSmall + 10)
        .chartAccessibility(
            label: "VO₂max-Verlauf in 6-Wochen-Fenstern", value: sentence,
            descriptor: ChartAccessibility.timeSeries(
                title: "VO₂max-Verlauf", summary: sentence, yTitle: "ml/kg/min",
                series: [("VO₂max", points.map { ($0.windowEnd, $0.value) })], yLabel: { ChartMath.format($0, decimals: 1) }))
    }
}
