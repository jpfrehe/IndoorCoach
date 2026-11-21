import SwiftUI
import TipKit

struct WorkoutDetailView: View {
    @Bindable var workout: StoredWorkout
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    @State private var zwoURL: URL?
    @State private var confirmDelete = false

    var body: some View {
        if workout.isDeleted || workout.modelContext == nil {
            // The model was deleted while the pop animation is still running.
            Color.clear
        } else {
            content
        }
    }

    private var content: some View {
        ScrollView {
            WorkoutDetailContent(workout: workout, zwoURL: zwoURL,
                                 onCalendar: { Task { await model.addToCalendar([workout]) } })
                .padding(.horizontal)
                .padding(.bottom, 24)
        }
        .background(Theme.canvas)
        .navigationTitle(workout.title)
        .inlineNavigationTitle()
        .checkInOnOpen(workout) // ANCHOR-CHECKIN
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Menu {
                    Picker("Status", selection: Binding(get: { workout.status },
                                                        set: { model.setStatus($0, for: workout) })) {
                        ForEach(WorkoutStatus.allCases, id: \.self) { s in
                            Label(s.label, systemImage: s.symbol).tag(s)
                        }
                    }
                    Divider()
                    Button(role: .destructive) { confirmDelete = true } label: { Label("Löschen", systemImage: "trash") }
                } label: {
                    Image(systemName: "ellipsis.circle")
                }
            }
        }
        .confirmationDialog("Einheit löschen?", isPresented: $confirmDelete, titleVisibility: .visible) {
            Button("Löschen", role: .destructive) {
                let target = workout
                dismiss()
                Task {
                    try? await Task.sleep(for: .milliseconds(450)) // let the pop animation finish first
                    await model.delete(target)
                }
            }
        } message: {
            Text("Ein vorhandener Kalendereintrag wird ebenfalls entfernt.")
        }
        .task(id: workout.id) {
            zwoURL = try? model.zwoFile(for: workout)
        }
    }
}

struct WorkoutDetailContent: View {
    var workout: StoredWorkout
    var zwoURL: URL?
    var onCalendar: () -> Void
    @Environment(AppModel.self) private var model
    @State private var showAdjust = false

    var body: some View {
        let d = workout.definition
        let ftp = model.profile.ftp
        let avgWatts = Double(ftp) * d.steps.reduce(0.0) { $0 + $1.averagePower * Double($1.duration) } / Double(max(1, d.totalDuration))

        VStack(alignment: .leading, spacing: 16) {
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    TypeBadge(type: d.type)
                    if workout.status != .planned {
                        // Text in the row colour (≥ 4.5:1); only the icon carries the green chart tone (audit 3: "Erledigt" failed contrast).
                        Label {
                            Text(workout.status.label).foregroundStyle(Theme.rowSecondary)
                        } icon: {
                            Image(systemName: workout.status.symbol)
                                .foregroundStyle(workout.status == .done ? Theme.done : Theme.rowSecondary)
                        }
                        .font(.caption.weight(.semibold))
                    }
                    Spacer()
                    if workout.source == .claude {
                        Label("Claude", systemImage: "sparkles").font(.caption).foregroundStyle(.secondary)
                    }
                }
                Text(workout.title).font(.largeTitle.weight(.bold))
                Text(WorkoutRow.dayLabel(workout.date) + " · " + model.startDate(for: workout).formatted(date: .omitted, time: .shortened) + " Uhr")
                    .font(.headline).foregroundStyle(.secondary)
                Text(d.summary).font(.body)
            }
            .padding(.top, 8)

