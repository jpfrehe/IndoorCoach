import Foundation
import Synchronization
#if canImport(HealthKit) && os(iOS)
@preconcurrency import HealthKit
#endif

// Lesender HealthKit-Zugriff (docs/17 §3.1, B46). Es wird nichts geschrieben; Gesundheitswerte werden nie geloggt.
// Hinter einem Protokoll, damit Store/UI/Tests gegen den Stub laufen.

// MARK: - Protokoll

public protocol HealthDataSource: Sendable {
    /// Health auf diesem Gerät vorhanden (iPad ohne Health: false).
    var isAvailable: Bool { get }
    /// Ob die Berechtigungsanfrage noch aussteht (der Lese-Status selbst ist in HealthKit nicht abfragbar).
    func authorizationStatus(for types: Set<HealthReadType>) async -> HealthAuthorizationStatus
    func requestReadAuthorization(_ types: Set<HealthReadType>) async throws
    /// Neue und gelöschte Workouts seit `anchor` (`nil` = alles). Den neuen Anker speichert der Aufrufer (`HealthAnchorStore`).
    func workouts(since anchor: HealthAnchor?) async throws -> HealthWorkoutChanges
    /// Puls des Workouts als 1-Hz-Reihe, Leistung 0. `nil` ohne Pulsdaten.
    func heartRateSeconds(for workout: HealthWorkout) async throws -> RideSeconds?
    /// Tageswerte je Quelle im Zeitraum.
    func dailyValues(_ metric: HealthMetric, in range: ClosedRange<Date>) async throws -> [HealthDaily]
    /// Mittel der Körpergewicht-Tageswerte der letzten 7 Tage, optional nur einer Quelle.
    func bodyMass7DayMean(asOf: Date, source: HealthSourceRef?) async throws -> Double?
    /// Weckt die App bei neuen Workouts. `onChange` läuft auf einer beliebigen Queue und muss kurz bleiben.
    func enableBackgroundDeliveryForWorkouts(_ onChange: @escaping @Sendable () -> Void) async throws
}

public enum HealthDataError: Error, Equatable, Sendable {
    case unavailable
}

// MARK: - Anker-Store

/// Merkt sich je Datentyp den Anker der letzten inkrementellen Abfrage (kein Gesundheitswert, nur ein Zeiger).
public struct HealthAnchorStore: @unchecked Sendable {
    private let defaults: UserDefaults

    public init(defaults: UserDefaults = .standard) { self.defaults = defaults }

    private func key(_ type: HealthReadType) -> String { "healthKit.anchor.\(type.rawValue)" }

    public func anchor(for type: HealthReadType) -> HealthAnchor? {
        defaults.data(forKey: key(type)).map(HealthAnchor.init(data:))
    }

    public func save(_ anchor: HealthAnchor?, for type: HealthReadType) {
        if let anchor { defaults.set(anchor.data, forKey: key(type)) } else { defaults.removeObject(forKey: key(type)) }
    }
}

// MARK: - Stub

/// Für Tests und UI (`-uiHealthStub`). Anker = Anzahl bereits gelieferter Workouts.
public final class StubHealthDataSource: HealthDataSource {
    private struct State {
        var workouts: [HealthWorkout]
        var handler: (@Sendable () -> Void)?
    }

    public let isAvailable: Bool
    private let daily: [HealthDaily]
    private let heartRate: RideSeconds?
    private let state: Mutex<State>

    public init(workouts: [HealthWorkout] = [], daily: [HealthDaily] = [], heartRate: RideSeconds? = nil, isAvailable: Bool = true) {
        self.isAvailable = isAvailable
        self.daily = daily
        self.heartRate = heartRate
        state = Mutex(State(workouts: workouts, handler: nil))
    }

    /// Fügt ein Workout hinzu und löst den Observer aus.
    public func simulateNewWorkouts(_ new: [HealthWorkout] = []) {
        let handler = state.withLock { s -> (@Sendable () -> Void)? in
            s.workouts.append(contentsOf: new)
            return s.handler
        }
        handler?()
    }

    public func authorizationStatus(for types: Set<HealthReadType>) async -> HealthAuthorizationStatus {
        isAvailable ? .requested : .unavailable
    }

    public func requestReadAuthorization(_ types: Set<HealthReadType>) async throws {
        guard isAvailable else { throw HealthDataError.unavailable }
    }

