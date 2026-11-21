import Charts
import SwiftUI

/// S10 – Relative Effort on the ride detail, with Perceived Exertion entry.
struct RelativeEffortCard: View {
    var ride: RideSummary
    @Environment(AppModel.self) private var model
    @State private var pe: Double = 5
    @State private var hasPE = false
    @State private var prefer = false

    /// The ride as currently edited, so the value updates immediately while the slider moves.
    private var edited: RideSummary {
        var r = ride
        r.perceivedExertion = hasPE ? Int(pe) : nil
        r.preferPerceivedExertion = hasPE && prefer
        return r
    }

    var body: some View {
        let estimate = model.relativeEffort(for: edited)
        Card(title: "Relative Effort", systemImage: "heart.text.square") {
            HStack(alignment: .firstTextBaseline) {
                Text(estimate.value.map { "\(Int($0.rounded()))" } ?? "–")
                    .font(.largeTitle.weight(.bold)).monospacedDigit()
                Spacer()
                if let value = estimate.value { JellyChip(text: Self.band(for: value).label, fill: Self.band(for: value).color) }
            }
            Text(sourceText(estimate)).font(.footnote).foregroundStyle(Theme.rowSecondary)

            Divider()
            Toggle("Gefühlte Anstrengung angeben", isOn: $hasPE.animation())
            if hasPE {
                VStack(alignment: .leading, spacing: 6) {
                    HStack {
                        Text("\(Int(pe)) · \(RelativeEffort.perceivedExertionLabels[Int(pe)] ?? "")").font(.headline)
                        Spacer()
                    }
                    Slider(value: $pe, in: 1...10, step: 1) { Text("Gefühlte Anstrengung") }
                        minimumValueLabel: { Text("1") } maximumValueLabel: { Text("10") }
                        .accessibilityValue("\(Int(pe)), \(RelativeEffort.perceivedExertionLabels[Int(pe)] ?? "")")
                    if ride.averageHeartrate != nil || ride.stravaRelativeEffort != nil {
                        Toggle("Statt Herzfrequenz verwenden", isOn: $prefer)
                            .font(.subheadline)
                    }
                }
            }
        }
        .onAppear {
            hasPE = ride.perceivedExertion != nil
            pe = Double(ride.perceivedExertion ?? 5)
            prefer = ride.preferPerceivedExertion
        }
        // save() is a no-op when nothing changed, so the initial onAppear assignment does not write.
        .onChange(of: hasPE) { save() }
        .onChange(of: prefer) { save() }
        // Debounced: dragging (or VoiceOver adjusting) does not write on every step – each save re-fires all queries.
        .task(id: pe) {
            try? await Task.sleep(for: .milliseconds(400))
            if !Task.isCancelled { save() }
        }
    }

    private func save() {
        model.setPerceivedExertion(hasPE ? Int(pe) : nil, prefer: prefer, rideID: ride.id)
    }

    private func sourceText(_ e: RelativeEffort.Estimate) -> String {
        switch e.source {
        case .strava: "Wert von Strava."
        case .heartRate: "IndoorCoach-Schätzung aus Ø-Herzfrequenz (Ruhe-/Max-HF aus dem Profil)."
        case .heartRateSeconds: "IndoorCoach-Schätzung aus deinem Puls, Sekunde für Sekunde (Ruhe-/Max-HF aus dem Profil)."
        case .perceivedExertion: "IndoorCoach-Schätzung aus deiner gefühlten Anstrengung."
        case nil: "Keine Herzfrequenz – gib an, wie anstrengend es sich angefühlt hat."
        }
    }

    struct Band { var label: String; var color: Color }

