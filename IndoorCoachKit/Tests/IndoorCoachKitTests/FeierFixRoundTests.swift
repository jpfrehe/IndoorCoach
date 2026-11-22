import Foundation
import SwiftData
import Testing
@testable import IndoorCoachKit

/// Fix-Runde Begeisterung: einmaliges Zeigen, Fingerabdruck, Check-in-Tag, Comeback-Lücke, Cache, Schalter.
@MainActor
@Suite("Begeisterung · Fix-Runde (Store)")
struct FeierFixRoundTests {
    private struct Rig {
        var model: AppModel
        var defaults: UserDefaults
        var container: ModelContainer
        var suite: String
    }

    private let now: Date = Calendar.current.date(from: DateComponents(year: 2026, month: 12, day: 18, hour: 12))!

    private func makeRig(existing: Rig? = nil) throws -> Rig {
        let container = try existing?.container ?? AppEnvironment.makeContainer(inMemory: true)
        let suite = existing?.suite ?? "fix-\(UUID().uuidString)"
        let defaults = try existing?.defaults ?? #require(UserDefaults(suiteName: suite))
        defaults.set(true, forKey: AppModel.Keys.onboardingCompleted)
        let model = AppModel(context: container.mainContext, secrets: InMemorySecretStore(), defaults: defaults)
        return Rig(model: model, defaults: defaults, container: container, suite: suite)
    }

    private func finish(_ rig: Rig) { rig.defaults.removePersistentDomain(forName: rig.suite) }

    private func ride(_ id: Int, minutesAgo: Int, curve: [Int: Double]? = nil) -> RideSummary {
        var r = RideSummary(id: -id, name: "Sweet Spot 3×12", sportType: "VirtualRide",
                            startDate: now.addingTimeInterval(-Double(minutesAgo) * 60), movingTime: 3600, distance: 30_000,
                            averageWatts: 150, weightedAverageWatts: 160, trainer: true)
        r.powerCurve = curve
        return r
    }

    private func plan(_ rig: Rig) -> StoredWorkout {
        let proposal = PlannedWorkoutProposal(date: Calendar.current.startOfDay(for: now), definition: DemoData.library.endurance, rationale: "")
        let workout = StoredWorkout(proposal: proposal, source: .demo, weekFocus: nil)
        rig.model.context.insert(workout)
        return workout
    }

    // MARK: 1 · sofort quittieren

    @Test func presentingAcknowledgesImmediatelyAndNeverTwice() throws {
        let rig = try makeRig()
        defer { finish(rig) }
        let r = ride(1, minutesAgo: 120, curve: [300: 220])
        rig.model.storeImportedRides([r])
        rig.model.evaluateMoments(now: now)
        let first = try #require(rig.model.takeMomentToPresent(now: now))
        #expect(first.batch.headline?.id == "first-2026")
        #expect(rig.model.pendingMoments.isEmpty)
        #expect(rig.model.momentLedger.hasSeen("first-2026"))
        #expect(rig.model.takeMomentToPresent(now: now) == nil)            // der nächste Versuch findet nichts mehr
        rig.model.evaluateMoments(now: now, force: true)
        #expect(rig.model.takeMomentToPresent(now: now) == nil)
        // App-Abbruch während der Animation: ein neues Modell zeigt nichts mehr
        let second = try makeRig(existing: rig)
        second.model.evaluateMoments(now: now)
        #expect(second.model.takeMomentToPresent(now: now) == nil)
        // Wiederholen bleibt über die Fahrt möglich
        #expect(rig.model.momentBatch(forRide: r, now: now) != nil)
    }

    @Test func blockedGateKeepsTheMomentPending() throws {
        let rig = try makeRig()
        defer { finish(rig) }
        rig.model.storeImportedRides([ride(1, minutesAgo: 120, curve: [300: 220])])
        rig.model.evaluateMoments(now: now)
        #expect(rig.model.takeMomentToPresent(gate: .init(recordingRunning: true), now: now) == nil)
        #expect(!rig.model.pendingMoments.isEmpty)
        #expect(!rig.model.momentLedger.hasSeen("first-2026"))
    }

    // MARK: 4 · echte Startzeit

    @Test func gateUsesTheProfileStartTimeNotMidnight() throws {
        let rig = try makeRig()
        defer { finish(rig) }
        rig.model.storeImportedRides([ride(1, minutesAgo: 120, curve: [300: 220])])
        rig.model.evaluateMoments(now: now)
        rig.model.profile.preferredStartHour = 18
        rig.model.profile.preferredStartMinute = 30
        _ = plan(rig)
        try rig.model.context.save()
        let cal = Calendar.current
        func at(_ h: Int, _ m: Int) -> Date { cal.date(bySettingHour: h, minute: m, second: 0, of: now)! }
        #expect(rig.model.momentToPresent(now: at(18, 10)) == nil)    // 20 min vorher
        #expect(rig.model.momentToPresent(now: at(18, 0)) == nil)     // genau 30 min
        #expect(rig.model.momentToPresent(now: at(17, 50)) != nil)    // 40 min vorher
        #expect(rig.model.momentToPresent(now: at(18, 45)) != nil)    // nach dem Start
    }

    // MARK: 5 · Fingerabdruck

