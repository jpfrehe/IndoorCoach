import Combine
import SwiftUI

/// Baut den Inhalt neu auf, wenn der Kalendertag wechselt (Mitternacht bei offener App oder Rückkehr am nächsten Tag).
/// Sonst zeigen „Heute“, „Morgen“ und das Datum oben noch den Vortag, bis sich zufällig etwas anderes ändert.
private struct RefreshOnNewDay: ViewModifier {
    @Environment(\.scenePhase) private var scenePhase
    @State private var day = Calendar.current.startOfDay(for: .now)

    func body(content: Content) -> some View {
        content
            .id(day)
            .onChange(of: scenePhase) { _, phase in
                if phase == .active { update() }
            }
            .onReceive(NotificationCenter.default.publisher(for: .NSCalendarDayChanged).receive(on: DispatchQueue.main)) { _ in
                update()
            }
    }

    private func update() {
        let today = Calendar.current.startOfDay(for: .now)
        if today != day { day = today }
    }
}

extension View {
    func refreshesOnNewDay() -> some View { modifier(RefreshOnNewDay()) }
}
