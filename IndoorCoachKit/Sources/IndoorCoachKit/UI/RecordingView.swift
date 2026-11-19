import SwiftUI

/// B39: full-screen recording with the strap on the iPhone. For `.ride` with a start-sync button and the plan timeline;
/// for `.strength` / `.other` generic (time, pulse, stop) with a slot for the caller's content (e.g. the exercise list).
public struct RecordingView<Content: View>: View {
    var kind: RecordingKind
    var title: String
    var plannedWorkoutID: UUID?
    var definition: WorkoutDefinition?
    var service: RecordingService
    var onFinish: ((RecordingResult) -> Void)?
    @ViewBuilder var content: Content

    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    @State private var confirmStop = false
    @State private var outcome: RecordingOutcome?
    @State private var result: RecordingResult?

    public init(kind: RecordingKind, title: String, plannedWorkoutID: UUID? = nil, definition: WorkoutDefinition? = nil,
                service: RecordingService = .shared, onFinish: ((RecordingResult) -> Void)? = nil,
                @ViewBuilder content: () -> Content) {
        self.kind = kind
        self.title = title
        self.plannedWorkoutID = plannedWorkoutID
        self.definition = definition
        self.service = service
        self.onFinish = onFinish
        self.content = content()
    }

    public var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    if let result {
                        RecordingResultCard(result: result, outcome: outcome)
                    } else if service.isRunning {
                        running
                    } else {
                        ready
                    }
                    content
                }
                .padding(.horizontal)
                .padding(.bottom, 24)
            }
            .background(Theme.canvas)
            .navigationTitle(service.isRunning ? service.title : title)
            .inlineNavigationTitle()
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    if !service.isRunning {
                        Button(result == nil ? "Abbrechen" : "Fertig") { dismiss() }
                            .accessibilityIdentifier("recording.close")
                    }
                }
            }
            .confirmationDialog("Aufzeichnung beenden?", isPresented: $confirmStop, titleVisibility: .visible) {
                Button("Beenden und speichern", role: .destructive) { finish() }
                    .accessibilityIdentifier("recording.stop.confirm")
                Button("Weiter aufzeichnen", role: .cancel) {}
            } message: {
                Text("Die Pulsspur wird gespeichert und, bei einer Radeinheit, der passenden Fahrt zugeordnet.")
            }
        }
        .accessibilityIdentifier("recording.screen")
        .onAppear { if !service.isRunning { StrapSession.shared.reconnectSaved() } }
    }

    // MARK: Ready

    @ViewBuilder
    private var ready: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text(title).font(.largeTitle.weight(.bold))
            ConnectionRow(service: service, strap: StrapSession.shared)
            if service.lowBattery {
                Label("Der Akku des Gurts ist unter 20 %. Für diese Einheit besser vorher tauschen oder laden.",
                      systemImage: "battery.25percent")
                    .font(.subheadline).foregroundStyle(.orange)
                    .accessibilityIdentifier("recording.battery")
            }
            if kind == .ride {
                Text("Starte zuerst die Einheit in MyWhoosh. Tippe auf den Knopf, sobald MyWhoosh losläuft – so liegen Puls und Fahrt zeitlich übereinander.")
                    .font(.subheadline).foregroundStyle(Theme.rowSecondary)
            }
            Button {
                service.start(kind: kind, title: title, plannedWorkoutID: plannedWorkoutID, definition: definition)
            } label: {
                Text(kind == .ride ? "Los, wenn MyWhoosh startet" : "Start").frame(maxWidth: .infinity)
            }
            .buttonStyle(.jelly)
            .accessibilityIdentifier("recording.start")
        }
        .padding(.top, 8)
    }

    // MARK: Running

    @ViewBuilder
    private var running: some View {
        VStack(alignment: .leading, spacing: 16) {
            if let startedAt = service.startedAt {
                Text(startedAt, style: .timer)
                    .font(.system(size: 44, weight: .semibold).monospacedDigit())
                    .accessibilityLabel("Dauer")
                    .accessibilityIdentifier("recording.elapsed")
            }
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text(service.heartRate.map(String.init) ?? "–")
                    .font(.system(size: 96, weight: .bold, design: .rounded).monospacedDigit())
                    .minimumScaleFactor(0.5)
                Text("bpm").font(.title3).foregroundStyle(Theme.rowSecondary)
            }
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(service.heartRate.map { "Puls \($0) Schläge pro Minute" } ?? "Kein Pulssignal")
            .accessibilityIdentifier("recording.pulse")
            ConnectionRow(service: service, strap: StrapSession.shared)
            if kind == .ride, !service.plan.isEmpty { PlanTimeline(service: service, ftp: model.profile.ftp) }
            Button(role: .destructive) { confirmStop = true } label: {
                Label("Stopp", systemImage: "stop.fill").frame(maxWidth: .infinity)
            }
            .buttonStyle(.soft)
            .accessibilityIdentifier("recording.stop")
        }
        .padding(.top, 8)
    }

    private func finish() {
        guard let stopped = service.stop() else { return }
        outcome = model.finishRecording(stopped)
        result = stopped
        onFinish?(stopped)
    }
}

