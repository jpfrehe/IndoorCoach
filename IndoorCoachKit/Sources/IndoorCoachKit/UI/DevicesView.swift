import SwiftUI

/// Geräte → Brustgurt (B36): explanation before the Bluetooth prompt, search, connect, live pulse and the
/// device-test protocol (B26).
struct DevicesView: View {
    @State private var session = StrapSession.shared
    @AppStorage("strapExplainerSeen") private var explainerSeen = false
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.openURL) private var openURL

    var body: some View {
        Group {
            if explainerSeen || session.savedStrapID != nil {
                content
            } else {
                explainer
            }
        }
        .background(Theme.canvas)
        .navigationTitle("Brustgurt")
        .onAppear { session.setAppActive(scenePhase == .active) }
        .onChange(of: scenePhase) { _, phase in session.setAppActive(phase == .active) }
        .task {
            if explainerSeen || session.savedStrapID != nil { session.reconnectSaved() }
        }
    }

    // MARK: Explainer

    private var explainer: some View {
        VStack(spacing: 20) {
            Spacer()
            Image(systemName: "heart.circle.fill").font(.system(size: 64)).foregroundStyle(Theme.accent)
                .accessibilityHidden(true)
            Text("Nur dein Pulsgurt. Nichts verlässt das iPhone.").font(.title2.bold()).multilineTextAlignment(.center)
            Text("IndoorCoach nutzt Bluetooth ausschließlich, um einen Brustgurt mit Pulsmessung zu finden und seinen Puls zu lesen. Es werden keine anderen Geräte gesucht und nichts wird hochgeladen. Gleich fragt iOS einmal nach der Bluetooth-Erlaubnis.")
                .foregroundStyle(.secondary).multilineTextAlignment(.center)
            Button {
                explainerSeen = true
                session.startScan()
            } label: {
                Text("Weiter").frame(maxWidth: .infinity, minHeight: 44)
            }
            .buttonStyle(.borderedProminent)
            .accessibilityIdentifier("strap.explainer.continue")
            Spacer()
        }
        .padding(24)
    }

    // MARK: Content

    private var content: some View {
        Form {
            connectionSection
            if session.isConnected || session.state == .reconnecting { StrapDetailView(session: session) }
            else { searchSection }
            testSection
        }
        .scrollContentBackground(.hidden)
    }

    private var connectionSection: some View {
        Section {
            LabeledContent("Status") { Text(Self.statusText(session.state)).accessibilityIdentifier("strap.status") }
            if case .unavailable(let reason) = session.state {
                Text(Self.unavailableText(reason)).font(.footnote).foregroundStyle(.secondary)
                if reason == .unauthorized || reason == .bluetoothOff {
                    Button("Einstellungen öffnen") {
                        if let url = URL(string: "app-settings:") { openURL(url) }
                    }
                }
            }
        }
    }

    private var searchSection: some View {
        Section {
            Button {
                if session.state == .scanning { session.stopScan() } else { session.startScan() }
            } label: {
                Label(session.state == .scanning ? "Suche beenden" : "Gurt suchen", systemImage: "dot.radiowaves.left.and.right")
                    .frame(minHeight: 44)
            }
            .accessibilityIdentifier("strap.scan")
            ForEach(session.discovered) { strap in
                HStack {
                    VStack(alignment: .leading) {
                        Text(strap.name)
                        Text(Self.signalText(strap.rssi)).font(.footnote).foregroundStyle(.secondary)
                    }
                    Spacer()
                    Button("Verbinden") { session.connect(strap.id) }
                        .buttonStyle(.bordered)
                        .accessibilityIdentifier("strap.connect")
                }
                .frame(minHeight: 44)
            }
            if session.state == .scanning && session.discovered.isEmpty {
                HStack { ProgressView(); Text("Suche läuft …").foregroundStyle(.secondary) }
            }
        } header: { Text("Gurt suchen") } footer: {
            Text("Tipp: Gurt anfeuchten und anlegen, sonst sendet er oft nicht. Halte das iPhone nah heran. Gesucht wird nur, solange die App offen ist.")
        }
    }

    private var testSection: some View {
        Section {
            if session.protocolRunning {
                LabeledContent("Pakete", value: "\(session.protocolPackets)")
                LabeledContent("Lücken > 2 s", value: "\(session.protocolGaps)")
                LabeledContent("Reconnects", value: "\(session.protocolReconnects)")
                Button("Protokoll beenden", role: .destructive) { session.stopProtocol() }
                    .accessibilityIdentifier("strap.protocol.stop")
            } else {
                Button("Protokoll starten") { session.startProtocol() }
                    .disabled(!session.isConnected)
                    .accessibilityIdentifier("strap.protocol.start")
            }
            if !session.lastProtocolReport.isEmpty {
                Text(session.lastProtocolReport.joined(separator: "\n")).font(.footnote.monospaced())
            }
        } header: { Text("Gerätetest (für Entwickler/Pilot)") } footer: {
            Text("Zählt Pakete, Lücken über 2 Sekunden, Reconnects, RR-Pakete, Akku und App-Zustand. Das Ergebnis landet ohne Pulswerte im Diagnose-Export (Profil → Hilfe & Feedback).")
        }
    }

    // MARK: Text helpers

    static func statusText(_ state: StrapConnectionState) -> String {
        switch state {
        case .idle: "Nicht verbunden"
        case .scanning: "Suche läuft"
        case .connecting: "Verbinde …"
        case .connected: "Verbunden"
        case .reconnecting: "Verbindung weg, versuche erneut …"
        case .unavailable: "Nicht verfügbar"
        }
    }

    static func unavailableText(_ reason: StrapUnavailableReason) -> String {
        switch reason {
        case .bluetoothOff: "Bluetooth ist ausgeschaltet. Schalte es in den iPhone-Einstellungen oder im Kontrollzentrum ein."
        case .unauthorized: "IndoorCoach darf Bluetooth nicht nutzen. Erlaube es in den iPhone-Einstellungen unter IndoorCoach."
        case .unsupported: "Dieses Gerät unterstützt kein Bluetooth Low Energy."
        case .notFound: "Der gekoppelte Gurt wurde nicht gefunden. Gurt anfeuchten oder anlegen, Bluetooth prüfen und erneut verbinden."
        }
    }

    static func signalText(_ rssi: Int) -> String {
        switch rssi {
        case (-60)...: "Signal: stark"
        case (-75)...: "Signal: mittel"
        default: "Signal: schwach"
        }
    }
}
