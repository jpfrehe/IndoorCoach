import SwiftUI

// K3 – Saison-Challenges + Trophäenschrank (Konstanz-Paket, docs/10).

extension AppModel {
    /// Season challenges of the winter containing `now` (cheap: one pass over the rides per challenge).
    func seasonChallenges(rides: [RideSummary], now: Date = .now) -> [Challenges.Challenge] {
        Challenges.season(rides: rides, ftp: profile.ftp, now: now)
    }

    /// All trophies, earned ones first.
    func trophies(rides: [RideSummary], arc: WinterArc.Status?, now: Date = .now) -> [Trophy] {
        Trophies.all(rides: rides, ftp: profile.ftp, arc: arc, fitness: fitnessSeries(rides: rides, now: now).points, now: now,
                       strengthDates: strengthSessionDates())
    }
}

private enum ChallengeFormat {
    static func date(_ d: Date) -> String {
        d.formatted(.dateTime.day().month(.abbreviated).locale(Locale.de))
    }

    static func days(_ n: Int) -> String { "\(n) \(n == 1 ? "Tag" : "Tage")" }
}

// MARK: - Heute: Highlight

/// Ring with the percentage in the middle; the sunset gradient is decoration, the text carries the value.
struct ChallengeRing: View {
    var fraction: Double
    var symbol: String
    @ScaledMetric(relativeTo: .title) private var size: CGFloat = 64

    var body: some View {
        ZStack {
            Circle().stroke(Theme.softFill, lineWidth: 8)
            Circle().trim(from: 0, to: max(0.02, fraction))
                .stroke(Theme.sunsetAngular, style: StrokeStyle(lineWidth: 8, lineCap: .round))
                .rotationEffect(.degrees(-90))
            Image(systemName: symbol).font(.system(size: size * 0.32, weight: .semibold)).foregroundStyle(Theme.accent)
        }
        .frame(width: size, height: size)
        .accessibilityHidden(true)
    }
}

/// Highlight card on Heute: a running challenge or one starting within 7 days. Tap → Winter Arc (Saison-Hub).
struct ChallengeHighlightCard: View {
    var challenge: Challenges.Challenge

    var body: some View {
        Card(title: "Saison-Challenge", systemImage: "flag.checkered") {
            HStack(spacing: 16) {
                ChallengeRing(fraction: challenge.fraction, symbol: challenge.symbol)
                VStack(alignment: .leading, spacing: 4) {
                    Text(challenge.title).font(.headline)
                    switch challenge.state {
                    case .active(let left):
                        Text("\(challenge.progressText) · \(challenge.remainingText)").font(.subheadline)
                        Text("Noch \(ChallengeFormat.days(left))").font(.caption).foregroundStyle(Theme.rowSecondary)
                    case .upcoming(let until):
                        Text(challenge.rule).font(.subheadline)
                        Text("Startet in \(ChallengeFormat.days(until))").font(.caption).foregroundStyle(Theme.rowSecondary)
                    default:
                        Text(challenge.progressText).font(.subheadline)
                    }
                }
                .fixedSize(horizontal: false, vertical: true)
                Spacer(minLength: 0)
                Image(systemName: "chevron.right").font(.footnote.weight(.semibold)).foregroundStyle(Theme.rowSecondary)
                    .accessibilityHidden(true)
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Challenges.summary(challenge))
        .accessibilityHint("Öffnet den Winter Arc")
        .accessibilityAddTraits(.isButton)
    }
}

/// Slot content for `ANCHOR-K3-HEUTE`: renders nothing unless a challenge runs or starts within 7 days.
struct ChallengeHighlightSlot: View {
    var rides: [RideSummary]
    @Environment(AppModel.self) private var model

