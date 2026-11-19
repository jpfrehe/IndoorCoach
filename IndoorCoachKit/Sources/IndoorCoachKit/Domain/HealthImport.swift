import Foundation

/// Reine Logik des Health-Imports (docs/17 §2.3, §8.2, §10.1 O6, B47/B48): was wird aus einem Workout aus Apple Health?
///
/// - Eigene App-Quelle und nicht zählende Sportarten fallen weg.
/// - Überlappt das Workout zu ≥ 50 % (seiner eigenen Dauer) mit einer vorhandenen Fahrt oder Krafteinheit, ist es keine
///   neue Belastung; es ergänzt höchstens fehlenden Puls (Priorität FIT/Brücke > Gurt-iPhone > Health > MyWhoosh-Liste).
/// - Rad ohne Überlappung ist eine Outdoor-/Fremdfahrt und zählt normal als Rad.
/// - Aerobe Fremdsportarten bekommen eine geschätzte TSS (O6): Puls-TSS mit Schwellenpuls, sonst aus dem TRIMP, sonst
///   Dauer × Sportart-Faktor.
/// - Kraft, Klettern und Gemischtes werden offene Annotations-Kandidaten.
public enum HealthImport {
    /// Ab diesem Anteil seiner eigenen Dauer gilt ein Health-Workout als bereits vorhanden.
    public static let overlapThreshold = 0.5

    // MARK: Puls-Priorität

    /// Woher ein vorhandener Puls stammt, aufsteigend nach Verlässlichkeit.
    public enum HeartRateRank: Int, Comparable, Sendable {
        /// MyWhoosh-Fahrtenliste (nur Durchschnitt).
        case list
        /// Apple Health.
        case health
        /// Brustgurt am iPhone oder Strava-Fahrt.
        case strap
        /// FIT-Datei oder Brücke (Leistungskurve vorhanden).
        case fit

        public static func < (lhs: Self, rhs: Self) -> Bool { lhs.rawValue < rhs.rawValue }
    }

    /// Rang des Pulses einer vorhandenen Fahrt; `nil`, wenn sie keinen Puls hat.
    public static func rank(hasCurve: Bool, hasSecondsHeartRate: Bool, isStrava: Bool, hasHeartRate: Bool) -> HeartRateRank? {
        guard hasHeartRate || hasSecondsHeartRate else { return nil }
        if hasCurve { return .fit }
        if hasSecondsHeartRate || isStrava { return .strap }
        return .list
    }

    // MARK: Entscheidung

    /// Eine vorhandene Fahrt oder Krafteinheit, mit der ein Health-Workout zeitlich überlappen kann.
    public struct Occupied: Equatable, Sendable {
        public enum Kind: Hashable, Sendable {
            case ride(Int)
            case strength(UUID)
        }

        public var kind: Kind
        public var start: Date
        public var end: Date
        /// Rang des vorhandenen Pulses, `nil` = kein Puls.
        public var heartRate: HeartRateRank?

        public init(kind: Kind, start: Date, end: Date, heartRate: HeartRateRank?) {
            self.kind = kind
            self.start = start
            self.end = end
            self.heartRate = heartRate
        }
    }

    public enum SkipReason: Equatable, Sendable {
        case ownSource, ignoredSport, empty
    }

    public enum Decision: Equatable, Sendable {
        case skip(SkipReason)
        /// Schon vorhanden. `supplyHeartRate`: der Puls des Health-Workouts ersetzt oder ergänzt den vorhandenen.
        case merge(Occupied.Kind, supplyHeartRate: Bool)
        /// Aerobe Fremdsportart mit geschätzter TSS.
        case aerobic(Estimate)
        /// Outdoor-/Fremdfahrt: zählt normal als Rad.
        case cycling
        /// Kraft/Klettern/Gemischt: Nutzer ergänzt Härte und Beine.
        case candidate
    }

    public static func decide(_ workout: HealthWorkout, occupied: [Occupied], thresholdHeartRate: Int?,
                              heartRate: RelativeEffort.HeartRateProfile) -> Decision {
        if workout.isOwnSource { return .skip(.ownSource) }
        let category = workout.category
        if category == .ignore { return .skip(.ignoredSport) }
        guard workout.end > workout.start else { return .skip(.empty) }
        if let best = bestOverlap(of: workout, in: occupied) {
            let supply = workout.avgHR != nil && (best.heartRate.map { $0 < .health } ?? true)
            return .merge(best.kind, supplyHeartRate: supply)
        }
        switch category {
        case .cycling: return .cycling
        case .aerobic: return .aerobic(estimate(for: workout, thresholdHeartRate: thresholdHeartRate, heartRate: heartRate))
        case .muscular, .mixed: return .candidate
        case .ignore: return .skip(.ignoredSport)
        }
    }

