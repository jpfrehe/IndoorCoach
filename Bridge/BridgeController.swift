import AppKit
import IndoorCoachKit
import Observation
import ServiceManagement

enum PairingState: Equatable {
    case idle
    case active(code: String, until: Date)
    case paired(device: String)
    case expired
    case failed(String)
}

/// Result of looking into the chosen folder (setup window).
enum FolderCheck: Equatable {
    case found(Int)
    case empty
}

@Observable @MainActor
final class BridgeController {
    // MARK: Observable state
    private(set) var folderState: BridgeFolderState = .none
    private(set) var folderURL: URL?
    private(set) var folderCheck: FolderCheck?
    private(set) var rideCount = 0
    private(set) var latestRide: BridgeRide?
    private(set) var pairedDeviceName: String?
    private(set) var lastFetch: Date?
    private(set) var serverRunning = false
    private(set) var serverError: String?
    /// Set when the secret could not be stored (release build without keychain access): pairing would not survive a restart.
    private(set) var secretStorageError: String?
    private(set) var pairing: PairingState = .idle
    private(set) var launchAtLogin = false
    private(set) var launchAtLoginError: String?
    /// True when MyWhoosh's container directory does not seem to exist (hint in the setup window).
    private(set) var myWhooshMissing = false

    let launchOptions: BridgeLaunchOptions
    let needsSetupOnLaunch: Bool

    // MARK: Internals
    private let defaults = UserDefaults.standard
    private let keychain = Keychain(service: "app.indoorcoach.bridge", dataProtection: true)
    private let bookmarks = SecurityScopedBookmarks()
    private let outbox: BridgeOutbox
    private var scanner = RideFolderScanner()
    private var server: BridgeServer?
    private var secret: Data?
    private var scopedURL: URL?
    private var scanTask: Task<Void, Never>?
    private var serverTask: Task<Void, Never>?
    private var pairingTask: Task<Void, Never>?
    private var lastPrune = Date.distantPast
    private var started = false

    private enum Key {
        static let bookmark = "folderBookmark"
        static let pairedDevice = "pairedDeviceName"
        static let lastFetch = "lastFetchDate"
        static let loginConfigured = "launchAtLoginConfigured"
        static let debugSecret = "debug.bridgeSecret"
    }

    init() {
        #if DEBUG
        launchOptions = BridgeLaunchOptions.parse(.standard)
        #else
        launchOptions = BridgeLaunchOptions()
        #endif
        let support = URL.applicationSupportDirectory.appending(path: "IndoorCoach Brücke/Outbox", directoryHint: .isDirectory)
        try? FileManager.default.createDirectory(at: support, withIntermediateDirectories: true)
        outbox = BridgeOutbox(directory: support)
        pairedDeviceName = defaults.string(forKey: Key.pairedDevice)
        lastFetch = defaults.object(forKey: Key.lastFetch) as? Date
        needsSetupOnLaunch = !launchOptions.skipSetup && launchOptions.folder == nil && defaults.data(forKey: Key.bookmark) == nil
    }

    // MARK: Lifecycle

    func start() {
        guard !started else { return }
        started = true
        myWhooshMissing = !FileManager.default.fileExists(atPath: RideFolderScanner.myWhooshFolder(home: RealHome.url()).deletingLastPathComponent().path)
        activateFolder()
        refreshOutboxInfo()
        configureLoginItem()
        secret = loadOrCreateSecret()
        startServer()
        if let code = launchOptions.pairingCode { Task { await startPairing(code: code) } }
        scanTask = Task { [weak self] in
            while !Task.isCancelled {
                await self?.scan()
                try? await Task.sleep(for: .seconds(20))
            }
        }
        Log.notice(.bridge, "Brücke gestartet: Ordner \(folderStateName), \(rideCount) Fahrten im Ausgang")
    }

    private var folderStateName: String {
        switch folderState {
        case .none: "nicht gewählt"
        case .ready: "bereit"
        case .needsReshare: "neu freigeben"
        }
    }

    // MARK: Status

    var statusLine: BridgeStatusLine {
        BridgeFormat.statusLine(BridgeStatusInput(folder: folderState, pairedDeviceName: pairedDeviceName, rideCount: rideCount,
                                                  lastFetch: lastFetch, serverError: serverError ?? secretStorageError))
    }

    var needsAttention: Bool { folderState != .ready || serverError != nil || secretStorageError != nil }

    var menuSymbol: String { needsAttention ? "exclamationmark.triangle" : "figure.indoor.cycle" }

    var latestRideText: String? {
        latestRide.map { BridgeFormat.rideLabel(start: $0.startDate, durationSeconds: $0.durationSeconds) }
    }

    // MARK: Folder

