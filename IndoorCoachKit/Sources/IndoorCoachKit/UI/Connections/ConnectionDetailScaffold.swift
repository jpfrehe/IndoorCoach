import SwiftUI

// Gerüst jeder Dienst-Detailseite (docs/18, „Detailseite eines Dienstes“): Status-Kopf, Hauptaktion, Optionen,
// Hilfe-Footer mit Link, Trennen ganz unten (immer mit Rückfrage).

/// „Trennen“ ganz unten samt Rückfrage.
struct ConnectionDisconnect {
    var buttonTitle: String
    var dialogTitle: String
    var confirmTitle: String
    var message: String
    var identifier: String?
    var perform: () -> Void
}

struct ConnectionHelpLink {
    var title: String
    var systemImage: String
    var url: URL
}

struct ConnectionDetailScaffold<Status: View, Main: View, Options: View>: View {
    var title: String
    var footer: String?
    var help: ConnectionHelpLink?
    var disconnect: ConnectionDisconnect?
    private let status: Status
    private let main: Main
    private let options: Options
    private let hasOptions: Bool
    @State private var confirmDisconnect = false

    init(title: String, footer: String? = nil, help: ConnectionHelpLink? = nil, disconnect: ConnectionDisconnect? = nil,
         showsOptions: Bool = true,
         @ViewBuilder status: () -> Status, @ViewBuilder main: () -> Main, @ViewBuilder options: () -> Options) {
        self.title = title
        self.footer = footer
        self.help = help
        self.disconnect = disconnect
        self.status = status()
        self.main = main()
        self.options = options()
        hasOptions = showsOptions
    }

    var body: some View {
        Form {
            Section { status }
            Section { main }
            if hasOptions { Section { options } }
            if footer != nil || help != nil {
                Section {
                    if let help {
                        Link(destination: help.url) { Label(help.title, systemImage: help.systemImage).frame(minHeight: 44) }
                    }
                } footer: {
                    if let footer { Text(footer) }
                }
            }
            if let disconnect {
                Section {
                    Button(disconnect.buttonTitle, role: .destructive) { confirmDisconnect = true }
                        .frame(minHeight: 44)
                        .accessibilityIdentifier(disconnect.identifier ?? "connection.disconnect")
                }
            }
        }
        .scrollContentBackground(.hidden)
        .scrollDismissesKeyboard(.interactively)
        .background(Theme.canvas)
        .navigationTitle(title)
        .confirmationDialog(disconnect?.dialogTitle ?? "", isPresented: $confirmDisconnect, titleVisibility: .visible) {
            if let disconnect {
                Button(disconnect.confirmTitle, role: .destructive, action: disconnect.perform)
            }
        } message: {
            if let disconnect { Text(disconnect.message) }
        }
    }
}

extension ConnectionDetailScaffold where Options == EmptyView {
    init(title: String, footer: String? = nil, help: ConnectionHelpLink? = nil, disconnect: ConnectionDisconnect? = nil,
         @ViewBuilder status: () -> Status, @ViewBuilder main: () -> Main) {
        self.title = title
        self.footer = footer
        self.help = help
        self.disconnect = disconnect
        self.status = status()
        self.main = main()
        options = EmptyView()
        hasOptions = false
    }
}

// MARK: - Status

/// Symbol UND Text, nie nur Farbe.
struct ConnectionStatusLabel: View {
    var status: ConnectionStatus
    /// Im Kopf einer Detailseite: Text in Primärfarbe statt grau (in der Liste bleibt er zurückhaltend).
    var emphasized = false

    private var symbol: String {
        switch status {
        case .connected: "checkmark.circle.fill"
        case .needsSetup, .error: "exclamationmark.triangle.fill"
        case .notConnected: "circle.dashed"
        case .unavailable: "minus.circle"
        }
    }

    private var tint: Color {
        switch status {
        case .connected: Theme.done
        case .needsSetup, .error: .orange
        case .notConnected, .unavailable: .secondary
        }
    }

    var body: some View {
        Label {
            Text(status.label).foregroundStyle(status.needsAttention ? Color.orange : (emphasized ? .primary : .secondary))
        } icon: {
            Image(systemName: symbol).foregroundStyle(tint)
        }
        .labelStyle(.titleAndIcon)
    }
}

/// Kopf einer Detailseite: Status, „verbunden als …“, letzter Sync, ggf. Fehlertext.
/// `account`/`lastSync` gelten, wenn der Status nicht `.connected` ist, das Konto aber besteht (Fehler, abgelaufen).
struct ConnectionStatusHeader: View {
    var status: ConnectionStatus
    var syncTitle: String
    var account: String? = nil
    var lastSync: Date? = nil

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            ConnectionStatusLabel(status: status, emphasized: true).font(.headline)
            let shown = shownDetails
            if let detail = shown.detail { LabeledContent("Verbunden als", value: detail) }
            if let sync = shown.lastSync {
                LabeledContent(syncTitle, value: sync.formatted(.relative(presentation: .named).locale(Locale.de)))
            }
            if case let .error(message) = status {
                Text(message).font(.subheadline).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            }
        }
        .frame(minHeight: 44, alignment: .leading)
    }

    private var shownDetails: (detail: String?, lastSync: Date?) {
        switch status {
        case let .connected(detail, lastSync): (detail, lastSync)
        case .error, .needsSetup: (account, lastSync)
        case .notConnected, .unavailable: (nil, nil)
        }
    }
}
