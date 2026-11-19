import Foundation
import Testing
@testable import IndoorCoachKit

@Suite("HealthData: Mapping, Aggregation, Pinning, Stub")
struct HealthDataTests {
    static let cal: Calendar = {
        var c = Calendar(identifier: .gregorian)
        c.timeZone = TimeZone(identifier: "Europe/Berlin")!
        return c
    }()
    static func date(_ y: Int, _ m: Int, _ d: Int, _ h: Int = 0, _ min: Int = 0) -> Date {
        cal.date(from: DateComponents(year: y, month: m, day: d, hour: h, minute: min))!
    }
    static let watch = HealthSourceRef(name: "Apple Watch", bundleID: "com.apple.health.watch")
    static let garmin = HealthSourceRef(name: "Garmin", bundleID: "com.garmin.connect")

    // MARK: Workout-Typ-Mapping

    @Test func mappingKnownTypes() {
        let expected: [(UInt, String, SportCategory)] = [
            (13, "cycling", .cycling), (74, "handCycling", .cycling),
            (37, "running", .aerobic), (52, "walking", .aerobic), (24, "hiking", .aerobic),
            (35, "rowing", .aerobic), (46, "swimming", .aerobic), (16, "elliptical", .aerobic),
            (50, "traditionalStrengthTraining", .muscular), (20, "functionalStrengthTraining", .muscular),
            (59, "coreTraining", .muscular), (9, "climbing", .muscular),
            (63, "highIntensityIntervalTraining", .mixed), (11, "crossTraining", .mixed),
            (57, "yoga", .ignore), (3000, "other", .ignore)
        ]
        for (raw, name, category) in expected {
            #expect(HealthWorkoutTypeMap.name(forRawValue: raw) == name)
            #expect(SportClassification.category(for: name) == category, "\(name)")
        }
    }