    private func activateFolder() {
        stopScopedAccess()
        if let debugFolder = launchOptions.folder {
            folderURL = debugFolder
            folderState = .ready
            return
        }
        switch FolderBookmark.resolve(bookmark: defaults.data(forKey: Key.bookmark), using: bookmarks) {
        case .none:
            folderURL = nil
            folderState = .none
        case .needsReshare:
            folderURL = nil
            folderState = .needsReshare
        case let .accessible(url, refreshed):
            if url.startAccessingSecurityScopedResource() { scopedURL = url }
            if let refreshed { defaults.set(refreshed, forKey: Key.bookmark) }
            folderURL = url
            folderState = FileManager.default.isReadableFile(atPath: url.path) ? .ready : .needsReshare
        }
    }

    private func stopScopedAccess() {
        scopedURL?.stopAccessingSecurityScopedResource()
        scopedURL = nil
    }

    /// Shows the open panel (pre-filled with MyWhoosh's folder) and stores the choice.
    func chooseFolder() {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.allowsMultipleSelection = false
        panel.canCreateDirectories = false
        panel.showsHiddenFiles = true
        panel.prompt = "Freigeben"
        panel.message = "Wähle den Ordner mit deinen Fahrten (FIT-Dateien). macOS fragt dich eventuell, ob die Brücke auf Daten anderer Apps zugreifen darf – das ist nötig, um MyWhoosh zu lesen."
        let myWhoosh = RideFolderScanner.myWhooshFolder(home: RealHome.url())
        panel.directoryURL = FileManager.default.fileExists(atPath: myWhoosh.path) ? myWhoosh : RealHome.url()
        NSApp.activate()
        guard panel.runModal() == .OK, let url = panel.url else { return }
        adoptFolder(url)
    }

    private func adoptFolder(_ url: URL) {
        guard let data = try? bookmarks.makeBookmark(for: url) else {
            folderState = .needsReshare
            Log.error(.bridge, "Lesezeichen für den Ordner konnte nicht erstellt werden")
            return
        }
        defaults.set(data, forKey: Key.bookmark)
        scanner = RideFolderScanner()
        activateFolder()
        let count = folderURL.map { RideFolderScanner.listFITFiles(in: $0).count } ?? 0
        folderCheck = count > 0 ? .found(count) : .empty
        Log.notice(.bridge, "Ordner freigegeben: \(count) FIT-Dateien gefunden")
        Task {
            await scan()
            // The scanner needs two identical listings; run the second one right away for a quick first import.
            try? await Task.sleep(for: .seconds(2))
            await scan()
        }
    }

    // MARK: Scanning

    private func scan() async {
        if folderState == .needsReshare { activateFolder() }
        guard folderState == .ready, let folder = folderURL else { return }
        let listing = RideFolderScanner.listFITFiles(in: folder)
        if listing.isEmpty, !FileManager.default.isReadableFile(atPath: folder.path), launchOptions.folder == nil {
            folderState = .needsReshare
            return
        }
        let ready = scanner.ready(listing, now: .now)
        if !ready.isEmpty {
            let outbox = self.outbox
            let added = await Task.detached(priority: .utility) { () -> Int in
                var added = 0
                for file in ready where file.size <= 50 * 1024 * 1024 {   // a ride file is 1–2 MB; skip anything absurd
                    guard let data = try? Data(contentsOf: file.url) else { continue }
                    if (try? outbox.add(fit: data)) != nil { added += 1 }
                }
                return added
            }.value
            Log.notice(.bridge, "Scan: \(ready.count) neue Dateien, \(added) übernommen")
        }
        if Date.now.timeIntervalSince(lastPrune) > 24 * 3600 {
            lastPrune = .now
            let outbox = self.outbox
            await Task.detached(priority: .utility) { outbox.prune() }.value
        }
        refreshOutboxInfo()
    }

    private func refreshOutboxInfo() {
        rideCount = outbox.count
        latestRide = outbox.latest
    }

    // MARK: Server

    private func loadOrCreateSecret() -> Data {
        if let existing = keychain.data(.bridgeSecret), existing.count == 32 { return existing }
        #if DEBUG
        // Unsigned debug builds have no data-protection keychain: keep the secret in the defaults so pairing
        // survives restarts during development. Release builds are signed and never take this path.
        if let existing = defaults.data(forKey: Key.debugSecret), existing.count == 32 { return existing }
        #endif
        let fresh = BridgeCrypto.newPairingSecret()
        storeSecret(fresh)
        return fresh
    }

    private func storeSecret(_ secret: Data) {
        if keychain.set(secret, for: .bridgeSecret) { secretStorageError = nil; return }
        #if DEBUG
        defaults.set(secret, forKey: Key.debugSecret)
        Log.notice(.bridge, "Schlüsselbund nicht verfügbar (unsignierter Debug-Build) – Geheimnis in den Einstellungen")
        #else
        Log.error(.bridge, "Schlüsselbund nicht verfügbar – Geheimnis nur im Speicher")
        secretStorageError = "Schlüsselbund nicht verfügbar – nach einem Neustart musst du dein iPhone neu koppeln."
        #endif
    }

    private func makeServer() -> BridgeServer? {
        if let server { return server }
        guard let secret else { return nil }
        let name = Host.current().localizedName ?? "Mac"
        let server = BridgeServer(name: name, secret: secret, source: outbox)
        server.onEvent = { [weak self] event in
            Task { @MainActor in self?.handle(event) }
        }
        self.server = server
        return server
    }

