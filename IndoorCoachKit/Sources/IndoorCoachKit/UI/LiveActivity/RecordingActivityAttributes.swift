#if canImport(ActivityKit) && os(iOS)
import ActivityKit
import Foundation

/// Gemeinsam von App (Start/Update) und Widget-Extension (Darstellung) genutzt.
public struct RecordingActivityAttributes: ActivityAttributes {
    public typealias ContentState = RecordingLiveState

    public let kind: RecordingKind
    public let title: String

    public init(kind: RecordingKind, title: String) {
        self.kind = kind
        self.title = title
    }
}
#endif