extension RecordingView where Content == EmptyView {
    public init(kind: RecordingKind, title: String, plannedWorkoutID: UUID? = nil, definition: WorkoutDefinition? = nil,
                service: RecordingService = .shared, onFinish: ((RecordingResult) -> Void)? = nil) {
        self.init(kind: kind, title: title, plannedWorkoutID: plannedWorkoutID, definition: definition, service: service,
                  onFinish: onFinish) { EmptyView() }
    }
}

// MARK: - Parts

private struct ConnectionRow: View {
    var service: RecordingService
    var strap: StrapSession

    var body: some View {
        let connected = service.isRunning ? service.connected : strap.isConnected
        Label {
            VStack(alignment: .leading, spacing: 2) {
                Text(connected ? "Gurt verbunden" : "Gurt nicht verbunden – suche …").font(.subheadline.weight(.semibold))
                if service.isRunning, service.reconnects > 0 {
                    Text("\(service.reconnects)× neu verbunden").font(.caption).foregroundStyle(Theme.rowSecondary)
                }
            }
        } icon: {
            Image(systemName: connected ? "heart.circle.fill" : "heart.slash.circle")
                .foregroundStyle(connected ? Theme.done : .orange)
        }
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier("recording.connection")
    }
}

private struct PlanTimeline: View {
    var service: RecordingService
    var ftp: Int

    var body: some View {
        let plan = service.plan
        let total = max(1, plan.last?.end ?? 1)
        let now = RecordingPlan.current(in: plan, elapsed: service.elapsed)
        Card(title: "Plan", systemImage: "list.bullet") {
            if let now {
                HStack(alignment: .firstTextBaseline) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(now.block.title).font(.title3.weight(.semibold))
                        if let f = now.block.fraction, ftp > 0 {
                            Text("Ziel \(Int((f * Double(ftp)).rounded())) W").font(.subheadline).foregroundStyle(Theme.rowSecondary)
                        }
                    }
                    Spacer()
                    Text(Formatters.clock(now.remaining)).font(.title2.monospacedDigit().weight(.semibold))
                }
                .accessibilityElement(children: .combine)
                .accessibilityIdentifier("recording.block")
                if now.index + 1 < plan.count {
                    Text("Danach: \(plan[now.index + 1].title)").font(.footnote).foregroundStyle(Theme.rowSecondary)
                }
            } else {
                Text(service.elapsed >= total ? "Plan zu Ende – noch ausrollen, dann Stopp." : "Plan startet gleich.")
                    .font(.subheadline)
            }
            ProgressView(value: Double(min(service.elapsed, total)), total: Double(total))
                .accessibilityLabel("Fortschritt im Plan")
        }
    }
}

private extension Formatters {
    static func clock(_ seconds: Int) -> String { String(format: "%d:%02d", seconds / 60, seconds % 60) }
}

// MARK: - Result