    var body: some View {
        if let challenge = Challenges.highlight(in: model.seasonChallenges(rides: rides)) {
            NavigationLink { WinterArcView() } label: { ChallengeHighlightCard(challenge: challenge) }
                .buttonStyle(.plain)
                .accessibilityIdentifier("challenge.highlight")
        }
    }
}

// MARK: - Winter-Arc-Detail: Challenges

private struct ChallengeRow: View {
    var challenge: Challenges.Challenge

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: challenge.isCompleted ? "checkmark.circle.fill" : challenge.symbol)
                .font(.title3)
                .foregroundStyle(challenge.isCompleted ? Theme.done : Theme.accent)
                .frame(width: 28)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 4) {
                Text(challenge.title).font(.subheadline.weight(.semibold))
                switch challenge.state {
                case .active(let left):
                    ProgressView(value: challenge.fraction).tint(Theme.accent)
                    Text("\(challenge.progressText) · noch \(ChallengeFormat.days(left))")
                        .font(.caption).foregroundStyle(Theme.rowSecondary)
                case .upcoming(let until):
                    Text("\(challenge.rule) · startet in \(ChallengeFormat.days(until))")
                        .font(.caption).foregroundStyle(Theme.rowSecondary)
                case .completed(let on):
                    Text("Geschafft am \(ChallengeFormat.date(on))").font(.caption).foregroundStyle(Theme.rowSecondary)
                case .missed:
                    Text(challenge.rule).font(.caption).foregroundStyle(Theme.rowSecondary)
                }
            }
            .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Challenges.summary(challenge))
    }
}

/// Card "Challenges": running, coming up (next three) and completed ones. Missed ones stay out of sight.
struct ChallengesCard: View {
    var rides: [RideSummary]
    @Environment(AppModel.self) private var model

    var body: some View {
        let all = model.seasonChallenges(rides: rides)
        let active = all.filter(\.isActive)
        let upcoming = Array(all.filter(\.isUpcoming).prefix(3))
        let done = all.filter(\.isCompleted)
        Card(title: "Challenges", systemImage: "flag.checkered") {
            if active.isEmpty && upcoming.isEmpty && done.isEmpty {
                Text("Gerade läuft keine Challenge. Im November geht die nächste Saison los.")
                    .font(.subheadline).foregroundStyle(Theme.rowSecondary)
            }
            ForEach(active + upcoming + done) { ChallengeRow(challenge: $0) }
            Text("Zählt nur Indoor-Fahrten. Der Fortschritt wird aus deinen Fahrten berechnet.")
                .font(.caption).foregroundStyle(Theme.rowSecondary)
        }
        // A container element: otherwise the card's identifier is copied onto every child and replaces their own
        // (audit 2, A2-03b: "Alle anzeigen" lost its id "trophies.all" and could not be found).
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("challenges.card")
    }
}

// MARK: - Trophäen

private struct TrophyRow: View {
    var trophy: Trophy

    var body: some View {
        HStack(spacing: 12) {
            TrophyBadge(trophy: trophy, size: 40)
            VStack(alignment: .leading, spacing: 2) {
                Text(trophy.title).font(.subheadline.weight(.semibold))
                Text(trophy.earnedOn.map { ChallengeFormat.date($0) } ?? trophy.condition)
                    .font(.caption).foregroundStyle(Theme.rowSecondary)
            }
            .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 0)
            // ANCHOR-B1-TROPHY: kleiner Punkt „neu“ für Trophäen der letzten 7 Tage – Agent A
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(trophy.summary)
    }
}

struct TrophyBadge: View {
    var trophy: Trophy
    var size: CGFloat = 48

    var body: some View {
        Image(systemName: trophy.symbol)
            .font(.system(size: size * 0.42, weight: .semibold))
            .foregroundStyle(trophy.isEarned ? Theme.ink : Theme.rowSecondary)
            .frame(width: size, height: size)
            .background(trophy.isEarned ? AnyShapeStyle(Theme.sunset) : AnyShapeStyle(.quaternary), in: Circle())
            .accessibilityHidden(true)
    }
}

