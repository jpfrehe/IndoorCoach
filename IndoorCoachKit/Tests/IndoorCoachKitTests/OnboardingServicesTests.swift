import Foundation
import SwiftData
import Testing
@testable import IndoorCoachKit

/// docs/20-KONZEPT-ONBOARDING-DIENSTE.md §9 / AP2: Zustand der Dienst-Auswahl, Schritt-Migration, Zusammenfassung, intervals.icu-Fehler.
@MainActor
@Suite("Onboarding · Dienste")
struct OnboardingServicesTests {
    let container = try! AppEnvironment.makeContainer(inMemory: true)
    let defaults = UserDefaults(suiteName: "onboarding-services-\(UUID().uuidString)")!
    let secrets = InMemorySecretStore()

    func makeModel(transport: HTTPTransport = MockTransport([]), clientID: String = "",
                   store: MyWhooshSessionStore = InMemoryMyWhooshSessionStore()) -> AppModel {
        AppModel(context: container.mainContext, secrets: secrets, defaults: defaults, transport: transport,
                 myWhooshStore: store, intervalsConfig: IntervalsConfig(clientID: clientID))
    }

    // MARK: Persistenz

    @Test func servicesStateIsPersistedAndResumed() {
        let first = makeModel()
        #expect(first.onboardingServices == OnboardingServicesState())
        first.onboardingServices.answers = ServiceAnswers(rideApps: [.myWhoosh, .zwift], myWhooshDevice: .mac,
                                                          extras: [.appleWatch], showAll: false)
        first.onboardingServices.deferred = [.appleHealth, .macBridge]
        first.onboardingServices.stravaAfterwards = true
        let second = makeModel()
        #expect(second.onboardingServices == first.onboardingServices)
        #expect(second.onboardingServices.answers.rideApps == [.myWhoosh, .zwift])
        #expect(second.onboardingServices.deferred == [.appleHealth, .macBridge])
        #expect(second.onboardingServices.stravaAfterwards)
    }

    @Test func corruptStoredStateFallsBackToEmpty() {
        defaults.set(Data("kein json".utf8), forKey: AppModel.Keys.onboardingServices)
        #expect(makeModel().onboardingServices == OnboardingServicesState())
    }

    @Test func servicesStateSurvivesCompletingOnboarding() {
        let model = makeModel()
        model.onboardingServices.answers.rideApps = [.zwift]
        model.completeOnboarding()
        #expect(model.onboardingServices.answers.rideApps == [.zwift])
        #expect(makeModel().onboardingServices.answers.rideApps == [.zwift])
    }

    @Test func newKeysAreRegisteredForWiping() {
        #expect(AppModel.Keys.all.contains(AppModel.Keys.onboardingServices))
        #expect(AppModel.Keys.all.contains(AppModel.Keys.onboardingStep))
        #expect(AppModel.Keys.onboardingStep == "onboarding.step.v3")
        #expect(AppModel.Keys.onboardingServices == "onboarding.services.v1")
        #expect(!AppModel.Keys.all.contains("onboarding.step.v2"))
    }

    @Test func deleteAllDataResetsTheServicesState() async {
        let model = makeModel()
        model.onboardingServices.answers.rideApps = [.rouvy]
        model.onboardingServices.stravaAfterwards = true
        await model.deleteAllData()
        #expect(model.onboardingServices == OnboardingServicesState())
        #expect(defaults.object(forKey: AppModel.Keys.onboardingServices) == nil)
        #expect(defaults.object(forKey: AppModel.Keys.onboardingStep) == nil)
    }

    // MARK: Schritt-Migration v2 → v3

    @Test(arguments: [(0, 0), (1, 1), (2, 2), (3, 5), (4, 6)])
    func stepV2IsMigrated(v2: Int, v3: Int) {
        #expect(AppModel.migratedStep(v2: v2) == v3)
        defaults.set(v2, forKey: "onboarding.step.v2")
        #expect(makeModel().onboardingStep == v3)
    }

