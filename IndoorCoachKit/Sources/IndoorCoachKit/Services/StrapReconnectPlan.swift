import Foundation

/// Zustandsmaschine für das Wiederverbinden mit dem gemerkten Gurt (ohne CoreBluetooth, damit testbar).
///
/// - Kennt das iPhone den Gurt nicht mehr, startet ein Rückfall-Scan (höchstens `fallbackScanSeconds`). Taucht der gemerkte
///   Gurt dort auf, wird verbunden und der Scan beendet; sonst meldet der Scan nach Ablauf „nicht gefunden“.
/// - Schlägt ein Verbindungsversuch fehl, wird mit wachsendem Abstand (2, 5, 10, dann höchstens 30 s) erneut versucht,
///   statt in einer Schleife auf den Funk zu hämmern.
public struct StrapReconnectPlan: Equatable, Sendable {
    public static let fallbackScanSeconds: TimeInterval = 60
    public static let backoffSeconds: [TimeInterval] = [2, 5, 10, 30]

    public enum Action: Equatable, Sendable {
        case none
        /// Scan nach dem gemerkten Gurt starten; zum Ablauf `fallbackTimerFired` aufrufen.
        case startFallbackScan(deadline: Date)
        /// Mit dem gefundenen Gurt verbinden und den Scan beenden.
        case connect(UUID)
        /// Zeit abgelaufen: Scan beenden, Status „nicht gefunden“.
        case reportNotFound
        /// Nach `after` Sekunden erneut verbinden.
        case retryConnect(after: TimeInterval)
    }

    public private(set) var pendingID: UUID?
    public private(set) var fallbackDeadline: Date?
    public private(set) var failures = 0

    public init() {}

    public var isFallbackScanning: Bool { fallbackDeadline != nil }

    /// Ein Verbindungswunsch für `id` (neuer Versuch, Zähler zurück).
    public mutating func connectRequested(_ id: UUID) {
        pendingID = id
        fallbackDeadline = nil
        failures = 0
    }

    /// Der gemerkte Gurt ist dem iPhone nicht bekannt: Rückfall-Scan, zeitlich begrenzt.
    public mutating func peripheralUnknown(now: Date) -> Action {
        guard pendingID != nil else { return .none }
        let deadline = now.addingTimeInterval(Self.fallbackScanSeconds)
        fallbackDeadline = deadline
        return .startFallbackScan(deadline: deadline)
    }

    /// Ein Gurt wurde beim Scan gesehen. Nur im Rückfall-Scan und nur der gemerkte verbindet; der Scan der Geräte-Ansicht nie.
    public mutating func discovered(_ id: UUID) -> Action {
        guard isFallbackScanning, id == pendingID else { return .none }
        fallbackDeadline = nil
        return .connect(id)
    }

    /// Der Zeitgeber des Rückfall-Scans ist abgelaufen (auch verspätet oder doppelt aufrufbar).
    public mutating func fallbackTimerFired(now: Date) -> Action {
        guard let deadline = fallbackDeadline, now >= deadline else { return .none }
        fallbackDeadline = nil
        pendingID = nil
        return .reportNotFound
    }

    public mutating func connectFailed() -> Action {
        guard pendingID != nil || failures > 0 else { return .none }
        let delay = Self.delay(afterFailures: failures)
        failures += 1
        return .retryConnect(after: delay)
    }

    public mutating func connected() { failures = 0; fallbackDeadline = nil }

    public mutating func cancel() { pendingID = nil; fallbackDeadline = nil; failures = 0 }

    /// 2, 5, 10, 30, 30 … Sekunden.
    public static func delay(afterFailures count: Int) -> TimeInterval {
        backoffSeconds[min(max(count, 0), backoffSeconds.count - 1)]
    }
}
