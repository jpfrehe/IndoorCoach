import Foundation

/// „Dein Herz im Winter Arc“ (docs/17 §9.8, B57): was sich seit dem Arc-Start am Herzen zeigt, je Monat.
/// Vier Kennzahlen, jede nur mit genug Daten und mit Quelle: Aufwärm-Puls bei gleicher Referenz, Ruhepuls-Basis (Health),
/// aerobe Effizienz, Krafteinheiten. Rein rechnerisch, nichts wird erfunden: ohne Daten fehlt die Kennzahl.
public struct HeartInWinterArc: Equatable, Sendable {
    /// Mindestzahl gültiger Aufwärm-Checks (gleiche Referenz) und Ausdauerfahrten je Monat.
    public static let minSamplesPerMonth = 2
    /// Mindestzahl Ruhepuls-Tageswerte je Monat.
    public static let minRestingDaysPerMonth = 10
    /// Ab so viel Rückgang des Ruhepulses (bpm) gilt das Herz als ruhiger.
    public static let calmerThreshold = 2.0

    public struct MonthValue: Equatable, Sendable, Identifiable {
        public var monthStart: Date
        /// Median (Puls, Ruhepuls, Effizienz) bzw. Anzahl (Kraft).
        public var value: Double
        public var samples: Int
        public var id: Date { monthStart }
    }

    public struct Series: Equatable, Sendable {
        public var months: [MonthValue]
        /// „gemessen“, „angenommen (ERG)“, „Apple Health · Apple Watch“ …
        public var sourceText: String
        public var first: MonthValue? { months.first }
        public var last: MonthValue? { months.last }
        /// Letzter minus erster Monat; 0 ohne Monate.
        public var change: Double { (last?.value ?? 0) - (first?.value ?? 0) }
    }

    public var warmupRefWatts: Int
    public var warmup: Series?
    public var resting: Series?
    public var efficiency: Series?
    /// Krafteinheiten je Monat (nur Monate mit mindestens einer Einheit).
    public var strength: [MonthValue]
    public var strengthTotal: Int

    public var isEmpty: Bool { warmup == nil && resting == nil && efficiency == nil && strengthTotal == 0 }

    public static let efficiencySource = "Aufzeichnungen (Leistung ÷ Puls)"
    public static let strengthSource = "deine Krafteinheiten"

    // MARK: Berechnung

    public static func make(from start: Date, now: Date, refWatts: Int, checks: [WarmupCheck], restingDailies: [HealthDaily],
                            rides: [RideSummary], ftp: Int, strengthStarts: [Date], calendar: Calendar = .current) -> HeartInWinterArc {
        func inWindow(_ date: Date) -> Bool { date >= start && date <= now }
        func month(_ date: Date) -> Date { calendar.dateInterval(of: .month, for: date)?.start ?? calendar.startOfDay(for: date) }
        func series(_ buckets: [Date: [Double]], minSamples: Int, source: String) -> Series? {
            let months = buckets.filter { $0.value.count >= minSamples }
                .compactMap { key, values in Wellness.median(values).map { MonthValue(monthStart: key, value: $0, samples: values.count) } }
                .sorted { $0.monthStart < $1.monthStart }
            return months.count >= 2 ? Series(months: months, sourceText: source) : nil
        }

        // Aufwärm-Puls: nur gültige Checks bei der gleichen Referenz.
        let usedChecks = checks.filter { $0.valid && $0.hrMean != nil && $0.refWatts == refWatts && inWindow($0.date) }
        var warmupBuckets: [Date: [Double]] = [:]
        for c in usedChecks { warmupBuckets[month(c.date), default: []].append(c.hrMean ?? 0) }
        let warmup = series(warmupBuckets, minSamples: minSamplesPerMonth, source: "")
            .map { Series(months: $0.months, sourceText: usedChecks.allSatisfy { $0.source == .measured } ? "gemessen" : "angenommen (ERG)") }

        // Ruhepuls: Median der Tageswerte je Monat.
        let restingRows = restingDailies.filter { $0.metric == .restingHR && $0.value > 0 && inWindow($0.date) }
        var restingBuckets: [Date: [Double]] = [:]
        for d in restingRows { restingBuckets[month(d.date), default: []].append(d.value) }
        let newest = restingRows.max { $0.date < $1.date }
        let restingSource = newest.map { "Apple Health · \($0.source.name)" } ?? ""
        let resting = series(restingBuckets, minSamples: minRestingDaysPerMonth, source: restingSource)

        // Aerobe Effizienz: Median je Monat über vergleichbare Ausdauerfahrten.
        var efBuckets: [Date: [Double]] = [:]
        for r in rides where inWindow(r.startDate) {
            if let ef = AerobicEfficiency.factor(for: r, ftp: ftp) { efBuckets[month(r.startDate), default: []].append(ef) }
        }
        let efficiency = series(efBuckets, minSamples: minSamplesPerMonth, source: efficiencySource)

        // Kraft: Einheiten je Monat.
        var strengthBuckets: [Date: Int] = [:]
        for s in strengthStarts where inWindow(s) { strengthBuckets[month(s), default: 0] += 1 }
        let strength = strengthBuckets.map { MonthValue(monthStart: $0.key, value: Double($0.value), samples: $0.value) }
            .sorted { $0.monthStart < $1.monthStart }

        return HeartInWinterArc(warmupRefWatts: refWatts, warmup: warmup, resting: resting, efficiency: efficiency,
                                strength: strength, strengthTotal: strength.reduce(0) { $0 + $1.samples })
    }

    // MARK: Aussagen

    /// Weniger Puls bei gleicher Leistung: Aufwärm-Puls fällt oder aerobe Effizienz steigt (je mindestens Schwelle).
    var lessPulse: Bool {
        if let warmup, warmup.change <= -WarmupCheck.trendThreshold { return true }
        if let efficiency, let first = efficiency.first, first.value > 0,
           efficiency.change / first.value * 100 >= AerobicEfficiency.stableBand { return true }
        return false
    }

    var calmerHeart: Bool {
        if let resting, resting.change <= -Self.calmerThreshold { return true }
        return false
    }

    /// Der Satz der Karte, nur wenn die Daten es hergeben.
    public var sentence: String? {
        switch (lessPulse, calmerHeart) {
        case (true, true): "Gleiche Watt, weniger Puls, ruhigeres Herz."
        case (true, false): "Gleiche Watt, weniger Puls."
        case (false, true): "Ruhigeres Herz in Ruhe."
        case (false, false): nil
        }
    }

    /// Je verfügbarer Kennzahl eine Zeile für den Saisonrückblick; leer, wenn nichts da ist.
    public var seasonLines: [String] {
        var lines: [String] = []
        func arrow(_ s: Series, digits: Int = 0) -> String {
            "\(Formatters.decimal(s.first?.value ?? 0, digits: digits)) → \(Formatters.decimal(s.last?.value ?? 0, digits: digits))"
        }
        if let warmup { lines.append("Puls bei \(warmupRefWatts) W: \(arrow(warmup))") }
        if let resting { lines.append("Ruhepuls \(arrow(resting))") }
        if let efficiency { lines.append("Aerobe Effizienz \(arrow(efficiency, digits: 2))") }
        if strengthTotal > 0 { lines.append("Kraft-Winter: \(strengthTotal) \(strengthTotal == 1 ? "Einheit" : "Einheiten")") }
        return lines
    }
}
