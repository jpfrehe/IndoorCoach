#if canImport(ActivityKit) && os(iOS)
import ActivityKit
import Foundation

/// `Activity` ist nicht `Sendable`, seine async-Methoden aber nicht an den Main Actor gebunden. Der Controller ruft
/// das Backend seriell auf, daher ist die Weitergabe unkritisch.
private struct ActivityBox: @unchecked Sendable {
    let activity: Activity<RecordingActivityAttributes>
}

@MainActor
final class ActivityKitBackend: RecordingActivityBackend {
    private var box: ActivityBox?

    var isAvailable: Bool { ActivityAuthorizationInfo().areActivitiesEnabled }

    func request(_ state: RecordingLiveState, staleDate: Date) -> Bool {
        let attributes = RecordingActivityAttributes(kind: state.kind, title: state.title)
        do {
            let activity = try Activity.request(attributes: attributes,
                                                content: ActivityContent(state: state, staleDate: staleDate),
                                                pushType: nil)
            box = ActivityBox(activity: activity)
            return true
        } catch {
            return false   // die Aufzeichnung läuft ohne Live Activity weiter
        }
    }

    func update(_ state: RecordingLiveState, staleDate: Date) async {
        guard let box else { return }
        await box.activity.update(ActivityContent(state: state, staleDate: staleDate))
    }

    func endAll() async {
        box = nil
        for activity in Activity<RecordingActivityAttributes>.activities {
            await activity.end(nil, dismissalPolicy: .immediate)
        }
    }

    func end(_ state: RecordingLiveState, dismissAfter: TimeInterval) async {
        guard let box else { return }
        self.box = nil
        await box.activity.end(ActivityContent(state: state, staleDate: nil),
                               dismissalPolicy: .after(Date().addingTimeInterval(dismissAfter)))
    }
}

/// Live Activity für laufende Aufzeichnungen (Sperrbildschirm, Dynamic Island). Fehlt die Berechtigung, passiert nichts.
@MainActor
public enum LiveActivityPresenter {
    public static func make() -> RecordingLivePresenting {
        RecordingLiveController(backend: ActivityKitBackend())
    }
}
#endif
