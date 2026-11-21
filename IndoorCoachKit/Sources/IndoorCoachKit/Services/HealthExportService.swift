import Foundation
import Synchronization
#if canImport(HealthKit) && os(iOS)
@preconcurrency import HealthKit
#endif

// Schreibender Health-Zugriff (docs/17 §8.4, B51): nur eigene Einheiten, je Sportart opt-in, Standard aus.
// Schreibrecht nur für Workout + Herzfrequenz und erst, wenn der Nutzer eine Sportart einschaltet. Keine Leistung.

// MARK: - Protokoll

public protocol HealthWorkoutWriting: Sendable {
    var isAvailable: Bool { get }
    func requestWriteAuthorization(_ types: Set<HealthWriteType>) async throws
    /// Schreibt ein Workout samt Pulswerten; liefert die Health-ID, falls bekannt.
    func save(_ payload: HealthExportPayload) async throws -> UUID?
}

/// Für Tests und UI (`-uiHealthStub`): merkt sich Anfragen und Workouts, schreibt nichts.
public final class StubHealthWorkoutWriter: HealthWorkoutWriting {
    private struct State {
        var requests: [Set<HealthWriteType>] = []
        var saved: [HealthExportPayload] = []
    }

    public let isAvailable: Bool
    private let state = Mutex(State())

    public init(isAvailable: Bool = true) { self.isAvailable = isAvailable }

    public var authorizationRequests: [Set<HealthWriteType>] { state.withLock { $0.requests } }
    public var saved: [HealthExportPayload] { state.withLock { $0.saved } }

    public func requestWriteAuthorization(_ types: Set<HealthWriteType>) async throws {
        guard isAvailable else { throw HealthDataError.unavailable }
        state.withLock { $0.requests.append(types) }
    }

    public func save(_ payload: HealthExportPayload) async throws -> UUID? {
        guard isAvailable else { throw HealthDataError.unavailable }
        state.withLock { $0.saved.append(payload) }
        return UUID()
    }
}

// MARK: - Service

public struct HealthExportResult: Equatable, Sendable {
    public var exported: [UUID] = []
    public var skipped: [UUID: HealthExportRules.Decision] = [:]
    public var failed: [UUID] = []
}

/// Einstellungen und Protokoll (damit nichts doppelt geschrieben wird) liegen in `UserDefaults`; keine Gesundheitswerte.
public struct HealthExportService: @unchecked Sendable {
    static let settingsKey = "healthExport.settings.v1"
    static let ledgerKey = "healthExport.ledger.v1"

    private let writer: any HealthWorkoutWriting
    private let defaults: UserDefaults

    public init(writer: any HealthWorkoutWriting, defaults: UserDefaults = .standard) {
        self.writer = writer
        self.defaults = defaults
    }

    public var isAvailable: Bool { writer.isAvailable }

    public var settings: HealthExportSettings {
        defaults.data(forKey: Self.settingsKey).flatMap { try? JSONDecoder().decode(HealthExportSettings.self, from: $0) }
            ?? HealthExportSettings()
    }

    private func store(_ settings: HealthExportSettings) {
        defaults.set(try? JSONEncoder().encode(settings), forKey: Self.settingsKey)
    }

    private var exportedIDs: Set<String> { Set(defaults.stringArray(forKey: Self.ledgerKey) ?? []) }

    /// Einschalten fragt das Schreibrecht an (Workout + Herzfrequenz); scheitert die Anfrage, bleibt die Sportart aus.
    public func setEnabled(_ sport: HealthExportSport, _ on: Bool) async throws {
        var next = settings
        next.set(sport, on)
        if on {
            guard writer.isAvailable else { throw HealthDataError.unavailable }
            try await writer.requestWriteAuthorization(HealthExportRules.writeTypes(for: next))
        }
        store(next)
    }

    /// Schreibt, was die Regeln erlauben. `existing` = Workouts aus Health (alle Quellen) für die Überlappungsprüfung.
    public func export(_ candidates: [HealthExportCandidate], existing: [HealthWorkout]) async -> HealthExportResult {
        var result = HealthExportResult()
        var ledger = exportedIDs
        let current = settings
        for candidate in candidates where !ledger.contains(candidate.id.uuidString) {
            let decision = HealthExportRules.decide(candidate, settings: current, existing: existing)
            guard decision == .export else { result.skipped[candidate.id] = decision; continue }
            do {
                _ = try await writer.save(HealthExportRules.payload(for: candidate))
                ledger.insert(candidate.id.uuidString)
                result.exported.append(candidate.id)
            } catch {
                result.failed.append(candidate.id)
            }
        }
        defaults.set(Array(ledger), forKey: Self.ledgerKey)
        return result
    }
}

public enum HealthWorkoutWriterFactory {
    /// `-uiHealthStub` → Stub; sonst HealthKit (iOS) bzw. ein nicht verfügbarer Stub (macOS).
    public static func make(arguments: [String] = ProcessInfo.processInfo.arguments) -> any HealthWorkoutWriting {
        #if DEBUG
        if arguments.contains("-uiHealthStub") { return StubHealthWorkoutWriter() }
        #endif
        #if canImport(HealthKit) && os(iOS)
        return HealthKitWorkoutWriter()
        #else
        return StubHealthWorkoutWriter(isAvailable: false)
        #endif
    }
}

// MARK: - HealthKit (iOS)

#if canImport(HealthKit) && os(iOS)

public final class HealthKitWorkoutWriter: HealthWorkoutWriting, @unchecked Sendable {
    private let store = HKHealthStore()

    public init() {}

    public var isAvailable: Bool { HKHealthStore.isHealthDataAvailable() }

    public func requestWriteAuthorization(_ types: Set<HealthWriteType>) async throws {
        guard isAvailable else { throw HealthDataError.unavailable }
        var share = Set<HKSampleType>()
        if types.contains(.workout) { share.insert(HKObjectType.workoutType()) }
        if types.contains(.heartRate) { share.insert(HKQuantityType(.heartRate)) }
        guard !share.isEmpty else { return }
        try await store.requestAuthorization(toShare: share, read: [])
    }

    public func save(_ payload: HealthExportPayload) async throws -> UUID? {
        guard isAvailable else { throw HealthDataError.unavailable }
        let configuration = HKWorkoutConfiguration()
        let raw = HealthWorkoutTypeMap.table.first { $0.value == payload.activityTypeName }?.key
        configuration.activityType = raw.flatMap { HKWorkoutActivityType(rawValue: $0) } ?? .other
        configuration.locationType = payload.activityTypeName == "cycling" ? .indoor : .unknown
        let builder = HKWorkoutBuilder(healthStore: store, configuration: configuration, device: .local())
        try await builder.beginCollection(at: payload.start)
        let type = HKQuantityType(.heartRate)
        let bpm = HKUnit.count().unitDivided(by: .minute())
        let samples = payload.heartRate.map {
            HKQuantitySample(type: type, quantity: HKQuantity(unit: bpm, doubleValue: $0.bpm), start: $0.date, end: $0.date)
        }
        if !samples.isEmpty { try await builder.addSamples(samples) }
        try await builder.addMetadata([HKMetadataKeyExternalUUID: payload.id.uuidString])
        try await builder.endCollection(at: payload.end)
        return try await builder.finishWorkout()?.uuid
    }
}

#endif
