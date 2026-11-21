import Foundation
import Testing
@testable import IndoorCoachKit

@Suite("Momente · Vertrag (AP0)")
struct MomentsContractTests {
    private func moment(_ kind: Moment.Kind, id: String? = nil, day: Int = 1) -> Moment {
        Moment(id: id ?? "\(kind.rawValue)-x", kind: kind, date: Date(timeIntervalSince1970: Double(day) * 86_400),
               headline: "H", detail: nil, rideID: nil)
    }

    @Test func kindsFollowTheDocumentedPriorityOrder() {
        let order: [Moment.Kind] = [.levelUp, .record, .ftpRise, .challengeCompleted, .comeback, .streak, .firstRide,
                                    .weekPlanDone, .strengthTier, .secondData]
        #expect(Moment.Kind.allCases == order)
        let priorities = order.map(\.priority)
        #expect(priorities == priorities.sorted(by: >))
        #expect(Set(priorities).count == order.count)
        #expect(moment(.levelUp).priority == Moment.Kind.levelUp.priority)
    }

    @Test func stableIDs() {
        #expect(Moment.Key.level(4, season: "2026") == "level-4-2026")
        #expect(Moment.Key.record(duration: 300, rideID: 77) == "record-300-77")
        #expect(Moment.Key.ftp(238, season: "2026") == "ftp-238-2026")
        #expect(Moment.Key.challenge("indoor-500") == "challenge-indoor-500")
        #expect(Moment.Key.comeback(rideID: 9) == "comeback-9")
        #expect(Moment.Key.streak(8, season: "2026") == "streak-8-2026")
        #expect(Moment.Key.firstRide(season: "2026") == "first-2026")
        #expect(Moment.Key.week(start: "2026-12-14") == "week-2026-12-14")
        #expect(Moment.Key.strength(16, season: "2026") == "strength-16-2026")
        #expect(Moment.Key.secondsFirst == "seconds-first")
    }

    @Test func batchKeepsTheThreeMostImportantAndReportsTheRest() {
        let all = [moment(.secondData), moment(.streak), moment(.levelUp), moment(.record), moment(.weekPlanDone)]
        let batch = MomentBatch(all)
        #expect(MomentBatch.maxMoments == 3)
        #expect(batch.moments.map(\.kind) == [.levelUp, .record, .streak])
        #expect(batch.overflow.map(\.kind) == [.weekPlanDone, .secondData])
        #expect(batch.headline?.kind == .levelUp)
        #expect(batch.allIDs.count == 5)
        #expect(!batch.isEmpty)
    }

    @Test func batchOrdersEqualKindsByDateNewestFirstAndHandlesEmpty() {
        let older = moment(.record, id: "record-60-1", day: 1)
        let newer = moment(.record, id: "record-60-2", day: 2)
        #expect(MomentBatch([older, newer]).moments.map(\.id) == ["record-60-2", "record-60-1"])
        #expect(MomentBatch.empty.isEmpty)
        #expect(MomentBatch.empty.headline == nil)
        #expect(MomentBatch([]) == .empty)
    }

    @Test func ledgerRemembersAndNeverRepeats() {
        var ledger = MomentLedger()
        #expect(!ledger.isInitialized)
        #expect(!ledger.hasSeen("level-4-2026"))
        ledger.markSeen("level-4-2026")
        ledger.markSeen("level-4-2026")
        #expect(ledger.hasSeen("level-4-2026"))
        #expect(ledger.seenIDs == ["level-4-2026"])
    }

    @Test func ledgerCapsAtFiveHundredAndDropsTheOldest() {
        var ledger = MomentLedger()
        ledger.markSeen((0..<510).map { "id-\($0)" })
        #expect(MomentLedger.maxSeen == 500)
        #expect(ledger.seenIDs.count == 500)
        #expect(!ledger.hasSeen("id-9"))
        #expect(ledger.hasSeen("id-10"))
        #expect(ledger.hasSeen("id-509"))
        // A repeated ID does not push others out.
        ledger.markSeen("id-10")
        #expect(ledger.seenIDs.count == 500 && ledger.hasSeen("id-10"))
    }

    @Test func ledgerNoteRulesVaryWithinAWindowOfThree() {
        var ledger = MomentLedger()
        #expect(ledger.canUseNoteRule("effizienz"))
        ledger.recordNoteRule("effizienz")
        #expect(!ledger.canUseNoteRule("effizienz"))
        ledger.recordNoteRule("serie")
        ledger.recordNoteRule("fitness")
        #expect(!ledger.canUseNoteRule("effizienz")) // still among the last 3
        ledger.recordNoteRule("rueckfall")
        #expect(ledger.recentNoteRules == ["serie", "fitness", "rueckfall"])
        #expect(ledger.canUseNoteRule("effizienz"))
    }

    @Test func ledgerRoundTripsAsJSONAndSurvivesMissingFields() throws {
        var ledger = MomentLedger()
        ledger.markSeen(["a", "b"])
        ledger.isInitialized = true
        ledger.lastCelebratedFTP = 238
        ledger.recordNoteRule("serie")
        let data = try JSONEncoder().encode(ledger)
        #expect(try JSONDecoder().decode(MomentLedger.self, from: data) == ledger)
        let sparse = try JSONDecoder().decode(MomentLedger.self, from: Data("{}".utf8))
        #expect(sparse == MomentLedger())
    }

    @Test func ledgerPersistsInDefaultsUnderItsKey() throws {
        let suite = "moments-\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        #expect(MomentLedger.defaultsKey == "moments.ledger")
        #expect(MomentLedger.load(from: defaults) == MomentLedger())
        var ledger = MomentLedger()
        ledger.markSeen("x")
        ledger.save(to: defaults)
        #expect(MomentLedger.load(from: defaults).hasSeen("x"))
        defaults.set(Data("kaputt".utf8), forKey: MomentLedger.defaultsKey)
        #expect(MomentLedger.load(from: defaults) == MomentLedger())
    }

    @Test func removeAllForgetsEverything() {
        var ledger = MomentLedger()
        ledger.markSeen("x")
        ledger.isInitialized = true
        ledger.recordNoteRule("serie")
        ledger.lastCelebratedFTP = 200
        ledger.removeAll()
        #expect(ledger == MomentLedger())
    }
}