    @Test func migrationIgnoresMissingOrUnknownValues() {
        #expect(AppModel.migratedStep(v2: nil) == nil)
        #expect(AppModel.migratedStep(v2: -1) == nil)
        #expect(AppModel.migratedStep(v2: 5) == nil)
        defaults.set(42, forKey: "onboarding.step.v2")
        #expect(makeModel().onboardingStep == 0)
    }

    @Test func v2KeyIsRemovedAfterMigration() {
        defaults.set(3, forKey: "onboarding.step.v2")
        let model = makeModel()
        #expect(model.onboardingStep == 5)
        #expect(defaults.object(forKey: "onboarding.step.v2") == nil)
        #expect(defaults.integer(forKey: AppModel.Keys.onboardingStep) == 5)
        #expect(makeModel().onboardingStep == 5)   // zweiter Start: kein erneutes Umrechnen
    }

    @Test func v3WinsWhenBothKeysExist() {
        defaults.set(3, forKey: "onboarding.step.v2")
        defaults.set(1, forKey: AppModel.Keys.onboardingStep)
        #expect(makeModel().onboardingStep == 1)
        #expect(defaults.object(forKey: "onboarding.step.v2") == nil)
    }

    @Test func storedStepIsClamped() {
        #expect(AppModel.onboardingStepCount == 7)
        defaults.set(99, forKey: AppModel.Keys.onboardingStep)
        #expect(makeModel().onboardingStep == 6)
        defaults.set(-4, forKey: AppModel.Keys.onboardingStep)
        #expect(makeModel().onboardingStep == 0)
        let model = makeModel()
        model.onboardingStep = 12
        #expect(model.onboardingStep == 6)
    }

    @Test func existingInstallThatFinishedV1NeverSeesTheNewFlow() {
        defaults.set(true, forKey: AppModel.Keys.onboardingCompleted)
        defaults.set(3, forKey: "onboarding.step.v2")   // Rest einer alten Version
        #expect(!makeModel().needsOnboarding)
    }

    // MARK: Verfügbarkeit und Empfehlungen

    @Test func recommendationsFollowAvailability() {
        let plain = makeModel()
        plain.onboardingServices.answers = ServiceAnswers(rideApps: [.zwift])
        #expect(!plain.serviceAvailability.intervalsOAuth)
        #expect(!plain.serviceRecommendations.contains { $0.id == .intervalsICU })
        #expect(plain.serviceRecommendations.first { $0.id == .fitImport }?.tier == .optional)

        let withClient = makeModel(clientID: "cid-77")
        withClient.onboardingServices.answers = ServiceAnswers(rideApps: [.zwift])
        #expect(withClient.serviceAvailability.intervalsOAuth)
        #expect(withClient.serviceRecommendations.first { $0.id == .intervalsICU }?.tier == .recommended)
    }

    @Test func healthAvailabilityComesFromTheHealthSource() {
        let model = makeModel()
        model.healthSource = StubHealthDataSource(isAvailable: false)
        model.onboardingServices.answers = ServiceAnswers(extras: [.appleWatch])
        #expect(!model.serviceAvailability.health)
        #expect(!model.serviceRecommendations.contains { $0.id == .appleHealth })
        model.healthSource = StubHealthDataSource(isAvailable: true)
        #expect(model.serviceAvailability.health)
        #expect(model.serviceRecommendations.first { $0.id == .appleHealth }?.tier == .recommended)
    }

    @Test func bridgeAvailabilityComesFromTheDownloadURL() throws {
        let model = makeModel()
        model.onboardingServices.answers = ServiceAnswers(rideApps: [.myWhoosh], myWhooshDevice: .mac)
        #expect(AppConfig.bridgeDownloadURL == nil)   // Info.plist-Schlüssel ist leer (E1)
        #expect(model.bridgeDownloadURL == nil && !model.serviceAvailability.bridgeDownload)
        #expect(!model.serviceRecommendations.contains { $0.id == .macBridge })
        model.bridgeDownloadURLOverride = try #require(URL(string: "https://example.invalid/bridge"))
        #expect(model.serviceAvailability.bridgeDownload)
        #expect(model.serviceRecommendations.first { $0.id == .macBridge }?.tier == .recommended)
    }

