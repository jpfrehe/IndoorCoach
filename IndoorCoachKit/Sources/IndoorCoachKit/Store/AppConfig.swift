import Foundation

/// Build-time constants for the pilot.
public enum AppConfig {
    /// Recipient of "Feedback senden". Deliberately empty: the address is set before the pilot starts.
    public static let feedbackEmail = ""

    /// `mailto:` link with subject and body, or nil when no address is configured.
    public static func feedbackMailURL(email: String = feedbackEmail, subject: String, body: String) -> URL? {
        let address = email.trimmingCharacters(in: .whitespaces)
        guard !address.isEmpty, address.contains("@") else { return nil }
        var components = URLComponents()
        components.scheme = "mailto"
        components.path = address
        components.queryItems = [URLQueryItem(name: "subject", value: subject), URLQueryItem(name: "body", value: body)]
        return components.url
    }

    /// Public issue tracker – the feedback route while no pilot address is configured.
    public static let issueTrackerURL = URL(string: "https://github.com/jpfrehe/IndoorCoach/issues/new")!

    /// New-issue link with title and body prefilled (no diagnostics, no personal data: the issue is public).
    public static func feedbackIssueURL(title: String, body: String) -> URL {
        var components = URLComponents(url: issueTrackerURL, resolvingAgainstBaseURL: false)!
        components.queryItems = [URLQueryItem(name: "title", value: title), URLQueryItem(name: "body", value: body)]
        return components.url ?? issueTrackerURL
    }

    /// "0.1 (1)" from the app bundle, "–" when unavailable (tests, previews).
    public static var versionString: String {
        let info = Bundle.main.infoDictionary
        let version = info?["CFBundleShortVersionString"] as? String ?? "–"
        let build = info?["CFBundleVersion"] as? String ?? "–"
        return "\(version) (\(build))"
    }

    /// e.g. "iOS 18.2.1".
    public static var osVersionString: String {
        let v = ProcessInfo.processInfo.operatingSystemVersion
        #if os(iOS)
        let name = "iOS"
        #else
        let name = "macOS"
        #endif
        return "\(name) \(v.majorVersion).\(v.minorVersion).\(v.patchVersion)"
    }

    /// Hardware model identifier, e.g. "iPhone17,3" (simulator: model + "(Simulator)").
    public static var deviceModel: String {
        if let simulated = ProcessInfo.processInfo.environment["SIMULATOR_MODEL_IDENTIFIER"] {
            return "\(simulated) (Simulator)"
        }
        var info = utsname()
        uname(&info)
        let machine = withUnsafeBytes(of: &info.machine) { raw in
            String(decoding: raw.prefix { $0 != 0 }, as: UTF8.self)
        }
        return machine.isEmpty ? "unbekannt" : machine
    }
}
