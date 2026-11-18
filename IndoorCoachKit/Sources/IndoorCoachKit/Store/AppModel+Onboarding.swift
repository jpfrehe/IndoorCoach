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

    public var profileReady: Bool
    public var myWhooshConnected: Bool
    public var coachReady: Bool
    public var rideCount: Int

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
    public static let onboardingStepCount = 5

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
        OnboardingSummary(profileReady: !profile.trainingDays.isEmpty, myWhooshConnected: isMyWhooshConnected,
                          coachReady: hasClaudeKey, rideCount: importedRideCount)
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
