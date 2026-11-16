import SwiftUI

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
        .navigationTitle(workout.title)
        .inlineNavigationTitle()
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

    var body: some View {
        let d = workout.definition
        let ftp = model.profile.ftp
        let avgWatts = Double(ftp) * d.steps.reduce(0.0) { $0 + $1.averagePower * Double($1.duration) } / Double(max(1, d.totalDuration))

        VStack(alignment: .leading, spacing: 16) {
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    TypeBadge(type: d.type)
                    if workout.status != .planned {
                        Label(workout.status.label, systemImage: workout.status.symbol)
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(workout.status == .done ? .green : .secondary)
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

            Card(title: "Zeit in Zonen", systemImage: "square.stack.3d.up") {
                ZoneDistributionBar(definition: d)
            }

            Card(title: "Ablauf", systemImage: "list.bullet") {
                ForEach(Array(d.segments.enumerated()), id: \.offset) { _, segment in
                    HStack(alignment: .top, spacing: 10) {
                        RoundedRectangle(cornerRadius: 2)
                            .fill(Theme.color(for: PowerZone(fractionOfFTP: segment.onPower ?? segment.power ?? segment.powerHigh ?? 0.5)))
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
                Button(action: onCalendar) {
                    Label(workout.calendarEventID == nil ? "In Kalender eintragen" : "Kalender aktualisieren",
                          systemImage: "calendar.badge.plus")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)

                if let zwoURL {
                    ShareLink(item: zwoURL, preview: SharePreview(workout.title)) {
                        Label("Für MyWhoosh exportieren (.zwo)", systemImage: "square.and.arrow.up")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.large)
                }
                Link(destination: URL(string: "https://workout.mywhoosh.com")!) {
                    Label("MyWhoosh Workout Builder öffnen", systemImage: "safari")
                        .font(.subheadline)
                }
                Text("Die .zwo-Datei per AirDrop an den Mac schicken, im MyWhoosh Workout Builder hochladen und „Export to MyWhoosh“ wählen. Das Workout erscheint dann unter „My Workouts“.")
                    .font(.caption).foregroundStyle(.secondary)
            }
        }
    }
}
