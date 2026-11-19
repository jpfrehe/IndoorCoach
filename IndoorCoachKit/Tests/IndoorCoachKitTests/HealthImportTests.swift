import Foundation
import Testing
@testable import IndoorCoachKit

@Suite("HealthImport: Klassifizierung, Überlappung, Fremd-TSS")
struct HealthImportTests {
    let day = Date(timeIntervalSince1970: 1_800_000_000)
    let profile = RelativeEffort.HeartRateProfile(resting: 50, max: 190)

    func workout(_ type: String, start: TimeInterval = 0, minutes: Double = 60, hr: Double? = nil, own: Bool = false,
                 source: String = "Apple Watch") -> HealthWorkout {
        HealthWorkout(uuid: UUID(), start: day.addingTimeInterval(start * 60), end: day.addingTimeInterval((start + minutes) * 60),
                      activityTypeName: type, sourceName: source, sourceBundleID: "bundle.\(source)", isOwnSource: own,
                      avgHR: hr, maxHR: hr.map { $0 + 20 }, energyKcal: nil)
    }

    func ride(_ id: Int = 1, start: TimeInterval = 0, minutes: Double = 60, rank: HealthImport.HeartRateRank? = .fit) -> HealthImport.Occupied {
        .init(kind: .ride(id), start: day.addingTimeInterval(start * 60), end: day.addingTimeInterval((start + minutes) * 60), heartRate: rank)
    }

    func decide(_ w: HealthWorkout, _ occupied: [HealthImport.Occupied] = [], threshold: Int? = nil) -> HealthImport.Decision {
        HealthImport.decide(w, occupied: occupied, thresholdHeartRate: threshold, heartRate: profile)
    }

    // MARK: Überlappung (B48)

    @Test func watchStartingFourMinutesEarlyMergesIntoTheRide() {
        let health = workout("cycling", start: -4, minutes: 60, hr: 140)
        let result = decide(health, [ride(7, start: 0, minutes: 60, rank: .fit)])
        #expect(result == .merge(.ride(7), supplyHeartRate: false))
    }

    @Test func garminDuplicateOfAFitRideIsNotANewLoad() {
        let garmin = workout("cycling", start: 1, minutes: 58, hr: 150, source: "Garmin Connect")
        #expect(decide(garmin, [ride(3)]) == .merge(.ride(3), supplyHeartRate: false))
    }

    @Test func realOutdoorRideWithoutOverlapCountsAsCycling() {
        let outdoor = workout("cycling", start: 600, minutes: 150, hr: 135)
        #expect(decide(outdoor, [ride(1, start: 0, minutes: 60)]) == .cycling)
    }

    @Test func overlapIsMeasuredAgainstTheHealthWorkout() {
        // 30 von 60 Minuten = genau 50 % → zusammengeführt; 29 → nicht.
        #expect(decide(workout("cycling", start: 30), [ride(start: 0, minutes: 60)]) == .merge(.ride(1), supplyHeartRate: false))
        #expect(decide(workout("cycling", start: 31), [ride(start: 0, minutes: 60)]) == .cycling)
        // Eine kurze Krafteinheit mitten in einem langen Spaziergang: nur 25 % des Spaziergangs überlappen.
        let walk = workout("walking", start: 0, minutes: 120)
        let strength = HealthImport.Occupied(kind: .strength(UUID()), start: day.addingTimeInterval(30 * 60),
                                             end: day.addingTimeInterval(60 * 60), heartRate: nil)
        if case .aerobic = decide(walk, [strength]) {} else { Issue.record("Spaziergang mit 25 % Überlappung muss eigenständig bleiben") }
    }

    @Test func strengthHealthWorkoutOverlappingAStrengthSessionMerges() {
        let id = UUID()
        let occupied = HealthImport.Occupied(kind: .strength(id), start: day, end: day.addingTimeInterval(3000), heartRate: nil)
        let result = decide(workout("traditionalStrengthTraining", start: 2, minutes: 50, hr: 120), [occupied])
        #expect(result == .merge(.strength(id), supplyHeartRate: true))
    }

    @Test func bestOverlapWinsAmongSeveral() {
        let result = decide(workout("cycling", start: 0, minutes: 60), [ride(1, start: 40, minutes: 60), ride(2, start: 5, minutes: 60)])
        #expect(result == .merge(.ride(2), supplyHeartRate: false))
    }

    // MARK: Puls-Priorität

    @Test func heartRatePriorityFitBridgeStrapHealthList() {
        typealias R = HealthImport.HeartRateRank
        #expect(R.list < R.health && R.health < R.strap && R.strap < R.fit)
        #expect(HealthImport.rank(hasCurve: true, hasSecondsHeartRate: false, isStrava: false, hasHeartRate: true) == .fit)
        #expect(HealthImport.rank(hasCurve: false, hasSecondsHeartRate: true, isStrava: false, hasHeartRate: true) == .strap)
        #expect(HealthImport.rank(hasCurve: false, hasSecondsHeartRate: false, isStrava: true, hasHeartRate: true) == .strap)
        #expect(HealthImport.rank(hasCurve: false, hasSecondsHeartRate: false, isStrava: false, hasHeartRate: true) == .list)
        #expect(HealthImport.rank(hasCurve: true, hasSecondsHeartRate: false, isStrava: false, hasHeartRate: false) == nil)
    }

