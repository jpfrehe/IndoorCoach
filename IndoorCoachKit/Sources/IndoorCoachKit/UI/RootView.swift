import SwiftData
import SwiftUI

public enum AppTab: Hashable { case today, plan, history, profile }

public struct RootView: View {
    @Environment(AppModel.self) private var model
    @State private var tab: AppTab = RootView.initialTab
    @State private var showTour = false
    @State private var recordRequest: RecordingRequest?

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
            .badge(model.connectionsNeedingAttention)
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
        .onboardingCover(isPresented: model.needsOnboarding) { choice in
            model.completeOnboarding()
            switch choice {
            case .strava:
                tab = .profile
                model.pendingProfileRoute = [.connections, .connection(.strava)]
            case .tour:
                tab = .today
                // Let the onboarding cover finish dismissing before the next full-screen cover is presented.
                Task {
                    try? await Task.sleep(for: .milliseconds(700))
                    showTour = true
                }
            case .start, .skipped:
                tab = .today
            }
        }
        .tourCover(isPresented: $showTour)
        // ANCHOR-W3A: Aufzeichnung mit Gurt (Kraft, Andere Einheit) und unterbrochene Aufzeichnungen
        .interruptedRecordingPrompt()
        .strengthRecordAction { template in present(.strength(template: template)) }
        .otherRecordAction { sport in present(.other(sport: sport)) }
        .recordingCover(item: $recordRequest) { StrengthRecordingView(request: $0) }
        .task {
            model.bootstrap()
            #if DEBUG
            model.applyBridgeStubSeed()
            model.applyComplianceSeed()   // -uiComplianceSeed YES (after bootstrap: needs the demo rides)
            model.applyConnectionErrorSeed()   // -uiConnectionErrorSeed YES
            #endif
            await model.rescheduleWorkoutReminders()
            await model.syncRides()
            await model.syncFromBridge(announce: false)
        }
    }
}

extension RootView {
    /// Das Schnellstart-Sheet schließt sich gleichzeitig: erst danach das Vollbild zeigen.
    private func present(_ request: RecordingRequest) {
        Task {
            try? await Task.sleep(for: .milliseconds(500))
            recordRequest = request
        }
    }
}

#if DEBUG
/// Answers every request with a plausible success body (UI tests only).
struct StubTransport: HTTPTransport {
    func data(for request: URLRequest) async throws -> (Data, HTTPURLResponse) {
        try await Task.sleep(for: .milliseconds(300))
        let path = request.url?.path ?? ""
        let body = path.contains("task/create") ? #"{"status":true,"data":{"id":"stub-task"}}"#
            : path.contains("profile/activities") ? #"{"activities":[]}"# : #"{"message":"ok"}"#
        return (Data(body.utf8), HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!)
    }
}
#endif

extension View {
    /// Feature tour after onboarding ("Kurze Tour ansehen"); landing on Heute afterwards.
    func tourCover(isPresented: Binding<Bool>) -> some View {
        #if os(iOS)
        fullScreenCover(isPresented: isPresented) {
            FeatureTourView(context: .onboarding) { isPresented.wrappedValue = false }
        }
        #else
        sheet(isPresented: isPresented) {
            FeatureTourView(context: .onboarding) { isPresented.wrappedValue = false }
        }
        #endif
    }
}

#if DEBUG
/// UI-test transport for the onboarding journey (`-uiMyWhooshStubLogin YES`, `-uiClaudeStub YES`).
/// Stubbed services answer locally; everything else goes to the network.
struct JourneyStubTransport: HTTPTransport {
    var stubLogin: Bool
    var stubClaude: Bool
    var network: HTTPTransport = URLSessionTransport()

