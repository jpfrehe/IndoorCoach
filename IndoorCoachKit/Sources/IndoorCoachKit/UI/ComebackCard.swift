import SwiftData
import SwiftUI

/// Der Highlight-Slot auf Heute (docs/22, B4): „Willkommen zurück“ hat höchste Priorität, danach die einmalige Warum-Frage;
/// sonst gilt, was vorher dort stand (Wochenrückblick, Challenge).
struct WinterHighlightSlot<Fallback: View>: View {
    var rides: [RideSummary]
    var workouts: [StoredWorkout]
    @ViewBuilder var fallback: Fallback
    @Environment(AppModel.self) private var model
    @AppStorage(Comeback.dismissedKey) private var dismissedDay = ""
    @AppStorage(WhyNote.promptDismissedKey) private var promptDismissed = false

    var body: some View {
        switch model.winterHighlight(rides: rides, dismissedDay: dismissedDay.isEmpty ? nil : dismissedDay,
                                     whyPromptDismissed: promptDismissed) {
        case .comeback(let state): ComebackCard(state: state, rides: rides, workouts: workouts)
        case .whyPrompt: WhyPromptCard()
        case nil: fallback
        }
    }
}

/// „Schön, dass du wieder da bist“: freundlich, ohne Urteil, ohne Formkurve. „Heute locker einsteigen“ führt über das vorhandene
/// Anpassen oder Tauschen (oder eine lockere Grundlage ohne Plan) zu einer startbaren Einheit, ohne Claude.
struct ComebackCard: View {
    var state: Comeback.State
    var rides: [RideSummary]
    var workouts: [StoredWorkout]
    @Environment(AppModel.self) private var model
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @AppStorage(Comeback.dismissedKey) private var dismissedDay = ""
    @State private var bounce = false
    @State private var destination: Target?
    @State private var confirmSwap = false

    struct Target: Hashable {
        var workout: StoredWorkout
        var preset: AdjustPreset?
    }

    private var now: Date { AppModel.today }

    private var planned: StoredWorkout? {
        let cal = Calendar.current
        let today = cal.startOfDay(for: now)
        let end = cal.date(byAdding: .day, value: 2, to: today) ?? today
        return workouts.filter { $0.status == .planned && $0.date >= today && $0.date < end }.min { $0.date < $1.date }
    }

    var body: some View {
        let last = model.lastActivityDate(rides: rides)
        let texts = Comeback.texts(state: state, jokerWeek: model.comebackJokerWeek(rides: rides, lastActivity: last, now: now),
                                   why: model.whyNote)
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .top, spacing: 12) {
                Image(systemName: "sunrise").font(.title2).foregroundStyle(Theme.accent)
                    .symbolEffect(.bounce, value: bounce)
                    .accessibilityHidden(true)
                Text(texts.title).font(.title3.weight(.bold)).accessibilityAddTraits(.isHeader)
            }
            Text(texts.lead).font(.body)
            if let landmark = texts.landmark { Text(landmark).font(.body.weight(.semibold)) }
            Text(texts.streak).font(.subheadline).foregroundStyle(Theme.rowSecondary)
            if let quote = texts.quote, let spoken = texts.quoteSpoken {
                Text(quote).font(.callout.italic())
                    .padding(12)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(Theme.softFill, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                    .accessibilityLabel(spoken)
            }
            let layout = dynamicTypeSize.isAccessibilitySize ? AnyLayout(VStackLayout(spacing: 10)) : AnyLayout(HStackLayout(spacing: 10))
            layout {
                Button(action: start) { Text(texts.start).frame(maxWidth: .infinity, minHeight: 44) }
                    .buttonStyle(.jelly)
                    .accessibilityIdentifier("comeback.start")
                Button { dismissedDay = Comeback.dayKey(now) } label: { Text(texts.later).frame(maxWidth: .infinity, minHeight: 44) }
                    .buttonStyle(.soft)
                    .accessibilityIdentifier("comeback.later")
            }
            Text(texts.hint).font(.caption).foregroundStyle(Theme.rowSecondary)
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Theme.card, in: RoundedRectangle(cornerRadius: 22, style: .continuous))
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("comeback.card")
        .transition(.opacity)
        .onAppear { if !reduceMotion { bounce.toggle() } }
        .navigationDestination(item: $destination) { WorkoutDetailView(workout: $0.workout, adjustPreset: $0.preset) }
        .confirmationDialog("Gegen Grundlage tauschen?", isPresented: $confirmSwap, titleVisibility: .visible) {
            Button("Tauschen") {
                guard let workout = planned else { return }
                Task {
                    await model.swapToBase(workout)
                    destination = Target(workout: workout, preset: nil)
                }
            }
            Button("Abbrechen", role: .cancel) {}
        } message: {
            Text("Die geplante Einheit wird durch lockere Grundlage in gleicher Länge ersetzt. Das Original lässt sich wiederherstellen.")
        }
    }

    private func start() {
        switch Comeback.startAction(planned: planned?.definition) {
        case .adjust(let minutes, let easier):
            if let planned { destination = Target(workout: planned, preset: AdjustPreset(minutes: minutes, easierBy: easier)) }
        case .swapToBase:
            confirmSwap = true
        case .easyRide:
            if let workout = model.createEasyReturnWorkout(now: now) { destination = Target(workout: workout, preset: nil) }
        }
    }
}
