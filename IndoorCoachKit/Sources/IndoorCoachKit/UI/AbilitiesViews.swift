import SwiftUI

/// "Fähigkeiten" in Leistung (A4): level 1–10 for Ausdauer, Schwelle, VO₂ and Anaerob from the last 90 days.
struct AbilityLevelsCard: View {
    var rides: [RideSummary]
    var weightKg: Double
    var now: Date = .now

    var body: some View {
        let abilities = AbilityLevels.abilities(rides: rides, weightKg: weightKg, now: now)
        Card(title: "Fähigkeiten", systemImage: "chart.bar.fill") {
            VStack(alignment: .leading, spacing: 14) {
                ForEach(abilities, id: \.band.duration) { AbilityRow(ability: $0) }
            }
            if weightKg <= 0 {
                Label("Trag dein Gewicht im Profil ein, damit Watt pro Kilogramm berechnet werden kann.", systemImage: "scalemass")
                    .font(.footnote.weight(.semibold))
            }
            Text("Level 1 bis 10 nach Watt pro Kilogramm: Ausdauer (60 min), Schwelle (20 min), VO₂ (5 min) und Anaerob (1 min), jeweils aus deiner besten Leistung der letzten 90 Tage. „mindestens“ heißt: Der Wert ist nur eine Untergrenze aus der Durchschnittsleistung einer Fahrt. Die Veränderung vergleicht mit den 90 Tagen davor.")
                .font(.footnote).foregroundStyle(Theme.rowSecondary)
        }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("abilities.card")
    }
}

private struct AbilityRow: View {
    var ability: AbilityLevels.Ability
    @Environment(\.dynamicTypeSize) private var typeSize

    var body: some View {
        let layout = typeSize.isAccessibilitySize ? AnyLayout(VStackLayout(alignment: .leading, spacing: 6))
                                                  : AnyLayout(HStackLayout(alignment: .center, spacing: 12))
        layout {
            VStack(alignment: .leading, spacing: 2) {
                Text(ability.band.name).font(.subheadline.weight(.semibold))
                Text(ability.band.durationLabel).font(.caption).foregroundStyle(Theme.rowSecondary)
            }
            .frame(minWidth: 72, alignment: .leading)
            .fixedSize(horizontal: typeSize.isAccessibilitySize ? false : true, vertical: true)

            LevelBar(level: ability.level)
                .frame(maxWidth: .infinity)

            valueColumn
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel(Self.spoken(ability))
        .accessibilityIdentifier("abilities.row.\(ability.band.duration)")
    }

    private var valueColumn: some View {
        VStack(alignment: typeSize.isAccessibilitySize ? .leading : .trailing, spacing: 4) {
            if let level = ability.level {
                Text("Level \(level)").font(.subheadline.weight(.bold)).monospacedDigit()
                if let wkg = ability.wattsPerKg {
                    Text("\(Formatters.decimal(wkg, digits: 2)) W/kg").font(.caption).foregroundStyle(Theme.rowSecondary)
                }
                HStack(spacing: 6) {
                    if ability.isFloor { JellyChip(text: "mindestens", fill: Theme.softFill).fixedSize() }
                    if let c = ability.change, c != 0 {
                        JellyChip(text: c > 0 ? "+\(c)" : "−\(abs(c))", systemImage: c > 0 ? "arrow.up.right" : "arrow.down.right",
                                  fill: c > 0 ? Theme.fill(.z2) : Theme.softFill).fixedSize()
                    }
                }
            } else {
                Text("keine Daten").font(.subheadline).foregroundStyle(Theme.rowSecondary)
            }
        }
        .fixedSize(horizontal: !typeSize.isAccessibilitySize, vertical: true)
    }

    static func spoken(_ a: AbilityLevels.Ability) -> String {
        guard let level = a.level else { return "\(a.band.name), \(a.band.durationLabel): keine Daten" }
        var text = "\(a.band.name), \(a.band.durationLabel): Level \(level) von 10"
        if a.isFloor { text += ", mindestens" }
        if let c = a.change, c != 0 { text += c > 0 ? ", \(c) Level besser als davor" : ", \(abs(c)) Level schwächer als davor" }
        return text
    }
}

/// Ten non-lazy segments; the first `level` are filled.
private struct LevelBar: View {
    var level: Int?
    var body: some View {
        HStack(spacing: 3) {
            ForEach(1...10, id: \.self) { i in
                RoundedRectangle(cornerRadius: 3, style: .continuous)
                    .fill(i <= (level ?? 0) ? Theme.accent : Color.primary.opacity(0.14))
                    .frame(height: 10)
            }
        }
        .frame(minWidth: 100)
        .accessibilityHidden(true)
    }
}

/// "Ermüdungsresistenz" in Leistung (A7): 90-day average with a one-sentence scale.
struct DurabilityCard: View {
    var rides: [RideSummary]
    var now: Date = .now

    var body: some View {
        let avg = Durability.average(rides: rides, now: now)
        Card(title: "Ermüdungsresistenz", systemImage: "battery.75percent") {
            if let avg {
                HStack(alignment: .firstTextBaseline, spacing: 10) {
                    StatTile(title: "Ø der letzten 90 Tage", value: "\(Int(avg.percent.rounded()))", unit: "%")
                    JellyChip(text: Durability.rating(percent: avg.percent).label, fill: Theme.fill(.z2)).fixedSize()
                }
                Text("Aus \(avg.count) \(avg.count == 1 ? "Fahrt" : "Fahrten") ab 60 Minuten mit Leistungsdaten.")
                    .font(.footnote).foregroundStyle(Theme.rowSecondary)
                    .accessibilityIdentifier("durability.coverage")
            } else {
                Text("Keine Daten: Es zählen Fahrten ab 60 Minuten, die als FIT-Datei importiert wurden.")
                    .font(.subheadline).foregroundStyle(Theme.rowSecondary)
                    .accessibilityIdentifier("durability.empty")
            }
            Text("Vergleicht deine beste 5-Minuten-Leistung in der letzten Stunde einer Fahrt mit deiner besten 5-Minuten-Leistung der ganzen Fahrt. 100 % heißt: Du hast am Ende nichts eingebüßt. Ab 90 % ist stark.")
                .font(.footnote).foregroundStyle(Theme.rowSecondary)
        }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("durability.card")
    }
}

/// Fatigue resistance of one ride in the ride detail; only when a value exists.
struct RideDurabilityRow: View {
    var ride: RideSummary

    var body: some View {
        if let value = ride.durability {
            Card(title: "Ermüdungsresistenz", systemImage: "battery.75percent") {
                HStack(alignment: .firstTextBaseline, spacing: 10) {
                    StatTile(title: "Letzte Stunde gegen Bestwert", value: "\(Int(value.rounded()))", unit: "%")
                    JellyChip(text: Durability.rating(percent: value).label, fill: Theme.fill(.z2)).fixedSize()
                }
                Text("Beste 5-Minuten-Leistung in der letzten Stunde im Vergleich zur besten 5-Minuten-Leistung der Fahrt.")
                    .font(.caption).foregroundStyle(Theme.rowSecondary)
            }
            .accessibilityElement(children: .combine)
            .accessibilityIdentifier("ride.durability")
        }
    }
}
