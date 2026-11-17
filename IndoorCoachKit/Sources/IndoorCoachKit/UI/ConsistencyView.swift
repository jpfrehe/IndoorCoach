import SwiftUI

/// K1 – Karte „Konstanz“ im Winter-Arc-Detail: die letzten 8 Wochen als Punkte mit Legende.
struct ConsistencyCard: View {
    var result: Consistency.Result
    var weeksShown = 8

    private var weeks: [Consistency.Week] { Array(result.weeks.suffix(weeksShown)) }

    var body: some View {
        Card(title: "Konstanz", systemImage: "calendar.badge.checkmark") {
            Text(Consistency.summary(streak: result.streak, jokers: result.jokers)
                 ?? (result.jokers > 0 ? "Noch keine Serie · \(result.jokers) Joker" : "Noch keine Serie"))
                .font(.headline)
                .accessibilityIdentifier("consistency.summary")
            if weeks.isEmpty {
                Text("Sobald die erste volle Woche der Saison vorbei ist, siehst du hier deine Wochen.")
                    .font(.footnote).foregroundStyle(Theme.rowSecondary)
            } else {
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 38), spacing: 6, alignment: .top)], alignment: .leading, spacing: 8) {
                    ForEach(weeks) { week in
                        VStack(spacing: 3) {
                            WeekDot(state: week.state)
                            Text("KW \(Self.isoWeek(week.start))").font(.caption2).foregroundStyle(Theme.rowSecondary)
                                .lineLimit(1).minimumScaleFactor(0.7)
                        }
                        .accessibilityElement(children: .ignore)
                        .accessibilityLabel("Woche ab \(Self.dayLabel(week.start))")
                        .accessibilityValue(Self.description(week.state))
                    }
                }
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 130), spacing: 8, alignment: .leading)], alignment: .leading, spacing: 6) {
                    ForEach(Self.legend, id: \.title) { item in
                        HStack(spacing: 6) {
                            WeekDot(state: item.state, size: 20)
                            Text(item.title).font(.caption).foregroundStyle(Theme.rowSecondary)
                        }
                    }
                }
                .accessibilityHidden(true)   // the dots already speak their state
            }
            Text("Eine Woche zählt, wenn du 80 % deines Wochenbudgets fährst, alle geplanten Einheiten schaffst oder eine geplante Erholungswoche zur Hälfte fährst. Alle 4 erfüllten Wochen in Folge bringen einen Joker (höchstens 2): Er fängt eine verpasste Woche automatisch auf.")
                .font(.footnote).foregroundStyle(Theme.rowSecondary)
        }
        .accessibilityIdentifier("consistency.card")
    }

    static let legend: [(title: String, state: Consistency.State)] = [
        ("erfüllt", .fulfilled(.budget)), ("Erholung", .fulfilled(.recovery)), ("Joker", .joker),
        ("verpasst", .missed), ("läuft", .running),
    ]

    static func description(_ state: Consistency.State) -> String {
        switch state {
        case .fulfilled(.recovery): "Erholungswoche, erfüllt"
        case .fulfilled(let reason): "erfüllt, \(reason.label)"
        case .joker: "Joker eingesetzt"
        case .missed: "verpasst"
        case .running: "läuft noch"
        }
    }

    private static func isoWeek(_ date: Date) -> Int {
        var cal = Calendar.current
        cal.firstWeekday = 2
        cal.minimumDaysInFirstWeek = 4
        return cal.component(.weekOfYear, from: date)
    }

    private static func dayLabel(_ date: Date) -> String {
        date.formatted(.dateTime.day().month(.wide).locale(Locale(identifier: "de_DE")))
    }
}

/// One week as a dot: jelly fill + ink symbol (≥ 4.5:1); state is never colour alone.
struct WeekDot: View {
    var state: Consistency.State
    var size: CGFloat = 30

    var body: some View {
        ZStack {
            switch state {
            case .fulfilled(.recovery):
                Circle().fill(Theme.fill(.z1))
                symbol("leaf.fill", ink: true)
            case .fulfilled:
                Circle().fill(Theme.fill(.z2))
                symbol("checkmark", ink: true)
            case .joker:
                Circle().fill(Color(Palette.mangoPop))
                symbol("shield.fill", ink: true)
            case .missed:
                Circle().strokeBorder(Theme.rowSecondary, lineWidth: 2)
                symbol("xmark", ink: false)
            case .running:
                Circle().strokeBorder(Theme.rowSecondary, style: StrokeStyle(lineWidth: 2, dash: [3, 3]))
                symbol("ellipsis", ink: false)
            }
        }
        .frame(width: size, height: size)
    }

    private func symbol(_ name: String, ink: Bool) -> some View {
        Image(systemName: name).font(.system(size: size * 0.42, weight: .bold))
            .foregroundStyle(ink ? Theme.ink : Theme.rowSecondary)
    }
}