            Card {
                PowerProfileChart(definition: d, ftp: ftp, height: 210)
                Grid(alignment: .leading, horizontalSpacing: 12, verticalSpacing: 12) {
                    GridRow {
                        StatTile(title: "Dauer", value: Formatters.duration(d.totalDuration))
                        StatTile(title: "TSS", value: "\(Int(d.estimatedTSS.rounded()))")
                        StatTile(title: "IF", value: Formatters.decimal(d.intensityFactor, digits: 2))
                    }
                    GridRow {
                        StatTile(title: "Ø Leistung", value: "\(Int(avgWatts.rounded()))", unit: "W")
                        StatTile(title: "NP ≈", value: "\(Int((d.intensityFactor * Double(ftp)).rounded()))", unit: "W")
                        StatTile(title: "Arbeit", value: "\(Int((avgWatts * Double(d.totalDuration) / 1000).rounded()))", unit: "kJ")
                    }
                }
            }

            if workout.status == .planned {
                LegLoadBanner(workout: workout) // ANCHOR-W3C
                AdjustSection(workout: workout) { showAdjust = true }
            }

            // Soll/Ist je Intervall: renders only for done workouts whose linked ride has seconds data.
            IntervalComplianceCard(workout: workout)

            RecordingEntry(workout: workout) // ANCHOR-REC

            Card(title: "Zeit in Zonen", systemImage: "square.stack.3d.up") {
                ZoneDistributionBar(definition: d)
            }

            Card(title: "Ablauf", systemImage: "list.bullet") {
                ForEach(Array(d.segments.enumerated()), id: \.offset) { _, segment in
                    HStack(alignment: .top, spacing: 10) {
                        RoundedRectangle(cornerRadius: 2)
                            .fill(Theme.cap(PowerZone(fractionOfFTP: segment.onPower ?? segment.power ?? segment.powerHigh ?? 0.5)))
                            .frame(width: 4)
                        Text(segment.describe(ftp: ftp)).font(.subheadline)
                        Spacer(minLength: 0)
                    }
                    .fixedSize(horizontal: false, vertical: true)
                }
            }

            if !workout.rationale.isEmpty {
                Card(title: "Warum diese Einheit?", systemImage: "lightbulb") {
                    Text(workout.rationale).font(.body)
                    if let focus = workout.weekFocus, !focus.isEmpty {
                        Text("Wochenfokus: \(focus)").font(.subheadline).foregroundStyle(.secondary)
                    }
                }
            }

