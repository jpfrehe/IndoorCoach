import SwiftUI

/// Schnellstart „Kraft“: Vorlage wählen (Vorlagen, „Wie letzte Woche“, ohne Vorlage), dann mit Gurt aufzeichnen
/// (nur wenn die Integration `strengthRecordAction` gesetzt hat) oder nachtragen.
struct StrengthQuickStartSheet: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    @Environment(\.strengthRecordAction) private var recordAction
    @State private var templates: [StrengthTemplate] = []
    @State private var lastWeek: StrengthTemplate?
    /// nil = ohne Vorlage
    @State private var selected: StrengthTemplate?
    @State private var path: [Step] = []

    enum Step: Hashable { case entry }

    var body: some View {
        NavigationStack(path: $path) {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    Text("Womit startest du?").font(.headline)
                    VStack(spacing: 8) {
                        if let lastWeek {
                            templateButton(lastWeek, subtitle: "\(lastWeek.exerciseIDs.count) Übungen, mit deinen Werten", id: "lastweek")
                        }
                        ForEach(templates) { t in
                            templateButton(t, subtitle: "\(t.exerciseIDs.count) Übungen", id: "template.\(t.name)")
                        }
                        noTemplateButton
                    }
                    if let selected {
                        Text(selected.exerciseIDs.map(StrengthFormat.exerciseName).joined(separator: ", "))
                            .font(.footnote).foregroundStyle(Theme.rowSecondary)
                    }
                    VStack(spacing: 10) {
                        if let recordAction {
                            Button { dismiss(); recordAction(selected) } label: {
                                Label("Mit Gurt aufzeichnen", systemImage: "heart.circle.fill").frame(maxWidth: .infinity)
                            }
                            .buttonStyle(.jelly)
                            .accessibilityIdentifier("strength.start.record")
                        }
                        Button { path.append(.entry) } label: {
                            Text("Nachtragen").frame(maxWidth: .infinity)
                        }
                        .buttonStyle(recordAction == nil ? AnyButtonStyle(.jelly) : AnyButtonStyle(.soft))
                        .accessibilityIdentifier("strength.start.manual")
                    }
                }
                .padding(.horizontal)
                .padding(.bottom, 24)
            }
            .background(Theme.canvas)
            .navigationTitle("Kraft")
            .inlineNavigationTitle()
            .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Schließen") { dismiss() } } }
            .navigationDestination(for: Step.self) { _ in
                StrengthEntryForm(kind: .strength, template: selected) { dismiss() }
            }
        }
        .presentationDetents([.large])
        .onAppear(perform: load)
    }

    private func load() {
        templates = model.strengthTemplates()
        lastWeek = model.lastWeekTemplate()
        if selected == nil, let lastWeek { selected = lastWeek }
    }

    private var noTemplateButton: some View {
        tile(title: "Ohne Vorlage", subtitle: "Übungen später frei wählen", isSelected: selected == nil, id: "none") { selected = nil }
    }

    private func templateButton(_ t: StrengthTemplate, subtitle: String, id: String) -> some View {
        tile(title: t.name, subtitle: subtitle, isSelected: selected == t, id: id) { selected = t }
    }

    private func tile(title: String, subtitle: String, isSelected: Bool, id: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text(title).font(.body.weight(.semibold))
                    Text(subtitle).font(.caption).foregroundStyle(isSelected ? Theme.ink.opacity(0.75) : Theme.rowSecondary)
                }
                Spacer()
                if isSelected { Image(systemName: "checkmark.circle.fill") }
            }
            .foregroundStyle(isSelected ? Theme.ink : .primary)
            .padding(.horizontal, 14)
            .frame(maxWidth: .infinity, minHeight: 60, alignment: .leading)
            .background(isSelected ? AnyShapeStyle(Theme.sunset) : AnyShapeStyle(Theme.softFill),
                        in: RoundedRectangle(cornerRadius: 16, style: .continuous))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(isSelected ? .isSelected : [])
        .accessibilityIdentifier("strength.start.\(id)")
    }
}

/// Sheet „Andere Einheit“: Sportart wählen, dann mit Gurt aufzeichnen (nur wenn die Integration `otherRecordAction`
/// gesetzt hat) oder nachtragen.
struct OtherSessionSheet: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.otherRecordAction) private var recordAction
    @State private var sport = StrengthEntryForm.sports[0]
    @State private var path: [StrengthQuickStartSheet.Step] = []

    var body: some View {
        NavigationStack(path: $path) {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    Text("Welche Sportart?").font(.headline)
                    Picker("Sportart", selection: $sport) {
                        ForEach(StrengthEntryForm.sports, id: \.self) { Text($0).tag($0) }
                    }
                    .pickerStyle(.menu)
                    .frame(minHeight: 44)
                    .accessibilityIdentifier("other.start.sport")
                    VStack(spacing: 10) {
                        if let recordAction {
                            Button { dismiss(); recordAction(sport) } label: {
                                Label("Mit Gurt aufzeichnen", systemImage: "heart.circle.fill").frame(maxWidth: .infinity)
                            }
                            .buttonStyle(.jelly)
                            .accessibilityIdentifier("other.start.record")
                        }
                        Button { path.append(.entry) } label: { Text("Nachtragen").frame(maxWidth: .infinity) }
                            .buttonStyle(recordAction == nil ? AnyButtonStyle(.jelly) : AnyButtonStyle(.soft))
                            .accessibilityIdentifier("other.start.manual")
                    }
                }
                .padding(.horizontal)
                .padding(.bottom, 24)
            }
            .background(Theme.canvas)
            .navigationTitle("Andere Einheit")
            .inlineNavigationTitle()
            .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Schließen") { dismiss() } } }
            .navigationDestination(for: StrengthQuickStartSheet.Step.self) { _ in
                StrengthEntryForm(kind: .other, sport: sport) { dismiss() }
            }
        }
        .presentationDetents([.large])
    }
}

/// Schnellstart-Zeile auf Heute: [Kraft] [Andere Einheit].
struct StrengthQuickStartRow: View {
    @Environment(AppModel.self) private var model
    @State private var showStrength = false
    @State private var showOther = false

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 10) {
                button("Kraft", systemImage: "dumbbell", id: "strength.quick.kraft") { showStrength = true }
                button("Andere Einheit", systemImage: "figure.run", id: "strength.quick.other") { showOther = true }
            }
            if model.isStrengthDay() {
                Text("Heute ist Studio-Tag.").font(.caption).foregroundStyle(Theme.rowSecondary)
            }
        }
        .sheet(isPresented: $showStrength) { StrengthQuickStartSheet() }
        .sheet(isPresented: $showOther) { OtherSessionSheet() }
    }

    private func button(_ title: String, systemImage: String, id: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Label(title, systemImage: systemImage)
                .font(.body.weight(.semibold))
                .foregroundStyle(Theme.accent)
                .frame(maxWidth: .infinity, minHeight: 52)
                .background(Theme.softFill, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier(id)
    }
}
