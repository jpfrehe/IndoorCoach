import SwiftData
import SwiftUI
import TipKit

struct PlanView: View {
    @Environment(AppModel.self) private var model
    @Query(sort: \StoredWorkout.date) private var workouts: [StoredWorkout]
    @Query(sort: \StoredRide.startDate) private var storedRides: [StoredRide]
    @State private var showGenerator = PlanView.debugFlag("uiPlanner")
    @State private var showPast = false
    @State private var path: [StoredWorkout] = []
    @State private var pendingDelete: StoredWorkout?

    static func debugFlag(_ key: String) -> Bool {
        #if DEBUG
        UserDefaults.standard.bool(forKey: key)
        #else
        false
        #endif
    }

    private var today: Date { Calendar.current.startOfDay(for: .now) }

    var body: some View {
        NavigationStack(path: $path) {
            List {
                let upcoming = workouts.filter { $0.date >= today }
                if upcoming.isEmpty {
                    Section {
                        EmptyStateView(title: "Noch kein Plan", systemImage: "sparkles",
                                       message: "Dein Coach plant die nächsten Tage auf Basis deiner Form und Ziele.")
                        Button { showGenerator = true } label: {
                            Label("Plan erstellen", systemImage: "sparkles").frame(maxWidth: .infinity)
                        }
                        .buttonStyle(.jelly)
                        .listRowBackground(Color.clear)
                    }
                }
                ForEach(weekGroups(upcoming), id: \.start) { group in
                    Section {
                        ForEach(group.items) { workout in
                            NavigationLink(value: workout) { WorkoutRow(workout: workout, ftp: model.profile.ftp) }
                                .swipeActions(edge: .leading) {
                                    Button { Task { await model.addToCalendar([workout]) } } label: {
                                        Label("Kalender", systemImage: "calendar.badge.plus")
                                    }
                                    .tint(Theme.calendarAction)
                                }
                                .swipeActions(edge: .trailing) {
                                    Button(role: .destructive) { pendingDelete = workout } label: {
                                        Label("Löschen", systemImage: "trash")
                                    }
                                }
                        }
                    } header: {
                        weekHeader(group)
                    }
                }
                let past = workouts.filter { $0.date < today }.reversed()
                if !past.isEmpty {
                    Section {
                        Button {
                            withAnimation { showPast.toggle() }
                        } label: {
                            Label(showPast ? "Vergangene ausblenden" : "Vergangene Einheiten (\(past.count))",
                                  systemImage: showPast ? "chevron.up" : "clock.arrow.circlepath")
                        }
                        if showPast {
                            ForEach(Array(past)) { workout in
                                NavigationLink(value: workout) { WorkoutRow(workout: workout, ftp: model.profile.ftp) }
                            }
                        }
                    }
                }
            }
            .refreshesOnNewDay()   // „Morgen“/„Diese Woche“ stimmen auch nach Mitternacht
            .scrollContentBackground(.hidden)
            .background(Theme.canvas)
            .navigationTitle("Plan")
            .navigationDestination(for: StoredWorkout.self) { WorkoutDetailView(workout: $0) }
            .toolbar {
                ToolbarItem(placement: .primaryAction) {
                    // Text + icon as one HStack: iOS 26+ toolbars render a plain Label icon-only,
                    // and the empty state tells the user to tap "Planen".
                    Button { showGenerator = true } label: {
                        HStack(spacing: 4) {
                            Image(systemName: "sparkles")
                            Text("Planen")
                        }
                    }
                    .buttonStyle(.jellySmall)
                    .popoverTip(PlanTip())
                    .accessibilityLabel("Planen")
                }
                ToolbarItem(placement: .secondaryAction) {
                    Button {
                        Task { await model.addToCalendar(workouts.filter { $0.date >= today && $0.status == .planned }) }
                    } label: { Label("Alle in Kalender", systemImage: "calendar.badge.plus") }
                }
                if model.isMyWhooshConnected {
                    ToolbarItem(placement: .secondaryAction) {
                        Button {
                            Task { await model.sendToMyWhoosh(workouts.filter { $0.date >= today && $0.status == .planned }) }
                        } label: { Label("Alle an MyWhoosh senden", systemImage: "paperplane") }
                    }
                }
            }
            .sheet(isPresented: $showGenerator) {
                PlanGeneratorSheet()
            }
            .onChange(of: model.plannerRequested, initial: true) { _, requested in
                if requested { showGenerator = true; model.plannerRequested = false }
            }
            .confirmationDialog("Einheit löschen?", isPresented: Binding(get: { pendingDelete != nil }, set: { if !$0 { pendingDelete = nil } }),
                                titleVisibility: .visible, presenting: pendingDelete) { workout in
                Button("Löschen", role: .destructive) { Task { await model.delete(workout) } }
            } message: { workout in
                Text(workout.calendarEventID == nil ? "„\(workout.title)“ wird aus dem Plan entfernt."
                     : "„\(workout.title)“ wird aus dem Plan und aus dem Kalender entfernt.")
            }
            .task {
                // Debug launch argument `-uiDetail YES` opens the first upcoming workout.
                if Self.debugFlag("uiDetail"), path.isEmpty,
                   let first = workouts.first(where: { $0.date >= today && $0.type != .endurance }) ?? workouts.first {
                    path = [first]
                }
            }
        }
    }

