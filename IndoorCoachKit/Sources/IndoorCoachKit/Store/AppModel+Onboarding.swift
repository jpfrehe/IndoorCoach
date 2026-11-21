import Foundation
import SwiftData

/// Result of checking a Claude API key against `GET /v1/models`.
public enum ClaudeKeyCheck: Equatable, Sendable {
    case valid
    /// 401 – wrong or revoked key.
    case invalid
    /// 403 – the key exists but may not use the API.
    case forbidden
    /// Network or server trouble: the key could not be checked (the user may save it anyway).
    case unreachable
}

/// Antworten und Entscheidungen der Einführung (docs/20, Abschnitt 9). Lokal in UserDefaults, nie gesendet.
public struct OnboardingServicesState: Codable, Equatable, Sendable {
    public var answers = ServiceAnswers()
    /// „Später“ getippt.
    public var deferred: Set<ConnectionID> = []
    /// „Nach der Einführung einrichten“ bei Strava.
    public var stravaAfterwards = false

    public init(answers: ServiceAnswers = ServiceAnswers(), deferred: Set<ConnectionID> = [], stravaAfterwards: Bool = false) {
        self.answers = answers
        self.deferred = deferred
        self.stravaAfterwards = stravaAfterwards
    }
}

/// "Fertig" step: what the athlete set up during onboarding.
public struct OnboardingSummary: Equatable, Sendable {
    public struct Item: Equatable, Sendable, Identifiable {
        public let title: String
        public let symbol: String
        public let isDone: Bool
        public let detail: String
        public var id: String { title }
        /// One spoken sentence for VoiceOver.
        public var accessibilityLabel: String { "\(title): \(detail)" }
    }

    /// Eine Dienstzeile der Zusammenfassung (nur empfohlene, angefasste oder verbundene Dienste).
    public struct ServiceLine: Equatable, Sendable, Identifiable {
        public enum State: Equatable, Sendable {
            /// Mit Detail, z. B. „Verbunden · 23 Fahrten geladen“.
            case connected(String)
            case later
            case notConnected
        }

        public let id: ConnectionID
        /// Name in der Einführung (die Mac-Brücke heißt dort „Fahrten im Detail vom Mac“).
        public let name: String
        /// Name unter Profil → Dienste & Geräte, damit die Zeile dort wiederzufinden ist.
        public let hubName: String
        public let state: State

        public var isConnected: Bool { if case .connected = state { true } else { false } }

        /// Text unter dem Namen.
        public var visualDetail: String {
            switch state {
            case .connected(let detail): detail
            case .later, .notConnected: "Später unter Profil → Dienste & Geräte → \(hubName)"
            }
        }

        /// One spoken sentence for VoiceOver (ohne Pfeile).
        public var accessibilityLabel: String {
            switch state {
            case .connected(let detail): "\(name): \(detail)"
            case .later, .notConnected: "\(name): später unter Profil, Dienste und Geräte, \(hubName)"
            }
        }
    }

    public var profileReady: Bool
    public var myWhooshConnected: Bool
    public var coachReady: Bool
    public var rideCount: Int
    /// Dienstzeilen in der Reihenfolge der Empfehlungen (ohne Strava, das hat `stravaAfterwards`).
    public var services: [ServiceLine] = []
    /// „Strava nach der Einführung einrichten“ wurde gewählt.
    public var stravaAfterwards = false

    public var items: [Item] {
        [Item(title: "Profil", symbol: "person.crop.circle", isDone: profileReady,
              detail: profileReady ? "eingerichtet" : "Trainingstag fehlt"),
         Item(title: "MyWhoosh", symbol: "figure.indoor.cycle", isDone: myWhooshConnected,
              detail: myWhooshConnected ? (rideCount > 0 ? "verbunden, \(rideCount) Fahrten geladen" : "verbunden") : "nicht verbunden"),
         Item(title: "Coach", symbol: "sparkles", isDone: coachReady,
              detail: coachReady ? "Claude-Key gespeichert" : "nicht eingerichtet, Demo-Plan")]
    }
}

extension AppModel {
    /// welcome, training, rides, extras, services, coach, done (docs/20 §4.1).
    public static let onboardingStepCount = 7

    /// Einmalige Umrechnung des Schritts aus `onboarding.step.v2` (5 Schritte) in die 7 Schritte von v3.
    /// Unbekannte Werte liefern nil: dann beginnt die Einführung vorn.
    static func migratedStep(v2: Int?) -> Int? {
        switch v2 {
        case 0?: 0
        case 1?: 1
        case 2?: 2   // Trainings-App → Womit fährst du drinnen?
        case 3?: 5   // Coach
        case 4?: 6   // Fertig
        default: nil
        }
    }

    /// Was auf diesem Gerät und in diesem Build angeboten werden kann (Empfehlungen werden nie gespeichert).
    public var serviceAvailability: ServiceAvailability {
        ServiceAvailability(intervalsOAuth: intervalsConfig.isOAuthAvailable, bridgeDownload: bridgeDownloadURL != nil,
                            health: healthAvailable)
    }

    /// Download der Mac-App „IndoorCoach Brücke“ (E1); nil, solange es keinen Bezugsweg gibt.
    public var bridgeDownloadURL: URL? {
        #if DEBUG
        if UserDefaults.standard.bool(forKey: "uiBridgeAvailable") { return URL(string: "https://example.invalid/bridge") }
        #endif
        return bridgeDownloadURLOverride ?? AppConfig.bridgeDownloadURL
    }

