import Charts
import SwiftData
import SwiftUI

/// S12 – compact Winter Arc card for the Heute dashboard.
struct WinterArcCard: View {
    var status: WinterArc.Status
    /// Chip „+34 min Licht“; im Hub steht stattdessen der Winterlicht-Kopf.
    var showsLight = true

    var body: some View {
        Card(title: "Winter Arc", systemImage: "snowflake") {
            HStack(spacing: 14) {
                LevelBadge(level: status.level, size: 56)
                VStack(alignment: .leading, spacing: 4) {
                    Text("Level \(status.level.number) · \(status.level.name)").font(.headline)
                    ProgressView(value: status.levelProgress)
                        .tint(Theme.accent)
                        .accessibilityLabel("Fortschritt zum nächsten Level")
                        .accessibilityValue("\(Int((status.levelProgress * 100).rounded())) Prozent")
                    Text(subtitle).font(.caption).foregroundStyle(Theme.rowSecondary)
                }
            }
            // ANCHOR-B3-CARD: Chip „+34 min Licht“ (sun.horizon) unter der Level-Zeile, Tipp öffnet den Hub – Agent B
            if showsLight, let light = lightChip {
                JellyChip(text: light, systemImage: "sun.horizon", fill: Theme.softFill)
                    .fixedSize(horizontal: false, vertical: true)
                    .accessibilityIdentifier("winterlight.line")
            }
            // Side by side when they fit, otherwise stacked – never clipped (audit 2, A2-05: "5 Wochen in Folge · 1 Joker").
            ViewThatFits(in: .horizontal) {
                HStack(spacing: 8) { chips }
                VStack(alignment: .leading, spacing: 8) { chips }
            }
        }
        // One VoiceOver stop: "Winter Arc, Level 5 Wintersonnenwende, 40 % zum nächsten Level, …"
        .accessibilityElement(children: .combine)
    }

    @ViewBuilder
    private var chips: some View {
        JellyChip(text: status.pace.label, systemImage: paceSymbol, fill: paceColor).fixedSize()
        if let streak = Consistency.summary(streak: status.streakWeeks, jokers: status.jokers) {
            JellyChip(text: streak, systemImage: "flame", fill: Color(Palette.mangoPop))
                .fixedSize()
                .accessibilityIdentifier("arc.streak")
        }
    }

    /// Nur ab dem Saisonstart (davor erscheint die Zeile nur im Hub).
    private var lightChip: String? {
        let calendar = Calendar.current
        let today = AppModel.today
        guard calendar.startOfDay(for: today) >= status.start else { return nil }
        let phase = Daylight.phase(now: today, latitude: Daylight.latitude(for: calendar.timeZone), calendar: calendar)
        return Daylight.chip(for: phase)
    }

    private var subtitle: String {
        if status.isFinished { return "Ziel-Tag erreicht – Zeit für den Frühling." }
        let goal = status.goal.formatted(.dateTime.day().month(.wide).locale(Locale.de))
        return "Noch \(status.daysLeft) Tage bis \(goal)"
    }

    private var paceSymbol: String {
        switch status.pace {
        case .ahead: "hare"
        case .onTrack: "checkmark"
        case .behind: "tortoise"
        }
    }

    private var paceColor: Color {
        switch status.pace {
        case .ahead: Theme.fill(.z3)
        case .onTrack: Theme.fill(.z2)
        case .behind: Theme.fill(.z5)
        }
    }
}

struct LevelBadge: View {
    var level: WinterArc.Level
    var size: CGFloat = 44
    var reached = true

    var body: some View {
        Image(systemName: level.symbol)
            .font(.system(size: size * 0.42, weight: .semibold))
            .foregroundStyle(reached ? Theme.ink : Color.secondary)
            .frame(width: size, height: size)
            .background(reached ? AnyShapeStyle(Theme.sunset) : AnyShapeStyle(.quaternary), in: Circle())
            .accessibilityHidden(true)
    }
}