    public func workouts(since anchor: HealthAnchor?) async throws -> HealthWorkoutChanges {
        let all = state.withLock { $0.workouts }
        let seen = anchor.flatMap { String(data: $0.data, encoding: .utf8) }.flatMap(Int.init) ?? 0
        let new = Array(all.dropFirst(seen))
        return HealthWorkoutChanges(added: new, deleted: [], anchor: HealthAnchor(data: Data(String(all.count).utf8)))
    }

    public func heartRateSeconds(for workout: HealthWorkout) async throws -> RideSeconds? { heartRate }

    public func dailyValues(_ metric: HealthMetric, in range: ClosedRange<Date>) async throws -> [HealthDaily] {
        daily.filter { $0.metric == metric && range.contains($0.date) }
    }

    public func bodyMass7DayMean(asOf: Date, source: HealthSourceRef?) async throws -> Double? {
        HealthAggregation.mean7Day(daily.filter { source == nil || $0.source == source }, asOf: asOf)
    }

    public func enableBackgroundDeliveryForWorkouts(_ onChange: @escaping @Sendable () -> Void) async throws {
        state.withLock { $0.handler = onChange }
    }
}

// MARK: - Auswahl

public enum HealthDataSourceFactory {
    /// `-uiHealthStub` → Stub mit Beispieldaten; sonst HealthKit (iOS) bzw. ein nicht verfügbarer Stub (macOS).
    public static func make(arguments: [String] = ProcessInfo.processInfo.arguments) -> any HealthDataSource {
        if arguments.contains("-uiHealthStub") { return uiStub() }
        #if canImport(HealthKit) && os(iOS)
        return HealthKitService()
        #else
        return StubHealthDataSource(isAvailable: false)
        #endif
    }

    private static func uiStub() -> StubHealthDataSource {
        let end = Date.now.addingTimeInterval(-3600)
        let hevy = HealthSourceRef(name: "Hevy", bundleID: "com.hevy.app")
        let watch = HealthSourceRef(name: "Apple Watch", bundleID: "com.apple.health")
        let workouts = [
            HealthWorkout(uuid: UUID(), start: end.addingTimeInterval(-3600), end: end, activityTypeName: "traditionalStrengthTraining",
                          sourceName: hevy.name, sourceBundleID: hevy.bundleID, isOwnSource: false, avgHR: nil, maxHR: nil, energyKcal: 320),
            HealthWorkout(uuid: UUID(), start: end.addingTimeInterval(-90_000), end: end.addingTimeInterval(-86_400), activityTypeName: "running",
                          sourceName: watch.name, sourceBundleID: watch.bundleID, isOwnSource: false, avgHR: 148, maxHR: 171, energyKcal: 480)
        ]
        let today = Calendar.current.startOfDay(for: .now)
        let daily = (0..<14).flatMap { i -> [HealthDaily] in
            let day = Calendar.current.date(byAdding: .day, value: -i, to: today) ?? today
            return [HealthDaily(date: day, metric: .restingHR, value: 52 + Double(i % 3), source: watch),
                    HealthDaily(date: day, metric: .sleepHours, value: 7 + Double(i % 2) * 0.5, source: watch),
                    HealthDaily(date: day, metric: .bodyMass, value: 78.5, source: watch)]
        }
        return StubHealthDataSource(workouts: workouts, daily: daily)
    }
}

// MARK: - HealthKit (iOS)

#if canImport(HealthKit) && os(iOS)

/// Concurrency: `HKHealthStore` ist thread-sicher; die Klasse hält nur ihn und eine mutex-geschützte Observer-Query.
/// Alle Callback-APIs werden per Continuation in async/await gewandelt; die nicht-`Sendable` HealthKit-Objekte
/// werden innerhalb des Callbacks in Werttypen überführt und verlassen ihn nie.
public final class HealthKitService: HealthDataSource, @unchecked Sendable {
    private let store = HKHealthStore()
    private let observer = Mutex<HKObserverQuery?>(nil)

    public init() {}

    public var isAvailable: Bool { HKHealthStore.isHealthDataAvailable() }

    // MARK: Typen

