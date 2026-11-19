import SwiftData
import SwiftUI

/// Check-in vor der Einheit: drei Fragen mit je drei großen Tipp-Zielen, optionale Chips, überspringbar.
/// Danach (bei negativen Antworten) die Angebote. Kein Push, keine Mitteilung.
struct CheckInSheet: View {
    var workout: StoredWorkout
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    @Environment(\.dynamicTypeSize) private var typeSize
    @Query(sort: \StoredRide.startDate) private var rides: [StoredRide]
    @State private var answers = CheckIn.Answers()
    @State private var saved: StoredCheckIn?

    init(workout: StoredWorkout, existing: StoredCheckIn? = nil) {
        self.workout = workout
        _saved = State(initialValue: existing)
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    if let saved { offersView(saved) } else { questionsView }
                }
                .padding(.horizontal)
                .padding(.bottom, 24)
            }
            .background(Theme.canvas)
            .navigationTitle("Check-in")
            .inlineNavigationTitle()
        }
        .presentationDetents([.large])
    }

    // MARK: Fragen

    private var questionsView: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Wie startest du heute? Drei Tipps, alles optional.")
                .font(.subheadline).foregroundStyle(Theme.rowSecondary)
            ForEach(CheckIn.Question.allCases) { question in
                VStack(alignment: .leading, spacing: 8) {
                    Text(question.title).font(.headline)
                    let layout = typeSize.isAccessibilitySize ? AnyLayout(VStackLayout(spacing: 8)) : AnyLayout(HStackLayout(spacing: 8))
                    layout {
                        ForEach(CheckIn.Level.allCases) { level in levelButton(question, level) }
                    }
                }
                .accessibilityElement(children: .contain)
            }
            Text("Gibt es etwas Besonderes?").font(.headline)
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 130), spacing: 8)], spacing: 8) {
                ForEach(CheckIn.Tag.allCases) { tag in tagButton(tag) }
            }
            VStack(spacing: 10) {
                Button { save() } label: { Text("Fertig").frame(maxWidth: .infinity) }
                    .buttonStyle(.jelly)
                    .accessibilityIdentifier("checkin.done")
                Button { model.skipCheckIn(); dismiss() } label: { Text("Überspringen").frame(maxWidth: .infinity) }
                    .buttonStyle(.soft)
                    .accessibilityIdentifier("checkin.skip")
            }
        }
    }

    private func levelButton(_ question: CheckIn.Question, _ level: CheckIn.Level) -> some View {
        let selected = answers[question] == level
        return Button { answers[question] = level } label: {
            Text(level.label(for: question))
                .font(.body.weight(.semibold))
                .multilineTextAlignment(.center)
                .frame(maxWidth: .infinity, minHeight: 56)
                .foregroundStyle(selected ? Theme.ink : Theme.accent)
                .background(selected ? AnyShapeStyle(Theme.sunset) : AnyShapeStyle(Theme.softFill),
                            in: RoundedRectangle(cornerRadius: 16, style: .continuous))
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel("\(question.title): \(level.label(for: question))")
        .accessibilityAddTraits(selected ? .isSelected : [])
        .accessibilityIdentifier("checkin.\(question.rawValue).\(level.rawValue)")
    }

    private func tagButton(_ tag: CheckIn.Tag) -> some View {
        let selected = answers.tags.contains(tag)
        return Button {
            if selected { answers.tags.remove(tag) } else { answers.tags.insert(tag) }
        } label: {
            HStack(spacing: 6) {
                Image(systemName: selected ? "checkmark.circle.fill" : "circle")
                Text(tag.label)
            }
            .font(.body)
            .frame(maxWidth: .infinity, minHeight: 48)
            .foregroundStyle(selected ? Theme.ink : Theme.accent)
            .background(selected ? AnyShapeStyle(Theme.sunset) : AnyShapeStyle(Theme.softFill),
                        in: RoundedRectangle(cornerRadius: 14, style: .continuous))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(tag.label)
        .accessibilityAddTraits(selected ? .isSelected : [])
        .accessibilityIdentifier("checkin.tag.\(tag.rawValue)")
    }

    private func save() {
        let jokers = model.consistency(rides: rides.map(\.summary)).jokers
        guard let row = model.saveCheckIn(answers, jokersAvailable: jokers) else { dismiss(); return }
        if row.offered.isEmpty && CheckIn.healthHint(for: row.answers) == nil { dismiss() } else { saved = row }
    }

    // MARK: Angebote

    @ViewBuilder
    private func offersView(_ row: StoredCheckIn) -> some View {
        let original = workout.originalDefinition ?? workout.definition
        if let hint = CheckIn.healthHint(for: row.answers) {
            Label(hint, systemImage: "heart.text.square").font(.headline)
                .accessibilityIdentifier("checkin.hint")
        }
        if !row.offered.isEmpty {
            Text(row.answers.hasInfection ? "Heute besser pausieren." : "Das kannst du heute tun. Du entscheidest.")
                .font(.subheadline).foregroundStyle(Theme.rowSecondary)
            ForEach(row.offered, id: \.raw) { action in
                Button { choose(action) } label: {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(Self.title(action)).font(.body.weight(.semibold))
                        Text(Self.detail(action, original: original)).font(.caption).foregroundStyle(Theme.rowSecondary)
                    }
                    .multilineTextAlignment(.leading)
                    .frame(maxWidth: .infinity, minHeight: 56, alignment: .leading)
                    .padding(.horizontal, 14)
                    .background(Theme.softFill, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityElement(children: .combine)
                .accessibilityIdentifier("checkin.offer.\(action.raw.replacingOccurrences(of: ":", with: "."))")
            }
        }
        Button { dismiss() } label: {
            Text(row.answers.hasInfection ? "Schließen" : "Wie geplant fahren").frame(maxWidth: .infinity)
        }
        .buttonStyle(.soft)
        .accessibilityIdentifier("checkin.offer.none")
    }

    private func choose(_ action: CheckIn.Action) {
        let target = workout
        dismiss()
        Task { await model.applyCheckInOffer(action, to: target) }
    }

    static func title(_ action: CheckIn.Action) -> String {
        switch action {
        case .shorten(let m, _): "Kürzer: \(m) min"
        case .easier(let p): "Leichter: −\(p)\u{00A0}% Intensität"
        case .swapToBase: "Gegen Grundlage tauschen"
        case .joker: "Joker einsetzen"
        }
    }

    static func detail(_ action: CheckIn.Action, original: WorkoutDefinition) -> String {
        let minutes = WorkoutAdjust.minutes(original.totalDuration)
        switch action {
        case .shorten(let m, let e): return "\(m) min statt \(minutes) min, \(e)\u{00A0}% leichter"
        case .easier: return "Gleiche Dauer, weniger Watt"
        case .swapToBase: return "\(minutes) min locker im Grundlagenbereich (Z2)"
        case .joker: return "Heute pausieren, deine Serie bleibt"
        }
    }
}

/// Opens the check-in when today's planned workout is opened (and no check-in exists yet).
struct CheckInOnOpen: ViewModifier {
    var workout: StoredWorkout
    @Environment(AppModel.self) private var model
    @State private var show = false

    func body(content: Content) -> some View {
        content
            .sheet(isPresented: $show) { CheckInSheet(workout: workout) }
            .task(id: workout.id) {
                guard !CheckInCard.suppressedInUITests, workout.status == .planned, !workout.isDeleted,
                      model.checkInDue(), model.plannedWorkoutToday()?.id == workout.id else { return }
                show = true
            }
    }
}

extension View {
    func checkInOnOpen(_ workout: StoredWorkout) -> some View { modifier(CheckInOnOpen(workout: workout)) }
}
