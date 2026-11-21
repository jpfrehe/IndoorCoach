import SwiftUI
import UniformTypeIdentifiers

/// Profil → Dienste & Geräte (docs/18): jede Verbindung eine Zeile mit Icon, Name, Rolle und Status (Symbol und Text).
struct ConnectionsView: View {
    @Environment(AppModel.self) private var model
    @State private var showFITImporter = false

    private static let rideServices: [ConnectionID] = [.strava, .myWhoosh, .macBridge, .fitImport]
    private static let deviceServices: [ConnectionID] = [.appleHealth, .strap]

    var body: some View {
        Form {
            Section {
                ForEach(Self.rideServices, id: \.self) { row($0) }
            } header: { Text("Fahrten & Pläne") } footer: {
                Text("Fahrten kommen von hier, neue Pläne gehen an MyWhoosh.")
            }
            Section {
                ForEach(Self.deviceServices, id: \.self) { row($0) }
            } header: { Text("Gesundheit & Geräte") } footer: {
                Text("Erholung und Puls bleiben auf diesem iPhone.")
            }
            Section {
                NavigationLink { FeedbackView() } label: {
                    Label("Dienst wünschen", systemImage: "plus.bubble").frame(minHeight: 44)
                }
                .accessibilityIdentifier("profile.requestService")
            } footer: {
                Text("Fehlt dir ein Dienst?")
            }
        }
        .scrollContentBackground(.hidden)
        .background(Theme.canvas)
        .navigationTitle("Dienste & Geräte")
        .fileImporter(isPresented: $showFITImporter, allowedContentTypes: [.data], allowsMultipleSelection: true) { result in
            if case .success(let urls) = result { model.importFITFiles(urls) }
        }
    }

    @ViewBuilder
    private func row(_ id: ConnectionID) -> some View {
        let descriptor = model.connection(id)
        if id == .fitImport {
            Button { showFITImporter = true } label: { ServiceRow(descriptor: descriptor) }
                .buttonStyle(.plain)
                .accessibilityIdentifier(Self.identifier(id))
        } else {
            NavigationLink(value: ProfileRoute.connection(id)) { ServiceRow(descriptor: descriptor) }
                .accessibilityIdentifier(Self.identifier(id))
        }
    }

    static func identifier(_ id: ConnectionID) -> String {
        switch id {
        case .strava: "profile.strava"
        case .myWhoosh: "profile.mywhoosh"
        case .macBridge: "profile.bridge"
        case .fitImport: "profile.fitImport"
        case .appleHealth: "profile.dataSources"
        case .strap: "profile.strap"
        }
    }
}

/// Eine Zeile: nebeneinander, bei AX-Größen untereinander und ohne Zeilenlimit.
struct ServiceRow: View {
    var descriptor: ConnectionDescriptor
    @Environment(\.dynamicTypeSize) private var typeSize

    private var showsStatus: Bool { descriptor.id != .fitImport }

    var body: some View {
        let layout = typeSize.isAccessibilitySize ? AnyLayout(VStackLayout(alignment: .leading, spacing: 6))
            : AnyLayout(HStackLayout(alignment: .center, spacing: 12))
        layout {
            HStack(spacing: 12) {
                Image(systemName: descriptor.systemImage)
                    .frame(width: 28)
                    .foregroundStyle(Theme.accent)
                    .accessibilityHidden(true)
                VStack(alignment: .leading, spacing: 2) {
                    Text(descriptor.name).fixedSize(horizontal: false, vertical: true)
                    Text(descriptor.rolesText).font(.caption).foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            if showsStatus {
                if !typeSize.isAccessibilitySize { Spacer(minLength: 8) }
                ConnectionStatusLabel(status: descriptor.status)
                    .font(.footnote)
                    .multilineTextAlignment(.trailing)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .frame(minHeight: 44)
        .accessibilityElement(children: .combine)
        .accessibilityLabel(accessibilityLabel)
        .accessibilityValue(descriptor.status.needsAttention ? "Braucht Aufmerksamkeit" : "")
    }

    private var accessibilityLabel: String {
        var parts = [descriptor.name, descriptor.rolesText]
        if showsStatus { parts.append(descriptor.status.label) }
        return parts.joined(separator: ", ")
    }
}

/// Ziel einer Zeile aus „Dienste & Geräte“; die älteren Seiten behalten ihr Layout.
struct ConnectionDestination: View {
    var id: ConnectionID

    var body: some View {
        switch id {
        case .strava: StravaConnectionView()
        case .myWhoosh: MyWhooshConnectionView()
        case .macBridge: MacBridgeView()
        case .appleHealth: DataSourcesView()
        case .strap: DevicesView()
        case .fitImport: EmptyView()   // fitImport öffnet direkt die Dateiauswahl, nie eine Seite
        }
    }
}