    private func objectTypes(for types: Set<HealthReadType>) -> Set<HKObjectType> {
        var out = Set<HKObjectType>()
        for t in types {
            switch t {
            case .workouts: out.insert(.workoutType())
            case .heartRate: out.insert(HKQuantityType(.heartRate))
            case .bodyMass: out.insert(HKQuantityType(.bodyMass))
            case .restingHR: out.insert(HKQuantityType(.restingHeartRate))
            case .hrvSDNN: out.insert(HKQuantityType(.heartRateVariabilitySDNN))
            case .sleep: out.insert(HKCategoryType(.sleepAnalysis))
            case .respiratoryRate: out.insert(HKQuantityType(.respiratoryRate))
            case .wristTemperature: out.insert(HKQuantityType(.appleSleepingWristTemperature))
            }
        }
        return out
    }

    // MARK: Berechtigung

    public func authorizationStatus(for types: Set<HealthReadType>) async -> HealthAuthorizationStatus {
        guard isAvailable else { return .unavailable }
        let status = try? await store.statusForAuthorizationRequest(toShare: [], read: objectTypes(for: types))
        return status == .shouldRequest ? .notDetermined : .requested
    }

    public func requestReadAuthorization(_ types: Set<HealthReadType>) async throws {
        guard isAvailable else { throw HealthDataError.unavailable }
        try await store.requestAuthorization(toShare: [], read: objectTypes(for: types))
    }

    // MARK: Workouts

    public func workouts(since anchor: HealthAnchor?) async throws -> HealthWorkoutChanges {
        guard isAvailable else { throw HealthDataError.unavailable }
        let hkAnchor = anchor.flatMap { try? NSKeyedUnarchiver.unarchivedObject(ofClass: HKQueryAnchor.self, from: $0.data) }
        return try await withCheckedThrowingContinuation { continuation in
            let query = HKAnchoredObjectQuery(type: .workoutType(), predicate: nil, anchor: hkAnchor, limit: HKObjectQueryNoLimit) {
                _, added, deleted, newAnchor, error in
                if let error { continuation.resume(throwing: error); return }
                let data = newAnchor.flatMap { try? NSKeyedArchiver.archivedData(withRootObject: $0, requiringSecureCoding: true) } ?? Data()
                let workouts = (added ?? []).compactMap { ($0 as? HKWorkout).map(Self.workout(from:)) }
                continuation.resume(returning: HealthWorkoutChanges(
                    added: workouts, deleted: (deleted ?? []).map(\.uuid), anchor: HealthAnchor(data: data)))
            }
            store.execute(query)
        }
    }

    private static func workout(from w: HKWorkout) -> HealthWorkout {
        let source = w.sourceRevision.source
        let bpm = HKUnit.count().unitDivided(by: .minute())
        let hr = w.statistics(for: HKQuantityType(.heartRate))
        return HealthWorkout(
            uuid: w.uuid, start: w.startDate, end: w.endDate,
            activityTypeName: HealthWorkoutTypeMap.name(forRawValue: w.workoutActivityType.rawValue),
            sourceName: source.name, sourceBundleID: source.bundleIdentifier,
            isOwnSource: source == HKSource.default(),
            avgHR: hr?.averageQuantity()?.doubleValue(for: bpm),
            maxHR: hr?.maximumQuantity()?.doubleValue(for: bpm),
            energyKcal: w.statistics(for: HKQuantityType(.activeEnergyBurned))?.sumQuantity()?.doubleValue(for: .kilocalorie()))
    }

    // MARK: Puls

    public func heartRateSeconds(for workout: HealthWorkout) async throws -> RideSeconds? {
        guard isAvailable else { throw HealthDataError.unavailable }
        let predicate = HKQuery.predicateForSamples(withStart: workout.start, end: workout.end, options: .strictStartDate)
        let bpm = HKUnit.count().unitDivided(by: .minute())
        let samples = try await quantitySamples(HKQuantityType(.heartRate), predicate: predicate, unit: bpm)
        let fromWorkoutSource = samples.filter { $0.source.bundleID == workout.sourceBundleID }
        return HealthAggregation.heartRateSeconds(fromWorkoutSource.isEmpty ? samples : fromWorkoutSource,
                                                  start: workout.start, end: workout.end)
    }

    // MARK: Tageswerte

