import Charts
import SwiftUI

/// A5 – "Prognose" in the Winter Arc detail: projected fitness on the goal day, with a what-if slider for the
/// weekly hours. The slider is view-only; it never writes the profile (the budget is set in Profil).
struct GoalForecastCard: View {
    var rides: [RideSummary]
    var status: WinterArc.Status
    var now: Date = .now

    @Environment(AppModel.self) private var model
    @Environment(\.colorScheme) private var scheme
    @State private var hours: Double

    init(rides: [RideSummary], status: WinterArc.Status, weeklyHours: Double, now: Date = .now) {
        self.rides = rides
        self.status = status
        self.now = now
        _hours = State(initialValue: min(15, max(2, (weeklyHours * 2).rounded() / 2)))
    }

    var body: some View {
        let perHour = GoalForecast.tssPerHour(rides: rides, ftp: model.profile.ftp,
                                              thresholdHeartRate: model.profile.thresholdHeartRate,
                                              heartRate: model.profile.heartRateProfile, now: now)
        let hasRecent = perHour != GoalForecast.fallbackTSSPerHour || rides.contains { $0.startDate > now.addingTimeInterval(-42 * 86_400) }
        let result = GoalForecast.forecast(currentCTL: status.currentCTL, targetCTL: status.targetCTL, hoursPerWeek: hours,
                                           tssPerHour: perHour, today: now, goal: status.goal)
        Card(title: "Prognose zum Ziel", systemImage: "scope") {
            if status.isFinished {
                Text("Der Ziel-Tag ist erreicht – eine Prognose gibt es für die nächste Saison.")
                    .font(.subheadline).foregroundStyle(Theme.rowSecondary)
            } else {
                Text(result.text)
                    .font(.subheadline.weight(.semibold))
                    .fixedSize(horizontal: false, vertical: true)
                    .accessibilityIdentifier("forecast.text")
                chart(result)
                VStack(alignment: .leading, spacing: 4) {
                    HStack {
                        Text("Wenn du pro Woche fährst").font(.subheadline)
                        Spacer(minLength: 8)
                        Text("\(GoalForecast.hoursText(hours)) h").font(.subheadline.weight(.semibold)).monospacedDigit()
                    }
                    Slider(value: $hours, in: 2...15, step: 0.5) {
                        Text("Stunden pro Woche")
                    } minimumValueLabel: {
                        Text("2").font(.caption).foregroundStyle(Theme.rowSecondary)
                    } maximumValueLabel: {
                        Text("15").font(.caption).foregroundStyle(Theme.rowSecondary)
                    }
                    .tint(Theme.accent)
                    .accessibilityValue("\(GoalForecast.hoursText(hours)) Stunden pro Woche")
                    .accessibilityIdentifier("forecast.slider")
                }
                Text("Was-wäre-wenn: nur Ansicht, dein Wochenbudget im Profil (\(Formatters.decimal(model.profile.weeklyHours, digits: 1)) h) bleibt unverändert. Rechnung: \(GoalForecast.hoursText(hours)) h × \(Formatters.decimal(perHour)) TSS/h = \(Formatters.decimal(result.weeklyTSS)) TSS pro Woche, \(hasRecent ? "dein Schnitt der letzten 6 Wochen" : "Annahme 50 TSS/h, weil es in den letzten 6 Wochen keine Fahrten gibt"); die Fitness wird mit dem 42-Tage-Mittel fortgeschrieben.")
                    .font(.footnote).foregroundStyle(Theme.rowSecondary)
            }
        }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("forecast.card")
    }

    private func chart(_ result: GoalForecast.Result) -> some View {
        let dark = scheme == .dark
        let values = result.curve.map(\.ctl) + [result.targetCTL]
        let ticks = ChartMath.niceTicks(min: values.min() ?? 0, max: values.max() ?? 1, count: 4)
        let lowest = ticks.first ?? 0
        let crossing = result.crossing
        let showsToday = GoalForecast.todayLabelFits(today: result.curve.first?.date ?? .now, crossing: crossing?.date,
                                                     end: result.curve.last?.date ?? .now)
        return Chart {
            // Everything from today on is projection: solid but muted (dashes mean target/goal only), no area.
            ForEach(result.curve, id: \.date) { p in
                LineMark(x: .value("Tag", p.date), y: .value("Fitness", p.ctl))
                    .interpolationMethod(ChartStyle.interpolation(pointCount: result.curve.count))
                    .lineStyle(ChartStyle.stroke(.main))
                    .foregroundStyle(ChartPalette.fitness.opacity(0.7))
            }
            ChartRule(y: .value("Ziel", result.targetCTL), kind: .target, label: "Ziel \(Formatters.decimal(result.targetCTL))")
            if let today = result.curve.first {
                HighlightPoint(x: .value("Tag", today.date), y: .value("Fitness", today.ctl), color: ChartPalette.fitness,
                               baseline: .value("Fitness", lowest), dark: dark)
                PointMark(x: .value("Tag", today.date), y: .value("Fitness", today.ctl))
                    .symbolSize(1).foregroundStyle(.clear)
                    .annotation(position: .bottom, alignment: .leading, spacing: 8) {
                        if showsToday {
                            Text("Heute").font(ChartStyle.ruleLabelFont).foregroundStyle(Theme.axisLabel)
                        }
                    }
            }
            if let crossing {
                HighlightPoint(x: .value("Tag", crossing.date), y: .value("Fitness", crossing.ctl), color: ChartPalette.fitness,
                               dark: dark)
                PointMark(x: .value("Tag", crossing.date), y: .value("Fitness", crossing.ctl))
                    .symbolSize(1).foregroundStyle(.clear)
                    .annotation(position: .bottom, spacing: 10) {
                        Text(GoalForecast.crossingLabel(crossing.date, calendar: .current))
                            .font(ChartStyle.ruleLabelFont).foregroundStyle(Theme.axisLabel)
                    }
            }
        }
        .chartYScale(domain: lowest...(ticks.last ?? 1))
        .chartStyleAxes(yTicks: ticks, yLabel: { ChartMath.format($0) })
        .chartStyleHeight(ChartStyle.heightNormal)
        .chartAccessibility(
            label: "Prognose der Fitness bis zum Ziel-Tag",
            value: "Heute \(Formatters.decimal(status.currentCTL)), am Ziel-Tag \(Formatters.decimal(result.ctlAtGoal)), Ziel \(Formatters.decimal(result.targetCTL))")
        .accessibilityIdentifier("forecast.chart")
    }
}
