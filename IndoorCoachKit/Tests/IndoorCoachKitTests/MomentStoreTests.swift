import Foundation
import SwiftData
import Testing
@testable import IndoorCoachKit

@MainActor
@Suite("Gipfelmomente · Store (AP3)")
struct MomentStoreTests {
    private struct Rig {
        var model: AppModel
        var defaults: UserDefaults
        var container: ModelContainer
        var suite: String
    }

    private let now: Date = Calendar.current.date(from: DateComponents(year: 2026, month: 12, day: 18, hour: 12))!

    /// The container must outlive the model (a released container traps SwiftData).
    private func makeRig(defaults existing: (UserDefaults, ModelContainer, String)? = nil) throws -> Rig {
        let container = try existing?.1 ?? AppEnvironment.makeContainer(inMemory: true)
        let suite = existing?.2 ?? "moments-\(UUID().uuidString)"
        let defaults = try existing?.0 ?? #require(UserDefaults(suiteName: suite))
        defaults.set(true, forKey: AppModel.Keys.onboardingCompleted)
        let model = AppModel(context: container.mainContext, secrets: InMemorySecretStore(), defaults: defaults)
        return Rig(model: model, defaults: defaults, container: container, suite: suite)
    }

    private func ride(_ id: Int, minutesAgo: Int, curve: [Int: Double]? = nil, watts: Double = 150) -> RideSummary {
        var r = RideSummary(id: -id, name: "Sweet Spot 3×12", sportType: "VirtualRide",
                            startDate: now.addingTimeInterval(-Double(minutesAgo) * 60), movingTime: 3600, distance: 30_000,
                            averageWatts: watts, weightedAverageWatts: watts + 10, trainer: true)
        r.powerCurve = curve
        return r
    }

    private func finish(_ rig: Rig) { rig.defaults.removePersistentDomain(forName: rig.suite) }

    // MARK: Auswertung

    @Test func oneCelebrationAfterTheFirstImport() throws {
        let rig = try makeRig()
        defer { finish(rig) }
        rig.model.storeImportedRides([ride(1, minutesAgo: 120, curve: [300: 220])])
        rig.model.evaluateMoments(now: now)
        #expect(rig.model.pendingMoments.moments.count == 1)
        #expect(rig.model.pendingMoments.headline?.kind == .firstRide)
        #expect(rig.model.pendingMoments.headline?.headline == "Start in Garmisch")
    }

    @Test func secondPassShowsNothingNew() throws {
        let rig = try makeRig()
        defer { finish(rig) }
        rig.model.storeImportedRides([ride(1, minutesAgo: 120, curve: [300: 220])])
        rig.model.evaluateMoments(now: now)
        rig.model.acknowledgeMoments(noteRule: nil)
        #expect(rig.model.pendingMoments.isEmpty)
        rig.model.evaluateMoments(now: now, force: true)
        #expect(rig.model.pendingMoments.isEmpty)
        // eine weitere unauffällige Fahrt ändert daran nichts
        rig.model.storeImportedRides([ride(2, minutesAgo: 30, watts: 100)])
        rig.model.evaluateMoments(now: now)
        #expect(rig.model.pendingMoments.isEmpty)
    }

    @Test func acknowledgedMomentDoesNotReturnAfterARestart() throws {
        let first = try makeRig()
        defer { finish(first) }
        first.model.storeImportedRides([ride(1, minutesAgo: 120, curve: [300: 220])])
        first.model.evaluateMoments(now: now)
        first.model.acknowledgeMoments(noteRule: "season")
        let second = try makeRig(defaults: (first.defaults, first.container, first.suite))
        second.model.evaluateMoments(now: now)
        #expect(second.model.pendingMoments.isEmpty)
        #expect(second.model.momentLedger.recentNoteRules == ["season"])
    }

