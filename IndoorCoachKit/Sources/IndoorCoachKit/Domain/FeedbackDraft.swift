import Foundation

/// Kind of feedback. Decides the GitHub issue-form template, the title prefix and the prefilled field ids.
/// The ids must match `.github/ISSUE_TEMPLATE/*.yml` (checked by a unit test).
public enum FeedbackKind: String, CaseIterable, Identifiable, Sendable {
    case bug, wish, praise

    public var id: String { rawValue }

    public var title: String {
        switch self {
        case .bug: "Fehler"
        case .wish: "Wunsch"
        case .praise: "Lob & Frage"
        }
    }

    public var symbol: String {
        switch self {
        case .bug: "ladybug"
        case .wish: "lightbulb"
        case .praise: "heart"
        }
    }

    public var templateFile: String {
        switch self {
        case .bug: "bug_report.yml"
        case .wish: "feature_request.yml"
        case .praise: "feedback.yml"
        }
    }

    public var titlePrefix: String {
        switch self {
        case .bug: "[Fehler] "
        case .wish: "[Wunsch] "
        case .praise: "[Feedback] "
        }
    }

    /// Id of the main text field in the issue form.
    public var bodyFieldID: String {
        switch self {
        case .bug: "beschreibung"
        case .wish: "wunsch"
        case .praise: "feedback"
        }
    }

    public var appInfoFieldID: String { "app-info" }

    /// Guiding prompt shown in the empty description field.
    public var prompt: String {
        switch self {
        case .bug: "Was ist passiert? Was hast du erwartet? Auf welchem Bildschirm warst du?"
        case .wish: "Was wünschst du dir? Wofür würdest du es brauchen?"
        case .praise: "Was gefällt dir, oder was möchtest du fragen?"
        }
    }
}

/// A feedback draft that becomes a prefilled GitHub issue-form URL (no token needed; the user taps "Create" on GitHub).
public struct FeedbackDraft: Equatable, Sendable {
    public struct AppInfo: Equatable, Sendable {
        public var version: String
        public var os: String
        public var device: String

        public init(version: String, os: String, device: String) {
            self.version = version; self.os = os; self.device = device
        }

        public static var current: AppInfo {
            AppInfo(version: AppConfig.versionString, os: AppConfig.osVersionString, device: AppConfig.deviceModel)
        }

        /// Exactly the text that is attached (and shown to the user).
        public var text: String { "App \(version) · \(os) · \(device)" }
    }

    public static let maxURLLength = 8000
    public static let minTitleLength = 5
    public static let minBodyLength = 10
    public static let truncationMarker = "…(gekürzt)"

    public static let existingWishesURL = URL(string: "https://github.com/jpfrehe/IndoorCoach/issues?q=is%3Aissue+label%3Aenhancement")!

    public var kind: FeedbackKind
    public var title: String
    public var body: String

    public init(kind: FeedbackKind, title: String, body: String) {
        self.kind = kind; self.title = title; self.body = body
    }

    private var trimmedTitle: String { title.trimmingCharacters(in: .whitespacesAndNewlines) }
    private var trimmedBody: String { body.trimmingCharacters(in: .whitespacesAndNewlines) }

    public var isValid: Bool {
        trimmedTitle.count >= Self.minTitleLength && trimmedBody.count >= Self.minBodyLength
    }

    /// Title as sent: prefix plus redacted text.
    var issueTitle: String { kind.titlePrefix + Redactor.scrub(trimmedTitle) }

    /// Plain text for "Text kopieren" / e-mail (redacted, never truncated).
    public func plainText(appInfo: AppInfo, includeAppInfo: Bool) -> String {
        var text = "\(issueTitle)\n\n\(Redactor.scrub(trimmedBody))"
        if includeAppInfo { text += "\n\n—\n\(appInfo.text)" }
        return text
    }

    /// `https://github.com/<repo>/issues/new?template=…&title=…&<field-id>=…`, always shorter than `maxURLLength`.
    public func issueURL(appInfo: AppInfo, includeAppInfo: Bool) -> URL {
        let full = Redactor.scrub(trimmedBody)
        func make(_ body: String) -> String {
            var pairs = [("template", kind.templateFile), ("title", issueTitle), (kind.bodyFieldID, body)]
            if includeAppInfo { pairs.append((kind.appInfoFieldID, appInfo.text)) }
            let query = pairs.map { "\($0.0)=\(Self.encode($0.1))" }.joined(separator: "&")
            return AppConfig.repoURL.absoluteString + "/issues/new?" + query
        }
        var result = make(full)
        if result.count >= Self.maxURLLength {
            // Longest prefix that still fits together with the marker (binary search; encoded length is monotonic).
            let chars = Array(full)
            var low = 0, high = chars.count
            while low < high {
                let mid = (low + high + 1) / 2
                if make(String(chars[..<mid]) + Self.truncationMarker).count < Self.maxURLLength { low = mid } else { high = mid - 1 }
            }
            result = make(String(chars[..<low]) + Self.truncationMarker)
        }
        return URL(string: result) ?? AppConfig.repoURL
    }

    private static let allowed = CharacterSet(charactersIn: "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789-._~")

    private static func encode(_ value: String) -> String {
        value.addingPercentEncoding(withAllowedCharacters: allowed) ?? ""
    }
}