    private func startServer() {
        serverTask?.cancel()
        guard let server = makeServer() else { return }
        serverTask = Task { [weak self] in
            var delay = 2
            while !Task.isCancelled {
                do {
                    try await server.start()
                    self?.serverRunning = true
                    self?.serverError = nil
                    Log.notice(.bridge, "Server läuft")
                    return
                } catch {
                    self?.serverRunning = false
                    self?.serverError = Self.describe(error)
                    Log.error(.bridge, "Server-Start fehlgeschlagen (\(type(of: error))), neuer Versuch in \(delay) s")
                }
                try? await Task.sleep(for: .seconds(delay))
                delay = min(delay * 2, 60)
            }
        }
    }

    private static func describe(_ error: Error) -> String {
        if let bridge = error as? BridgeError, bridge == .notImplemented {
            return "Die Übertragung ist in dieser Version noch nicht verfügbar."
        }
        return "Die Brücke konnte nicht gestartet werden. Ich versuche es gleich noch einmal."
    }

    private func handle(_ event: BridgeServer.Event) {
        switch event.kind {
        case .paired:
            pairedDeviceName = event.deviceName
            defaults.set(event.deviceName, forKey: Key.pairedDevice)
            pairingTask?.cancel()
            pairing = .paired(device: event.deviceName)
            Log.notice(.bridge, "iPhone gekoppelt")
        case .connected:
            break
        case let .listed(count):
            noteContact(event.deviceName)
            Log.notice(.bridge, "iPhone hat \(count) Fahrten abgefragt")
        case .fetched:
            noteContact(event.deviceName)
            Log.notice(.bridge, "iPhone hat eine Fahrt abgeholt")
        }
    }

    private func noteContact(_ device: String) {
        lastFetch = .now
        defaults.set(lastFetch, forKey: Key.lastFetch)
        if pairedDeviceName == nil {
            pairedDeviceName = device
            defaults.set(device, forKey: Key.pairedDevice)
        }
    }

    // MARK: Pairing

    func startPairing(code: String? = nil) async {
        let code = code ?? launchOptions.pairingCode ?? BridgeCrypto.generatePairingCode()
        guard let server = makeServer() else {
            pairing = .failed("Die Brücke ist noch nicht bereit.")
            return
        }
        do {
            try await server.startPairing(code: code)
        } catch {
            pairing = .failed(Self.describe(error))
            Log.error(.bridge, "Kopplung konnte nicht gestartet werden (\(type(of: error)))")
            return
        }
        let until = Date.now.addingTimeInterval(300)
        pairing = .active(code: code, until: until)
        Log.notice(.bridge, "Kopplungsfenster geöffnet")
        pairingTask?.cancel()
        pairingTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(300))
            guard !Task.isCancelled, let self else { return }
            if case .active = pairing {
                server.stopPairing()
                pairing = .expired
            }
        }
    }

    func cancelPairing() {
        pairingTask?.cancel()
        server?.stopPairing()
        pairing = .idle
    }

    /// Asks for confirmation, then replaces the secret: all paired phones have to pair again.
    func resetPairing() {
        let alert = NSAlert()
        alert.messageText = "Kopplung zurücksetzen?"
        alert.informativeText = "Alle gekoppelten iPhones müssen danach neu gekoppelt werden."
        alert.addButton(withTitle: "Zurücksetzen")
        alert.addButton(withTitle: "Abbrechen")
        NSApp.activate()
        guard alert.runModal() == .alertFirstButtonReturn else { return }
        let fresh = BridgeCrypto.newPairingSecret()
        storeSecret(fresh)
        secret = fresh
        server?.updateSecret(fresh)
        pairedDeviceName = nil
        lastFetch = nil
        defaults.removeObject(forKey: Key.pairedDevice)
        defaults.removeObject(forKey: Key.lastFetch)
        pairing = .idle
        Log.notice(.bridge, "Kopplung zurückgesetzt")
    }

    // MARK: Login item

    private func configureLoginItem() {
        if !defaults.bool(forKey: Key.loginConfigured), launchOptions.folder == nil {
            defaults.set(true, forKey: Key.loginConfigured)
            setLaunchAtLogin(true)
        }
        launchAtLogin = SMAppService.mainApp.status == .enabled
    }

    func setLaunchAtLogin(_ enabled: Bool) {
        do {
            if enabled { try SMAppService.mainApp.register() } else { try SMAppService.mainApp.unregister() }
            launchAtLoginError = nil
        } catch {
            launchAtLoginError = "Das automatische Starten ließ sich nicht ändern. Du kannst es in den Systemeinstellungen unter „Allgemein › Anmeldeobjekte“ einstellen."
            Log.error(.bridge, "Anmeldeobjekt: \(type(of: error))")
        }
        launchAtLogin = SMAppService.mainApp.status == .enabled
    }
}