/// What the recording means after the stop: where it went, time in pulse zones, TRIMP, warm-up check and the hint
/// that watts-based analyses need real power.
public struct RecordingResultCard: View {
    var result: RecordingResult
    var outcome: RecordingOutcome?
    @Environment(AppModel.self) private var model

    public init(result: RecordingResult, outcome: RecordingOutcome?) {
        self.result = result
        self.outcome = outcome
    }

    public var body: some View {
        let zones = ZoneTime.compute(result.seconds, ftp: model.profile.ftp, heartRate: model.heartRateZones())
        let trimp = RelativeEffort.trimp(seconds: result.seconds, heartRate: model.profile.heartRateProfile)
        VStack(alignment: .leading, spacing: 16) {
            Text("Aufzeichnung gespeichert").font(.largeTitle.weight(.bold))
            Text(Formatters.duration(Int(result.duration)) + (result.reconnects > 0 ? " · \(result.reconnects)× neu verbunden" : "")
                 + (result.gapSeconds > 0 ? " · \(result.gapSeconds) s ohne Puls" : ""))
                .font(.headline).foregroundStyle(.secondary)
            if result.kind == .ride { rideStatus }
            if let heart = zones.heart, zones.heartTotal > 0 {
                Card(title: "Zeit in Pulszonen", systemImage: "chart.bar.xaxis") {
                    ForEach(0..<5, id: \.self) { i in
                        HStack {
                            Text("Zone \(i + 1) \(HeartRateZones.names[i])").font(.subheadline)
                            Spacer()
                            Text("\(Int((Double(heart[i]) / 60).rounded())) min").font(.subheadline.weight(.semibold)).monospacedDigit()
                        }
                        .accessibilityElement(children: .combine)
                    }
                    if let trimp {
                        Text("Belastung (TRIMP): \(Int(trimp.rounded()))").font(.footnote).foregroundStyle(Theme.rowSecondary)
                    }
                }
            }
            if result.kind == .ride, let definition = result.definitionForAnalysis(model) { ergCard(definition) }
        }
        .padding(.top, 8)
        .accessibilityIdentifier("recording.result")
    }

    @ViewBuilder
    private var rideStatus: some View {
        switch outcome {
        case .attached(let rideID):
            let ride = model.allRides().first { $0.id == rideID }
            Card(title: "Zur Fahrt gehängt", systemImage: "link") {
                Text("Der Puls liegt jetzt an deiner Fahrt „\(ride?.name ?? "Fahrt")“.").font(.subheadline)
                if let ride, let source = model.recordingSource(for: ride) {
                    Text("Leistung: \(source.label)").font(.footnote.weight(.semibold))
                        .accessibilityIdentifier("recording.source")
                    if let check = model.warmupCheck(for: ride), check.valid, let hr = check.hrMean {
                        Text("Aufwärm-Check: \(Int(hr.rounded())) bpm bei \(check.refWatts) W (\(check.source == .assumedERG ? "angenommen (ERG)" : "gemessen"))")
                            .font(.footnote).foregroundStyle(Theme.rowSecondary)
                    }
                    if source == .assumedERG { powerHint }
                }
            }
        case .pending:
            Card(title: "Wartet auf die Fahrt", systemImage: "hourglass") {
                Text("Die Fahrt ist noch nicht in der App. Die Aufzeichnung wartet und wird beim nächsten Import (MyWhoosh, FIT, Strava) automatisch zugeordnet.")
                    .font(.subheadline)
                powerHint
            }
            .accessibilityIdentifier("recording.pending")
        default:
            EmptyView()
        }
    }

    private var powerHint: some View {
        Label("Leistungskurve und Soll/Ist brauchen echte Watt: Mac-Brücke einrichten?", systemImage: "desktopcomputer")
            .font(.footnote).foregroundStyle(Theme.rowSecondary)
            .accessibilityIdentifier("recording.powerHint")
    }

