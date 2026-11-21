import Foundation
import SwiftData
import Testing
@testable import IndoorCoachKit

@MainActor
@Suite("AppModel · Vertrag Begeisterung (AP0)")
struct AppModelContractTests {
    /// The container must outlive the model (a released container traps SwiftData).
    private func makeModel(_ suite: String) throws -> (AppModel, UserDefaults, ModelContainer) {
        let container = try AppEnvironment.makeContainer(inMemory: true)
        let defaults = try #require(UserDefaults(suiteName: suite))
        return (AppModel(context: container.mainContext, secrets: InMemorySecretStore(), defaults: defaults), defaults, container)
    }

    @Test func newKeysAreRegisteredForDeletionAndUIFlags() {
        for key in ["moments.ledger", "moments.enabled", "why.note"] {
            #expect(AppModel.Keys.all.contains(key), "\(key) fehlt in Keys.all")
            #expect(AppModel.uiFlagKeys.contains(key), "\(key) fehlt in uiFlagKeys")
        }
        #expect(AppModel.Keys.momentsLedger == MomentLedger.defaultsKey)
    }

    @Test func defaultsAreEmptyAndCelebrationIsOn() throws {
        let suite = "ap0-\(UUID().uuidString)"
        let (model, defaults, container) = try makeModel(suite)
        defer { withExtendedLifetime(container) {} }
        defer { defaults.removePersistentDomain(forName: suite) }
        #expect(model.pendingMoments.isEmpty)
        #expect(model.whyNote == nil)
        #expect(model.momentsEnabled)
    }

    @Test func whyNoteAndSwitchPersistAndReload() throws {
        let suite = "ap0-\(UUID().uuidString)"
        let (model, defaults, container) = try makeModel(suite)
        defer { withExtendedLifetime(container) {} }
        defer { defaults.removePersistentDomain(forName: suite) }
        model.whyNote = "Im Mai die RTF mit Freunden"
        model.momentsEnabled = false
        #expect(defaults.string(forKey: "why.note") == "Im Mai die RTF mit Freunden")
        #expect(defaults.object(forKey: "moments.enabled") as? Bool == false)
        let reopened = AppModel(context: container.mainContext, secrets: InMemorySecretStore(), defaults: defaults)
        #expect(reopened.whyNote == "Im Mai die RTF mit Freunden")
        #expect(!reopened.momentsEnabled)
        model.whyNote = nil
        #expect(defaults.object(forKey: "why.note") == nil)
    }

    @Test func deleteAllDataRemovesLedgerSwitchAndWhyNote() async throws {
        let suite = "ap0-\(UUID().uuidString)"
        let (model, defaults, container) = try makeModel(suite)
        defer { withExtendedLifetime(container) {} }
        defer { defaults.removePersistentDomain(forName: suite) }
        var ledger = MomentLedger()
        ledger.markSeen("level-4-2026")
        ledger.save(to: defaults)
        model.momentsEnabled = false
        model.whyNote = "Mein Grund"
        model.pendingMoments = MomentBatch([Moment(id: "level-1-2026", kind: .levelUp, date: .now, headline: "H",
                                                   detail: nil, rideID: nil)])
        await model.deleteAllData()
        for key in ["moments.ledger", "moments.enabled", "why.note"] { #expect(defaults.object(forKey: key) == nil, "\(key)") }
        #expect(model.whyNote == nil && model.momentsEnabled && model.pendingMoments.isEmpty)
    }

    @Test func todayReadsTheUIOverrideOnlyFromWellFormedValues() throws {
        let suite = "ap0-\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "Europe/Berlin")!
        let now = Date(timeIntervalSince1970: 1_790_000_000)
        #expect(AppModel.today(defaults: defaults, now: now, calendar: calendar) == now)

        defaults.set("2027-01-10", forKey: AppModel.uiTodayKey)
        let overridden = AppModel.today(defaults: defaults, now: now, calendar: calendar)
        #if DEBUG
        let parts = calendar.dateComponents([.year, .month, .day, .hour], from: overridden)
        #expect(parts.year == 2027 && parts.month == 1 && parts.day == 10 && parts.hour == 12)
        #else
        #expect(overridden == now)
        #endif

        for bad in ["", "morgen", "2027-13-01", "2027-02-30", "10.01.2027"] {
            defaults.set(bad, forKey: AppModel.uiTodayKey)
            #expect(AppModel.today(defaults: defaults, now: now, calendar: calendar) == now, "\(bad)")
        }
        #expect(AppModel.parseUIToday("2026-12-21", calendar: calendar) != nil)
        #expect(AppModel.parseUIToday("2026-12-21x", calendar: calendar) == nil)
    }
}