            Card(title: "Fahren", systemImage: "play.circle") {
                if model.isMyWhooshConnected {
                    Button { Task { await model.sendToMyWhoosh([workout]) } } label: {
                        HStack {
                            if model.isSendingToMyWhoosh { ProgressView().tint(Theme.ink) }
                            else { Image(systemName: "paperplane.fill") }
                            Text(workout.myWhooshSentAt == nil ? "An MyWhoosh senden" : "In MyWhoosh aktualisieren")
                        }
                        .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.jelly)
                    .disabled(model.isSendingToMyWhoosh)
                    .popoverTip(SendToMyWhooshTip())
                    if let sent = workout.myWhooshSentAt {
                        Label("In MyWhoosh seit \(sent.formatted(.dateTime.day().month().hour().minute().locale(Locale.de)))"
                              + (workout.myWhooshTaskID != nil ? " · im MyWhoosh-Kalender" : ""),
                              systemImage: "checkmark.circle.fill")
                            .font(.caption).foregroundStyle(Theme.rowSecondary)
                    }
                }
                if model.isIntervalsConnected {
                    Button { Task { await model.sendToIntervals([workout]) } } label: {
                        HStack {
                            if model.isSendingToIntervals { ProgressView().tint(Theme.ink) }
                            else { Image(systemName: "paperplane.fill") }
                            Text(workout.intervalsSentAt == nil ? "An intervals.icu senden" : "In intervals.icu aktualisieren")
                        }
                        .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(model.isMyWhooshConnected ? AnyButtonStyle(.soft) : AnyButtonStyle(.jelly))
                    .disabled(model.isSendingToIntervals)
                    .accessibilityIdentifier("workout.sendIntervals")
                    if let sent = workout.intervalsSentAt {
                        Label("In intervals.icu seit \(sent.formatted(.dateTime.day().month().hour().minute().locale(Locale.de)))",
                              systemImage: "checkmark.circle.fill")
                            .font(.caption).foregroundStyle(Theme.rowSecondary)
                    }
                }
                Button(action: onCalendar) {
                    Label(workout.calendarEventID == nil ? "In Kalender eintragen" : "Kalender aktualisieren",
                          systemImage: "calendar.badge.plus")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(model.isMyWhooshConnected || model.isIntervalsConnected ? AnyButtonStyle(.soft) : AnyButtonStyle(.jelly))
                if !model.isMyWhooshConnected && !model.isIntervalsConnected {
                    Text("Tipp: Verbinde MyWhoosh unter Profil → Dienste & Geräte – dann landet die Einheit mit einem Tipp direkt in MyWhoosh.")
                        .font(.caption).foregroundStyle(Theme.rowSecondary)
                }
                DisclosureGroup("Alternativ: .zwo-Datei") {
                    if let zwoURL {
                        ShareLink(item: zwoURL, preview: SharePreview(workout.title)) {
                            Label("Für MyWhoosh exportieren (.zwo)", systemImage: "square.and.arrow.up")
                                .frame(maxWidth: .infinity)
                        }
                        .buttonStyle(.soft)
                    }
                    Link(destination: URL(string: "https://workout.mywhoosh.com")!) {
                        Label("MyWhoosh Workout Builder öffnen", systemImage: "safari")
                            .font(.subheadline)
                    }
                    Text("Die .zwo-Datei per AirDrop an den Mac schicken, im MyWhoosh Workout Builder hochladen und „Export to MyWhoosh“ wählen.")
                        .font(.caption).foregroundStyle(Theme.rowSecondary)
                }
                .font(.subheadline)
            }
        }
        .sheet(isPresented: $showAdjust) { AdjustSheet(workout: workout) }
    }
}

// MARK: - Einheit anpassen

/// Button plus, after an adjustment, the note "Angepasst · vorher 75 min" with a restore button.
private struct AdjustSection: View {
    var workout: StoredWorkout
    var onAdjust: () -> Void
    @Environment(AppModel.self) private var model

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            if let original = workout.originalDefinition {
                VStack(alignment: .leading, spacing: 6) {
                    Label("Angepasst · vorher \(WorkoutAdjust.minutes(original.totalDuration)) min", systemImage: "slider.horizontal.3")
                        .font(.subheadline.weight(.semibold))
                        .accessibilityIdentifier("workout.adjust.note")
                    if let note = workout.adjustmentNote {
                        Text(note).font(.caption).foregroundStyle(Theme.rowSecondary)
                    }
                    Button { Task { await model.restoreOriginal(workout) } } label: {
                        Text("Original wiederherstellen").multilineTextAlignment(.center).frame(maxWidth: .infinity)
                    }
                        .buttonStyle(.soft)
                        .accessibilityIdentifier("workout.adjust.restore")
                }
                .padding(14)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(Theme.card, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
                .accessibilityElement(children: .contain)
            }
            Button(action: onAdjust) {
                Label("Anpassen", systemImage: "slider.horizontal.3").frame(maxWidth: .infinity)
            }
            .buttonStyle(.soft)
            .accessibilityHint("Einheit kürzer oder leichter machen")
            .accessibilityIdentifier("workout.adjust")
        }
    }
}

private struct AdjustSheet: View {
    var workout: StoredWorkout
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var minutes: Int?
    @State private var easier = 0