    @Test func unacknowledgedMomentReturnsAfterARestart() throws {
        let first = try makeRig()
        defer { finish(first) }
        first.model.storeImportedRides([ride(1, minutesAgo: 120, curve: [300: 220])])
        first.model.evaluateMoments(now: now)
        #expect(!first.model.pendingMoments.isEmpty)
        let second = try makeRig(defaults: (first.defaults, first.container, first.suite))
        second.model.evaluateMoments(now: now)
        #expect(second.model.pendingMoments.headline?.id == "first-2026")
    }

    @Test func pendingMomentIsKeptWhileItWaits() throws {
        let rig = try makeRig()
        defer { finish(rig) }
        rig.model.storeImportedRides([ride(1, minutesAgo: 120, curve: [300: 220])])
        rig.model.evaluateMoments(now: now)
        let pending = rig.model.pendingMoments
        rig.model.storeImportedRides([ride(2, minutesAgo: 30, curve: [300: 260])])
        rig.model.evaluateMoments(now: now)
        #expect(rig.model.pendingMoments == pending)
    }

    // MARK: Sperren

    @Test func nothingIsPresentedWhileRecordingOrAnotherSheetOrOnboarding() throws {
        let rig = try makeRig()
        defer { finish(rig) }
        rig.model.storeImportedRides([ride(1, minutesAgo: 120, curve: [300: 220])])
        rig.model.evaluateMoments(now: now)
        #expect(!rig.model.pendingMoments.isEmpty)
        #expect(rig.model.momentToPresent(gate: .init(recordingRunning: true), now: now) == nil)
        #expect(rig.model.momentToPresent(gate: .init(anotherPresentation: true), now: now) == nil)
        // frei: der Moment wartet nicht verloren, sondern kommt jetzt
        #expect(rig.model.momentToPresent(gate: .init(), now: now) == rig.model.pendingMoments)
        let fresh = try makeRig()
        defer { finish(fresh) }
        fresh.defaults.removeObject(forKey: AppModel.Keys.onboardingCompleted)
        let onboarding = AppModel(context: fresh.container.mainContext, secrets: InMemorySecretStore(), defaults: fresh.defaults)
        onboarding.pendingMoments = rig.model.pendingMoments
        #expect(onboarding.needsOnboarding)
        #expect(onboarding.momentToPresent(gate: .init(), now: now) == nil)
    }

    @Test func nothingIsPresentedShortlyBeforeAPlannedWorkout() throws {
        let rig = try makeRig()
        defer { finish(rig) }
        rig.model.storeImportedRides([ride(1, minutesAgo: 120, curve: [300: 220])])
        rig.model.evaluateMoments(now: now)
        // Der Plan trägt nur den Tag (Tagesbeginn); die Startzeit kommt aus dem Profil: hier 12:20, „jetzt“ ist 12:00.
        rig.model.profile.preferredStartHour = 12
        rig.model.profile.preferredStartMinute = 20
        let soon = PlannedWorkoutProposal(date: Calendar.current.startOfDay(for: now), definition: DemoData.library.endurance, rationale: "")
        rig.model.context.insert(StoredWorkout(proposal: soon, source: .demo, weekFocus: nil))
        try rig.model.context.save()
        #expect(rig.model.momentToPresent(gate: .init(), now: now) == nil)
        // eine Stunde früher ist die Einheit noch nicht „gleich“, nach dem Start auch nicht mehr
        #expect(rig.model.momentToPresent(gate: .init(), now: now.addingTimeInterval(-60 * 60)) != nil)
        #expect(rig.model.momentToPresent(gate: .init(), now: now.addingTimeInterval(30 * 60)) != nil)
    }

    @Test func switchOffShowsNothingButTrophiesStayEarned() throws {
        let rig = try makeRig()
        defer { finish(rig) }
        rig.model.momentsEnabled = false
        let r = ride(1, minutesAgo: 120, curve: [300: 220])
        rig.model.storeImportedRides([r])
        rig.model.evaluateMoments(now: now)
        #expect(rig.model.pendingMoments.isEmpty)
        #expect(!rig.model.momentLedger.isInitialized)
        #expect(rig.model.momentToPresent(gate: .init(), now: now) == nil)
        let trophies = rig.model.trophies(rides: rig.model.allRides(), arc: rig.model.winterArc(rides: rig.model.allRides(), now: now), now: now)
        #expect(trophies.first { $0.id == "second-data" }?.isEarned == true)
    }

