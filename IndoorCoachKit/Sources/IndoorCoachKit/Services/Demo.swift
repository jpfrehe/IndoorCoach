import Foundation

/// Offline planner used in demo mode (no Claude key) – deterministic, rule-based, good enough to explore the UI.
public struct DemoCoach: Coach {
    public init() {}

    public func plan(_ ctx: PlanContext) async throws -> PlanProposal {
        try await Task.sleep(for: .milliseconds(600))
        return Self.makePlan(ctx)
    }

    static func makePlan(_ ctx: PlanContext, calendar: Calendar = .current) -> PlanProposal {
        let library = DemoData.library
        let tsb = ctx.load?.tsb ?? 0
        var rotation: [WorkoutDefinition] = tsb < -20
            ? [library.recovery, library.endurance, library.tempo, library.endurance]
            : [library.sweetSpot, library.endurance, library.vo2, library.longEndurance, library.threshold, library.recovery]
        var workouts: [PlannedWorkoutProposal] = []
        let taken = Set(ctx.alreadyPlanned.map { calendar.startOfDay(for: $0.date) })
        var day = calendar.startOfDay(for: ctx.horizonStart)
        var budget = Int(ctx.profile.weeklyHours * 3600 * Double(max(1, ctx.profile.planHorizonDays)) / 7)
        while day <= ctx.horizonEnd, !rotation.isEmpty {
            let weekday = AthleteProfile.isoWeekday(of: day, calendar: calendar)
            if ctx.profile.trainingDays.contains(weekday), !taken.contains(day) {
                var w = rotation.removeFirst()
                if w.totalDuration > ctx.profile.longestSessionMinutes * 60 { w = library.endurance }
                if w.totalDuration <= budget {
                    budget -= w.totalDuration
                    workouts.append(PlannedWorkoutProposal(date: day, definition: w,
                                                           rationale: "Demo-Plan: \(w.type.label) passend zur aktuellen Form (TSB \(Int(tsb))). Mit Claude-Key gibt es echte, begründete Vorschläge."))
                }
            }
            day = calendar.date(byAdding: .day, value: 1, to: day)!
        }
        return PlanProposal(weekFocus: tsb < -20 ? "Erholen und Grundlage stabilisieren" : "Sweet Spot + VO₂max-Reiz, Rest Grundlage",
                            notes: "Dies ist ein Demo-Plan ohne KI. Hinterlege unter Profil → Coach · Claude einen Claude-API-Key für echte Planung."
                                + (ctx.wish.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? ""
                                   : " Dein Wunsch („\(ctx.wish.trimmingCharacters(in: .whitespacesAndNewlines))“) wird erst mit Claude berücksichtigt."),
                            workouts: workouts, rejected: [])
    }
}

public enum DemoData {
    public struct Library: Sendable {
        public let recovery, endurance, longEndurance, tempo, sweetSpot, threshold, vo2: WorkoutDefinition
    }