    private var base: WorkoutDefinition { workout.originalDefinition ?? workout.definition }
    private var options: [Int] { WorkoutAdjust.shortenOptions(for: base) }
    private var result: WorkoutAdjustment? { WorkoutAdjust.apply(to: base, minutes: minutes, easierBy: easier) }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    Card(title: "Dauer", systemImage: "clock") {
                        choice("Unverändert (\(WorkoutAdjust.minutes(base.totalDuration)) min)", selected: minutes == nil, id: "adjust.minutes.0") { minutes = nil }
                        ForEach(options, id: \.self) { m in
                            choice("\(m) min", selected: minutes == m, id: "adjust.minutes.\(m)") { minutes = m }
                        }
                        if options.isEmpty {
                            Text("Die Einheit ist schon kurz – kürzer geht hier nicht.").font(.caption).foregroundStyle(Theme.rowSecondary)
                        }
                    }
                    Card(title: "Intensität", systemImage: "gauge.with.dots.needle.33percent") {
                        choice("Normal", selected: easier == 0, id: "adjust.easier.0") { easier = 0 }
                        choice("−5 %", selected: easier == 5, id: "adjust.easier.5") { easier = 5 }
                        choice("−10 %", selected: easier == 10, id: "adjust.easier.10") { easier = 10 }
                    }
                    preview
                    VStack(spacing: 10) {
                        Button { apply() } label: { Text("Übernehmen").frame(maxWidth: .infinity) }
                            .buttonStyle(.jelly)
                            .disabled(result == nil)
                            .accessibilityIdentifier("workout.adjust.apply")
                        Button { dismiss() } label: { Text("Abbrechen").frame(maxWidth: .infinity) }
                            .buttonStyle(.soft)
                            .accessibilityIdentifier("workout.adjust.cancel")
                    }
                }
                .padding(.horizontal)
                .padding(.bottom, 24)
                .animation(reduceMotion ? nil : .default, value: minutes)
                .animation(reduceMotion ? nil : .default, value: easier)
            }
            .background(Theme.canvas)
            .navigationTitle("Einheit anpassen")
            .inlineNavigationTitle()
        }
        .presentationDetents([.large])
        .onAppear {
            // Start from the current adjustment so it can be tweaked.
            if let note = workout.adjustmentNote {
                if note.contains("−10 %") { easier = 10 } else if note.contains("−5 %") { easier = 5 }
                let current = WorkoutAdjust.minutes(workout.definition.totalDuration)
                if options.contains(current) { minutes = current }
            }
        }
    }

    private var preview: some View {
        let ftp = model.profile.ftp
        let shown = result?.definition ?? base
        return Card(title: "Vorschau", systemImage: "eye") {
            PowerProfileChart(definition: shown, ftp: ftp, showAxes: false, height: 110)
                .accessibilityHidden(true)
            let before = "\(WorkoutAdjust.minutes(base.totalDuration)) min"
            let after = "\(WorkoutAdjust.minutes(shown.totalDuration)) min"
            let tssBefore = Int(base.estimatedTSS.rounded()), tssAfter = Int(shown.estimatedTSS.rounded())
            VStack(alignment: .leading, spacing: 4) {
                Text("Dauer: \(before) → \(after)").font(.subheadline.weight(.semibold))
                Text("TSS: \(tssBefore) → \(tssAfter)").font(.subheadline.weight(.semibold))
                if let result, !result.isExact {
                    Text("So kurz geht es hier nicht genau – das ist der nächste sinnvolle Wert.")
                        .font(.caption).foregroundStyle(Theme.rowSecondary)
                }
            }
            .accessibilityElement(children: .combine)
            .accessibilityIdentifier("workout.adjust.preview")
        }
    }

    private func choice(_ title: String, selected: Bool, id: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack {
                Text(title).font(.body)
                Spacer(minLength: 8)
                Image(systemName: selected ? "checkmark.circle.fill" : "circle")
                    .foregroundStyle(selected ? Theme.accent : Color.secondary)
            }
            .frame(minHeight: 44)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(selected ? .isSelected : [])
        .accessibilityIdentifier(id)
    }

    private func apply() {
        let target = workout
        let (m, e) = (minutes, easier)
        dismiss()
        Task { await model.adjust(target, minutes: m, easierBy: e == 0 ? nil : e) }
    }
}
