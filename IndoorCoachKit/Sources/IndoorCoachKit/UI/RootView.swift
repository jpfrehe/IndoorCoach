import SwiftData
import SwiftUI

public enum AppTab: Hashable { case today, plan, history, profile }

public struct RootView: View {
    @Environment(AppModel.self) private var model
    @State private var tab: AppTab = RootView.initialTab

    public init() {}

    /// Debug-only launch argument for screenshots/UI checks: `-uiTab plan|history|profile`.
    static var initialTab: AppTab {
        #if DEBUG
        switch UserDefaults.standard.string(forKey: "uiTab") {
        case "plan": return .plan
        case "history": return .history
        case "profile": return .profile
        default: return .today
        }
        #else
        return .today
        #endif
    }

    public var body: some View {
        TabView(selection: $tab) {
            Tab("Heute", systemImage: "sun.max.fill", value: AppTab.today) {
                TodayView(tab: $tab)
            }
            Tab("Plan", systemImage: "calendar", value: AppTab.plan) {
                PlanView()
            }
            Tab("Verlauf", systemImage: "chart.bar.xaxis", value: AppTab.history) {
                HistoryView()
            }
            Tab("Profil", systemImage: "person.crop.circle", value: AppTab.profile) {
                ProfileView()
            }
        }
        .tint(Theme.accent)
        .overlay(alignment: .top) {
            if let banner = model.banner {
                BannerView(banner: banner)
                    .transition(.move(edge: .top).combined(with: .opacity))
                    .task(id: banner.id) {
                        try? await Task.sleep(for: .seconds(banner.isError ? 6 : 3))
                        withAnimation { if model.banner?.id == banner.id { model.banner = nil } }
                    }
                    .onTapGesture { withAnimation { model.banner = nil } }
            }
        }
        .animation(.spring(duration: 0.35), value: model.banner)
        .task {
            model.bootstrap()
            await model.syncStrava()
        }
    }
}

/// Container + model factory used by the app, previews and the snapshot tool.
@MainActor
public enum AppEnvironment {
    public static func makeContainer(inMemory: Bool = false) throws -> ModelContainer {
        let schema = Schema([StoredRide.self, StoredWorkout.self])
        let config = ModelConfiguration(schema: schema, isStoredInMemoryOnly: inMemory)
        return try ModelContainer(for: schema, configurations: [config])
    }

    /// Opens the store; if it cannot be opened (e.g. after an incompatible schema change in a sideloaded build),
    /// moves the old files aside and starts fresh instead of crashing. Rides re-sync from Strava.
    public static func makeContainerRecovering() -> ModelContainer {
        if let container = try? makeContainer() { return container }
        let support = URL.applicationSupportDirectory
        let fm = FileManager.default
        let stamp = Int(Date.now.timeIntervalSince1970)
        for name in ["default.store", "default.store-shm", "default.store-wal"] {
            let url = support.appendingPathComponent(name)
            if fm.fileExists(atPath: url.path) {
                try? fm.moveItem(at: url, to: support.appendingPathComponent("\(name).broken-\(stamp)"))
            }
        }
        if let container = try? makeContainer() { return container }
        return try! makeContainer(inMemory: true)
    }

    public static func makeModel(container: ModelContainer) -> AppModel {
        AppModel(context: container.mainContext, secrets: KeychainSecretStore())
    }

    /// Fully in-memory demo model (no Keychain, no persistent defaults).
    public static func makePreviewModel() -> (ModelContainer, AppModel) {
        let container = try! makeContainer(inMemory: true)
        let defaults = UserDefaults(suiteName: "preview-\(UUID().uuidString)")!
        let model = AppModel(context: container.mainContext, secrets: InMemorySecretStore(), defaults: defaults)
        model.bootstrap()
        return (container, model)
    }
}
