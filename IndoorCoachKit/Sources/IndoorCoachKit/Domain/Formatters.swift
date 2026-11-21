import Foundation

extension Locale {
    /// Die App spricht Deutsch: alle Datums- und Zahlenformate nutzen dieses Locale.
    public static let de = Locale(identifier: "de_DE")
}

public enum Formatters {
    /// "A", "A und B", "A, B und C" (deutsche Aufzählung ohne Komma vor „und“); leer bleibt leer.
    public static func germanList(_ items: [String], conjunction: String = "und") -> String {
        switch items.count {
        case 0: ""
        case 1: items[0]
        default: items.dropLast().joined(separator: ", ") + " \(conjunction) " + items[items.count - 1]
        }
    }

    /// "1:05 h", "45 min", "30 s".
    public static func duration(_ seconds: Int) -> String {
        if seconds == 0 { return "0 min" }
        if seconds < 60 { return "\(seconds) s" }
        let minutes = seconds / 60
        let rest = seconds % 60
        if minutes < 60 {
            return rest == 0 ? "\(minutes) min" : "\(minutes):\(String(format: "%02d", rest)) min"
        }
        return "\(minutes / 60):\(String(format: "%02d", minutes % 60)) h"
    }

    public static func distanceKm(_ meters: Double) -> String {
        String(format: "%.1f km", meters / 1000).replacingOccurrences(of: ".", with: ",")
    }

    /// "1,25" – deutsches Komma, ohne Tausenderpunkte. FormatStyle statt eines NumberFormatters je Aufruf
    /// (wird in Listen und Diagrammen oft aufgerufen).
    public static func decimal(_ value: Double, digits: Int = 0) -> String {
        value.formatted(.number.locale(.de).grouping(.never).precision(.fractionLength(digits)))
    }

    /// ISO calendar day "yyyy-MM-dd" in the current time zone – the format exchanged with Claude.
    public static let isoDay: DateFormatter = {
        let f = DateFormatter()
        f.calendar = Calendar(identifier: .gregorian)
        f.locale = Locale(identifier: "en_US_POSIX")
        f.timeZone = .current
        f.dateFormat = "yyyy-MM-dd"
        return f
    }()
}