    private func ergCard(_ definition: WorkoutDefinition) -> some View {
        let analysis = ERGAssumption.analyze(definition: definition, ftp: model.profile.ftp)
        let means = ERGAssumption.meanPulse(hr: result.seconds.heartRate ?? [], blocks: analysis.blocks)
        return Card(title: "Blöcke mit angenommener Leistung (ERG)", systemImage: "gauge.with.dots.needle.33percent") {
            ForEach(Array(analysis.blocks.enumerated()), id: \.offset) { i, block in
                HStack {
                    Text("\(Formatters.duration(block.duration)) bei \(block.watts) W").font(.subheadline)
                    Spacer()
                    Text(means[i].map { "\(Int($0.rounded())) bpm" } ?? "–").font(.subheadline.weight(.semibold)).monospacedDigit()
                }
                .accessibilityElement(children: .combine)
            }
            if analysis.unassessableSeconds > 0 {
                Text("\(Formatters.duration(analysis.unassessableSeconds)) in Rampen und kurzen Intervallen sind nicht auswertbar.")
                    .font(.footnote).foregroundStyle(Theme.rowSecondary)
            }
        }
    }
}

private extension RecordingResult {
    @MainActor
    func definitionForAnalysis(_ model: AppModel) -> WorkoutDefinition? {
        guard let id = plannedWorkoutID else { return nil }
        return model.workoutDefinition(id: id)
    }
}

// MARK: - Entry in the workout detail

/// "Puls am iPhone mitschreiben" – only with a paired strap and a workout planned for today.
struct RecordingEntry: View {
    var workout: StoredWorkout
    @Environment(AppModel.self) private var model
    @State private var show = false

    var body: some View {
        if workout.status == .planned, Calendar.current.isDateInToday(workout.date), StrapSession.shared.savedStrapID != nil {
            Card(title: "Puls am iPhone", systemImage: "heart.circle") {
                Button { show = true } label: {
                    Label("Puls am iPhone mitschreiben", systemImage: "waveform.path.ecg").frame(maxWidth: .infinity)
                }
                .buttonStyle(.soft)
                .accessibilityIdentifier("recording.entry")
                if model.isBridgePaired {
                    Text("Die Brücke liefert schon Sekundendaten – die Aufzeichnung am iPhone ist trotzdem möglich und ergänzt nur fehlenden Puls.")
                        .font(.caption).foregroundStyle(Theme.rowSecondary)
                        .accessibilityIdentifier("recording.bridgeHint")
                }
            }
            .recordingCover(isPresented: $show) {
                RecordingView(kind: .ride, title: workout.title, plannedWorkoutID: workout.id, definition: workout.definition)
            }
        }
    }
}

extension View {
    func recordingCover<C: View>(isPresented: Binding<Bool>, @ViewBuilder content: @escaping () -> C) -> some View {
        #if os(iOS)
        fullScreenCover(isPresented: isPresented, content: content)
        #else
        sheet(isPresented: isPresented, content: content)
        #endif
    }

    /// Asks at launch what to do with a recording the app left behind. Attach once, e.g. to the root view.
    public func interruptedRecordingPrompt(service: RecordingService = .shared) -> some View {
        modifier(InterruptedRecordingPrompt(service: service))
    }
}

struct InterruptedRecordingPrompt: ViewModifier {
    var service: RecordingService
    @Environment(AppModel.self) private var model
    @State private var resumed = false

    func body(content: Content) -> some View {
        content
            .alert("Unterbrochene Aufzeichnung",
                   isPresented: Binding(get: { service.interrupted != nil && !resumed }, set: { _ in })) {
                Button("Fortsetzen") { service.resumeInterrupted(); resumed = true }
                Button("Speichern") { if let r = service.finishInterrupted() { model.finishRecording(r) } }
                Button("Verwerfen", role: .destructive) { service.discardInterrupted() }
            } message: {
                Text("Die App wurde während einer Aufzeichnung beendet. Fortsetzen oder speichern?")
            }
            .recordingCover(isPresented: $resumed) {
                RecordingView(kind: service.kind, title: service.title, plannedWorkoutID: service.plannedWorkoutID)
            }
    }
}
