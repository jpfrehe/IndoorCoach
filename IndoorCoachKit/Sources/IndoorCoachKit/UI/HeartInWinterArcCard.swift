import SwiftUI

extension AppModel {
    /// „Dein Herz im Winter Arc“ seit dem Arc-Start (im Demo-Modus über ein Demo-Fenster). Ruhepuls kommt nur mit
    /// aktiviertem Health aus der gepinnten Quelle; alles andere aus den vorhandenen Fahrten und Einheiten.
    func heartInWinterArc(rides: [RideSummary], status: WinterArc.Status, now: Date = .now) async -> HeartInWinterArc {
        let calendar = Calendar.current
        let demo = isDemoMode
        let start = demo ? DemoData.heartWindowStart(now: now, calendar: calendar) : status.start
        var resting: [HealthDaily] = []
        if demo {
            resting = DemoData.heartRestingDailies(now: now, calendar: calendar)
        } else if healthEnabled, healthSource.isAvailable, start < now {
            resting = (try? await healthSource.dailyValues(.restingHR, in: start...now)) ?? []
        }
        let pins = self.pins // same pins as Datenquellen and Wellness (health.pins.v1)
        resting = HealthSourcePinning.filter(resting, pins: pins)
        let ref = profile.effectiveWarmupCheckWatts
        let checks = rides.filter(\.trainer).filter { $0.startDate >= start }.sorted { $0.startDate > $1.startDate }
            .prefix(200).compactMap { warmupCheck(for: $0) }
        let strength = demo ? DemoData.heartStrengthStarts(now: now, calendar: calendar) : strengthSessions().map(\.start)
        return HeartInWinterArc.make(from: start, now: now, refWatts: ref, checks: checks, restingDailies: resting,
                                     rides: rides, ftp: profile.ftp, strengthStarts: strength, calendar: calendar)
    }
}

/// B57 – Monatsansicht „Dein Herz im Winter Arc“. Zeigt nur Kennzahlen mit genug Daten, jede mit Quelle.
struct HeartInWinterArcCard: View {
    var heart: HeartInWinterArc

    private static let monthStyle = Date.FormatStyle(locale: Locale(identifier: "de_DE")).month(.abbreviated)

    var body: some View {
        if !heart.isEmpty {
            Card(title: "Dein Herz im Winter Arc", systemImage: "heart.text.square") {
                if let sentence = heart.sentence {
                    Text(sentence).font(.headline).accessibilityIdentifier("heart.sentence")
                }
                if let warmup = heart.warmup {
                    row("Aufwärm-Puls bei \(heart.warmupRefWatts) W", series: warmup, unit: "bpm", digits: 0)
                }
                if let resting = heart.resting {
                    row("Ruhepuls", series: resting, unit: "bpm", digits: 0)
                }
                if let efficiency = heart.efficiency {
                    row("Aerobe Effizienz", series: efficiency, unit: "W/bpm", digits: 2)
                }
                if !heart.strength.isEmpty {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Krafteinheiten").font(.subheadline.weight(.semibold))
                        Text(heart.strength.map { "\($0.monthStart.formatted(Self.monthStyle)) \(Int($0.value))" }.joined(separator: " · "))
                            .font(.subheadline).monospacedDigit()
                        Text("Quelle: \(HeartInWinterArc.strengthSource)").font(.caption).foregroundStyle(Theme.rowSecondary)
                    }
                    .accessibilityElement(children: .combine)
                }
                Text("Vergleich je Monat (Median). Eine Kennzahl erscheint erst, wenn zwei Monate genug Werte haben.")
                    .font(.caption).foregroundStyle(Theme.rowSecondary)
            }
            .accessibilityIdentifier("heart.card")
        }
    }

    private func row(_ title: String, series: HeartInWinterArc.Series, unit: String, digits: Int) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title).font(.subheadline.weight(.semibold))
            Text(series.months.map { "\($0.monthStart.formatted(Self.monthStyle)) \(Formatters.decimal($0.value, digits: digits))" }
                .joined(separator: " · ") + " \(unit)")
                .font(.subheadline).monospacedDigit()
            Text("Quelle: \(series.sourceText)").font(.caption).foregroundStyle(Theme.rowSecondary)
        }
        .accessibilityElement(children: .combine)
    }
}