/// S12 – detail: level path, fitness vs. pace line, numbers and how it works.
struct WinterArcView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.colorScheme) private var colorScheme
    @Query(sort: \StoredRide.startDate) private var storedRides: [StoredRide]
    @State private var heart: HeartInWinterArc?

    var body: some View {
        let rides = storedRides.map(\.summary)
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                if let status = model.winterArc(rides: rides) {   // series is cached in AppModel
                    // ANCHOR-B3-HUB: Winterlicht-Kopf mit Himmel, Schnee und Tageslicht-Gewinn – Agent B
                    WinterlightHeader(progress: status.progress, start: status.start, goal: status.goal)
                    WinterArcCard(status: status, showsLight: false)
                    // ANCHOR-K1-WINTERARC (Konstanz-Serie & Joker)
                    ConsistencyCard(result: model.consistency(rides: rides))
                    // Audit 2, A2-03: the season hub shows what to do now (streak, challenges, trophies) before the
                    // reference content; they used to sit below the 10-row level path, 5+ swipes down.
                    // ANCHOR-K3-WINTERARC (Challenges & Trophäen)
                    ChallengesCard(rides: rides)
                    TrophiesCard(rides: rides, arc: status)
                    // ANCHOR-P4-WINTERARC (Winter-Reise)
                    WinterJourneyCard(level: status.level.number, levelProgress: status.levelProgress)
                    // ANCHOR-B2-ALBUM: „Deine Postkarten · n von 10“ (PostcardAlbumView) – Agent B
                    PostcardAlbumCard(status: status, rides: rides)
                    // ANCHOR-B4-WHY: Karte „Dein Warum“ (WhyCard) – Agent B
                    WhyCard()
                    // ANCHOR-W5 (Dein Herz im Winter Arc)
                    if let heart { HeartInWinterArcCard(heart: heart) }

                    Card(title: "Fitness auf dem Weg zum Ziel", systemImage: "chart.line.uptrend.xyaxis") {
                        let points = model.fitnessSeries(rides: rides).points
                        let shadow = SeasonShadow.points(from: points, window: status.start...status.goal)
                        courseChart(status: status, points: points, shadow: shadow)
                        ShadowLegend(showsShadow: shadow != nil)
                        HStack {
                            StatTile(title: "Start", value: Formatters.decimal(status.startCTL))
                            StatTile(title: "Heute", value: Formatters.decimal(status.currentCTL), dot: Theme.fitness)
                            StatTile(title: "Ziel", value: Formatters.decimal(status.targetCTL), dot: Theme.accent)
                        }
                    }
                    Card(title: "Level-Pfad", systemImage: "point.topleft.down.to.point.bottomright.curvepath") {
                        ForEach(WinterArc.levels, id: \.number) { level in
                            levelRow(level, current: status.level.number)
                        }
                    }
                    // ANCHOR-P1-WINTERARC (Ziel-Prognose & Was-wäre-wenn)
                    GoalForecastCard(rides: rides, status: status, weeklyHours: model.profile.weeklyHours)

                    // ANCHOR-P3-WINTERARC (Saisonrückblick teilen)
                    SeasonShareSection(summary: SeasonSummary.make(status: status,
                                                                   challenges: model.seasonChallenges(rides: rides),
                                                                   rides: rides, name: model.profile.name,
                                                                   heartLines: heart?.seasonLines ?? []))

                    Card(title: "So funktioniert der Winter Arc", systemImage: "info.circle") {
                        Text("Der Arc misst, wie viel Fitness du vom Saisonstart bis zu deinem Ziel-Tag aufbaust. Jedes Zehntel des Wegs zur Ziel-Fitness ist ein Level. Ein Level bleibt dir auch nach einer Pause – nur der Kurs zeigt ehrlich, ob du gerade vorne oder hinten liegst.")
                            .font(.subheadline)
                        Text("Serie: Wochen in Folge, in denen du dein Wochenbudget zu 80 % schaffst, alle geplanten Einheiten erledigst oder eine geplante Erholungswoche fährst. Ein Joker fängt eine verpasste Woche auf (Details in der Karte „Konstanz“). Start, Ziel-Tag und Ziel-Fitness stellst du im Profil ein.")
                            .font(.footnote).foregroundStyle(Theme.rowSecondary)
                    }
                } else {
                    EmptyStateView(title: "Kein Winter Arc", systemImage: "calendar.badge.exclamationmark",
                                   message: "Das Zieldatum liegt vor dem Saisonstart. Passe beides im Profil an.")
                }
            }
            .padding()
        }
        .task(id: storedRides.count) {
            guard let status = model.winterArc(rides: rides) else { return }
            heart = await model.heartInWinterArc(rides: rides, status: status)
        }
        .background(Theme.canvas)
        .navigationTitle("Winter Arc")
        .inlineNavigationTitle()
    }

    private func levelRow(_ level: WinterArc.Level, current: Int) -> some View {
        let reached = level.number <= current
        return HStack(spacing: 12) {
            LevelBadge(level: level, size: 36, reached: reached)
            VStack(alignment: .leading, spacing: 2) {
                Text("Level \(level.number) · \(level.name)").font(.subheadline.weight(level.number == current ? .bold : .regular))
                Text("ab \(level.number * 10 - 10) % des Wegs").font(.caption).foregroundStyle(Theme.rowSecondary)
            }
            Spacer()
            if level.number == current { JellyChip(text: "Du bist hier", fill: Color(Palette.peachFizz)) }
            else if reached { Image(systemName: "checkmark.circle.fill").foregroundStyle(Theme.done) }
        }
        .accessibilityElement(children: .combine)
        .accessibilityValue(level.number == current ? "aktuelles Level" : (reached ? "erreicht" : "noch nicht erreicht"))
    }

    /// "Heute 34, Vorjahr 29" (just "Heute 34" without a shadow).
    private func todayText(status: WinterArc.Status, points: [FitnessFreshness.Point], shadow: [SeasonShadow.Point]?) -> String {
        let previous = points.last.flatMap { last in shadow.flatMap { SeasonShadow.fitness(on: last.date, in: $0) } }
        return SeasonShadow.comparisonText(today: status.currentCTL, previous: previous)
    }

    private func courseChart(status: WinterArc.Status, points: [FitnessFreshness.Point],
                             shadow: [SeasonShadow.Point]?) -> some View {
        let shown = points.filter { $0.date >= status.start }
        let dark = colorScheme == .dark
        let values = shown.map(\.fitness) + (shadow ?? []).map(\.fitness) + [status.startCTL, status.targetCTL]
        let span = ChartMath.domain(values: values, includeZero: false)
        let ticks = ChartMath.niceTicks(min: span.lowerBound, max: span.upperBound, count: 4)
        let lowest = ticks.first ?? 0
        return Chart {
            // Course line = target path: dashed, neutral (not the accent colour, so it does not compete with fitness).
            LineMark(x: .value("Tag", status.start), y: .value("Kurs", status.startCTL), series: .value("Linie", "Kurs"))
                .foregroundStyle(ChartPalette.reference)
                .lineStyle(ChartStyle.stroke(.target))
            LineMark(x: .value("Tag", status.goal), y: .value("Kurs", status.targetCTL), series: .value("Linie", "Kurs"))
                .foregroundStyle(ChartPalette.reference)
                .lineStyle(ChartStyle.stroke(.target))
            // G6: last year's curve of the same window, shifted by one year (dotted, muted).
            ForEach(shadow ?? []) { p in
                LineMark(x: .value("Tag", p.date), y: .value("Fitness", p.fitness), series: .value("Linie", "Vorjahr"))
                    .foregroundStyle(ChartPalette.reference)
                    .lineStyle(ChartStyle.stroke(.previous))
                    .interpolationMethod(.monotone)
            }
            ForEach(shown) { p in
                AreaMark(x: .value("Tag", p.date), yStart: .value("Basis", lowest), yEnd: .value("Fitness", p.fitness), series: .value("Linie", "Fläche"))
                    .interpolationMethod(ChartStyle.interpolation(pointCount: shown.count))
                    .foregroundStyle(ChartStyle.area(ChartPalette.fitness, dark: dark))
                LineMark(x: .value("Tag", p.date), y: .value("Fitness", p.fitness), series: .value("Linie", "Fitness"))
                    .foregroundStyle(ChartPalette.fitness)
                    .lineStyle(ChartStyle.stroke(.main))
                    .interpolationMethod(ChartStyle.interpolation(pointCount: shown.count))
            }
            if let last = shown.last {
                HighlightPoint(x: .value("Tag", last.date), y: .value("Fitness", last.fitness), color: ChartPalette.fitness, dark: dark)
            }
            HighlightPoint(x: .value("Tag", status.goal), y: .value("Ziel", status.targetCTL), color: Theme.accent, dark: dark)
            PointMark(x: .value("Tag", status.goal), y: .value("Ziel", status.targetCTL))
                .symbolSize(1).foregroundStyle(.clear)
                .annotation(position: .top, alignment: .trailing, spacing: 10) {
                    Text("Ziel \(Formatters.decimal(status.targetCTL))")
                        .font(ChartStyle.ruleLabelFont).foregroundStyle(Theme.axisLabel)
                }
        }
        .chartXScale(domain: status.start...status.goal)
        .chartYScale(domain: lowest...(ticks.last ?? 1))
        .chartStyleAxes(yTicks: ticks, yLabel: { ChartMath.format($0) })
        .chartStyleHeight(ChartStyle.heightNormal)
        .chartAccessibility(
            label: "Fitness gegenüber Kurslinie",
            value: "\(todayText(status: status, points: points, shadow: shadow)), Kurs \(Formatters.decimal(status.paceCTL)), Ziel \(Formatters.decimal(status.targetCTL))")
    }
}
