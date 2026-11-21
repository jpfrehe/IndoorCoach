import Foundation
import SwiftData
import Testing
@testable import IndoorCoachKit

/// Schaltbarer Antwortcode für den RoutingTransport (erst Fehler, dann Erfolg).
private final class Switch: @unchecked Sendable {
    private let lock = NSLock()
    private var code: Int
    init(_ code: Int) { self.code = code }
    var value: Int {
        get { lock.withLock { code } }
        set { lock.withLock { code = newValue } }
    }
}

private func jwt(exp: Date) -> String {
    func b64(_ s: String) -> String {
        Data(s.utf8).base64EncodedString().replacingOccurrences(of: "=", with: "")
            .replacingOccurrences(of: "+", with: "-").replacingOccurrences(of: "/", with: "_")
    }
    return b64(#"{"alg":"HS256"}"#) + "." + b64(#"{"exp":\#(Int(exp.timeIntervalSince1970))}"#) + ".sig"
}

@MainActor
@Suite("Verbindungsstatus")
struct ConnectionStatusTests {
    let container: ModelContainer
    let defaults: UserDefaults
    let secrets = InMemorySecretStore()
    let whooshStore = InMemoryMyWhooshSessionStore()
    let strap = StrapSession(controller: StubStrapController(autoplay: false))
    fileprivate let httpCode = Switch(200)
    let model: AppModel

    init() throws {
        container = try AppEnvironment.makeContainer(inMemory: true)
        defaults = UserDefaults(suiteName: "conn-\(UUID().uuidString)")!
        let code = httpCode
        model = AppModel(context: container.mainContext, secrets: secrets, defaults: defaults,
                         transport: RoutingTransport { request in
                             if request.url?.host?.contains("strava") == true { return (code.value, Data("[]".utf8)) }
                             return (code.value, Data(#"{"data":{"activities":[]}}"#.utf8))
                         },
                         myWhooshStore: whooshStore)
    }

    func connectStrava(lastSync: Date? = nil) {
        model.stravaClientID = "123"
        secrets.setSecret("secret", for: .stravaClientSecret)
        secrets.saveTokens(StravaTokens(accessToken: "a", refreshToken: "r", expiresAt: .distantFuture, athleteName: "Lena Test"))
        model.lastSync = lastSync
        model.refreshCredentialState()
    }

    func signInWhoosh(expiresIn: TimeInterval) {
        whooshStore.saveSession(MyWhooshSession(username: "rider@example.com", whooshId: "w",
                                                accessToken: jwt(exp: .now.addingTimeInterval(expiresIn)), refreshToken: ""))
        model.refreshCredentialState()
    }

    func status(_ id: ConnectionID) -> ConnectionStatus { model.connection(id, strap: strap).status }

    // MARK: Beschreibung

    @Test func descriptorsListEveryServiceWithRolesAndNames() {
        let all = model.connections(strap: strap)
        #expect(all.map(\.id) == ConnectionID.allCases)
        #expect(model.connection(.myWhoosh, strap: strap).rolesText == "Fahrten · Pläne")
        #expect(model.connection(.macBridge, strap: strap).roles == [.secondData])
        #expect(ConnectionRole.heartRate.label == "Puls" && ConnectionRole.secondData.label == "Sekundendaten")
        #expect(ConnectionStatus.notConnected.label == "Nicht verbunden")
        #expect(ConnectionStatus.needsSetup("Erneut verbinden").label == "Erneut verbinden")
        #expect(ConnectionStatus.error("x").label == "Fehler")
    }

    // MARK: Strava

    @Test func stravaWithoutSetupIsNotConnected() {
        #expect(status(.strava) == .notConnected)
        #expect(model.connectionsNeedingAttention == 0)
    }

    @Test func stravaConnectedCarriesNameAndLastSync() {
        let sync = Date(timeIntervalSince1970: 1_794_000_000)
        connectStrava(lastSync: sync)
        #expect(status(.strava) == .connected(detail: "Lena Test", lastSync: sync))
        #expect(model.connectionsNeedingAttention == 0)
    }

    @Test func stravaLostAccessAfterSyncNeedsReconnect() {
        connectStrava(lastSync: .now)
        secrets.saveTokens(nil)
        model.refreshCredentialState()
        #expect(status(.strava) == .needsSetup("Erneut verbinden"))
        #expect(model.connectionsNeedingAttention == 1)
    }

    @Test func disconnectingOnPurposeIsNotAProblem() async {
        connectStrava(lastSync: .now)
        await model.disconnectStrava()
        #expect(status(.strava) == .notConnected)
        #expect(model.connectionsNeedingAttention == 0)
    }

    @Test func stravaSyncFailureSetsErrorAndBadgeThenSuccessClearsIt() async {
        connectStrava(lastSync: .now)
        httpCode.value = 401
        await model.syncStrava()
        #expect(model.syncErrors[.strava] != nil)
        guard case .error = status(.strava) else { Issue.record("erwartet .error"); return }
        #expect(model.connectionsNeedingAttention == 1)
        #expect(model.banner?.isError == true)

        httpCode.value = 200
        await model.syncStrava()
        #expect(model.syncErrors[.strava] == nil)
        guard case .connected = status(.strava) else { Issue.record("erwartet .connected"); return }
        #expect(model.connectionsNeedingAttention == 0)
    }

    @Test func stravaServerErrorSetsError() async {
        connectStrava(lastSync: .now)
        httpCode.value = 500
        await model.syncStrava()
        #expect(model.syncErrors[.strava]?.isEmpty == false)
    }

    @Test func disconnectingStravaClearsItsError() async {
        connectStrava(lastSync: .now)
        httpCode.value = 500
        await model.syncStrava()
        #expect(model.syncErrors[.strava] != nil)
        await model.disconnectStrava()
        #expect(model.syncErrors[.strava] == nil)
    }

    // MARK: MyWhoosh

    @Test func myWhooshSignedInIsConnected() {
        #expect(status(.myWhoosh) == .notConnected)
        signInWhoosh(expiresIn: 3600)
        #expect(status(.myWhoosh) == .connected(detail: "rider@example.com", lastSync: nil))
    }

    @Test func myWhooshExpiredSessionNeedsSignIn() {
        signInWhoosh(expiresIn: -60)
        #expect(status(.myWhoosh) == .needsSetup("Anmeldung abgelaufen"))
        #expect(model.connectionsNeedingAttention == 1)
    }

    @Test func myWhooshStatusUsesCachedExpiryNotTheKeychain() {
        signInWhoosh(expiresIn: 3600)
        #expect(model.myWhooshSessionExpiry != nil)
        // Store changes behind the model's back: the status must not read it again.
        whooshStore.saveSession(MyWhooshSession(username: "rider@example.com", whooshId: "w",
                                                accessToken: jwt(exp: .now.addingTimeInterval(-60)), refreshToken: ""))
        #expect(status(.myWhoosh) == .connected(detail: "rider@example.com", lastSync: nil))
        model.refreshCredentialState()
        #expect(status(.myWhoosh) == .needsSetup("Anmeldung abgelaufen"))
    }

    @Test func myWhooshExpiryIsClearedOnDisconnect() async {
        signInWhoosh(expiresIn: 3600)
        await model.disconnectMyWhoosh()
        #expect(model.myWhooshSessionExpiry == nil)
    }

    @Test func myWhooshImportFailureSetsErrorAndSuccessClearsIt() async {
        signInWhoosh(expiresIn: 3600)
        httpCode.value = 500
        await model.importMyWhooshRides(announce: true)
        #expect(model.syncErrors[.myWhoosh] != nil)
        #expect(model.connectionsNeedingAttention == 1)

        httpCode.value = 200
        await model.importMyWhooshRides(announce: true)
        #expect(model.syncErrors[.myWhoosh] == nil)
        #expect(model.connectionsNeedingAttention == 0)
    }

    @Test func disconnectingMyWhooshClearsItsError() async {
        signInWhoosh(expiresIn: 3600)
        httpCode.value = 500
        await model.importMyWhooshRides(announce: true)
        #expect(model.syncErrors[.myWhoosh] != nil)
        await model.disconnectMyWhoosh()
        #expect(model.syncErrors[.myWhoosh] == nil)
    }

    // MARK: Mac-Brücke

    @Test func bridgePairedAndUnpaired() {
        #expect(status(.macBridge) == .notConnected)
        secrets.setSecret("c2VjcmV0", for: .bridgeSecret)
        defaults.set("Lenas MacBook Air", forKey: AppModel.Keys.bridgeMacName)
        let sync = Date(timeIntervalSince1970: 1_794_000_000)
        defaults.set(sync, forKey: AppModel.Keys.bridgeLastSync)
        model.bridge.load(defaults: defaults)
        #expect(status(.macBridge) == .connected(detail: "Lenas MacBook Air", lastSync: sync))
        model.unpairBridge()
        #expect(status(.macBridge) == .notConnected)
    }

    @Test func bridgeFailureSetsErrorAndSuccessClearsIt() async throws {
        let transport = FakeBridgeTransport()
        model.bridge.transport = transport
        let mac = try #require(await model.discoverBridges().first)
        _ = try await model.pairBridge(mac, code: "482913")
        #expect(model.isBridgePaired)

        transport.failure = .authenticationFailed
        _ = await model.syncFromBridge(announce: true)
        #expect(model.syncErrors[.macBridge] != nil)
        #expect(model.connectionsNeedingAttention == 1)

        transport.failure = nil
        _ = await model.syncFromBridge(announce: true)
        #expect(model.syncErrors[.macBridge] == nil)
    }

    @Test func silentAutoRunSetsErrorOnlyForInvalidPairing() async throws {
        let transport = FakeBridgeTransport()
        model.bridge.transport = transport
        let mac = try #require(await model.discoverBridges().first)
        _ = try await model.pairBridge(mac, code: "482913")

        // „Mac nicht erreichbar“ ist vorübergehend: stiller Lauf, kein Fehlerstatus, kein Banner.
        transport.failure = .unreachable
        model.banner = nil
        model.bridge.lastAttempt = nil
        _ = await model.syncFromBridge(announce: false)
        #expect(model.syncErrors[.macBridge] == nil)
        #expect(model.banner == nil)

        // Ungültige Kopplung bleibt, bis man neu koppelt: Status ja, Banner nein.
        transport.failure = .authenticationFailed
        model.bridge.lastAttempt = nil
        _ = await model.syncFromBridge(announce: false)
        #expect(model.syncErrors[.macBridge]?.contains("Kopplung erneuern") == true)
        #expect(model.banner == nil)
        #expect(model.connectionsNeedingAttention == 1)

        // Ein späterer stiller „nicht erreichbar“-Lauf löscht den dauerhaften Fehler nicht.
        transport.failure = .unreachable
        model.bridge.lastAttempt = nil
        _ = await model.syncFromBridge(announce: false)
        #expect(model.syncErrors[.macBridge] != nil)

        // Kopplung lösen räumt den Fehler weg.
        model.unpairBridge()
        #expect(model.syncErrors[.macBridge] == nil)
        #expect(model.connectionsNeedingAttention == 0)
    }

    // MARK: Zähler „n verbunden“

    @Test func connectedServiceCountIgnoresFitImportAndUnavailable() {
        #expect(model.connectedServiceCount(strap: strap) == 0)
        signInWhoosh(expiresIn: 3600)
        strap.connect(UUID())
        #expect(model.connectedServiceCount(strap: strap) == 2)
        connectStrava(lastSync: .now)
        #expect(model.connectedServiceCount(strap: strap) == 3)
        model.syncErrors[.strava] = "x"   // Fehler zählt nicht als verbunden
        #expect(model.connectedServiceCount(strap: strap) == 2)
    }

    @Test func profileRouteIsConsumedOnce() {
        #expect(model.pendingProfileRoute == nil)
        model.pendingProfileRoute = [.connections, .connection(.strava)]
        #expect(model.takePendingProfileRoute() == [.connections, .connection(.strava)])
        #expect(model.pendingProfileRoute == nil)
        #expect(model.takePendingProfileRoute() == nil)
    }

    // MARK: Health, Gurt, FIT

    @Test func healthIsNeverAProblem() {
        if model.healthAvailable {
            #expect(status(.appleHealth) == .notConnected)
        } else {
            #expect(status(.appleHealth) == .unavailable("Auf diesem Gerät nicht verfügbar"))
        }
        #expect(model.connectionsNeedingAttention == 0)
    }

    @Test func strapSavedIsConnectedOtherwiseNotConnected() {
        #expect(status(.strap) == .notConnected)
        strap.connect(UUID())
        guard case .connected = status(.strap) else { Issue.record("erwartet .connected"); return }
        #expect(model.connectionsNeedingAttention == 0)
    }

    @Test func fitImportIsAlwaysConnectedAndNeverNeedsAttention() {
        #expect(status(.fitImport) == .connected(detail: nil, lastSync: nil))
        model.syncErrors[.fitImport] = "egal"
        #expect(status(.fitImport) == .connected(detail: nil, lastSync: nil))
        #expect(model.connectionsNeedingAttention == 0)
    }

    @Test func notConnectedNeverCountsAsAttention() {
        #expect(ConnectionStatus.notConnected.needsAttention == false)
        #expect(ConnectionStatus.unavailable("x").needsAttention == false)
        #expect(ConnectionStatus.connected(detail: nil, lastSync: nil).needsAttention == false)
        #expect(ConnectionStatus.needsSetup("x").needsAttention && ConnectionStatus.error("x").needsAttention)
        #expect(model.connectionsNeedingAttention == 0)
    }
}