/// Card "Trophäen": the six latest earned ones and the way to the full case.
struct TrophiesCard: View {
    var rides: [RideSummary]
    var arc: WinterArc.Status?
    @Environment(AppModel.self) private var model

    var body: some View {
        let all = model.trophies(rides: rides, arc: arc)
        let earned = all.filter(\.isEarned)
        Card(title: "Trophäen", systemImage: "trophy") {
            if earned.isEmpty {
                Text("Noch keine Trophäe – die erste ist nicht weit. Jede Fahrt zählt.")
                    .font(.subheadline).foregroundStyle(Theme.rowSecondary)
            }
            ForEach(earned.prefix(6)) { TrophyRow(trophy: $0) }
            NavigationLink { TrophyCaseView(rides: rides, arc: arc) } label: {
                HStack {
                    Text("Alle anzeigen (\(earned.count) von \(all.count))").font(.subheadline.weight(.semibold))
                    Spacer()
                    Image(systemName: "chevron.right").font(.footnote.weight(.semibold))
                }
                .foregroundStyle(Theme.accent)
                .frame(minHeight: 44)
                .contentShape(Rectangle())
            }
            .accessibilityIdentifier("trophies.all")
        }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("trophies.card")
    }
}

/// Trophäenschrank: every trophy as a grid; the ones not earned yet are greyed out with their condition.
struct TrophyCaseView: View {
    var rides: [RideSummary]
    var arc: WinterArc.Status?
    @Environment(AppModel.self) private var model

    var body: some View {
        let all = model.trophies(rides: rides, arc: arc)
        let earnedCount = all.filter(\.isEarned).count
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                Text("\(earnedCount) von \(all.count) Trophäen")
                    .font(.headline)
                    .accessibilityIdentifier("trophies.count")
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 150), spacing: 12, alignment: .top)], spacing: 12) {
                    ForEach(all) { tile($0) }
                }
                Text("Trophäen werden aus deinen Fahrten berechnet. Das Datum zeigt, wann du sie erreicht hast.")
                    .font(.caption).foregroundStyle(Theme.rowSecondary)
            }
            .padding()
        }
        .background(Theme.canvas)
        .navigationTitle("Trophäen")
        .inlineNavigationTitle()
        .accessibilityIdentifier("trophies.case")
    }

    private func tile(_ t: Trophy) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            TrophyBadge(trophy: t, size: 52)
            Text(t.title).font(.subheadline.weight(.semibold))
                .foregroundStyle(t.isEarned ? Color.primary : Theme.rowSecondary)
            if let on = t.earnedOn {
                Text(ChallengeFormat.date(on)).font(.caption).foregroundStyle(Theme.rowSecondary)
                if let detail = t.detail { Text(detail).font(.caption2).foregroundStyle(Theme.rowSecondary) }
            } else {
                Text(t.condition).font(.caption).foregroundStyle(Theme.rowSecondary)
            }
        }
        .fixedSize(horizontal: false, vertical: true)
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .topLeading)
        .background(t.isEarned ? Theme.card : Theme.card.opacity(0.55), in: RoundedRectangle(cornerRadius: 18, style: .continuous))
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(t.summary)
    }
}

// MARK: - Fahrt-Detail

/// "Mit dieser Fahrt: Monats-Konstanz November geschafft" – only when this ride completed a challenge.
struct RideChallengeNote: View {
    var ride: RideSummary
    @Environment(AppModel.self) private var model

    var body: some View {
        if ride.isIndoor {
            let done = Challenges.completed(by: ride, in: model.seasonChallenges(rides: model.allRides(), now: ride.startDate))
            if !done.isEmpty {
                let text = "Mit dieser Fahrt: \(done.map(\.title).joined(separator: " und ")) geschafft"
                Label(text, systemImage: "flag.checkered")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(Color.primary)
                    .padding(.horizontal, 14).padding(.vertical, 10)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(Theme.softFill, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
                    .accessibilityElement(children: .combine)
                    .accessibilityIdentifier("ride.challenge")
            }
        }
    }
}