    /// Persönliche Liste „Für dich passt“, berechnet aus Antworten und Verfügbarkeit.
    public var serviceRecommendations: [ServiceRecommendation] {
        ServiceRecommender.recommend(onboardingServices.answers, serviceAvailability)
    }

    /// "Weiß ich nicht": 2,5 W/kg × Gewicht, auf 5 W gerundet und auf den FTP-Bereich begrenzt.
    public static func estimatedFTP(weightKg: Double) -> Int {
        let rounded = Int((weightKg * 2.5 / 5).rounded()) * 5
        return min(max(rounded, 80), 500)
    }

    public func estimateFTP() {
        profile.ftp = Self.estimatedFTP(weightKg: profile.weightKg)
    }

    /// Rides that came from MyWhoosh/Strava/FIT (no demo data).
    public var importedRideCount: Int {
        (try? context.fetchCount(FetchDescriptor<StoredRide>(predicate: #Predicate { !$0.isDemo }))) ?? 0
    }

    public var onboardingSummary: OnboardingSummary {
        let rides = importedRideCount
        return OnboardingSummary(profileReady: !profile.trainingDays.isEmpty, myWhooshConnected: isMyWhooshConnected,
                                 coachReady: hasClaudeKey, rideCount: rides,
                                 services: summaryServiceLines(rideCount: rides),
                                 stravaAfterwards: onboardingServices.stravaAfterwards)
    }

    /// Empfohlene Dienste, angefasste („Später“) und verbundene; Strava und FIT-Import zählen nie als „verbunden“.
    private func summaryServiceLines(rideCount: Int) -> [OnboardingSummary.ServiceLine] {
        let state = onboardingServices
        let strap = strapSessionOverride ?? StrapSession.shared
        return serviceRecommendations.compactMap { entry -> OnboardingSummary.ServiceLine? in
            let id = entry.id
            guard id != .strava else { return nil }
            var detail: String?
            if id != .fitImport, case .connected(let text, _) = connection(id, strap: strap).status {
                detail = Self.summaryDetail(id, statusDetail: text, rideCount: rideCount)
            }
            let later = state.deferred.contains(id)
            guard entry.tier == .recommended || later || detail != nil else { return nil }
            let lineState: OnboardingSummary.ServiceLine.State = detail.map { .connected($0) } ?? (later ? .later : .notConnected)
            let name = id == .macBridge ? "Fahrten im Detail vom Mac" : connection(id, strap: strap).name
            return OnboardingSummary.ServiceLine(id: id, name: name, hubName: connection(id, strap: strap).name, state: lineState)
        }
    }

    private static func summaryDetail(_ id: ConnectionID, statusDetail: String?, rideCount: Int) -> String {
        switch id {
        case .myWhoosh:
            return rideCount > 0 ? "Verbunden · \(rideCount) \(rideCount == 1 ? "Fahrt" : "Fahrten") geladen"
                                 : "Verbunden · noch keine Fahrten gefunden"
        case .intervalsICU: return statusDetail.map { "Verbunden als \($0)" } ?? "Verbunden"
        case .macBridge: return statusDetail.map { "Gekoppelt mit \($0)" } ?? "Gekoppelt"
        case .appleHealth: return "Freigabe erteilt"
        case .strap: return statusDetail ?? "Gekoppelt"
        case .strava, .fitImport: return "Verbunden"
        }
    }

    /// Checks the key (free `GET /v1/models`) and stores it in the Keychain only when Anthropic accepts it.
    public func validateAndStoreClaudeKey(_ raw: String) async -> ClaudeKeyCheck {
        let key = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !key.isEmpty else { return .invalid }
        do {
            try await ClaudeClient(apiKey: key, transport: transport).validateKey()
            setClaudeAPIKey(key)
            return .valid
        } catch ClaudeError.invalidAPIKey {
            return .invalid
        } catch ClaudeError.permissionDenied {
            return .forbidden
        } catch {
            Log.error(.claude, "Key-Prüfung nicht möglich: \(type(of: error))")
            return .unreachable
        }
    }
}

#if DEBUG
extension ServiceAnswers {
    /// `-uiOnboardingAnswers "rides=myWhoosh,zwift;device=mac;extras=appleWatch,heartStrap;showAll=true"`.
    /// Unbekannte Schlüssel und Werte werden übergangen.
    static func parseUITest(_ raw: String) -> ServiceAnswers {
        var answers = ServiceAnswers()
        for part in raw.split(separator: ";") {
            let pair = part.split(separator: "=", maxSplits: 1).map { $0.trimmingCharacters(in: .whitespaces) }
            guard pair.count == 2 else { continue }
            let values = pair[1].split(separator: ",").map { $0.trimmingCharacters(in: .whitespaces) }
            switch pair[0] {
            case "rides": answers.rideApps = Set(values.compactMap(RideApp.init(rawValue:)))
            case "device": answers.myWhooshDevice = values.first.flatMap(RideDevice.init(rawValue:))
            case "extras": answers.extras = Set(values.compactMap(ExtraGear.init(rawValue:)))
            case "showAll": answers.showAll = ["true", "yes", "1"].contains(pair[1].lowercased())
            default: break
            }
        }
        return answers
    }
}
#endif