    public static let library = Library(
        recovery: WorkoutDefinition(title: "Locker rollen", type: .recovery, summary: "45 Minuten ganz locker mit hoher Trittfrequenz.",
                                    segments: [.warmup(5, from: 0.4, to: 0.5), .steady(35, at: 0.5, cadence: 95), .cooldown(5, from: 0.5, to: 0.4)]),
        endurance: WorkoutDefinition(title: "Grundlage 60", type: .endurance, summary: "Ruhige Z2-Fahrt mit kurzen Trittfrequenz-Spielen.",
                                     segments: [.warmup(10, from: 0.45, to: 0.65), .steady(20, at: 0.68),
                                                .intervals(4, on: 60, at: 0.72, off: 60, at: 0.65, cadence: 105, text: "Hohe Kadenz, ruhiger Oberkörper"),
                                                .steady(12, at: 0.68), .cooldown(10, from: 0.6, to: 0.4)]),
        longEndurance: WorkoutDefinition(title: "Lange Grundlage", type: .endurance, summary: "90 Minuten Z2 – Fettstoffwechsel und Ausdauer.",
                                         segments: [.warmup(10, from: 0.45, to: 0.65), .steady(35, at: 0.68), .steady(30, at: 0.72), .cooldown(15, from: 0.6, to: 0.4)]),
        tempo: WorkoutDefinition(title: "Tempo 2×15", type: .tempo, summary: "Zwei gleichmäßige Tempoblöcke.",
                                 segments: [.warmup(12, from: 0.45, to: 0.75), .intervals(2, on: 900, at: 0.82, off: 300, at: 0.55), .cooldown(8, from: 0.6, to: 0.4)]),
        sweetSpot: WorkoutDefinition(title: "Sweet Spot 3×12", type: .sweetSpot, summary: "Drei lange Blöcke knapp unter der Schwelle.",
                                     segments: [.warmup(10, from: 0.45, to: 0.75), .intervals(3, on: 720, at: 0.9, off: 300, at: 0.55, text: "Gleichmäßig treten"), .cooldown(8, from: 0.65, to: 0.4)]),
        threshold: WorkoutDefinition(title: "Schwelle 4×8", type: .threshold, summary: "Vier Blöcke an der FTP.",
                                     segments: [.warmup(12, from: 0.45, to: 0.8), .intervals(4, on: 480, at: 0.98, off: 240, at: 0.5), .cooldown(8, from: 0.6, to: 0.4)]),
        vo2: WorkoutDefinition(title: "VO₂max 5×4", type: .vo2max, summary: "Fünf harte 4-Minuten-Intervalle für die maximale Sauerstoffaufnahme.",
                               segments: [.warmup(12, from: 0.45, to: 0.8), .steady(1, at: 1.1, text: "Kurz öffnen"), .steady(4, at: 0.55),
                                          .intervals(5, on: 240, at: 1.15, off: 240, at: 0.5, cadence: 100), .cooldown(8, from: 0.6, to: 0.4)])
    )

    /// ~12 weeks (or `days`) of plausible rides ending yesterday (mostly indoor, some outdoor weekend rides).
    public static func rides(endingAt end: Date = .now, days: Int = 84, ftp: Int = 250, calendar: Calendar = .current) -> [RideSummary] {
        var rng = SeededGenerator(seed: 42)
        var result: [RideSummary] = []
        let today = calendar.startOfDay(for: end)
        var id = 9_000_000
        for offset in stride(from: days, through: 1, by: -1) {
            let day = calendar.date(byAdding: .day, value: -offset, to: today)!
            let weekday = AthleteProfile.isoWeekday(of: day, calendar: calendar)
            let week = offset / 7
            let isRecoveryWeek = week % 4 == 0
            let plan: (minutes: Int, intensity: Double, indoor: Bool, name: String)?
            switch weekday {
            case 2: plan = (60, isRecoveryWeek ? 0.65 : 0.82, true, isRecoveryWeek ? "Lockere Runde" : "Sweet Spot 2×20")
            case 4: plan = (55, isRecoveryWeek ? 0.62 : 0.85, true, isRecoveryWeek ? "Grundlage" : "VO2max 5×3")
            case 6: plan = (75, 0.7, true, "MyWhoosh Grundlage")
            case 7: plan = Double.random(in: 0...1, using: &rng) < 0.4 ? (150, 0.72, false, "Sonntagsrunde") : (90, 0.7, true, "Lange Grundlage")
            default: plan = nil
            }
            guard let p = plan else { continue }
            if Double.random(in: 0...1, using: &rng) < 0.12 { continue } // occasionally skipped
            let minutes = p.minutes + Int.random(in: -8...8, using: &rng)
            let np = Double(ftp) * (p.intensity + Double.random(in: -0.03...0.03, using: &rng))
            let avg = np * (p.indoor ? 0.96 : 0.88)
            let start = calendar.date(bySettingHour: p.indoor ? 18 : 9, minute: 30, second: 0, of: day)!
            id += 1
            // Gentle fitness gain over the window: the same power costs up to 9 % less pulse by yesterday (EF trend).
            let progress = Double(days - offset) / Double(max(1, days - 1))
            let pulse = (1 - 0.09 * progress)
            var ride = RideSummary(id: id, name: p.name,
                                      sportType: p.indoor ? "VirtualRide" : "Ride", startDate: start,
                                      movingTime: minutes * 60,
                                      distance: Double(minutes) * (p.indoor ? 520 : 470),
                                      averageWatts: avg, weightedAverageWatts: np,
                                      kilojoules: avg * Double(minutes) * 60 / 1000,
                                      averageHeartrate: (118 + 50 * (p.intensity - 0.55)) * pulse, maxHeartrate: 150 + 40 * (p.intensity - 0.55),
                                      trainer: p.indoor)
            ride.powerCurve = syntheticCurve(rideID: id, durationSeconds: minutes * 60, averageWatts: avg,
                                             intensity: p.intensity, ftp: ftp)
            ride.maxWatts = ride.powerCurve?[1]
            ride.decoupling = syntheticDecoupling(rideID: id, minutes: minutes, intensity: p.intensity, progress: progress)
            result.append(ride)
        }
        return result
    }