    // MARK: Demo

    @Test func demoModeShowsExactlyOneMarkedExample() throws {
        let rig = try makeRig()
        defer { finish(rig) }
        rig.model.bootstrap()
        #expect(rig.model.isDemoMode)
        rig.model.evaluateMoments(now: now)
        let m = try #require(rig.model.pendingMoments.headline)
        #expect(m.kind == .levelUp)
        #expect(m.id.hasPrefix("demo-"))
        let presentation = rig.model.momentPresentation(for: rig.model.pendingMoments, now: now)
        #expect(presentation.isExample)
        #expect(presentation.postcard?.stage == 4)
        #expect(presentation.coachNote != nil)
        rig.model.acknowledgeMoments(noteRule: presentation.coachNote?.rule)
        rig.model.evaluateMoments(now: now, force: true)
        #expect(rig.model.pendingMoments.isEmpty)
        #expect(!rig.model.momentLedger.isInitialized) // Demo-Daten zählen nicht als Erstauswertung
    }

    // MARK: Präsentation

    @Test func presentationOfARealMomentIsNotAnExampleAndCarriesDateAndNote() throws {
        let rig = try makeRig()
        defer { finish(rig) }
        rig.model.storeImportedRides([ride(1, minutesAgo: 120, curve: [300: 220])])
        rig.model.evaluateMoments(now: now)
        let p = rig.model.momentPresentation(for: rig.model.pendingMoments, now: now)
        #expect(!p.isExample)
        #expect(p.postcard == nil)
        #expect(p.date == rig.model.pendingMoments.headline?.date)
    }

    @Test func whyQuoteOnlyAtLevelFiveAndTen() throws {
        let rig = try makeRig()
        defer { finish(rig) }
        rig.model.whyNote = "Im Mai die RTF mit Freunden"
        func batch(level: Int) -> MomentBatch {
            MomentBatch([Moment(id: "level-\(level)-2026", kind: .levelUp, date: now, headline: "Level \(level)", detail: nil, rideID: nil)])
        }
        #expect(rig.model.momentPresentation(for: batch(level: 5), now: now).whyQuote == "Im Mai die RTF mit Freunden")
        #expect(rig.model.momentPresentation(for: batch(level: 10), now: now).whyQuote == "Im Mai die RTF mit Freunden")
        #expect(rig.model.momentPresentation(for: batch(level: 4), now: now).whyQuote == nil)
        rig.model.whyNote = nil
        #expect(rig.model.momentPresentation(for: batch(level: 5), now: now).whyQuote == nil)
    }

    @Test func levelMomentCarriesItsPostcardForTheStage() throws {
        let rig = try makeRig()
        defer { finish(rig) }
        let batch = MomentBatch([Moment(id: "level-4-2026", kind: .levelUp, date: now, headline: "Level 4 · Rollen-Routine", detail: nil, rideID: nil)])
        let p = rig.model.momentPresentation(for: batch, now: now)
        #expect(p.postcard?.stage == 4)
        #expect(p.postcard?.place == "Stilfser Joch")
        #expect(p.postcard?.unlocked == true)
    }

    // MARK: Fahrt-Detail

    @Test func rideDetailFindsTheMomentOfThatRide() throws {
        let rig = try makeRig()
        defer { finish(rig) }
        let old = ride(1, minutesAgo: 60 * 24 * 14, curve: [300: 220])
        let newest = ride(2, minutesAgo: 120, curve: [300: 260])
        rig.model.storeImportedRides([old, newest])
        let batch = try #require(rig.model.momentBatch(forRide: newest, now: now))
        #expect(batch.moments.contains { $0.kind == .record })
        #expect(rig.model.momentBatch(forRide: ride(99, minutesAgo: 60), now: now) == nil)
    }
}