    struct WeekGroup { let start: Date; let items: [StoredWorkout] }

    private func weekGroups(_ items: [StoredWorkout]) -> [WeekGroup] {
        var cal = Calendar.current
        cal.firstWeekday = 2
        let grouped = Dictionary(grouping: items) { cal.dateInterval(of: .weekOfYear, for: $0.date)?.start ?? $0.date }
        return grouped.keys.sorted().map { WeekGroup(start: $0, items: grouped[$0]!.sorted { $0.date < $1.date }) }
    }

    private func weekHeader(_ group: WeekGroup) -> some View {
        var cal = Calendar.current
        cal.firstWeekday = 2
        let thisWeek = cal.dateInterval(of: .weekOfYear, for: .now)?.start
        let title: String
        if group.start == thisWeek { title = "Diese Woche" }
        else if let thisWeek, group.start == cal.date(byAdding: .weekOfYear, value: 1, to: thisWeek) { title = "Nächste Woche" }
        else { title = "Woche ab " + group.start.formatted(.dateTime.day().month().locale(Locale.de)) }
        let seconds = group.items.reduce(0) { $0 + $1.definition.totalDuration }
        let tss = group.items.reduce(0.0) { $0 + $1.definition.estimatedTSS }
        return VStack(alignment: .leading, spacing: 2) {
            HStack {
                Text(title)
                Spacer()
                Text("\(Formatters.duration(seconds)) · TSS \(Int(tss.rounded()))").monospacedDigit()
            }
            if let thisWeek, group.start <= thisWeek, let text = adherence(weekStart: group.start)?.text {
                Text(text).font(.caption).monospacedDigit()
                    .accessibilityLabel("Plan-Treue: \(text)")
                    .accessibilityIdentifier("plan.adherence")
            }
        }
    }

    /// K1 – Plan-Treue of a week from *all* planned workouts of that week (also those before today) and its rides.
    private func adherence(weekStart: Date) -> Consistency.Adherence? {
        let end = Calendar.current.date(byAdding: .day, value: 7, to: weekStart) ?? weekStart
        let planned = workouts.filter { $0.date >= weekStart && $0.date < end }.map {
            Consistency.PlannedItem(date: $0.date, tss: $0.definition.estimatedTSS, done: $0.status == .done || $0.linkedRideID != nil)
        }
        let rides = model.consistencyRides(storedRides.filter { $0.startDate >= weekStart && $0.startDate < end }.map(\.summary))
        let result = Consistency.adherence(weekStart: weekStart, rides: rides, planned: planned)
        return result.planned > 0 ? result : nil
    }
}

// MARK: - Generator

