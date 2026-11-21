import Foundation

// Verbindungsstatus für Profil → Dienste & Geräte (docs/18-KONZEPT-PROFIL-VERBINDUNGEN.md, „Datenmodell“).
// Der Status wird nur aus vorhandenen Werten abgeleitet; neu ist allein `AppModel.syncErrors` (nur im Speicher).

public enum ConnectionID: String, CaseIterable, Hashable, Sendable {
    case strava, myWhoosh, macBridge, fitImport, appleHealth, strap
}

/// Wofür ein Dienst in der App genutzt wird (Zeile „Fahrten · Pläne“).
public enum ConnectionRole: Sendable {
    case rides, plans, secondData, recovery, heartRate

    public var label: String {
        switch self {
        case .rides: "Fahrten"
        case .plans: "Pläne"
        case .secondData: "Sekundendaten"
        case .recovery: "Erholung"
        case .heartRate: "Puls"
        }
    }
}

public enum ConnectionStatus: Equatable, Sendable {
    case connected(detail: String?, lastSync: Date?)
    case notConnected
    /// „Erneut verbinden“, „Anmeldung abgelaufen“.
    case needsSetup(String)
    case error(String)
    case unavailable(String)

    /// Nur was der Nutzer beheben sollte. „Nicht verbunden“ ist kein Problem, sonst trüge jeder ohne Strava ein Badge.
    public var needsAttention: Bool {
        switch self {
        case .needsSetup, .error: true
        case .connected, .notConnected, .unavailable: false
        }
    }

    /// Kurzer Statustext rechts in der Zeile.
    public var label: String {
        switch self {
        case .connected: "Verbunden"
        case .notConnected: "Nicht verbunden"
        case .needsSetup(let text): text
        case .error: "Fehler"
        case .unavailable: "Nicht verfügbar"
        }
    }
}

public struct ConnectionDescriptor: Identifiable, Equatable, Sendable {
    public let id: ConnectionID
    public let name: String
    public let systemImage: String
    public let roles: [ConnectionRole]
    public let status: ConnectionStatus

    /// „Fahrten · Pläne“
    public var rolesText: String { roles.map(\.label).joined(separator: " · ") }
}

extension AppModel {
    /// Alle Dienste in Anzeigereihenfolge. `strap` nil: die Sitzung des Modells (wie in `deleteAllData`).
    public func connections(strap: StrapSession? = nil) -> [ConnectionDescriptor] {
        ConnectionID.allCases.map { connection($0, strap: strap) }
    }

    public func connection(_ id: ConnectionID, strap: StrapSession? = nil) -> ConnectionDescriptor {
        let (name, image, roles): (String, String, [ConnectionRole]) = switch id {
        case .strava: ("Strava", "arrow.triangle.2.circlepath", [.rides])
        case .myWhoosh: ("MyWhoosh", "figure.indoor.cycle", [.rides, .plans])
        case .macBridge: ("Sekundendaten vom Mac", "macbook.and.iphone", [.secondData])
        case .fitImport: ("FIT-Dateien importieren …", "doc.badge.plus", [.rides])
        case .appleHealth: ("Apple Health", "heart.text.square", [.recovery])
        case .strap: ("Brustgurt", "heart.circle", [.heartRate])
        }
        return ConnectionDescriptor(id: id, name: name, systemImage: image, roles: roles,
                                    status: connectionStatus(id, strap: strap ?? strapSessionOverride ?? StrapSession.shared))
    }

    /// Anzahl der Dienste mit „Erneut verbinden“ oder Fehler (Badge am Profil-Tab).
    public var connectionsNeedingAttention: Int {
        let strap = strapSessionOverride ?? StrapSession.shared
        return ConnectionID.allCases.filter { connectionStatus($0, strap: strap).needsAttention }.count
    }

    private func connectionStatus(_ id: ConnectionID, strap: StrapSession) -> ConnectionStatus {
        let failure = syncErrors[id]
        switch id {
        case .fitImport:
            return .connected(detail: nil, lastSync: nil)   // eine Aktion, kein Dienst: nie ein Problem
        case .strava:
            if let failure { return .error(failure) }
            if isStravaConnected { return .connected(detail: stravaAthleteName, lastSync: lastSync) }
            // Bewusstes Trennen löscht `lastSync` (disconnectStrava); bleibt es stehen, ging der Zugang verloren.
            return lastSync != nil ? .needsSetup("Erneut verbinden") : .notConnected
        case .myWhoosh:
            guard isMyWhooshConnected else { return .notConnected }
            // Es gibt keinen Refresh: ein abgelaufenes Token heißt „neu anmelden“ (MyWhooshClient).
            if myWhooshStore.loadSession()?.isExpired == true { return .needsSetup("Anmeldung abgelaufen") }
            if let failure { return .error(failure) }
            return .connected(detail: myWhooshUser, lastSync: lastMyWhooshImport)
        case .macBridge:
            guard isBridgePaired else { return .notConnected }
            if let failure { return .error(failure) }
            return .connected(detail: bridgeMacName, lastSync: lastBridgeSync)
        case .appleHealth:
            if !healthAvailable { return .unavailable("Auf diesem Gerät nicht verfügbar") }
            return healthEnabled ? .connected(detail: nil, lastSync: nil) : .notConnected
        case .strap:
            return strap.savedStrapID != nil ? .connected(detail: strap.deviceName, lastSync: nil) : .notConnected
        }
    }
}