    /// Demo "last winter" for the Vorjahres-Schatten (G6): lighter rides from `daysBefore` days before to `daysAfter`
    /// days after the day exactly one year before `end`, so the shadow lines up with the current season window
    /// (1 Nov – 21 Mar) from late summer to spring. A separate block with its own generator
    /// and ids (8_xxx_xxx), so `rides(days:)` – and every test built on it – stays untouched. `-uiSeed heavy`
    /// (730 days) already contains a previous year and does not add this block.
    public static func previousYearRides(endingAt end: Date = .now, daysBefore: Int = 140, daysAfter: Int = 125,
                                         ftp: Int = 250, calendar: Calendar = .current) -> [RideSummary] {
        var rng = SeededGenerator(seed: 2025)
        var result: [RideSummary] = []
        let today = calendar.startOfDay(for: end)
        guard let lastYear = calendar.date(byAdding: .year, value: -1, to: today) else { return [] }
        var id = 8_000_000
        for offset in (-daysAfter...daysBefore).reversed() {
            let day = calendar.date(byAdding: .day, value: -offset, to: lastYear)!
            let plan: (minutes: Int, intensity: Double, name: String)?
            switch AthleteProfile.isoWeekday(of: day, calendar: calendar) {
            case 2: plan = (50, offset / 7 % 4 == 0 ? 0.6 : 0.74, "Sweet Spot light")
            case 5: plan = (45, 0.66, "Grundlage")
            case 7: plan = (80, 0.68, "Lange Grundlage")
            default: plan = nil
            }
            guard let p = plan else { continue }
            if Double.random(in: 0...1, using: &rng) < 0.2 { continue }
            let minutes = p.minutes + Int.random(in: -6...6, using: &rng)
            let np = Double(ftp) * (p.intensity + Double.random(in: -0.03...0.03, using: &rng))
            let avg = np * 0.96
            id += 1
            var ride = RideSummary(id: id, name: p.name, sportType: "VirtualRide",
                                   startDate: calendar.date(bySettingHour: 18, minute: 30, second: 0, of: day)!,
                                   movingTime: minutes * 60, distance: Double(minutes) * 520,
                                   averageWatts: avg, weightedAverageWatts: np,
                                   kilojoules: avg * Double(minutes) * 60 / 1000,
                                   averageHeartrate: 118 + 50 * (p.intensity - 0.55), maxHeartrate: 150 + 40 * (p.intensity - 0.55),
                                   trainer: true)
            ride.powerCurve = syntheticCurve(rideID: id, durationSeconds: minutes * 60, averageWatts: avg,
                                             intensity: p.intensity, ftp: ftp)
            ride.maxWatts = ride.powerCurve?[1]
            result.append(ride)
        }
        return result
    }