struct PlanGeneratorSheet: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    @State private var wish = ""
    @State private var startToday = false
    @State private var showConsent = false // ANCHOR-W4C
    /// Cached so typing in the wish field does not re-run fetches and load calculations.
    @State private var ctx: PlanContext?

    static func shortDay(_ date: Date) -> String {
        date.formatted(.dateTime.weekday(.abbreviated).day().month(.twoDigits).locale(Locale.de))
    }

    var body: some View {
        @Bindable var model = model
        NavigationStack {
            Group {
                if let proposal = model.proposal {
                    ProposalReview(proposal: proposal, onDone: { dismiss() })
                } else {
                    form(model: model)
                }
            }
            .navigationTitle(model.proposal == nil ? "Neuer Plan" : "Vorschlag")
            .inlineNavigationTitle()
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Abbrechen") { model.discardProposal(); dismiss() }
                        .disabled(model.isPlanning)
                }
            }
        }
        .interactiveDismissDisabled(model.isPlanning)
        .task(id: "\(startToday)-\(model.profile.planHorizonDays)") {
            ctx = model.planContext(wish: "", startToday: startToday)
        }
    }

    @ViewBuilder
    private func form(model: AppModel) -> some View {
        if let ctx {
            form(model: model, ctx: ctx)
        } else {
            ProgressView()
        }
    }

    @ViewBuilder
    private func form(model: AppModel, ctx: PlanContext) -> some View {
        @Bindable var model = model
        Form {
            Section {
                Picker("Zeitraum", selection: $model.profile.planHorizonDays) {
                    Text("7 Tage").tag(7)
                    Text("14 Tage").tag(14)
                }
                .pickerStyle(.segmented)
                Toggle("Ab heute planen", isOn: $startToday)
                LabeledContent("Zeitraum", value: "\(Self.shortDay(ctx.horizonStart)) – \(Self.shortDay(ctx.horizonEnd))")
            } header: { Text("Was soll geplant werden?") }

            Section {
                TextField("z. B. „Mittwoch habe ich nur 45 Minuten“ oder „Fokus VO₂max“", text: $wish, axis: .vertical)
                    .lineLimit(2...5)
            } header: { Text("Wünsche an den Coach (optional)") }

            Section {
                if let load = ctx.load, load.ctl > 0 || load.atl > 0 {
                    LabeledContent("Form (TSB)", value: Formatters.decimal(load.tsb))
                    LabeledContent("Fitness (CTL)", value: Formatters.decimal(load.ctl))
                }
                LabeledContent("Ziel", value: model.profile.goal)
                LabeledContent("Trainingstage", value: model.profile.trainingDays.sorted().compactMap { AthleteProfile.weekdayNames[$0] }.joined(separator: ", "))
                if !ctx.alreadyPlanned.isEmpty {
                    LabeledContent("Bereits geplant", value: "\(ctx.alreadyPlanned.count) Einheiten")
                }
            } header: { Text("Grundlage") } footer: {
                Text(model.hasClaudeKey
                     ? "Claude (\(model.profile.model)) erhält nur Kennzahlen deiner Fahrten – keine Namen, Orte oder GPS-Daten."
                     : "Kein Claude-API-Key hinterlegt – es wird ein einfacher Demo-Plan ohne KI erstellt.")
            }

        }
        .scrollContentBackground(.hidden)
        .background(Theme.canvas)
        .scrollDismissesKeyboard(.interactively)
        .sheet(isPresented: $showConsent) { // ANCHOR-W4C
            ClaudeConsentSheet { Task { await model.generatePlan(wish: wish, startToday: startToday) } }
        }
        // Primary action stays visible above the keyboard instead of sitting below the fold.
        .safeAreaInset(edge: .bottom) {
            VStack(spacing: 6) {
                Button {
                    // ANCHOR-W4C: beim ersten Planen mit Claude nach der Einwilligung fragen
                    if model.hasClaudeKey, model.needsClaudeConsentPrompt() { showConsent = true } else {
                        Task { await model.generatePlan(wish: wish, startToday: startToday) }
                    }
                } label: {
                    HStack {
                        if model.isPlanning {
                            ProgressView().tint(Theme.ink).padding(.trailing, 6)
                            Text(model.hasClaudeKey ? "Claude plant …" : "Plane …")
                        } else {
                            Label(model.hasClaudeKey ? "Mit Claude planen" : "Demo-Plan erstellen", systemImage: "sparkles")
                        }
                    }
                    .frame(maxWidth: .infinity)
                }
                .buttonStyle(.jelly)
                .disabled(model.isPlanning)
                if model.isPlanning && model.hasClaudeKey {
                    Text("Das dauert meist 30–90 Sekunden.").font(.caption).foregroundStyle(.secondary)
                }
            }
            .padding()
            .background(.bar)
        }
    }
}

