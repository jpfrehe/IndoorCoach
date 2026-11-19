import SwiftUI

/// Profil → Kraft: Studio-Tage, Vorlagen und Übungskatalog.
struct StrengthSettingsView: View {
    @Environment(AppModel.self) private var model
    @State private var templates: [StrengthTemplate] = []
    @State private var days: Set<Int> = []
    @State private var editing: StrengthTemplate?
    @State private var creating = false

    /// Kalender-Wochentage (1 = Sonntag) in der Reihenfolge Mo–So.
    static let weekdays: [(day: Int, short: String, long: String)] = [
        (2, "Mo", "Montag"), (3, "Di", "Dienstag"), (4, "Mi", "Mittwoch"), (5, "Do", "Donnerstag"),
        (6, "Fr", "Freitag"), (7, "Sa", "Samstag"), (1, "So", "Sonntag"),
    ]

    var body: some View {
        Form {
            Section {
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 44), spacing: 8)], spacing: 8) {
                    ForEach(Self.weekdays, id: \.day) { d in
                        ChoiceTile(title: d.short, selected: days.contains(d.day), identifier: "strength.day.\(d.day)") {
                            if days.contains(d.day) { days.remove(d.day) } else { days.insert(d.day) }
                            model.strengthDays = days
                        }
                        .accessibilityLabel(d.long)
                    }
                }
                .listRowBackground(Color.clear)
                .listRowInsets(EdgeInsets())
            } header: {
                Text("Studio-Tage")
            } footer: {
                Text("An diesen Tagen erinnert Heute dich an Kraft. Keine Mitteilung, kein Zwang.")
            }
            Section("Vorlagen") {
                if templates.isEmpty {
                    Text("Noch keine Vorlage.").foregroundStyle(Theme.rowSecondary)
                }
                ForEach(templates) { t in
                    Button { editing = t } label: {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(t.name).font(.body.weight(.semibold)).foregroundStyle(.primary)
                            Text(t.exerciseIDs.map(StrengthFormat.exerciseName).joined(separator: ", "))
                                .font(.caption).foregroundStyle(Theme.rowSecondary).lineLimit(2)
                        }
                        .frame(maxWidth: .infinity, minHeight: 48, alignment: .leading)
                        .contentShape(Rectangle())
                    }
                    .accessibilityIdentifier("strength.template.\(t.name)")
                }
                .onDelete { offsets in
                    for i in offsets { model.deleteStrengthTemplate(named: templates[i].name) }
                    reload()
                }
                Button { creating = true } label: {
                    Label("Neue Vorlage", systemImage: "plus.circle").frame(minHeight: 44)
                }
                .accessibilityIdentifier("strength.template.new")
            }
            Section("Übungskatalog") {
                NavigationLink { StrengthCatalogView() } label: {
                    Label("Alle \(ExerciseCatalog.all.count) Übungen", systemImage: "list.bullet.rectangle").frame(minHeight: 44)
                }
                .accessibilityIdentifier("strength.catalog.open")
            }
        }
        .scrollContentBackground(.hidden)
        .background(Theme.canvas)
        .navigationTitle("Kraft")
        .inlineNavigationTitle()
        .onAppear(perform: reload)
        .sheet(item: $editing, onDismiss: reload) { t in StrengthTemplateEditor(template: t) }
        .sheet(isPresented: $creating, onDismiss: reload) { StrengthTemplateEditor(template: nil) }
    }

    private func reload() {
        templates = model.strengthTemplates()
        days = model.strengthDays
    }
}

/// Vorlage bearbeiten: Name, Übungen in Reihenfolge, Vorwerte.
struct StrengthTemplateEditor: View {
    var template: StrengthTemplate?
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    @State private var name: String
    @State private var items: [PerformedExercise]
    private let originalName: String?

    init(template: StrengthTemplate?) {
        self.template = template
        originalName = template?.name
        _name = State(initialValue: template?.name ?? "")
        _items = State(initialValue: template.map { t in
            t.exerciseIDs.map { id in
                let d = t.defaults[id]
                return PerformedExercise(exerciseID: id, sets: d?.sets, reps: d?.reps, weightKg: d?.weightKg, checked: false)
            }
        } ?? [])
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    TextField("Name der Vorlage", text: $name)
                        .padding(12)
                        .background(Theme.softFill, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                        .accessibilityIdentifier("strength.template.name")
                    Text("Übungen (Häkchen sind hier ohne Bedeutung, Vorwerte über den Regler).")
                        .font(.footnote).foregroundStyle(Theme.rowSecondary)
                    StrengthExerciseChecklist(exercises: $items)
                    Button { save() } label: { Text("Speichern").frame(maxWidth: .infinity) }
                        .buttonStyle(.jelly)
                        .disabled(!canSave)
                        .accessibilityIdentifier("strength.template.save")
                }
                .padding(.horizontal)
                .padding(.bottom, 24)
            }
            .background(Theme.canvas)
            .navigationTitle(template == nil ? "Neue Vorlage" : "Vorlage")
            .inlineNavigationTitle()
            .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Abbrechen") { dismiss() } } }
        }
        .presentationDetents([.large])
    }

    private var canSave: Bool { !name.trimmingCharacters(in: .whitespaces).isEmpty && !items.isEmpty }

    private func save() {
        var defaults: [String: SetDefaults] = [:]
        for e in items where !e.setDefaults.isEmpty { defaults[e.exerciseID] = e.setDefaults }
        if let originalName, originalName.lowercased() != name.trimmingCharacters(in: .whitespaces).lowercased() {
            model.deleteStrengthTemplate(named: originalName)
        }
        model.saveStrengthTemplate(StrengthTemplate(name: name, exerciseIDs: items.map(\.exerciseID), defaults: defaults))
        dismiss()
    }
}

/// Alle Katalogübungen nach Muskelgruppe, mit Beinanteil.
struct StrengthCatalogView: View {
    var body: some View {
        List {
            ForEach(MuscleGroup.allCases, id: \.self) { group in
                let items = ExerciseCatalog.all.filter { $0.muscles.first == group }
                if !items.isEmpty {
                    Section(group.label) {
                        ForEach(items) { e in
                            HStack {
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(e.name)
                                    Text(e.muscles.map(\.label).joined(separator: ", ")).font(.caption).foregroundStyle(Theme.rowSecondary)
                                }
                                Spacer()
                                Text("Beine \(e.legInvolvement.label)").font(.caption).foregroundStyle(Theme.rowSecondary)
                            }
                            .frame(minHeight: 44)
                            .accessibilityElement(children: .combine)
                        }
                    }
                }
            }
        }
        .scrollContentBackground(.hidden)
        .background(Theme.canvas)
        .navigationTitle("Übungskatalog")
        .inlineNavigationTitle()
    }
}
