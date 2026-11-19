import Observation
import SwiftUI

// Profil → Datenquellen (docs/17 §5, §6.1 P2, §8.4, §9.9; B51): Apple Health an/aus, erkannte Quellen, Pinning je
// Kennzahl, ehrliche Lücken, Health-Export (opt-in) und die Methodenseite.

// MARK: - Integrationspunkt

/// Was die Ansicht von der Health-Anbindung braucht. Die einzige Implementierung ist das `AppModel` (`AppModel+Health`):
/// ein Health-Ein/Aus-Zustand für Import, Gewicht und diese Ansicht.
@MainActor
public protocol HealthSettingsControlling: AnyObject {
    var healthAvailable: Bool { get }
    var healthEnabled: Bool { get }
    func setHealthEnabled(_ on: Bool) async
    func requestAuthorization() async throws
    /// Quellen der letzten Wochen je Kennzahl (nil = Workouts).
    func connectedSources() async -> [HealthSourceUsage]
    var pins: HealthSourcePins { get }
    /// `nil` = automatisch (Pin lösen). Ein Wechsel startet eine neue Basis ab heute.
    func pin(_ source: HealthSourceRef?, for metric: HealthMetric)
}

extension AppModel: HealthSettingsControlling {}

// MARK: - Ansicht

struct DataSourcesView: View {
    @Environment(AppModel.self) private var model
    @State private var usage: [HealthSourceUsage] = []
    @State private var exportSettings = HealthExportSettings()
    @State private var exportError: String?

    private var controller: any HealthSettingsControlling { model }
    private var exportService: HealthExportService { model.healthExport }

    var body: some View {
        Form {
            healthSection
            if controller.healthEnabled {
                typesSection
                sourcesSection
            }
            gapsSection
            exportSection
            Section {
                NavigationLink { MethodView() } label: {
                    Label("So rechnet IndoorCoach", systemImage: "function").frame(minHeight: 44)
                }
                .accessibilityIdentifier("dataSources.method")
            }
        }
        .scrollContentBackground(.hidden)
        .background(Theme.canvas)
        .navigationTitle("Datenquellen")
        .accessibilityIdentifier("dataSources.view")
        .task(id: controller.healthEnabled) {
            usage = await controller.connectedSources()
            exportSettings = exportService.settings
        }
    }

    // MARK: Apple Health

    private var healthSection: some View {
        Section {
            Toggle("Apple Health", isOn: Binding(get: { controller.healthEnabled },
                                                 set: { on in Task { await controller.setHealthEnabled(on) } }))
                .disabled(!controller.healthAvailable)
                .accessibilityIdentifier("dataSources.healthToggle")
            if controller.healthEnabled {
                Button("Berechtigung erneut anfragen") { Task { try? await controller.requestAuthorization() } }
                    .frame(minHeight: 44)
                    .accessibilityIdentifier("dataSources.authorize")
            }
        } header: { Text("Lesen") } footer: {
            Text(controller.healthAvailable
                 ? "IndoorCoach liest nur, was du in Health freigibst. Die Daten bleiben auf deinem Gerät und werden nicht an den Coach gesendet."
                 : "Health ist auf diesem Gerät nicht verfügbar.")
        }
    }

    private var typesSection: some View {
        Section("Was gelesen wird") {
            ForEach(DataSourceTexts.shownTypes, id: \.self) { type in
                VStack(alignment: .leading, spacing: 2) {
                    Text(DataSourceTexts.title(for: type)).font(.subheadline.weight(.semibold))
                    Text(DataSourceTexts.explanation(for: type)).font(.footnote).foregroundStyle(Theme.rowSecondary)
                }
                .padding(.vertical, 2)
                .accessibilityElement(children: .combine)
            }
        }
    }

    // MARK: Quellen & Pinning

