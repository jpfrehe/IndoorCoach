import SwiftUI
#if os(iOS)
import UIKit
#endif

/// Zeigt den Gipfelmoment (docs/22, B1): wertet beim Aktivwerden und danach im ruhigen Takt aus (neue Fahrten kommen auf
/// jedem Weg herein, auch während die App offen ist) und zeigt die Feier als Vollbild – nie während einer Aufzeichnung,
/// der Einführung, bei anderem offenen Blatt oder kurz vor einer geplanten Einheit. Dann wartet der Moment.
struct MomentPresenter: ViewModifier {
    @Environment(AppModel.self) private var model
    @Environment(\.scenePhase) private var scenePhase
    @State private var presented: PresentedMoment?
    @State private var noteRule: String?

    /// Takt der Prüfung, solange die App aktiv ist (Fingerabdruck der Fahrten macht leere Runden billig).
    private static let tick: Duration = .seconds(4)

    func body(content: Content) -> some View {
        content
            .task(id: scenePhase) { await watch() }
            // Eigener Anker für die Feier: so stört sie keine andere Vollbild-Präsentation derselben View-Kette.
            .background {
                Color.clear.momentCover(item: $presented, onDismiss: acknowledge) { item in
                    MomentSheet(presentation: item.presentation)
                }
            }
    }

    private func watch() async {
        guard scenePhase == .active else { return }
        try? await Task.sleep(for: .seconds(1.5)) // erst ankommen lassen (Start, Import)
        while !Task.isCancelled {
            model.evaluateMoments()
            if presented == nil, let batch = model.momentToPresent(gate: gate()) {
                let presentation = model.momentPresentation(for: batch)
                noteRule = presentation.coachNote?.rule
                presented = PresentedMoment(presentation: presentation)
            }
            try? await Task.sleep(for: Self.tick)
        }
    }

    private func gate() -> MomentGate {
        MomentGate(recordingRunning: RecordingService.shared.isRunning, anotherPresentation: Self.anotherPresentationActive())
    }

    private func acknowledge() {
        model.acknowledgeMoments(noteRule: noteRule)
        noteRule = nil
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
