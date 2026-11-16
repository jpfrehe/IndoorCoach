import Foundation

public enum Formatters {
    /// "1:05 h", "45 min", "30 s".
    public static func duration(_ seconds: Int) -> String {
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

    public static func decimal(_ value: Double, digits: Int = 0) -> String {
        let f = NumberFormatter()
        f.locale = Locale(identifier: "de_DE")
        f.minimumFractionDigits = digits
        f.maximumFractionDigits = digits
        return f.string(from: NSNumber(value: value)) ?? "\(value)"
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
