import Charts
import SwiftUI

/// A5 – "Prognose" in the Winter Arc detail: projected fitness on the goal day, with a what-if slider for the
/// weekly hours. The slider is view-only; it never writes the profile (the budget is set in Profil).
struct GoalForecastCard: View {
    var rides: [RideSummary]
    var status: WinterArc.Status
    var now: Date = .now

    @Environment(AppModel.self) private var model
    @State private var hours: Double

    init(rides: [RideSummary], status: WinterArc.Status, weeklyHours: Double, now: Date = .now) {
        self.rides = rides
        self.status = status
        self.now = now
        _hours = State(initialValue: min(15, max(2, (weeklyHours * 2).rounded() / 2)))
    }

    var body: some View {
        let perHour = GoalForecast.tssPerHour(rides: rides, ftp: model.profile.ftp,
                                              thresholdHeartRate: model.profile.thresholdHeartRate, now: now)
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
        Chart {
            ForEach(result.curve, id: \.date) { p in
                LineMark(x: .value("Tag", p.date), y: .value("Fitness", p.ctl))
                    .foregroundStyle(Theme.fitnessLine)
                    .lineStyle(StrokeStyle(lineWidth: 2.5, lineCap: .round))
                    .interpolationMethod(.monotone)
            }
            RuleMark(y: .value("Ziel", result.targetCTL))
                .foregroundStyle(Theme.accent.opacity(0.8))
                .lineStyle(StrokeStyle(lineWidth: 1.5, dash: [5, 4]))
                .annotation(position: .top, alignment: .leading) {
                    Text("Ziel \(Formatters.decimal(result.targetCTL))")
                        .font(.caption2.weight(.semibold)).foregroundStyle(Theme.accent)
                }
        }
        .chartYScale(domain: .automatic(includesZero: false))
        .chartXAxis {
            AxisMarks(values: .stride(by: .month)) { _ in
                AxisGridLine()
                AxisValueLabel(format: .dateTime.month(.abbreviated).locale(Locale(identifier: "de_DE")))
                    .foregroundStyle(Theme.axisLabel)
            }
        }
        .chartYAxis { AxisMarks { _ in AxisGridLine(); AxisValueLabel().foregroundStyle(Theme.axisLabel) } }
        .frame(height: 150)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Prognose der Fitness bis zum Ziel-Tag")
        .accessibilityValue("Heute \(Formatters.decimal(status.currentCTL)), am Ziel-Tag \(Formatters.decimal(result.ctlAtGoal)), Ziel \(Formatters.decimal(result.targetCTL))")
        .accessibilityIdentifier("forecast.chart")
    }
}