    @Test func mappedNamesAreUniqueAndClassified() {
        let ignored: Set<String> = ["yoga", "mindAndBody", "taiChi", "cooldown", "preparationAndRecovery", "other"]
        var seen = Set<String>()
        for (raw, name) in HealthWorkoutTypeMap.table {
            #expect(!name.isEmpty)
            #expect(seen.insert(name).inserted, "doppelt: \(name) (\(raw))")
            if ignored.contains(name) { #expect(SportClassification.category(for: name) == .ignore) }
        }
        // Jeder Name, den SportClassification explizit kennt (nicht-Deutsch), muss vom Mapping erzeugt werden.
        for name in ["cycling", "indoorCycling", "running", "walking", "hiking", "crossCountrySkiing", "downhillSkiing",
                     "snowboarding", "skatingSports", "rowing", "elliptical", "swimming", "stairClimbing", "stairs",
                     "stepTraining", "paddleSports", "traditionalStrengthTraining", "functionalStrengthTraining",
                     "coreTraining", "climbing", "flexibility", "pilates", "barre", "highIntensityIntervalTraining",
                     "crossTraining", "mixedCardio", "jumpRope", "boxing", "kickboxing", "martialArts", "yoga",
                     "mindAndBody", "taiChi", "cooldown", "preparationAndRecovery", "other"]
        where name != "indoorCycling" {   // indoorCycling ist in HealthKit kein eigener Typ (Rad + Indoor-Metadatum)
            #expect(seen.contains(name), "\(name)")
        }
    }

    @Test func unknownRawValueIsOther() {
        #expect(HealthWorkoutTypeMap.name(forRawValue: 9999) == "other")
    }

    @Test func importableDropsOwnSource() {
        func w(own: Bool) -> HealthWorkout {
            HealthWorkout(uuid: UUID(), start: Self.date(2026, 1, 1), end: Self.date(2026, 1, 1, 1), activityTypeName: "running",
                          sourceName: "x", sourceBundleID: "x", isOwnSource: own, avgHR: nil, maxHR: nil, energyKcal: nil)
        }
        #expect([w(own: true), w(own: false)].importable.count == 1)
    }

    // MARK: Aggregation

    @Test func dailyMeanPerSourceAndDay() {
        let s = [
            HealthSample(date: Self.date(2026, 3, 1, 3), value: 50, source: Self.watch),
            HealthSample(date: Self.date(2026, 3, 1, 4), value: 52, source: Self.watch),
            HealthSample(date: Self.date(2026, 3, 1, 5), value: 60, source: Self.garmin),
            HealthSample(date: Self.date(2026, 3, 2, 5), value: 48, source: Self.watch)
        ]
        let d = HealthAggregation.daily(s, metric: .restingHR, calendar: Self.cal)
        #expect(d.count == 3)
        #expect(d.first { $0.source == Self.watch && $0.date == Self.date(2026, 3, 1) }?.value == 51)
        #expect(d.first { $0.source == Self.garmin }?.value == 60)
    }

    @Test func bodyMassTakesLastOfDay() {
        let s = [
            HealthSample(date: Self.date(2026, 3, 1, 7), value: 80.4, source: Self.watch),
            HealthSample(date: Self.date(2026, 3, 1, 20), value: 81.0, source: Self.watch)
        ]
        #expect(HealthAggregation.daily(s, metric: .bodyMass, calendar: Self.cal).first?.value == 81.0)
    }

    @Test func sleepSumsAsleepOnlyAndMergesOverlap() {
        let seg = [
            HealthSleepSegment(start: Self.date(2026, 3, 1, 22, 30), end: Self.date(2026, 3, 2, 0, 30), isAsleep: true, source: Self.watch),
            HealthSleepSegment(start: Self.date(2026, 3, 2, 0, 0), end: Self.date(2026, 3, 2, 2, 0), isAsleep: true, source: Self.watch),
            HealthSleepSegment(start: Self.date(2026, 3, 2, 2, 0), end: Self.date(2026, 3, 2, 2, 30), isAsleep: false, source: Self.watch),
            HealthSleepSegment(start: Self.date(2026, 3, 2, 2, 30), end: Self.date(2026, 3, 2, 6, 30), isAsleep: true, source: Self.watch),
            HealthSleepSegment(start: Self.date(2026, 3, 1, 23), end: Self.date(2026, 3, 2, 5), isAsleep: true, source: Self.garmin)
        ]
        let d = HealthAggregation.sleepNights(seg, calendar: Self.cal)
        #expect(d.count == 2)
        let w = d.first { $0.source == Self.watch }
        #expect(w?.date == Self.date(2026, 3, 2))
        #expect(abs((w?.value ?? 0) - 7.5) < 1e-9)   // 22:30–02:00 + 02:30–06:30
        #expect(abs((d.first { $0.source == Self.garmin }?.value ?? 0) - 6) < 1e-9)
        #expect(d.allSatisfy { $0.metric == .sleepHours })
    }

    @Test func sleepValueClassification() {
        // HKCategoryValueSleepAnalysis: 0 inBed, 1 unspecified, 2 awake, 3 core, 4 deep, 5 REM
        #expect([1, 3, 4, 5].allSatisfy { HealthAggregation.isAsleep(rawValue: $0) })
        #expect([0, 2, 9].allSatisfy { !HealthAggregation.isAsleep(rawValue: $0) })
    }

    @Test func heartRateSecondsInterpolatesAndHolds() {
        let t0 = Self.date(2026, 3, 1, 10)
        let s = [
            HealthSample(date: t0, value: 100, source: Self.watch),
            HealthSample(date: t0.addingTimeInterval(4), value: 120, source: Self.watch),
            HealthSample(date: t0.addingTimeInterval(100), value: 130, source: Self.watch)
        ]
        let r = HealthAggregation.heartRateSeconds(s, start: t0, end: t0.addingTimeInterval(10))
        #expect(r?.count == 10)
        #expect(r?.power.allSatisfy { $0 == 0 } == true)
        #expect(r?.heartRate?[0] == 100)
        #expect(r?.heartRate?[2] == 110)
        #expect(r?.heartRate?[4] == 120)
        #expect(r?.heartRate?[9] == 120)   // Lücke > 15 s: letzter Wert gehalten
    }

    @Test func heartRateSecondsNilWithoutSamples() {
        let t0 = Self.date(2026, 3, 1, 10)
        #expect(HealthAggregation.heartRateSeconds([], start: t0, end: t0.addingTimeInterval(60)) == nil)
        #expect(HealthAggregation.heartRateSeconds([HealthSample(date: t0, value: 90, source: Self.watch)], start: t0, end: t0) == nil)
    }

    @Test func bodyMassSevenDayMean() {
        let now = Self.date(2026, 3, 10, 12)
        let ds = [
            HealthDaily(date: Self.date(2026, 3, 10), metric: .bodyMass, value: 80, source: Self.watch),
            HealthDaily(date: Self.date(2026, 3, 8), metric: .bodyMass, value: 82, source: Self.watch),
            HealthDaily(date: Self.date(2026, 3, 1), metric: .bodyMass, value: 90, source: Self.watch),
            HealthDaily(date: Self.date(2026, 3, 9), metric: .restingHR, value: 50, source: Self.watch)
        ]
        #expect(HealthAggregation.mean7Day(ds, asOf: now, calendar: Self.cal) == 81)
        #expect(HealthAggregation.mean7Day([], asOf: now, calendar: Self.cal) == nil)
    }

    // MARK: Pinning

    @Test func suggestionIsSourceWithMostValuesInLast28Days() {
        let now = Self.date(2026, 3, 30)
        func day(_ i: Int) -> Date { Self.cal.date(byAdding: .day, value: -i, to: now)! }
        var ds: [HealthDaily] = []
        for i in 0..<10 { ds.append(HealthDaily(date: day(i), metric: .restingHR, value: 50, source: Self.watch)) }
        for i in 0..<20 { ds.append(HealthDaily(date: day(i), metric: .restingHR, value: 55, source: Self.garmin)) }
        for i in 40..<80 { ds.append(HealthDaily(date: day(i), metric: .restingHR, value: 50, source: Self.watch)) }
        for i in 0..<30 { ds.append(HealthDaily(date: day(i), metric: .hrvSDNN, value: 40, source: Self.watch)) }
        #expect(HealthSourcePinning.suggestion(from: ds, metric: .restingHR, now: now, calendar: Self.cal) == Self.garmin)
        #expect(HealthSourcePinning.suggestion(from: ds, metric: .sleepHours, now: now, calendar: Self.cal) == nil)
    }

    @Test func pinnedSourceFiltersAndSwitchStartsNewBaseline() {
        var pins = HealthSourcePins()
        let ds = [
            HealthDaily(date: Self.date(2026, 3, 1), metric: .restingHR, value: 50, source: Self.watch),
            HealthDaily(date: Self.date(2026, 3, 5), metric: .restingHR, value: 51, source: Self.watch),
            HealthDaily(date: Self.date(2026, 3, 5), metric: .restingHR, value: 60, source: Self.garmin),
            HealthDaily(date: Self.date(2026, 3, 2), metric: .hrvSDNN, value: 40, source: Self.garmin)
        ]
        #expect(HealthSourcePinning.filter(ds, pins: pins).count == 4)

        pins.pin(Self.watch, for: .restingHR, from: Self.date(2026, 3, 1))
        #expect(HealthSourcePinning.filter(ds, pins: pins).filter { $0.metric == .restingHR }.count == 2)
        #expect(HealthSourcePinning.filter(ds, pins: pins).contains { $0.metric == .hrvSDNN })

        pins.pin(Self.watch, for: .restingHR, from: Self.date(2026, 3, 4))   // gleiche Quelle: Basis bleibt
        #expect(pins.pins[.restingHR]?.since == Self.date(2026, 3, 1))

        pins.pin(Self.garmin, for: .restingHR, from: Self.date(2026, 3, 5))   // Wechsel: neue Basis
        let r = HealthSourcePinning.filter(ds, pins: pins).filter { $0.metric == .restingHR }
        #expect(r.count == 1 && r[0].source == Self.garmin)
        #expect(pins.pins[.restingHR]?.since == Self.date(2026, 3, 5))
    }

    @Test func pinsAreCodable() throws {
        var pins = HealthSourcePins()
        pins.pin(Self.watch, for: .sleepHours, from: Self.date(2026, 3, 1))
        let back = try JSONDecoder().decode(HealthSourcePins.self, from: JSONEncoder().encode(pins))
        #expect(back == pins)
    }

    // MARK: Anker-Store, Stub

    @Test func anchorStoreRoundTrip() {
        let defaults = UserDefaults(suiteName: "HealthAnchorStoreTests-\(UUID().uuidString)")!
        let store = HealthAnchorStore(defaults: defaults)
        #expect(store.anchor(for: .workouts) == nil)
        store.save(HealthAnchor(data: Data([1, 2, 3])), for: .workouts)
        #expect(store.anchor(for: .workouts)?.data == Data([1, 2, 3]))
        #expect(store.anchor(for: .bodyMass) == nil)
        store.save(nil, for: .workouts)
        #expect(store.anchor(for: .workouts) == nil)
    }

    @Test func stubDeliversWorkoutsAndObserver() async throws {
        let w = HealthWorkout(uuid: UUID(), start: Self.date(2026, 3, 1), end: Self.date(2026, 3, 1, 1), activityTypeName: "running",
                              sourceName: "Garmin", sourceBundleID: "com.garmin.connect", isOwnSource: false, avgHR: 140, maxHR: 170, energyKcal: 500)
        let stub = StubHealthDataSource(workouts: [w])
        #expect(stub.isAvailable)
        try await stub.requestReadAuthorization([.workouts])
        let first = try await stub.workouts(since: nil)
        #expect(first.added == [w])
        let again = try await stub.workouts(since: first.anchor)
        #expect(again.added.isEmpty)

        let fired = Counter()
        try await stub.enableBackgroundDeliveryForWorkouts { fired.increment() }
        stub.simulateNewWorkouts()
        #expect(fired.value == 1)
    }

    @Test func factoryUsesStubForLaunchArgument() {
        #expect(HealthDataSourceFactory.make(arguments: ["app", "-uiHealthStub", "YES"]) is StubHealthDataSource)
    }
}

private final class Counter: @unchecked Sendable {
    private let lock = NSLock()
    private var n = 0
    func increment() { lock.lock(); n += 1; lock.unlock() }
    var value: Int { lock.lock(); defer { lock.unlock() }; return n }
}
