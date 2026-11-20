import Foundation

/// Exports a workout to the Zwift `.zwo` XML format, which the MyWhoosh Workout Builder imports.
public enum ZWOExporter {
    public static func xml(for workout: WorkoutDefinition, author: String = "IndoorCoach") -> String {
        var out = """
        <?xml version="1.0" encoding="UTF-8"?>
        <workout_file>
            <author>\(escape(author))</author>
            <name>\(escape(workout.title))</name>
            <description>\(escape(workout.summary))</description>
            <sportType>bike</sportType>
            <tags>
                <tag name="\(escape(workout.type.label))"/>
            </tags>
            <workout>

        """
        for s in workout.segments {
            out += "        " + element(for: s) + "\n"
        }
        out += """
            </workout>
        </workout_file>

        """
        return out
    }

    /// File name safe for AirDrop / Finder, e.g. "2026-11-18_Sweet_Spot_3x12.zwo".
    public static func fileName(for workout: WorkoutDefinition, date: Date) -> String {
        let day = Formatters.isoDay.string(from: date)
        let allowed = CharacterSet.alphanumerics.union(CharacterSet(charactersIn: "-"))
        let slug = workout.title
            .folding(options: [.diacriticInsensitive], locale: Locale.de)
            .components(separatedBy: allowed.inverted)
            .filter { !$0.isEmpty }
            .joined(separator: "_")
        return "\(day)_\(slug.isEmpty ? "Workout" : slug).zwo"
    }

    static func element(for s: Segment) -> String {
        let cad = s.cadence.map { " Cadence=\"\($0)\"" } ?? ""
        let body: String
        let tag: String
        switch s.kind {
        case .warmup:
            tag = "Warmup"
            body = "Duration=\"\(s.duration)\" PowerLow=\"\(f(s.powerLow ?? 0.45))\" PowerHigh=\"\(f(s.powerHigh ?? 0.75))\""
        case .ramp:
            tag = "Ramp"
            body = "Duration=\"\(s.duration)\" PowerLow=\"\(f(s.powerLow ?? 0.5))\" PowerHigh=\"\(f(s.powerHigh ?? 0.8))\""
        case .cooldown:
            // In .zwo, Cooldown runs from PowerLow (start) to PowerHigh (end); we store high→low semantically.
            tag = "Cooldown"
            body = "Duration=\"\(s.duration)\" PowerLow=\"\(f(s.powerHigh ?? 0.65))\" PowerHigh=\"\(f(s.powerLow ?? 0.4))\""
        case .steady:
            tag = "SteadyState"
            body = "Duration=\"\(s.duration)\" Power=\"\(f(s.power ?? 0.6))\""
        case .intervals:
            tag = "IntervalsT"
            body = "Repeat=\"\(s.repeatCount ?? 1)\" OnDuration=\"\(s.onDuration ?? 60)\" OffDuration=\"\(s.offDuration ?? 60)\" OnPower=\"\(f(s.onPower ?? 1.0))\" OffPower=\"\(f(s.offPower ?? 0.5))\""
        case .freeRide:
            tag = "FreeRide"
            body = "Duration=\"\(s.duration)\" FlatRoad=\"1\""
        }
        if let text = s.text, !text.isEmpty {
            return "<\(tag) \(body)\(cad)><textevent timeoffset=\"0\" message=\"\(escape(text))\"/></\(tag)>"
        }
        return "<\(tag) \(body)\(cad)/>"
    }

    static func f(_ value: Double) -> String {
        String(format: "%.2f", locale: Locale(identifier: "en_US_POSIX"), value)
    }

    static func escape(_ s: String) -> String {
        s.replacingOccurrences(of: "&", with: "&amp;")
            .replacingOccurrences(of: "<", with: "&lt;")
            .replacingOccurrences(of: ">", with: "&gt;")
            .replacingOccurrences(of: "\"", with: "&quot;")
            .replacingOccurrences(of: "'", with: "&apos;")
    }
}
