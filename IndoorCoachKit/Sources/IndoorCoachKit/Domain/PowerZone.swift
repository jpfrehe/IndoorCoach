import Foundation

/// Coggan power zones (fractions of FTP).
public enum PowerZone: Int, CaseIterable, Comparable, Sendable, Identifiable {
    case z1 = 1, z2, z3, z4, z5, z6, z7

    public init(fractionOfFTP p: Double) {
        switch p {
        case ..<0.56: self = .z1
        case ..<0.76: self = .z2
        case ..<0.91: self = .z3
        case ..<1.06: self = .z4
        case ..<1.21: self = .z5
        case ..<1.51: self = .z6
        default: self = .z7
        }
    }

    public var id: Int { rawValue }

    public static func < (lhs: PowerZone, rhs: PowerZone) -> Bool { lhs.rawValue < rhs.rawValue }

    public var shortName: String { "Z\(rawValue)" }

    public var name: String {
        switch self {
        case .z1: "Aktive Erholung"
        case .z2: "Grundlage"
        case .z3: "Tempo"
        case .z4: "Schwelle"
        case .z5: "VO₂max"
        case .z6: "Anaerob"
        case .z7: "Neuromuskulär"
        }
    }

    /// Lower bound in fraction of FTP.
    public var lowerBound: Double {
        switch self {
        case .z1: 0
        case .z2: 0.56
        case .z3: 0.76
        case .z4: 0.91
        case .z5: 1.06
        case .z6: 1.21
        case .z7: 1.51
        }
    }
}