    /// Rough bands for a single ride (Strava shows similar wording).
    static func band(for value: Double) -> Band {
        switch value {
        case ..<50: Band(label: "Locker", color: Theme.fill(.z2))
        case ..<120: Band(label: "Moderat", color: Theme.fill(.z3))
        case ..<200: Band(label: "Hart", color: Theme.fill(.z4))
        case ..<300: Band(label: "Sehr hart", color: Theme.fill(.z5))
        default: Band(label: "Episch", color: Theme.fill(.z6))
        }
    }
}

/// S10 – weekly Relative Effort with the suggested range from the previous three weeks.
struct EffortWeekCard: View {
    var weeks: [AppModel.EffortWeek]

    var body: some View {
        let current = weeks.last
        let range = RelativeEffort.weeklyRange(previousWeeks: weeks.dropLast().suffix(3).map(\.total))
        let ticks = ChartMath.niceTicks(min: 0, max: (weeks.map(\.total) + [range?.upper ?? 0]).max() ?? 1, count: 4)
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .firstTextBaseline) {
                Text("Relative Effort · diese Woche").font(.subheadline.weight(.semibold)).foregroundStyle(.secondary)
                Spacer()
                Text("\(Int((current?.total ?? 0).rounded()))").font(.title2.weight(.bold)).monospacedDigit()
            }
            if let range, let current {
                let status = range.status(for: current.total)
                // The running week is always "below" on Monday – phrase it as what is still open instead.
                let open = status == .below
                HStack(spacing: 8) {
                    JellyChip(text: open ? "Woche läuft" : status.label, fill: open ? Color(Palette.peachFizz) : color(for: status))
                    Text("Bereich \(Int(range.lower.rounded()))–\(Int(range.upper.rounded()))")
                        .font(.caption).foregroundStyle(Theme.rowSecondary)
                }
                Text(open ? "Noch \(Int((range.lower - current.total).rounded())) bis zum Wochenbereich deiner letzten drei Wochen."
                          : status.advice)
                    .font(.footnote).foregroundStyle(Theme.rowSecondary)
            } else {
                Text("Der Wochenbereich erscheint, sobald drei Wochen mit Herzfrequenz oder gefühlter Anstrengung vorliegen.")
                    .font(.footnote).foregroundStyle(Theme.rowSecondary)
            }
            Chart {
                if let range {
                    RectangleMark(xStart: .value("Von", weeks.first?.weekStart ?? .now),
                                  xEnd: .value("Bis", Calendar.current.date(byAdding: .day, value: 7, to: weeks.last?.weekStart ?? .now)!),
                                  yStart: .value("Unten", range.lower), yEnd: .value("Oben", range.upper))
                        .foregroundStyle(ChartPalette.band)
                        .annotation(position: .overlay, alignment: .topTrailing, spacing: 2) {
                            Text("dein Bereich").font(ChartStyle.ruleLabelFont).foregroundStyle(Theme.axisLabel).padding(.trailing, 4)
                        }
                }
                ForEach(weeks) { w in
                    BarMark(x: .value("Woche", w.weekStart, unit: .weekOfYear), y: .value("Relative Effort", w.total),
                            width: .ratio(0.6))
                        .foregroundStyle(w.id == weeks.last?.id ? Theme.accent : ChartPalette.pastBar)
                        .clipShape(UnevenRoundedRectangle(topLeadingRadius: ChartStyle.barCornerRadius,
                                                          topTrailingRadius: ChartStyle.barCornerRadius))
                }
            }
            .chartStyleAxes(yTicks: ticks, yLabel: { ChartMath.format($0) })
            .chartYScale(domain: 0...(ticks.last ?? 1))
            .chartStyleHeight(130)
            .chartAccessibility(label: "Relative Effort der letzten \(weeks.count) Wochen",
                                value: weeks.map { "\(Int($0.total.rounded()))" }.joined(separator: ", "))
        }
    }

    private func color(for status: RelativeEffort.RangeStatus) -> Color {
        switch status {
        case .below: Theme.fill(.z2)
        case .within: Theme.fill(.z3)
        case .above: Theme.fill(.z5)
        }
    }
}