    @Test func fingerprintReactsToStrengthWorkoutsAndArcStart() throws {
        let rig = try makeRig()
        defer { finish(rig) }
        rig.model.storeImportedRides([ride(1, minutesAgo: 120)])
        let base = rig.model.momentFingerprint(now: now)
        #expect(rig.model.momentFingerprint(now: now) == base)

        rig.model.context.insert(StoredStrengthSession(session: StrengthSession(start: now.addingTimeInterval(-3600), durationSeconds: 1800)))
        try rig.model.context.save()
        let afterStrength = rig.model.momentFingerprint(now: now)
        #expect(afterStrength != base)

        let workout = plan(rig)
        try rig.model.context.save()
        let afterPlan = rig.model.momentFingerprint(now: now)
        #expect(afterPlan != afterStrength)
        workout.status = .done
        try rig.model.context.save()
        let afterDone = rig.model.momentFingerprint(now: now)
        #expect(afterDone != afterPlan)

        rig.model.profile.arcStart = Calendar.current.date(byAdding: .day, value: -30, to: now)
        #expect(rig.model.momentFingerprint(now: now) != afterDone)
    }

    // MARK: 6 · Check-in nur vom Tag der Fahrt

    @Test func coachNoteIgnoresTodaysCheckInForAnOlderRide() throws {
        let rig = try makeRig()
        defer { finish(rig) }
        let old = ride(1, minutesAgo: 60 * 30)    // gestern 06:00
        rig.model.storeImportedRides([old])
        let batch = MomentBatch([Moment(id: "first-2026", kind: .firstRide, date: old.startDate, headline: "Start", detail: nil, rideID: old.id)])
        let today = Calendar.current.startOfDay(for: now)
        rig.model.context.insert(StoredCheckIn(day: today, answers: CheckIn.Answers(legs: .bad, sleep: .ok, mood: .ok), offered: [], createdAt: now))
        try rig.model.context.save()
        #expect(rig.model.momentPresentation(for: batch, now: now).coachNote?.rule != "checkin")

        let sameDay = ride(2, minutesAgo: 60)
        rig.model.storeImportedRides([sameDay])
        let batch2 = MomentBatch([Moment(id: "first-2026b", kind: .firstRide, date: sameDay.startDate, headline: "Start", detail: nil, rideID: sameDay.id)])
        #expect(rig.model.momentPresentation(for: batch2, now: now).coachNote?.rule == "checkin")
    }

    // MARK: 16 / 18 · Cache und Schalter

    @Test func switchingOffClearsPendingAndDeleteAllResetsTheCache() async throws {
        let rig = try makeRig()
        defer { finish(rig) }
        rig.model.storeImportedRides([ride(1, minutesAgo: 120, curve: [300: 220])])
        rig.model.evaluateMoments(now: now)
        #expect(!rig.model.pendingMoments.isEmpty)
        #expect(rig.model.hasMomentEvaluationCache)
        rig.model.momentsEnabled = false
        #expect(rig.model.pendingMoments.isEmpty)
        #expect(!rig.model.hasMomentEvaluationCache)

        rig.model.momentsEnabled = true
        rig.model.evaluateMoments(now: now)
        #expect(rig.model.hasMomentEvaluationCache)
        await rig.model.deleteAllData()
        #expect(!rig.model.hasMomentEvaluationCache)
    }

    // MARK: 9 · Highlight-Slot nur einmal je Fingerabdruck

    @Test func highlightIsComputedOncePerFingerprint() throws {
        let rig = try makeRig()
        defer { finish(rig) }
        let rides = [ride(1, minutesAgo: 60 * 24 * 20)]
        rig.model.storeImportedRides(rides)
        let memo = rig.model.comebackMemo
        let first = rig.model.winterHighlight(rides: rides, dismissedDay: nil, whyPromptDismissed: true, now: now)
        for _ in 0..<5 { #expect(rig.model.winterHighlight(rides: rides, dismissedDay: nil, whyPromptDismissed: true, now: now) == first) }
        #expect(memo.computations == 1)
        _ = rig.model.winterHighlight(rides: rides, dismissedDay: "2026-12-18", whyPromptDismissed: true, now: now)
        #expect(memo.computations == 2)
        rig.model.context.insert(StoredStrengthSession(session: StrengthSession(start: now.addingTimeInterval(-3600), durationSeconds: 1800)))
        try rig.model.context.save()
        _ = rig.model.winterHighlight(rides: rides, dismissedDay: "2026-12-18", whyPromptDismissed: true, now: now)
        #expect(memo.computations == 3)

        let before = memo.computations
        for _ in 0..<5 { _ = rig.model.comebackJokerWeek(rides: rides, now: now) }
        #expect(memo.computations == before + 1)
    }

    // MARK: 3 · eine Lücke für Moment, Karte und Notiz

    @Test func strengthSessionBreaksTheGapForTheMomentLikeForTheCard() throws {
        let rig = try makeRig()
        defer { finish(rig) }
        let cal = Calendar.current
        let start = cal.startOfDay(for: now)
        func day(_ n: Int) -> Date { cal.date(byAdding: .day, value: -n, to: start)!.addingTimeInterval(12 * 3600) }
        var old = ride(1, minutesAgo: 0); old.startDate = day(30)
        var back = ride(2, minutesAgo: 0); back.startDate = day(1)
        rig.model.storeImportedRides([old, back])
        let input = rig.model.momentInput(rides: [old, back], now: now)
        #expect(MomentDetector.moments(forRide: back.id, input: input, now: now).contains { $0.kind == .comeback })
        // Kraft zwei Tage vor der Fahrt: Karte und Moment sagen beide „kein Comeback“
        rig.model.context.insert(StoredStrengthSession(session: StrengthSession(start: day(3), durationSeconds: 1800)))
        try rig.model.context.save()
        let input2 = rig.model.momentInput(rides: [old, back], now: now)
        #expect(!MomentDetector.moments(forRide: back.id, input: input2, now: now).contains { $0.kind == .comeback })
        #expect(rig.model.comebackState(rides: [old, back], now: now) == .none)
    }
}