    /// Plausible Pw:HR decoupling in percent: grows with intensity and duration, shrinks as the (demo) athlete gets fitter.
    /// Uses its own generator so the ride sequence above stays unchanged.
    static func syntheticDecoupling(rideID: Int, minutes: Int, intensity: Double, progress: Double) -> Double {
        var rng = SeededGenerator(seed: UInt64(truncatingIfNeeded: rideID) &* 7919)
        let jitter = Double.random(in: -1...1.5, using: &rng)
        let value = 1.0 + 12 * (intensity - 0.55) + Double(minutes) / 60 + jitter - 2 * progress
        return (value * 10).rounded() / 10
    }

    /// Deterministic 1 Hz power and heart rate that follow the demo ride's structure (warm-up, main set by name,
    /// cool-down), so time-in-zones and planned-vs-actual have something to show. Synthetic like the rides.
    public static func syntheticSeconds(for ride: RideSummary, ftp: Int) -> RideSeconds {
        var rng = SeededGenerator(seed: UInt64(truncatingIfNeeded: ride.id) &* 31)
        let total = max(600, ride.movingTime)
        let f = Double(ftp)
        let intensity = (ride.weightedAverageWatts ?? ride.averageWatts ?? f * 0.7) / f
        let warm = 600, cool = 480
        func target(_ t: Int) -> Double {
            if t < warm { return 0.5 + 0.2 * Double(t) / Double(warm) }
            if t >= total - cool { return 0.5 }
            let m = t - warm
            if ride.name.contains("2×20") {                  // 2 × 20 min Sweet Spot, 5 min easy between
                let block = m % (25 * 60)
                return m < 2 * 25 * 60 && block < 20 * 60 ? 0.9 : 0.55
            }
            if ride.name.contains("5×3") {                   // 5 × 3 min VO2max, 3 min easy between
                let block = m % 360
                return m < 5 * 360 && block < 180 ? 1.15 : 0.5
            }
            return intensity
        }
        var power: [Double] = []
        var heart: [Double] = []
        var hr = 95.0
        power.reserveCapacity(total)
        heart.reserveCapacity(total)
        for t in 0..<total {
            let p = max(0, f * target(t) * Double.random(in: 0.95...1.05, using: &rng))
            power.append(p)
            let goal = 100 + 75 * min(1.2, p / f)
            hr += (goal - hr) / 25                           // pulse follows power with a lag
            heart.append(hr)
        }
        return applyingWarmupCheck(RideSeconds(watts: power, beatsPerMinute: heart), for: ride, ftp: ftp)   // Demo+Warmup.swift
    }

    /// Plausible, deterministic mean-maximal curve for a demo ride (critical-power model with a sprint cap),
    /// scaled by how hard the ride was. Synthetic like the rides themselves.
    static func syntheticCurve(rideID: Int, durationSeconds: Int, averageWatts: Double, intensity: Double, ftp: Int) -> [Int: Double] {
        var rng = SeededGenerator(seed: UInt64(truncatingIfNeeded: rideID))
        let jitter = Double.random(in: 0.97...1.03, using: &rng)
        let effort = (0.8 + 0.2 * min(1, max(0, (intensity - 0.6) / 0.3))) * jitter
        let cp = Double(ftp) * 0.93
        var curve: [Int: Double] = [:]
        for d in PowerCurve.standardDurations where d <= durationSeconds {
            let t = Double(d)
            let model = cp + 15_000 / (t + 8)
            let sprint = Double(ftp) * 4 * (1 - 0.06 * log(t))
            curve[d] = max(min(model, sprint) * effort, averageWatts).rounded()
        }
        return curve
    }
}

/// Small deterministic RNG so demo data is stable between launches.
struct SeededGenerator: RandomNumberGenerator {
    private var state: UInt64
    init(seed: UInt64) { state = seed }
    mutating func next() -> UInt64 {
        state &+= 0x9E3779B97F4A7C15
        var z = state
        z = (z ^ (z >> 30)) &* 0xBF58476D1CE4E5B9
        z = (z ^ (z >> 27)) &* 0x94D049BB133111EB
        return z ^ (z >> 31)
    }
}