    func data(for request: URLRequest) async throws -> (Data, HTTPURLResponse) {
        let url = request.url!
        if stubClaude, url.host == "api.anthropic.com" {
            try await Task.sleep(for: .milliseconds(400))
            let key = request.value(forHTTPHeaderField: "x-api-key") ?? ""
            if url.path == "/v1/models", key.contains("sk-ant-test") {
                return reply(200, #"{"data":[{"type":"model","id":"stub-model","display_name":"Stub"}],"has_more":false}"#, url)
            }
            return reply(401, #"{"type":"error","error":{"type":"authentication_error","message":"invalid x-api-key"}}"#, url)
        }
        if stubLogin, url.host?.hasSuffix("mywhoosh.com") == true {
            try await Task.sleep(for: .milliseconds(600))
            if url.path.hasSuffix("/login") {
                // JWT-shaped (header.payload.signature, no `exp`), as MyWhooshClient.login expects.
                let token = "eyJhbGciOiJIUzI1NiJ9.eyJzdWIiOiJzdHViIn0.c3R1Yg"
                return reply(200, #"{"Success":true,"WhooshId":"stub-whoosh","AccessToken":"\#(token)","RefreshToken":"stub-refresh"}"#, url)
            }
            if url.path.contains("profile/activities") { return reply(200, Self.activities, url) }
            return reply(200, #"{"message":"ok"}"#, url)
        }
        return try await network.data(for: request)
    }

    private func reply(_ code: Int, _ body: String, _ url: URL) -> (Data, HTTPURLResponse) {
        (Data(body.utf8), HTTPURLResponse(url: url, statusCode: code, httpVersion: nil, headerFields: nil)!)
    }

    /// Three rides on different days (list values only, no FIT file).
    private static var activities: String {
        let iso = ISO8601DateFormatter()
        let rides = [(2, 3600, 32.0, 190), (5, 2700, 24.0, 165), (9, 4500, 41.0, 205)].map { days, seconds, km, watts in
            #"{"id":"stub-\#(days)","name":"Stub-Fahrt","startDatetime":"\#(iso.string(from: .now.addingTimeInterval(-Double(days) * 86_400)))","rideDuration":\#(seconds),"distance":\#(km),"watt":\#(watts)}"#
        }
        return #"{"activities":[\#(rides.joined(separator: ","))]}"#
    }
}
#endif

/// Container + model factory used by the app, previews and the snapshot tool.
@MainActor
public enum AppEnvironment {
    public static func makeContainer(inMemory: Bool = false) throws -> ModelContainer {
        // One schema for app, tests and previews (Persistence.swift); a second list here once dropped StoredCheckIn.
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
        #if DEBUG
        // UI-test hook: `-uiMyWhooshStub YES` simulates a signed-in MyWhoosh account with canned answers,
        // so the connected flow can be checked without real servers or credentials.
        if UserDefaults.standard.bool(forKey: "uiMyWhooshStub") {
            let store = InMemoryMyWhooshSessionStore()
            store.saveSession(MyWhooshSession(username: "test@example.com", whooshId: "stub", accessToken: "stub", refreshToken: ""))
            return AppModel(context: container.mainContext, secrets: KeychainSecretStore(),
                            transport: StubTransport(), myWhooshStore: store)
        }
        // UI-test hook for the Mac bridge: `-uiBridgeStub YES` pairs with a fake Mac "Lenas MacBook Air" (code 482913).
        if UserDefaults.standard.bool(forKey: "uiBridgeStub") {
            let model = AppModel(context: container.mainContext, secrets: InMemorySecretStore(), transport: StubTransport(),
                                 myWhooshStore: InMemoryMyWhooshSessionStore())
            model.installBridgeStub()
            return model
        }
        // End-to-end hook: `-uiBridgeEndpoint host:mainPort:pairingPort` talks to a real bridge without Bonjour,
        // secrets in memory.
        if let endpoint = UserDefaults.standard.string(forKey: "uiBridgeEndpoint") {
            let model = AppModel(context: container.mainContext, secrets: InMemorySecretStore(), transport: StubTransport(),
                                 myWhooshStore: InMemoryMyWhooshSessionStore())
            model.installDirectBridgeEndpoint(endpoint)
            return model
        }
        // UI-test hooks for the onboarding journey: `-uiMyWhooshStubLogin YES` (not signed in, any login works) and
        // `-uiClaudeStub YES` (`/v1/models`: 200 for keys containing "sk-ant-test", else 401). Both keep secrets
        // in memory, so nothing leaks into the simulator's Keychain between runs.
        let stubLogin = UserDefaults.standard.bool(forKey: "uiMyWhooshStubLogin")
        let stubClaude = UserDefaults.standard.bool(forKey: "uiClaudeStub")
        if stubLogin || stubClaude {
            return AppModel(context: container.mainContext, secrets: InMemorySecretStore(),
                            transport: JourneyStubTransport(stubLogin: stubLogin, stubClaude: stubClaude),
                            myWhooshStore: InMemoryMyWhooshSessionStore())
        }
        #endif
        return AppModel(context: container.mainContext, secrets: KeychainSecretStore())
    }

    /// Fully in-memory demo model (no Keychain, no persistent defaults).
    public static func makePreviewModel() -> (ModelContainer, AppModel) {
        let container = try! makeContainer(inMemory: true)
        let defaults = UserDefaults(suiteName: "preview-\(UUID().uuidString)")!
        defaults.set(true, forKey: AppModel.Keys.onboardingCompleted) // previews/snapshots show the app itself
        let model = AppModel(context: container.mainContext, secrets: InMemorySecretStore(), defaults: defaults,
                             myWhooshStore: InMemoryMyWhooshSessionStore())
        model.bootstrap()
        return (container, model)
    }
}
