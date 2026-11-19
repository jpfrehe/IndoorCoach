import Foundation
import SwiftData

/// Cache of Aufwärm-Check results per ride (decoding the seconds of many rides must not slow the screens down).
@MainActor
private enum WarmupCheckCache {
    struct Key: Hashable {
        var model: ObjectIdentifier
        var rideID: Int
        var ftp: Int
        var refWatts: Int
    }
    /// nil = no block found in that ride (cached too; `invalidateWarmupChecks` runs on every import).
    static var entries: [Key: WarmupCheck?] = [:]
}

extension AppModel {
    /// Reference watts of the Aufwärm-Check. Persists the default derived from the FTP on first use, so a later
    /// FTP change does not move the baseline (only "Neue Basis ab heute" does).
    @discardableResult
    func ensureWarmupReference() -> Int {
        if let stored = profile.warmupCheckWatts { return stored }
        let watts = profile.effectiveWarmupCheckWatts
        guard watts > 0 else { return watts }
        profile.warmupCheckWatts = watts
        return watts
    }

    /// The ride's Aufwärm-Check, from the linked planned workout (if any) and its seconds; nil without a block or seconds.
    public func warmupCheck(for ride: RideSummary) -> WarmupCheck? {
        let ref = profile.effectiveWarmupCheckWatts
        let key = WarmupCheckCache.Key(model: ObjectIdentifier(self), rideID: ride.id, ftp: profile.ftp, refWatts: ref)
        if let cached = WarmupCheckCache.entries[key] { return cached }
        if WarmupCheckCache.entries.count > 2_000 { WarmupCheckCache.entries.removeAll() }
        var result: WarmupCheck?
        if ride.trainer, let seconds = rideSeconds(id: ride.id) {
            let rideID = ride.id
            var descriptor = FetchDescriptor<StoredWorkout>(predicate: #Predicate { $0.linkedRideID == rideID })
            descriptor.fetchLimit = 1
            let definition = (try? context.fetch(descriptor))?.first?.definition
            result = WarmupCheck.evaluate(date: ride.startDate, definition: definition, seconds: seconds,
                                          ftp: profile.ftp, refWatts: ref)
        }
        WarmupCheckCache.entries[key] = .some(result)
        return result
    }

    /// Trend over the indoor rides since the baseline date (newest 120 rides at most). Standard: nur gemessene Werte
    /// (Erholungskontext, Wächter); `.assumedERG` liefert den getrennten Trend der angenommenen Leistung (nur Anzeige).
    public func warmupTrend(rides: [RideSummary]? = nil, source: WarmupCheck.Source = .measured) -> WarmupCheck.Trend {
        let ref = profile.effectiveWarmupCheckWatts
        let since = profile.warmupCheckBaseSince
        let candidates = (rides ?? allRides())
            .filter { $0.trainer && $0.startDate >= (since ?? .distantPast) }
            .sorted { $0.startDate > $1.startDate }
            .prefix(120)
        return WarmupCheck.trend(checks: candidates.compactMap { warmupCheck(for: $0) }, refWatts: ref, since: since, source: source)
    }

    /// "Neue Basis ab heute": reference power from the current FTP, older measurements no longer count.
    public func startNewWarmupBase(now: Date = .now) {
        profile.warmupCheckWatts = WarmupCheck.defaultWatts(ftp: profile.ftp)
        profile.warmupCheckBaseSince = Calendar.current.startOfDay(for: now)
    }

    /// Imports add or replace seconds data: forget every result.
    func invalidateWarmupChecks() {
        WarmupCheckCache.entries.removeAll()
    }
}