struct ProposalReview: View {
    var proposal: PlanProposal
    var onDone: () -> Void
    @Environment(AppModel.self) private var model

    var body: some View {
        ScrollView {
            VStack(spacing: 16) {
                Card(title: "Fokus", systemImage: "scope") {
                    Text(proposal.weekFocus).font(.title3.weight(.bold))
                    if !proposal.notes.isEmpty {
                        Text(proposal.notes).font(.subheadline).foregroundStyle(.secondary)
                    }
                    let seconds = proposal.workouts.reduce(0) { $0 + $1.definition.totalDuration }
                    let tss = proposal.workouts.reduce(0.0) { $0 + $1.definition.estimatedTSS }
                    HStack {
                        StatTile(title: "Einheiten", value: "\(proposal.workouts.count)")
                        StatTile(title: "Zeit", value: Formatters.duration(seconds))
                        StatTile(title: "TSS", value: "\(Int(tss.rounded()))")
                    }
                }
                ForEach(proposal.workouts, id: \.self) { w in
                    Card {
                        HStack(alignment: .top) {
                            VStack(alignment: .leading, spacing: 3) {
                                Text(WorkoutRow.dayLabel(w.date)).font(.subheadline).foregroundStyle(.secondary)
                                Text(w.definition.title).font(.headline)
                            }
                            Spacer()
                            TypeBadge(type: w.definition.type)
                        }
                        PowerProfileChart(definition: w.definition, ftp: model.profile.ftp, showAxes: false, height: 56)
                        Text("\(Formatters.duration(w.definition.totalDuration)) · TSS \(Int(w.definition.estimatedTSS.rounded())) · \(w.definition.summary)")
                            .font(.caption).foregroundStyle(.secondary)
                        Label(w.rationale, systemImage: "lightbulb")
                            .font(.subheadline)
                    }
                }
                if proposal.workouts.isEmpty {
                    // Audit 3: an empty proposal used to disable every button, "Neu planen" included (dead end).
                    Card(title: "Keine freien Trainingstage", systemImage: "calendar.badge.exclamationmark") {
                        Text("Im gewählten Zeitraum sind alle Trainingstage schon belegt. Tippe auf „Neu planen“ und wähle einen längeren Zeitraum oder schalte „Ab heute planen“ aus. Oder entferne vorher Einheiten im Plan.")
                            .font(.subheadline).foregroundStyle(.secondary)
                    }
                    .accessibilityIdentifier("proposal.empty")
                }
                if !proposal.rejected.isEmpty {
                    Card(title: "Aussortiert", systemImage: "exclamationmark.triangle") {
                        ForEach(proposal.rejected, id: \.self) { Text($0).font(.caption).foregroundStyle(.secondary) }
                    }
                }
            }
            .padding()
        }
        .background(Theme.canvas)
        .safeAreaInset(edge: .bottom) {
            VStack(spacing: 8) {
                Button {
                    Task { await model.acceptProposal(addToCalendar: true); onDone() }
                } label: {
                    Label("Übernehmen & in Kalender", systemImage: "calendar.badge.plus").frame(maxWidth: .infinity)
                }
                .buttonStyle(.jelly)
                .disabled(proposal.workouts.isEmpty)
                HStack {
                    Button("Nur übernehmen") { Task { await model.acceptProposal(addToCalendar: false); onDone() } }
                        .disabled(proposal.workouts.isEmpty)
                    Spacer()
                    // Always available: the way out of an empty or unwanted proposal.
                    Button("Neu planen", role: .destructive) { model.discardProposal() }
                }
                .font(.subheadline.weight(.medium))
            }
            .padding()
            .background(.bar)
        }
    }
}