    /// Anteil von [start, end], der in [otherStart, otherEnd] liegt (0 … 1).
    public static func overlapFraction(start: Date, end: Date, otherStart: Date, otherEnd: Date) -> Double {
        let length = end.timeIntervalSince(start)
        guard length > 0 else { return 0 }
        let overlap = min(end, otherEnd).timeIntervalSince(max(start, otherStart))
        return max(0, overlap) / length
    }

    /// Die Fahrt/Einheit mit der größten Überlappung, sofern sie die Schwelle erreicht.
    static func bestOverlap(of workout: HealthWorkout, in occupied: [Occupied]) -> Occupied? {
        occupied
            .map { ($0, overlapFraction(start: workout.start, end: workout.end, otherStart: $0.start, otherEnd: $0.end)) }
            .filter { $0.1 >= overlapThreshold }
            .max { $0.1 < $1.1 }?.0
    }

    // MARK: Geschätzte Fremd-TSS (O6)

    public enum EstimateMethod: String, Equatable, Sendable {
        /// Stunden × (Ø-Puls ÷ Schwellenpuls)² × 100.
        case thresholdHeartRate
        /// Aus dem TRIMP (`RelativeEffort`), so skaliert, dass 1 h am Schwellenpuls ≈ 100 ergibt.
        case trimp
        /// Dauer × Sportart-Faktor (kein Puls).
        case duration
    }

    public struct Estimate: Equatable, Sendable {
        public var tss: Double
        public var method: EstimateMethod
        public init(tss: Double, method: EstimateMethod) {
            self.tss = tss
            self.method = method
        }
    }

    /// Ohne gesetzten Schwellenpuls gilt 85 % der Herzfrequenzreserve als Schwelle (Karvonen).
    public static let thresholdReserveFraction = 0.85

    public static func estimate(for workout: HealthWorkout, thresholdHeartRate: Int?,
                                heartRate profile: RelativeEffort.HeartRateProfile) -> Estimate {
        let seconds = max(0, workout.end.timeIntervalSince(workout.start))
        let hours = seconds / 3600
        if let hr = workout.avgHR, hr > 0 {
            if let threshold = thresholdHeartRate, threshold > 0 {
                let ratio = hr / Double(threshold)
                return Estimate(tss: hours * ratio * ratio * 100, method: .thresholdHeartRate)
            }
            if profile.isValid, hr > Double(profile.resting) {
                let fraction = min(1, (hr - Double(profile.resting)) / Double(profile.max - profile.resting))
                let trimp = RelativeEffort.trimp(minutes: seconds / 60, reserveFraction: fraction)
                let hourAtThreshold = RelativeEffort.trimp(minutes: 60, reserveFraction: thresholdReserveFraction)
                return Estimate(tss: trimp * 100 / hourAtThreshold, method: .trimp)
            }
        }
        return Estimate(tss: hours * sportFactor(for: workout.activityTypeName), method: .duration)
    }

    /// TSS pro Stunde ohne Puls.
    public static func sportFactor(for activityTypeName: String) -> Double {
        switch SportClassification.normalize(activityTypeName) {
        case "running", "laufen", "laufband": 60
        case "crosscountryskiing", "langlauf", "rowing", "rudern": 55
        case "hiking", "walking", "wandern", "gehen": 25
        default: 40
        }
    }

    // MARK: Namen

    public static func germanName(for activityTypeName: String) -> String {
        names[SportClassification.normalize(activityTypeName)] ?? "Training"
    }

    /// Strava-artiger Sporttyp für die Fahrtenliste.
    public static func sportType(for activityTypeName: String) -> String {
        switch SportClassification.normalize(activityTypeName) {
        case "running": "Run"
        case "walking": "Walk"
        case "hiking": "Hike"
        case "swimming": "Swim"
        case "rowing": "Rowing"
        case "crosscountryskiing": "NordicSki"
        case "downhillskiing": "AlpineSki"
        case "snowboarding": "Snowboard"
        case "elliptical": "Elliptical"
        case "cycling", "handcycling": "Ride"
        default: "Workout"
        }
    }

    /// HealthKit-Name für eine Sportart der App (deutsche Bezeichnung oder schon ein HealthKit-Name); `"other"` ohne Treffer.
    public static func activityTypeName(forSport sport: String) -> String {
        let key = SportClassification.normalize(sport)
        let known = HealthWorkoutTypeMap.table.values
        if let hit = known.first(where: { SportClassification.normalize($0) == key }) { return hit }
        let extras = ["laufband": "running", "bouldern": "climbing", "rumpf": "coreTraining", "kurs": "mixedCardio",
                      "gehen": "walking", "laufen": "running", "ski": "downhillSkiing", "skifahren": "downhillSkiing",
                      "langlauf": "crossCountrySkiing"]
        if let mapped = extras[key] { return mapped }
        if let english = names.first(where: { SportClassification.normalize($0.value) == key })?.key,
           let hit = known.first(where: { SportClassification.normalize($0) == english }) { return hit }
        return "other"
    }