    // MARK: AppConfig.bridgeDownloadURL

    @Test(arguments: [(nil, nil), ("", nil), ("   ", nil), ("nicht gültig", nil), ("http://example.com/bridge.dmg", nil),
                      ("ftp://example.com/b", nil), ("https://", nil), ("javascript:alert(1)", nil),
                      ("https://github.com/jpfrehe/IndoorCoach/releases/latest", "https://github.com/jpfrehe/IndoorCoach/releases/latest"),
                      ("  https://example.com/b.dmg \n", "https://example.com/b.dmg"), ("HTTPS://example.com/b", "HTTPS://example.com/b")] as [(String?, String?)])
    func bridgeDownloadURLAcceptsOnlyHTTPS(raw: String?, expected: String?) {
        #expect(AppConfig.bridgeDownloadURL(from: raw)?.absoluteString == expected)
    }

    // MARK: intervals.icu · Fehler und Rückgabe

    private func oauthStub(tokenStatus: Int = 200) -> RoutingTransport {
        RoutingTransport { request in
            switch request.url?.path ?? "" {
            case "/api/oauth/token" where tokenStatus == 200:
                return (200, Data(#"{"access_token":"tok-OAUTH-123456","scope":"ACTIVITY:READ,CALENDAR:WRITE","athlete":{"id":"i9","name":"Oskar"}}"#.utf8))
            case "/api/oauth/token": return (tokenStatus, Data("{}".utf8))
            case "/api/v1/athlete/0/activities": return (200, Data("[]".utf8))
            default: return (200, Data("[]".utf8))
            }
        }
    }

    private func callback(for url: URL) -> URL {
        let state = URLComponents(url: url, resolvingAgainstBaseURL: false)!.queryItems!.first { $0.name == "state" }!.value!
        return URL(string: "indoorcoach://localhost/intervals?code=CODE1&state=\(state)")!
    }

    @Test func connectingReportsSuccess() async {
        let model = makeModel(transport: oauthStub(), clientID: "cid-77")
        let ok = await model.connectIntervals { callback(for: $0) }
        #expect(ok && model.isIntervalsConnected && model.lastIntervalsError == nil)
    }

    @Test func intervalsErrorIsKeptForTheForm() async {
        let model = makeModel(transport: oauthStub(tokenStatus: 401), clientID: "cid-77")
        let ok = await model.connectIntervals { callback(for: $0) }
        #expect(!ok && !model.isIntervalsConnected)
        #expect(model.lastIntervalsError?.isEmpty == false)
        #expect(model.banner?.isError == true)
        // Der nächste Versuch löscht den alten Text.
        let model2 = makeModel(transport: oauthStub(), clientID: "cid-77")
        model2.lastIntervalsError = "alt"
        #expect(await model2.connectIntervals { callback(for: $0) })
        #expect(model2.lastIntervalsError == nil)
    }

    @Test func missingClientIDIsAnErrorForTheForm() async {
        let model = makeModel()
        #expect(await model.connectIntervals { _ in URL(string: "indoorcoach://x")! } == false)
        #expect(model.lastIntervalsError == IntervalsError.notConfigured.localizedDescription)
    }

    @Test func stateMismatchIsAnError() async {
        let model = makeModel(transport: oauthStub(), clientID: "cid-77")
        let ok = await model.connectIntervals { _ in URL(string: "indoorcoach://localhost/intervals?code=C&state=FALSCH")! }
        #expect(!ok && model.lastIntervalsError == IntervalsError.stateMismatch.localizedDescription)
    }

    /// Abbruch durch die Nutzerin (ASWebAuthenticationSession `.canceledLogin`, Task-Abbruch) ist kein Fehler.
    @Test(arguments: [0, 1])
    func cancellingTheWebSignInShowsNoError(kind: Int) async {
        let model = makeModel(transport: oauthStub(), clientID: "cid-77")
        let ok = await model.connectIntervals { _ in
            if kind == 0 { throw NSError(domain: "com.apple.AuthenticationServices.WebAuthenticationSession", code: 1) }
            throw CancellationError()
        }
        #expect(!ok && !model.isIntervalsConnected)
        #expect(model.lastIntervalsError == nil && model.banner == nil)
    }

    @Test func otherWebAuthErrorsStayVisible() async {
        let model = makeModel(transport: oauthStub(), clientID: "cid-77")
        // Code 2 = presentationContextNotProvided: ein echter Fehler.
        let ok = await model.connectIntervals { _ in throw NSError(domain: "com.apple.AuthenticationServices.WebAuthenticationSession", code: 2) }
        #expect(!ok && model.lastIntervalsError != nil)
    }

    @Test func apiKeyFailureAlsoFillsTheErrorAndReturnsFalse() async {
        let model = makeModel(transport: RoutingTransport { _ in (401, Data("{}".utf8)) })
        #expect(await model.connectIntervals(apiKey: "falsch-123456") == false)
        #expect(model.lastIntervalsError?.isEmpty == false)
    }

    // MARK: Zusammenfassung v2

    private func signedInStore() -> InMemoryMyWhooshSessionStore {
        let store = InMemoryMyWhooshSessionStore()
        store.saveSession(MyWhooshSession(username: "rider@example.com", whooshId: "w", accessToken: "a.b.c", refreshToken: ""))
        return store
    }

    @Test func summaryListsChosenServices() {
        let model = makeModel(store: signedInStore())
        model.healthSource = StubHealthDataSource()
        model.onboardingServices.answers = ServiceAnswers(rideApps: [.myWhoosh], extras: [.appleWatch])
        model.onboardingServices.deferred = [.appleHealth]
        let services = model.onboardingSummary.services
        #expect(services.map(\.id) == [.myWhoosh, .appleHealth])
        guard case .connected(let detail) = services[0].state else { Issue.record("MyWhoosh nicht verbunden"); return }
        #expect(detail.hasPrefix("Verbunden"))
        #expect(services[1].state == .later)
    }

    @Test func summaryOmitsUntouchedUnrecommendedServices() {
        let model = makeModel()
        model.healthSource = StubHealthDataSource()
        model.onboardingServices.answers = ServiceAnswers(rideApps: [.none], extras: [.none])
        #expect(model.onboardingSummary.services.isEmpty)
        // Empfohlen, aber nicht angefasst: steht in der Liste, noch nicht verbunden.
        model.onboardingServices.answers = ServiceAnswers(extras: [.heartStrap])
        #expect(model.onboardingSummary.services.map(\.id) == [.strap])
        #expect(model.onboardingSummary.services.first?.state == .notConnected)
        // Nur optional und nicht angefasst: fehlt.
        model.onboardingServices.answers = ServiceAnswers(rideApps: [.other])
        #expect(model.onboardingSummary.services.isEmpty)
        // Optional und „Später“: erscheint.
        model.onboardingServices.deferred = [.fitImport]
        #expect(model.onboardingSummary.services.map(\.id) == [.fitImport])
    }

    @Test func summaryNeverShowsStravaAsAServiceLine() {
        let model = makeModel()
        model.onboardingServices.answers = ServiceAnswers(extras: [.strava])
        model.onboardingServices.stravaAfterwards = true
        #expect(model.onboardingSummary.services.isEmpty)
        #expect(model.onboardingSummary.stravaAfterwards)
        model.onboardingServices.stravaAfterwards = false
        #expect(!model.onboardingSummary.stravaAfterwards)
    }

    @Test func connectedServiceAppearsEvenWhenNotRecommended() {
        let model = makeModel(store: signedInStore())
        model.onboardingServices.answers = ServiceAnswers(rideApps: [.zwift])   // MyWhoosh wäre nur „more“
        #expect(model.onboardingSummary.services.map(\.id) == [.myWhoosh])
    }

    @Test func summaryLabelsAreSpokenGerman() {
        let connected = OnboardingSummary.ServiceLine(id: .myWhoosh, name: "MyWhoosh", hubName: "MyWhoosh",
                                                      state: .connected("Verbunden · 23 Fahrten geladen"))
        #expect(connected.accessibilityLabel == "MyWhoosh: Verbunden · 23 Fahrten geladen")
        let later = OnboardingSummary.ServiceLine(id: .macBridge, name: "Fahrten im Detail vom Mac", hubName: "Sekundendaten vom Mac",
                                                  state: .later)
        #expect(later.visualDetail == "Später unter Profil → Dienste & Geräte → Sekundendaten vom Mac")
        #expect(later.accessibilityLabel == "Fahrten im Detail vom Mac: später unter Profil, Dienste und Geräte, Sekundendaten vom Mac")
        let open = OnboardingSummary.ServiceLine(id: .strap, name: "Brustgurt", hubName: "Brustgurt", state: .notConnected)
        #expect(open.visualDetail == later.visualDetail.replacingOccurrences(of: "Sekundendaten vom Mac", with: "Brustgurt"))
        // Die drei alten Zeilen bleiben unverändert.
        #expect(makeModel().onboardingSummary.items.map(\.title) == ["Profil", "MyWhoosh", "Coach"])
    }

    @Test func serviceLineNamesMatchTheIntroWording() {
        let model = makeModel()
        model.healthSource = StubHealthDataSource()
        model.bridgeDownloadURLOverride = URL(string: "https://example.invalid/bridge")
        model.onboardingServices.answers = ServiceAnswers(rideApps: [.myWhoosh], myWhooshDevice: .mac)
        let line = model.onboardingSummary.services.first { $0.id == .macBridge }
        #expect(line?.name == "Fahrten im Detail vom Mac")
        #expect(line?.hubName == "Sekundendaten vom Mac")
    }

    // MARK: Debug-Hooks (reines Parsen)

    #if DEBUG
    /// `-uiIntervalsStubLogin YES` (und `…Fails`): Web-Anmeldung und Token-Endpunkt kommen aus dem Stub, kein Netz.
    @Test(arguments: [false, true])
    func intervalsStubLoginHookWorksEndToEnd(fails: Bool) async {
        let transport = JourneyStubTransport(stubLogin: false, stubClaude: false, stubIntervals: true, intervalsFails: fails)
        let model = makeModel(transport: transport, clientID: "stub-client")
        var asked = false
        model.intervalsWebAuthOverride = { url in
            asked = true
            let state = URLComponents(url: url, resolvingAgainstBaseURL: false)!.queryItems!.first { $0.name == "state" }!.value!
            return URL(string: "\(IntervalsConfig.defaultRedirectURI)?code=stub&state=\(state)")!
        }
        // Das übergebene Web-Auth (die echte Sitzung) wird nicht benutzt, solange der Stub gesetzt ist.
        let ok = await model.connectIntervals { _ in Issue.record("echte Web-Anmeldung aufgerufen"); throw CancellationError() }
        #expect(asked && ok == !fails)
        #expect(model.isIntervalsConnected == !fails)
        #expect((model.lastIntervalsError != nil) == fails)
        if !fails { #expect(model.intervalsAthleteName == "Tobias") }
    }

    @Test func uiTestAnswersAreParsed() {
        let parsed = ServiceAnswers.parseUITest("rides=myWhoosh,zwift;device=mac;extras=appleWatch,heartStrap")
        #expect(parsed == ServiceAnswers(rideApps: [.myWhoosh, .zwift], myWhooshDevice: .mac, extras: [.appleWatch, .heartStrap]))
        #expect(ServiceAnswers.parseUITest("showAll=true;rides=none").showAll)
        #expect(ServiceAnswers.parseUITest("rides=unbekannt,rouvy;device=;foo=bar;extras=").rideApps == [.rouvy])
        #expect(ServiceAnswers.parseUITest("") == ServiceAnswers())
    }
    #endif
}