    public func dailyValues(_ metric: HealthMetric, in range: ClosedRange<Date>) async throws -> [HealthDaily] {
        guard isAvailable else { throw HealthDataError.unavailable }
        let calendar = Calendar.current
        switch metric {
        case .sleepHours:
            // Eine Nacht beginnt am Vorabend: Fenster großzügig nach vorn öffnen.
            let from = range.lowerBound.addingTimeInterval(-24 * 3600)
            let predicate = HKQuery.predicateForSamples(withStart: from, end: range.upperBound, options: [])
            let segments = try await sleepSegments(predicate: predicate)
            return HealthAggregation.sleepNights(segments, calendar: calendar).filter { range.contains($0.date) }
        default:
            let (type, unit) = Self.quantity(for: metric)
            let predicate = HKQuery.predicateForSamples(withStart: range.lowerBound, end: range.upperBound, options: [])
            let samples = try await quantitySamples(type, predicate: predicate, unit: unit)
            return HealthAggregation.daily(samples, metric: metric, calendar: calendar)
        }
    }

    public func bodyMass7DayMean(asOf: Date, source: HealthSourceRef?) async throws -> Double? {
        let calendar = Calendar.current
        let from = calendar.date(byAdding: .day, value: -6, to: calendar.startOfDay(for: asOf)) ?? asOf
        let all = try await dailyValues(.bodyMass, in: from...asOf)
        return HealthAggregation.mean7Day(all.filter { source == nil || $0.source == source }, asOf: asOf, calendar: calendar)
    }

    private static func quantity(for metric: HealthMetric) -> (HKQuantityType, HKUnit) {
        let perMinute = HKUnit.count().unitDivided(by: .minute())
        switch metric {
        case .restingHR: return (HKQuantityType(.restingHeartRate), perMinute)
        case .hrvSDNN: return (HKQuantityType(.heartRateVariabilitySDNN), .secondUnit(with: .milli))
        case .respiratoryRate: return (HKQuantityType(.respiratoryRate), perMinute)
        case .wristTempDelta: return (HKQuantityType(.appleSleepingWristTemperature), .degreeCelsius())
        case .bodyMass: return (HKQuantityType(.bodyMass), .gramUnit(with: .kilo))
        case .sleepHours: return (HKQuantityType(.restingHeartRate), perMinute)   // nicht erreichbar, Schlaf ist Kategorie
        }
    }

    // MARK: Abfragen

    private func quantitySamples(_ type: HKQuantityType, predicate: NSPredicate, unit: HKUnit) async throws -> [HealthSample] {
        try await withCheckedThrowingContinuation { continuation in
            let query = HKSampleQuery(sampleType: type, predicate: predicate, limit: HKObjectQueryNoLimit, sortDescriptors: nil) { _, results, error in
                if let error { continuation.resume(throwing: error); return }
                let samples = (results as? [HKQuantitySample] ?? []).map {
                    HealthSample(date: $0.startDate, value: $0.quantity.doubleValue(for: unit),
                                 source: HealthSourceRef(name: $0.sourceRevision.source.name, bundleID: $0.sourceRevision.source.bundleIdentifier))
                }
                continuation.resume(returning: samples)
            }
            store.execute(query)
        }
    }

    private func sleepSegments(predicate: NSPredicate) async throws -> [HealthSleepSegment] {
        try await withCheckedThrowingContinuation { continuation in
            let query = HKSampleQuery(sampleType: HKCategoryType(.sleepAnalysis), predicate: predicate, limit: HKObjectQueryNoLimit, sortDescriptors: nil) { _, results, error in
                if let error { continuation.resume(throwing: error); return }
                let segments = (results as? [HKCategorySample] ?? []).map {
                    HealthSleepSegment(start: $0.startDate, end: $0.endDate, isAsleep: HealthAggregation.isAsleep(rawValue: $0.value),
                                       source: HealthSourceRef(name: $0.sourceRevision.source.name, bundleID: $0.sourceRevision.source.bundleIdentifier))
                }
                continuation.resume(returning: segments)
            }
            store.execute(query)
        }
    }

    // MARK: Hintergrundzustellung

    public func enableBackgroundDeliveryForWorkouts(_ onChange: @escaping @Sendable () -> Void) async throws {
        guard isAvailable else { throw HealthDataError.unavailable }
        let query = HKObserverQuery(sampleType: .workoutType(), predicate: nil) { _, completion, error in
            if error == nil { onChange() }
            completion()
        }
        let old = observer.withLock { current -> HKObserverQuery? in
            defer { current = query }
            return current
        }
        if let old { store.stop(old) }
        store.execute(query)
        try await store.enableBackgroundDelivery(for: .workoutType(), frequency: .immediate)
    }
}

#endif