    private static let names: [String: String] = [
        "running": "Laufen", "walking": "Gehen", "hiking": "Wandern", "cycling": "Radfahren", "handcycling": "Handbike",
        "crosscountryskiing": "Ski-Langlauf", "downhillskiing": "Skifahren", "snowboarding": "Snowboarden",
        "skatingsports": "Eislaufen", "rowing": "Rudern", "elliptical": "Crosstrainer", "swimming": "Schwimmen",
        "stairclimbing": "Treppensteigen", "stairs": "Treppensteigen", "steptraining": "Step-Training",
        "paddlesports": "Paddeln", "traditionalstrengthtraining": "Krafttraining",
        "functionalstrengthtraining": "Funktionelles Krafttraining", "coretraining": "Rumpftraining",
        "climbing": "Klettern", "flexibility": "Beweglichkeit", "pilates": "Pilates", "barre": "Barre",
        "highintensityintervaltraining": "HIIT", "crosstraining": "Cross-Training", "mixedcardio": "Misch-Cardio",
        "mixedmetaboliccardiotraining": "Misch-Cardio", "jumprope": "Seilspringen", "boxing": "Boxen",
        "kickboxing": "Kickboxen", "martialarts": "Kampfsport"
    ]
}

// MARK: - Protokoll der Health-Workouts

/// Was aus einem Health-Workout geworden ist. Die Liste ist die Gedächtnisstütze des Imports: Anker verloren, Workout
/// nochmal geliefert, Zusammenführung rückgängig gemacht – nichts wird doppelt oder gegen den Willen des Nutzers verarbeitet.
public struct HealthLedgerEntry: Codable, Equatable, Identifiable, Sendable {
    public enum Outcome: String, Codable, Sendable {
        /// Als Fahrt gespeichert (aerobe Fremdsportart oder Rad).
        case imported
        /// Mit einer vorhandenen Fahrt/Krafteinheit zusammengeführt.
        case merged
        /// Wartet auf Härte und Beine (Karte auf Heute).
        case candidate
        /// Als Krafteinheit/„Andere Einheit“ gespeichert.
        case annotated
        /// Vom Nutzer ignoriert.
        case dismissed
    }

    public var uuid: UUID
    public var start: Date
    public var end: Date
    public var activityTypeName: String
    public var sourceName: String
    public var sourceBundleID: String
    public var avgHR: Double?
    public var maxHR: Double?
    public var energyKcal: Double?
    public var outcome: Outcome
    /// Fahrt (`StoredRide.stravaID`), die das Workout ist oder in die es zusammengeführt wurde.
    public var targetRideID: Int?
    /// Krafteinheit, in die es zusammengeführt wurde.
    public var targetStrengthID: UUID?
    /// Indoor-Kennzeichen des Workouts; `nil` bei älteren Einträgen.
    public var indoor: Bool?

    public var id: UUID { uuid }

    public init(_ workout: HealthWorkout, outcome: Outcome, targetRideID: Int? = nil, targetStrengthID: UUID? = nil) {
        uuid = workout.uuid
        start = workout.start
        end = workout.end
        activityTypeName = workout.activityTypeName
        sourceName = workout.sourceName
        sourceBundleID = workout.sourceBundleID
        avgHR = workout.avgHR
        maxHR = workout.maxHR
        energyKcal = workout.energyKcal
        indoor = workout.isIndoor ? true : nil
        self.outcome = outcome
        self.targetRideID = targetRideID
        self.targetStrengthID = targetStrengthID
    }

    public var workout: HealthWorkout {
        HealthWorkout(uuid: uuid, start: start, end: end, activityTypeName: activityTypeName, sourceName: sourceName,
                      sourceBundleID: sourceBundleID, isOwnSource: false, avgHR: avgHR, maxHR: maxHR, energyKcal: energyKcal,
                      isIndoor: indoor ?? false)
    }

    public var durationMinutes: Int { Int((end.timeIntervalSince(start) / 60).rounded()) }
    public var title: String { HealthImport.germanName(for: activityTypeName) }
}

public struct HealthSyncResult: Equatable, Sendable {
    public var imported = 0
    public var merged = 0
    public var candidates = 0
    public var removed = 0
    public init() {}
}