    private var sourcesSection: some View {
        Section {
            let workouts = usage.filter { $0.metric == nil }
            if usage.isEmpty {
                Text("Noch keine Quellen erkannt. Sie erscheinen, sobald Health Werte der letzten 4 Wochen liefert.")
                    .font(.footnote).foregroundStyle(Theme.rowSecondary)
            }
            if !workouts.isEmpty { sourceRows(title: "Workouts", rows: workouts) }
            ForEach(HealthMetric.allCases, id: \.self) { metric in
                let rows = usage.filter { $0.metric == metric }
                if !rows.isEmpty {
                    sourceRows(title: DataSourceTexts.title(for: metric), rows: rows)
                    pinPicker(metric: metric, rows: rows)
                }
            }
        } header: { Text("Erkannte Quellen") } footer: {
            Text(DataSourceTexts.pinNote)
        }
        .accessibilityIdentifier("dataSources.sources")
    }

    private func sourceRows(title: String, rows: [HealthSourceUsage]) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title).font(.subheadline.weight(.semibold))
            ForEach(rows, id: \.source) { row in
                Text("\(row.source.name) · \(row.days) \(row.days == 1 ? "Tag" : "Tage")")
                    .font(.footnote).foregroundStyle(Theme.rowSecondary)
            }
        }
        .accessibilityElement(children: .combine)
    }

    private func pinPicker(metric: HealthMetric, rows: [HealthSourceUsage]) -> some View {
        let suggestion = rows.first?.source
        return Picker("Quelle für \(DataSourceTexts.title(for: metric))",
                      selection: Binding(get: { controller.pins.pins[metric]?.source },
                                         set: { controller.pin($0, for: metric) })) {
            Text(suggestion.map { "Automatisch (Vorschlag: \($0.name))" } ?? "Automatisch").tag(HealthSourceRef?.none)
            ForEach(rows.map(\.source), id: \.self) { Text($0.name).tag(Optional($0)) }
        }
        .frame(minHeight: 44)
        .accessibilityIdentifier("dataSources.pin.\(metric.rawValue)")
    }

    // MARK: Lücken

    private var gapsSection: some View {
        Section {
            ForEach(DataSourceTexts.gaps, id: \.self) {
                Label($0, systemImage: "info.circle").font(.footnote).foregroundStyle(Theme.rowSecondary)
            }
        } header: { Text("Was fehlt – ehrlich gesagt") }
            .accessibilityIdentifier("dataSources.gaps")
    }

    // MARK: Export

    private var exportSection: some View {
        Section {
            ForEach(HealthExportSport.allCases, id: \.self) { sport in
                Toggle(sport.title, isOn: Binding(get: { exportSettings.isEnabled(sport) }, set: { on in setExport(sport, on) }))
                    .disabled(!exportService.isAvailable)
                    .accessibilityIdentifier("dataSources.export.\(sport.rawValue)")
            }
            if let exportError { Text(exportError).font(.footnote).foregroundStyle(.red) }
        } header: { Text("In Apple Health speichern (optional)") } footer: {
            Text("Standardmäßig aus. Gespeichert werden nur deine eigenen Aufzeichnungen als Workout mit Puls – nie Leistung oder angenommene Watt. Gibt es zur selben Zeit schon ein Workout einer anderen App (mind. 50 % Überschneidung), wird nichts gespeichert. Das Schreibrecht wird erst beim Einschalten angefragt.")
        }
    }

    private func setExport(_ sport: HealthExportSport, _ on: Bool) {
        exportError = nil
        Task {
            do { try await exportService.setEnabled(sport, on) } catch { exportError = "Konnte die Freigabe nicht einrichten." }
            exportSettings = exportService.settings
        }
    }
}

// MARK: - Methodenseite

struct MethodView: View {
    var body: some View {
        List {
            ForEach(DataSourceTexts.method, id: \.title) { item in
                VStack(alignment: .leading, spacing: 4) {
                    Text(item.title).font(.headline).accessibilityAddTraits(.isHeader)
                    Text(item.text).font(.subheadline).foregroundStyle(Theme.rowSecondary)
                }
                .padding(.vertical, 4)
                .accessibilityElement(children: .combine)
            }
        }
        .scrollContentBackground(.hidden)
        .background(Theme.canvas)
        .navigationTitle("So rechnet IndoorCoach")
        .accessibilityIdentifier("dataSources.methodView")
    }
}
