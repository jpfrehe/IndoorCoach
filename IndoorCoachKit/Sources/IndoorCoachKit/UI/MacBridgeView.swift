import Network
import SwiftData
import SwiftUI
import UniformTypeIdentifiers

/// "Sekundendaten vom Mac": setup (three steps, find the Mac, enter the code) and, once paired, the status.
/// Docs: docs/14-SEKUNDENDATEN-MAC-BRUECKE.md, user journey steps 2, 4, 5 and 8.
struct MacBridgeView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @Query private var storedRides: [StoredRide]

    @State private var found: [DiscoveredBridge] = []
    @State private var searching = true
    @State private var selected: DiscoveredBridge?
    @State private var code = ""
    @State private var pairing = false
    @State private var errorText: String?
    @State private var result: BridgeSyncSummary?
    @State private var activeStep = 0
    @State private var confirmUnpair = false
    @State private var showFITImporter = false
    @FocusState private var codeFocused: Bool

    private static let steps: [(symbol: String, title: String, detail: String)] = [
        ("macbook", "IndoorCoach Brücke auf dem Mac öffnen", "Die kleine Mac-App läuft in der Menüleiste. Erlaube ihr den Zugriff aufs lokale Netzwerk."),
        ("folder.badge.plus", "MyWhoosh-Ordner freigeben", "Einmal bestätigen, damit die Brücke deine Fahrten lesen darf."),
        ("lock.open", "Code eingeben", "Der Mac zeigt einen 6-stelligen Code. Gib ihn hier ein.")
    ]

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                if model.isBridgePaired {
                    pairedCard
                } else {
                    intro
                    stepsCard
                    macsCard
                }
                importFooter
            }
            .padding()
        }
        .background(Theme.canvas)
        .navigationTitle("Mac-Brücke")
        .inlineNavigationTitle()
        .fileImporter(isPresented: $showFITImporter, allowedContentTypes: [.data], allowsMultipleSelection: true) { result in
            if case .success(let urls) = result { model.importFITFiles(urls) }
        }
        .confirmationDialog("Kopplung lösen?", isPresented: $confirmUnpair, titleVisibility: .visible) {
            Button("Kopplung lösen", role: .destructive) { model.unpairBridge() }
        } message: {
            Text("Dein iPhone holt dann keine Fahrten mehr vom Mac. Bereits geladene Fahrten bleiben erhalten.")
        }
        .task(id: model.isBridgePaired) { await animateSteps() }
        .task(id: model.isBridgePaired) { await keepSearching() }
    }

    // MARK: Setup

    private var intro: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Volle Leistungskurve für jede Fahrt").font(.title3.weight(.semibold))
            Text("MyWhoosh speichert jede Fahrt sekundengenau auf deinem Mac. Die IndoorCoach Brücke bringt sie ins WLAN, dein iPhone holt sie automatisch ab. Es verlässt nichts dein Heimnetz.")
                .font(.subheadline).foregroundStyle(Theme.rowSecondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .accessibilityElement(children: .combine)
    }

    private var stepsCard: some View {
        Card(title: "So richtest du es ein", systemImage: "list.number") {
            VStack(alignment: .leading, spacing: 14) {
                ForEach(Array(Self.steps.enumerated()), id: \.offset) { index, step in
                    stepRow(index: index, step: step)
                }
            }
        }
        .accessibilityIdentifier("bridge.steps")
    }

    private func stepRow(index: Int, step: (symbol: String, title: String, detail: String)) -> some View {
        let active = index == activeStep
        let layout = dynamicTypeSize.isAccessibilitySize ? AnyLayout(VStackLayout(alignment: .leading, spacing: 8))
                                                          : AnyLayout(HStackLayout(alignment: .top, spacing: 12))
        return layout {
            Image(systemName: step.symbol)
                .font(.title2)
                .symbolEffect(.bounce, options: .nonRepeating, isActive: active && !reduceMotion)
                .symbolEffect(.pulse, isActive: active && !reduceMotion)
                .foregroundStyle(active ? Theme.ink : Theme.accent)
                .frame(width: 44, height: 44)
                .background(active ? AnyShapeStyle(Theme.sunset) : AnyShapeStyle(Theme.softFill), in: Circle())
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 2) {
                Text("\(index + 1). \(step.title)").font(.subheadline.weight(.semibold))
                    .fixedSize(horizontal: false, vertical: true)
                Text(step.detail).font(.footnote).foregroundStyle(Theme.rowSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .combine)
    }

    private var macsCard: some View {
        Card(title: selected == nil ? "Gefundene Macs" : "Code eingeben", systemImage: "wifi") {
            if let mac = selected {
                codeEntry(for: mac)
            } else if found.isEmpty {
                HStack(spacing: 10) {
                    if searching { ProgressView() }
                    Text("Ich suche im WLAN … Öffne die IndoorCoach Brücke auf dem Mac und klicke auf „iPhone koppeln“. Nichts gefunden? Beide Geräte müssen im selben WLAN sein, und IndoorCoach braucht unter Einstellungen → Datenschutz → Lokales Netzwerk die Erlaubnis.")
                        .font(.subheadline).foregroundStyle(Theme.rowSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .accessibilityElement(children: .combine)
                .accessibilityIdentifier("bridge.searching")
            } else {
                VStack(spacing: 8) {
                    ForEach(Array(found.enumerated()), id: \.element.id) { index, mac in
                        Button { select(mac) } label: {
                            HStack(spacing: 12) {
                                Image(systemName: "macbook").font(.title3).accessibilityHidden(true)
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(mac.name).font(.body.weight(.semibold))
                                    Text("Tippe zum Koppeln").font(.caption).foregroundStyle(Theme.rowSecondary)
                                }
                                Spacer(minLength: 8)
                                Image(systemName: "chevron.right").font(.footnote.weight(.semibold))
                                    .foregroundStyle(Theme.rowSecondary).accessibilityHidden(true)
                            }
                            .padding(.vertical, 10).padding(.horizontal, 12)
                            .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
                            .background(Theme.softFill, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel("Mac „\(mac.name)“ koppeln")
                        .accessibilityIdentifier("bridge.mac.\(index)")
                    }
                }
            }
        }
    }

    private func codeEntry(for mac: DiscoveredBridge) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Gib den 6-stelligen Code ein, den „\(mac.name)“ gerade anzeigt.")
                .font(.subheadline).fixedSize(horizontal: false, vertical: true)
            HStack(spacing: 10) {
                TextField("000000", text: $code)
                    .font(.system(.title, design: .monospaced).weight(.semibold))
                    .numericKeyboard()
                    .credentialInput()
                    .focused($codeFocused)
                    .multilineTextAlignment(.center)
                    .padding(.vertical, 8)
                    .frame(minHeight: 52)
                    .background(Theme.softFill, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                    .disabled(pairing)
                    .accessibilityLabel("Code vom Mac")
                    .accessibilityIdentifier("bridge.code")
                    .onChange(of: code) { _, new in codeChanged(new, mac: mac) }
                if pairing { ProgressView() }
            }
            if let errorText {
                Label(errorText, systemImage: "exclamationmark.triangle.fill")
                    .font(.footnote).foregroundStyle(Theme.accent)
                    .fixedSize(horizontal: false, vertical: true)
                    .accessibilityIdentifier("bridge.error")
            }
            Button { selected = nil; code = ""; errorText = nil } label: {
                Text("Anderen Mac wählen").font(.footnote).frame(minHeight: 44)
            }
            .disabled(pairing)
        }
        .onAppear { codeFocused = true }
    }

    // MARK: Paired

    private var coverage: (measured: Int, total: Int) {
        (storedRides.filter { $0.powerCurveData != nil }.count, storedRides.count)
    }

    private var pairedCard: some View {
        let c = coverage
        return VStack(alignment: .leading, spacing: 16) {
            Card(title: "Gekoppelt", systemImage: "checkmark.seal.fill") {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Gekoppelt mit \(model.bridgeMacName ?? "Mac")").font(.headline)
                    if let result {
                        Text(Self.resultText(result)).font(.subheadline).foregroundStyle(Theme.rowSecondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
                .accessibilityElement(children: .combine)
                .accessibilityIdentifier("bridge.paired")

                LabeledContent("Zuletzt abgeholt") {
                    if let last = model.lastBridgeSync {
                        Text(last.formatted(.relative(presentation: .named).locale(Locale(identifier: "de_DE"))))
                    } else {
                        Text("noch nie")
                    }
                }
                .font(.subheadline)

                Label(c.total == 0 ? "Noch keine Fahrten." : "\(c.measured) von \(c.total) Fahrten mit Sekundendaten",
                      systemImage: "waveform.path.ecg")
                    .font(.subheadline)
                    .fixedSize(horizontal: false, vertical: true)
                    .accessibilityIdentifier("bridge.coverage")

                Button {
                    Task { result = nil; await model.syncFromBridge(announce: true) }
                } label: {
                    HStack(spacing: 8) {
                        if model.bridgeSyncing { ProgressView() }
                        Text(model.bridgeSyncing ? "Hole Fahrten …" : "Jetzt abholen")
                    }
                    .frame(maxWidth: .infinity)
                }
                .buttonStyle(.jelly)
                .disabled(model.bridgeSyncing)
                .accessibilityIdentifier("bridge.syncNow")

                Button(role: .destructive) { confirmUnpair = true } label: {
                    Text("Kopplung lösen").frame(minHeight: 44)
                }
                .accessibilityIdentifier("bridge.unpair")
            }
            Text("Neue Fahrten holt dein iPhone automatisch ab, sobald du die App öffnest und der Mac im selben WLAN ist.")
                .font(.footnote).foregroundStyle(Theme.rowSecondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    static func resultText(_ r: BridgeSyncSummary) -> String {
        if r.received == 0 { return "Es lagen noch keine Fahrten bereit." }
        var parts = ["\(r.received) \(r.received == 1 ? "Fahrt" : "Fahrten") übertragen"]
        if r.enriched > 0 { parts.append("\(r.enriched) bestehende ergänzt") }
        return parts.joined(separator: ", ")
    }

    // MARK: Footer

    private var importFooter: some View {
        Button { showFITImporter = true } label: {
            Text("Kein Mac? FIT-Datei importieren")
                .font(.footnote.weight(.semibold))
                .frame(maxWidth: .infinity, minHeight: 44)
        }
        .accessibilityIdentifier("bridge.importFIT")
    }

    // MARK: Actions

    private func select(_ mac: DiscoveredBridge) {
        selected = mac
        code = ""
        errorText = nil
    }

    private func codeChanged(_ new: String, mac: DiscoveredBridge) {
        let digits = String(new.filter(\.isNumber).prefix(6))
        if digits != new { code = digits; return }
        if !digits.isEmpty { errorText = nil }
        if digits.count == 6, !pairing { Task { await pair(mac, code: digits) } }
    }

    private func pair(_ mac: DiscoveredBridge, code: String) async {
        pairing = true
        defer { pairing = false }
        do {
            result = try await model.pairBridge(mac, code: code)
            selected = nil
            self.code = ""
        } catch let error as BridgeError {
            self.code = ""
            switch error {
            case .authenticationFailed: errorText = "Der Code stimmt nicht. Schau noch einmal auf den Mac – er gilt nur 5 Minuten."
            case .unreachable: errorText = AppModel.bridgeUnreachableMessage
            default: errorText = "Das Koppeln hat nicht geklappt. Versuche es noch einmal."
            }
        } catch {
            self.code = ""
            errorText = "Das Koppeln hat nicht geklappt. Versuche es noch einmal."
        }
    }

    /// Highlights step 1 → 2 → 3 in turn (static with Reduce Motion).
    private func animateSteps() async {
        guard !reduceMotion, !model.isBridgePaired else { return }
        while !Task.isCancelled {
            try? await Task.sleep(for: .seconds(2.4))
            withAnimation(.snappy) { activeStep = (activeStep + 1) % Self.steps.count }
        }
    }

    /// Looks for Macs that currently show a code, as long as the screen is visible and nothing is selected.
    private func keepSearching() async {
        guard !model.isBridgePaired else { return }
        while !Task.isCancelled {
            if selected == nil {
                searching = true
                let list = await model.discoverBridges()
                if !Task.isCancelled, selected == nil { found = list }
                searching = false
            }
            try? await Task.sleep(for: .seconds(2))
        }
    }
}
