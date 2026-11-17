import SwiftUI

/// Profil → "Erinnerungen": opt-in Sunday notification for the Wochenrückblick (K2).
struct ReminderSection: View {
    @Environment(AppModel.self) private var model
    @Environment(\.openURL) private var openURL
    @State private var denied = false
    @State private var busy = false

    var body: some View {
        Section {
            Toggle("Wochenrückblick am Sonntag", isOn: Binding(get: { model.profile.weeklyReviewReminder },
                                                               set: { change(to: $0) }))
                .frame(minHeight: 44)
                .disabled(busy)
                .accessibilityIdentifier("reminder.toggle")
            if denied {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Mitteilungen sind für IndoorCoach ausgeschaltet.").font(.subheadline.weight(.semibold))
                    Text("Erlaube sie in den Einstellungen, dann kann die Erinnerung am Sonntag kommen.")
                        .font(.subheadline).foregroundStyle(.secondary)
                }
                Button {
                    if let url = URL(string: "app-settings:") { openURL(url) }
                } label: {
                    Label("Einstellungen öffnen", systemImage: "gearshape").frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
                }
                .accessibilityIdentifier("reminder.openSettings")
            }
        } header: { Text("Erinnerungen") } footer: {
            Text("Sonntag um 18:00 Uhr bekommst du eine Mitteilung, dass dein Wochenrückblick bereit ist. Sie wird nur auf diesem Gerät geplant.")
        }
        .task { await reconcile() }
    }

    private func change(to enabled: Bool) {
        if !enabled {
            model.profile.weeklyReviewReminder = false
            WeeklyReviewReminder.disable(center: model.reminderCenter)
            denied = false
            return
        }
        busy = true
        Task {
            defer { busy = false }
            switch await WeeklyReviewReminder.enable(center: model.reminderCenter) {
            case .scheduled:
                model.profile.weeklyReviewReminder = true
                denied = false
            case .denied:
                model.profile.weeklyReviewReminder = false
                denied = true
            case .failed:
                model.profile.weeklyReviewReminder = false
                model.show("Die Erinnerung konnte nicht geplant werden.", error: true)
            }
        }
    }

    /// Keeps the schedule in line with the switch: re-registers it, or turns the switch off when the
    /// permission was withdrawn in Settings in the meantime.
    private func reconcile() async {
        guard model.profile.weeklyReviewReminder else { return }
        if await model.reminderCenter.authorization() == .authorized {
            _ = await WeeklyReviewReminder.schedule(center: model.reminderCenter)
        } else {
            model.profile.weeklyReviewReminder = false
            denied = true
        }
    }
}
