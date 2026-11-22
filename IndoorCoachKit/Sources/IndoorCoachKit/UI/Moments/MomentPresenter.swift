import SwiftData
import SwiftUI
#if os(iOS)
import UIKit
#endif

private func momentNewestRide() -> FetchDescriptor<StoredRide> {
    var d = FetchDescriptor<StoredRide>(sortBy: [SortDescriptor(\.startDate, order: .reverse)])
    d.fetchLimit = 1
    return d
}

private func momentNewestStrength() -> FetchDescriptor<StoredStrengthSession> {
    var d = FetchDescriptor<StoredStrengthSession>(sortBy: [SortDescriptor(\.start, order: .reverse)])
    d.fetchLimit = 1
    return d
}

/// Zeigt den Gipfelmoment (docs/22, B1): wertet ereignisgesteuert aus (App wird aktiv, neue Fahrt oder Kraft-Einheit, Sync-Ende,
/// Tageswechsel – kein Dauer-Polling) und zeigt die Feier als Vollbild – nie während einer Aufzeichnung, der Einführung, bei
/// anderem offenen Blatt oder kurz vor einer geplanten Einheit. Dann wartet der Moment; nur solange etwas wartet, wird alle
/// paar Sekunden erneut versucht. Der Stapel gilt beim Zeigen sofort als gesehen (nie zweimal, auch nicht nach einem Abbruch).
struct MomentPresenter: ViewModifier {
    @Environment(AppModel.self) private var model
    @Environment(\.scenePhase) private var scenePhase
    @Query(momentNewestRide()) private var newestRide: [StoredRide]
    @Query(momentNewestStrength()) private var newestStrength: [StoredStrengthSession]
    @State private var presented: PresentedMoment?
    @State private var dayStamp = Calendar.current.startOfDay(for: AppModel.today)

    /// Nur solange ein Moment wartet (anderes Blatt offen, Aufzeichnung läuft): so oft wird erneut versucht.
    private static let retry: Duration = .seconds(4)

    /// Ändert sich bei: Aktivwerden, neuer Fahrt/Kraft-Einheit, Ende eines Syncs, neuem Tag.
    private struct Trigger: Hashable {
        var phase: ScenePhase
        var ride: Date?
        var rideID: Int?
        var strength: Date?
        var sync: Date?
        var day: Date
    }

    private var trigger: Trigger {
        Trigger(phase: scenePhase, ride: newestRide.first?.startDate, rideID: newestRide.first?.stravaID,
                strength: newestStrength.first?.start, sync: model.lastSync, day: dayStamp)
    }

    func body(content: Content) -> some View {
        content
            .task(id: trigger) { await watch() }
            .onReceive(NotificationCenter.default.publisher(for: .NSCalendarDayChanged)) { _ in
                dayStamp = Calendar.current.startOfDay(for: AppModel.today)
            }
            // Eigener Anker für die Feier: so stört sie keine andere Vollbild-Präsentation derselben View-Kette.
            .background {
                Color.clear.momentCover(item: $presented) { item in
                    MomentSheet(presentation: item.presentation)
                }
            }
    }

    private func watch() async {
        guard scenePhase == .active else { return }
        try? await Task.sleep(for: .seconds(1.5)) // erst ankommen lassen (Start, Import)
        guard !Task.isCancelled else { return }
        model.evaluateMoments()
        while !Task.isCancelled, !model.pendingMoments.isEmpty {
            if presented == nil, let presentation = model.takeMomentToPresent(gate: gate()) {
                presented = PresentedMoment(presentation: presentation)
                return
            }
            try? await Task.sleep(for: Self.retry)
        }
    }

    private func gate() -> MomentGate {
        MomentGate(recordingRunning: RecordingService.shared.isRunning, anotherPresentation: Self.anotherPresentationActive())
    }

    /// Ob schon ein Blatt, eine Vollbild-Ansicht oder ein Hinweis über der App liegt (jede Präsentation hängt am
    /// Wurzel-Controller des Fensters).
    @MainActor static func anotherPresentationActive() -> Bool {
        #if os(iOS)
        let scenes = UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }
        let window = scenes.first { $0.activationState == .foregroundActive }?.windows.first { $0.isKeyWindow }
        return window?.rootViewController?.presentedViewController != nil
        #else
        return false
        #endif
    }
}

extension View {
    /// Gipfelmoment nach der Fahrt (docs/22, B1). Einmal an der Wurzel anbringen.
    func momentCelebration() -> some View { modifier(MomentPresenter()) }
}

extension View {
    /// Vollbild auf dem iPhone; das Paket baut auch für den Mac (Tests, Schnappschüsse), wo es nur Blätter gibt.
    func momentCover<C: View>(item: Binding<PresentedMoment?>, onDismiss: (() -> Void)? = nil,
                              @ViewBuilder content: @escaping (PresentedMoment) -> C) -> some View {
        #if os(iOS)
        fullScreenCover(item: item, onDismiss: onDismiss, content: content)
        #else
        sheet(item: item, onDismiss: onDismiss, content: content)
        #endif
    }
}
