import Foundation

/// Ziele im Profil-Stack (NavigationStack(path:)); `connection(_)` ist die Detailseite eines Dienstes.
public enum ProfileRoute: Hashable, Sendable {
    case connections
    case connection(ConnectionID)
    case coach, winterArc, strength, reminders, help, storage
}
