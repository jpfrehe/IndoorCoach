import Foundation

/// Contract between the recording (RecordingService) and its lock-screen presentation (Live Activity).
/// Owned by the integration; the recording package only calls `RecordingLivePresenting`, the Live-Activity package
/// implements it. Kept free of ActivityKit so the Kit builds and tests on macOS.
public enum RecordingKind: String, Codable, Hashable, Sendable, CaseIterable {
    case ride       // Rollenfahrt mit Plan (Gurt am iPhone, ohne Mac-Brücke)
    case strength   // Krafteinheit im Studio
    case other      // andere Indoor-Einheit (Laufband, Kurs, Rudergerät …)
}

/// What the lock screen / Dynamic Island shows. Small and Codable: it travels as ActivityKit content state.
public struct RecordingLiveState: Codable, Hashable, Sendable {
    public var kind: RecordingKind
    public var title: String
    public var startedAt: Date
    public var heartRate: Int?
    public var connected: Bool
    /// Current plan block or exercise, e.g. "Sweet Spot 2/3" or "Kniebeuge".
    public var blockTitle: String?
    public var blockEndsAt: Date?

    public init(kind: RecordingKind, title: String, startedAt: Date, heartRate: Int? = nil, connected: Bool = true,
                blockTitle: String? = nil, blockEndsAt: Date? = nil) {
        self.kind = kind
        self.title = title
        self.startedAt = startedAt
        self.heartRate = heartRate
        self.connected = connected
        self.blockTitle = blockTitle
        self.blockEndsAt = blockEndsAt
    }
}

/// Presents a running recording outside the app. Implementations must tolerate calls in any order
/// (update before start, end twice) and must never throw into the recording.
@MainActor
public protocol RecordingLivePresenting: AnyObject {
    func start(_ state: RecordingLiveState)
    func update(_ state: RecordingLiveState)
    func end(_ state: RecordingLiveState?)
}

/// Default when no Live Activity is available (macOS, tests, iOS without permission).
@MainActor
public final class NoopRecordingLivePresenter: RecordingLivePresenting {
    public private(set) var lastState: RecordingLiveState?
    public private(set) var isActive = false
    public init() {}
    public func start(_ state: RecordingLiveState) { lastState = state; isActive = true }
    public func update(_ state: RecordingLiveState) { lastState = state }
    public func end(_ state: RecordingLiveState?) { if let state { lastState = state }; isActive = false }
}

/// Registry the app fills at launch (`LiveActivityPresenter` on iOS); everything else uses the no-op.
@MainActor
public enum RecordingLive {
    public static var presenter: RecordingLivePresenting = NoopRecordingLivePresenter()
}