    @Test func healthSuppliesMissingHeartRateAndBeatsTheMyWhooshList() {
        let health = workout("cycling", hr: 142)
        #expect(decide(health, [ride(rank: nil)]) == .merge(.ride(1), supplyHeartRate: true))      // fehlt
        #expect(decide(health, [ride(rank: .list)]) == .merge(.ride(1), supplyHeartRate: true))    // MyWhoosh-Liste < Health
        #expect(decide(health, [ride(rank: .strap)]) == .merge(.ride(1), supplyHeartRate: false))  // Gurt gewinnt
        #expect(decide(health, [ride(rank: .fit)]) == .merge(.ride(1), supplyHeartRate: false))
        // Ohne Puls im Health-Workout gibt es nichts zu ergänzen.
        #expect(decide(workout("cycling", hr: nil), [ride(rank: nil)]) == .merge(.ride(1), supplyHeartRate: false))
    }

    // MARK: Klassifizierung

    @Test func ownSourceAndIgnoredSportsAreSkipped() {
        #expect(decide(workout("running", hr: 150, own: true)) == .skip(.ownSource))
        #expect(decide(workout("yoga")) == .skip(.ignoredSport))
        #expect(decide(workout("running", minutes: 0)) == .skip(.empty))
    }

    @Test func strengthAndClimbingBecomeAnnotationCandidates() {
        #expect(decide(workout("traditionalStrengthTraining", hr: 118)) == .candidate)
        #expect(decide(workout("climbing")) == .candidate)
        #expect(decide(workout("highIntensityIntervalTraining")) == .candidate)   // gemischt: Nutzer entscheidet
    }

    // MARK: Fremd-TSS (O6)

    @Test func runWithHeartRateAndThresholdUsesHRTSS() throws {
        guard case .aerobic(let e) = decide(workout("running", hr: 148), threshold: 160) else { throw Fail() }
        #expect(e.method == .thresholdHeartRate)
        #expect(abs(e.tss - 1.0 * pow(148.0 / 160.0, 2) * 100) < 0.001)
    }

    @Test func hrTSSScalesWithDuration() {
        let e = HealthImport.estimate(for: workout("running", minutes: 30, hr: 160), thresholdHeartRate: 160, heartRate: profile)
        #expect(abs(e.tss - 50) < 0.001)
    }

    @Test func withoutThresholdTheTRIMPIsScaledToOneHourAtThreshold() {
        // Schwellenpuls ≙ 85 % der Herzfrequenzreserve (50 + 0,85 × 140 = 169): eine Stunde dort ≈ 100.
        let atThreshold = HealthImport.estimate(for: workout("running", hr: 169), thresholdHeartRate: nil, heartRate: profile)
        #expect(atThreshold.method == .trimp)
        #expect(abs(atThreshold.tss - 100) < 0.5)
        let easy = HealthImport.estimate(for: workout("running", hr: 130), thresholdHeartRate: nil, heartRate: profile)
        let expected = RelativeEffort.trimp(minutes: 60, reserveFraction: 80.0 / 140) * 100
            / RelativeEffort.trimp(minutes: 60, reserveFraction: 0.85)
        #expect(abs(easy.tss - expected) < 0.001)
        #expect(easy.tss < atThreshold.tss)
    }

    @Test func withoutHeartRateTheSportFactorApplies() {
        func tss(_ sport: String, _ minutes: Double = 60) -> Double {
            let e = HealthImport.estimate(for: workout(sport, minutes: minutes), thresholdHeartRate: 160, heartRate: profile)
            #expect(e.method == .duration)
            return e.tss
        }
        #expect(tss("running") == 60)
        #expect(tss("running", 30) == 30)
        #expect(tss("crossCountrySkiing") == 55)
        #expect(tss("rowing") == 55)
        #expect(tss("hiking") == 25)
        #expect(tss("walking") == 25)
        #expect(tss("swimming") == 40)
        #expect(tss("elliptical", 90) == 60)
    }

    @Test func invalidHeartRateProfileFallsBackToTheFactor() {
        let e = HealthImport.estimate(for: workout("running", hr: 150), thresholdHeartRate: nil,
                                      heartRate: .init(resting: 0, max: 0))
        #expect(e.method == .duration)
        #expect(e.tss == 60)
    }

    @Test func runDecisionCarriesTheEstimate() throws {
        guard case .aerobic(let e) = decide(workout("running")) else { throw Fail() }
        #expect(e.tss == 60 && e.method == .duration)
    }

    // MARK: Namen

    @Test func germanNames() {
        #expect(HealthImport.germanName(for: "running") == "Laufen")
        #expect(HealthImport.germanName(for: "traditionalStrengthTraining") == "Krafttraining")
        #expect(HealthImport.germanName(for: "somethingNew") == "Training")
    }

    struct Fail: Error {}
}
