import SwiftUI

/// Morgenmessung (B54): 60 s liegend mit Brustgurt. Zeigt am Ende nur den Trend, nie einen Tageswert.
struct MorningMeasurementView: View {
    var session: StrapSession = .shared
    var onFinished: () -> Void = {}
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss

    private enum Phase: Equatable {
        case ready, measuring
        case done(MorningHRV.DiscardReason?)
    }

    @State private var phase: Phase = .ready
    @State private var elapsed: TimeInterval = 0
    @State private var rr: [Double] = []
    @State private var observer: UUID?
    @State private var task: Task<Void, Never>?
    @State private var store = MorningHRVStore()
    @State private var message = ""

    var body: some View {
        NavigationStack {
            VStack(spacing: 24) {
                switch phase {
                case .ready: ready
                case .measuring: measuring
                case .done(let reason): result(reason)
                }
                Spacer(minLength: 0)
            }
            .padding(24)
            .background(Theme.canvas)
            .navigationTitle("Morgenmessung")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    if phase != .measuring { Button("Schließen") { close() }.accessibilityIdentifier("morning.close") }
                }
            }
        }
        .interactiveDismissDisabled(phase == .measuring)
        .onDisappear { stop() }
    }

    // MARK: Phasen

    private var ready: some View {
        VStack(spacing: 16) {
            Text("60 Sekunden liegend, ruhig atmen, nicht sprechen. Leg das Handy beiseite.")
                .font(.body)
            if !session.isConnected {
                Text("Der Gurt ist nicht verbunden. Lege ihn an, dann verbindet er sich von selbst.")
                    .font(.footnote).foregroundStyle(.secondary)
                    .accessibilityIdentifier("morning.notConnected")
            } else if session.contact == .notDetected {
                Text("Kein Hautkontakt. Gurt anfeuchten und enger anlegen.").font(.footnote).foregroundStyle(.orange)
            }
            Button { start() } label: { Text("Messung starten").frame(maxWidth: .infinity, minHeight: 44) }
                .buttonStyle(.borderedProminent)
                .disabled(!session.isConnected)
                .accessibilityIdentifier("morning.start")
            Text("3× pro Woche reicht.").font(.footnote).foregroundStyle(.secondary)
        }
        .onAppear { session.reconnectSaved() }
    }

    private var measuring: some View {
        VStack(spacing: 20) {
            ZStack {
                Circle().stroke(Color.secondary.opacity(0.2), lineWidth: 12)
                Circle().trim(from: 0, to: MorningHRV.progress(elapsed: elapsed))
                    .stroke(Theme.accent, style: StrokeStyle(lineWidth: 12, lineCap: .round))
                    .rotationEffect(.degrees(-90))
                Text("\(max(0, Int((MorningHRV.duration - elapsed).rounded(.up)))) s")
                    .font(.system(size: 44, weight: .semibold, design: .rounded).monospacedDigit())
                    .accessibilityIdentifier("morning.countdown")
            }
            .frame(width: 200, height: 200)
            .accessibilityElement(children: .combine)
            .accessibilityLabel("Messung läuft")
            .accessibilityValue("\(Int(MorningHRV.progress(elapsed: elapsed) * 100)) Prozent")
            Text("Atme ruhig und gleichmäßig. Bleib liegen.").font(.headline)
            Button("Abbrechen", role: .cancel) { cancel() }
                .buttonStyle(.bordered)
                .accessibilityIdentifier("morning.cancel")
        }
    }

    @ViewBuilder
    private func result(_ reason: MorningHRV.DiscardReason?) -> some View {
        VStack(spacing: 16) {
            if let reason {
                Image(systemName: "arrow.counterclockwise").font(.largeTitle).foregroundStyle(.secondary)
                Text("Messung nicht verwertbar").font(.headline)
                Text(reason == .lowQuality
                     ? "Das Signal war zu unruhig. Gurt anfeuchten, enger anlegen und ruhig liegen. Dann versuch es noch einmal."
                     : "Es kamen zu wenige Herzschläge an. Gurt anfeuchten, auf Hautkontakt achten und ruhig liegen.")
                    .font(.subheadline).multilineTextAlignment(.center)
                    .accessibilityIdentifier("morning.discarded")
                Button("Nochmal messen") { phase = .ready }
                    .buttonStyle(.bordered)
                    .accessibilityIdentifier("morning.retry")
            } else {
                Image(systemName: "checkmark.circle").font(.largeTitle).foregroundStyle(Theme.accent)
                Text("Messung gespeichert").font(.headline)
                Text("Quelle: gemessen (Gurt)").font(.caption).foregroundStyle(.secondary)
                Text(message).font(.subheadline).multilineTextAlignment(.center)
                    .accessibilityIdentifier("morning.result")
                Button("Fertig") { close() }
                    .buttonStyle(.borderedProminent)
                    .accessibilityIdentifier("morning.done")
            }
        }
    }

    // MARK: Ablauf

    private func start() {
        rr = []
        elapsed = 0
        phase = .measuring
        observer = session.addObserver { event in
            if case .measurement(let m, _) = event { rr.append(contentsOf: m.rrIntervalsMs) }
        }
        let began = Date()
        task = Task {
            while !Task.isCancelled, elapsed < MorningHRV.duration {
                try? await Task.sleep(for: .milliseconds(250))
                elapsed = min(Date().timeIntervalSince(began), MorningHRV.duration)
            }
            if !Task.isCancelled { finish() }
        }
    }

    private func finish() {
        let collected = rr
        stop()
        switch MorningHRV.evaluate(rr: collected, now: .now) {
        case .discarded(let reason):
            phase = .done(reason)
        case .valid(let measurement):
            store.save(measurement)
            let list = store.measurements()
            if let trend = MorningHRV.trend(list, now: .now) {
                message = trend.status.text
            } else {
                let missing = MorningHRV.measurementsUntilTrend(list, now: .now)
                message = missing == 1 ? "Noch 1 Messung bis zum Trend." : "Noch \(missing) Messungen bis zum Trend."
            }
            onFinished()
            phase = .done(nil)
        }
    }

    private func cancel() {
        stop()
        rr = []
        phase = .ready
    }

    private func stop() {
        task?.cancel()
        task = nil
        if let observer { session.removeObserver(observer) }
        observer = nil
    }

    private func close() {
        stop()
        dismiss()
    }
}

/// Kompakte Zeile auf „Heute“: nur wenn aktiviert, heute noch nicht gemessen und vor 11 Uhr.
struct MorningMeasurementRow: View {
    @AppStorage(MorningHRVStore.enabledKey) private var enabled = false
    @State private var showSheet = false
    @State private var refresh = 0

    var body: some View {
        let _ = refresh
        if enabled, MorningHRVStore().isDue() {
            Button { showSheet = true } label: {
                Label("Morgenmessung", systemImage: "waveform.path.ecg")
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .buttonStyle(.soft)
            .accessibilityIdentifier("morning.row")
            .sheet(isPresented: $showSheet) {
                MorningMeasurementView(onFinished: { refresh += 1 })
            }
        }
    }
}

/// Abschnitt im Gurt-Detail: Erklärung und Schalter (nur wenn der Gurt RR liefert).
struct MorningMeasurementSettings: View {
    let session: StrapSession
    @AppStorage(MorningHRVStore.enabledKey) private var enabled = false

    var body: some View {
        Section {
            Text("Einmal am Morgen 60 Sekunden liegend messen. Du siehst nur einen Trend über mehrere Tage, keinen Tageswert und keine Ampel. 3× pro Woche reicht. Die Messung bleibt auf dem iPhone.")
                .font(.footnote).foregroundStyle(.secondary)
            if session.rrSeen || enabled {
                Toggle("Morgenmessung", isOn: $enabled)
                    .accessibilityIdentifier("morning.toggle")
            } else {
                Text("Dieser Gurt liefert noch keine RR-Intervalle. Warte einen Moment mit angelegtem Gurt.")
                    .font(.footnote).foregroundStyle(.orange)
            }
        } header: { Text("Morgenmessung (HRV)") }
    }
}
