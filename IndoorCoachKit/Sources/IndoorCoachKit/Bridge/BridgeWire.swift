import CryptoKit
import Foundation
import Network

// Wire format helpers for the bridge: message types, JSON payloads and the framer.

enum BridgeWireType {
    static let hello: UInt32 = 1
    static let welcome: UInt32 = 2
    static let pairingSecret: UInt32 = 3
    static let listRides: UInt32 = 4
    static let rides: UInt32 = 5
    static let fetchRide: UInt32 = 6
    static let rideData: UInt32 = 7
    static let failure: UInt32 = 8
    static let pairingRequest: UInt32 = 9
}

enum BridgeWire {
    struct Hello: Codable { var deviceName: String; var protocolVersion: Int }
    struct Welcome: Codable { var macName: String; var protocolVersion: Int }
    struct PairingSecret: Codable { var secret: Data; var macName: String }
    struct PairingRequest: Codable { var publicKey: Data }
    struct ListRides: Codable { var since: Date? }
    struct Rides: Codable { var rides: [BridgeRide] }
    struct FetchRide: Codable { var id: String }
    struct Failure: Codable { var message: String }

    static func makeEncoder() -> JSONEncoder {
        let e = JSONEncoder()
        e.dateEncodingStrategy = .secondsSince1970
        return e
    }

    static func makeDecoder() -> JSONDecoder {
        let d = JSONDecoder()
        d.dateDecodingStrategy = .secondsSince1970
        return d
    }

    /// rideData payload: UInt16 big-endian id length, id (UTF-8), raw FIT bytes.
    static func encodeRideData(id: String, fit: Data) throws -> Data {
        let idBytes = Data(id.utf8)
        guard idBytes.count <= Int(UInt16.max) else { throw BridgeError.malformedMessage }
        var out = Data(capacity: 2 + idBytes.count + fit.count)
        out.append(UInt8(idBytes.count >> 8))
        out.append(UInt8(idBytes.count & 0xFF))
        out.append(idBytes)
        out.append(fit)
        return out
    }

    static func decodeRideData(_ payload: Data) throws -> (String, Data) {
        let bytes = [UInt8](payload.prefix(2))
        guard bytes.count == 2 else { throw BridgeError.malformedMessage }
        let idLength = Int(bytes[0]) << 8 | Int(bytes[1])
        let idStart = payload.startIndex + 2
        guard payload.count >= 2 + idLength,
              let id = String(data: payload.subdata(in: idStart..<idStart + idLength), encoding: .utf8)
        else { throw BridgeError.malformedMessage }
        return (id, payload.subdata(in: idStart + idLength..<payload.endIndex))
    }
}

// MARK: - Framer

/// 8-byte header (type UInt32 BE, length UInt32 BE) followed by the payload.
final class BridgeFramer: NWProtocolFramerImplementation {
    static let label = "IndoorCoachBridge"
    static let metadataKey = "BridgeMessageType"
    static let definition = NWProtocolFramer.Definition(implementation: BridgeFramer.self)
    static let headerSize = 8

    required init(framer: NWProtocolFramer.Instance) {}
    func start(framer: NWProtocolFramer.Instance) -> NWProtocolFramer.StartResult { .ready }
    func wakeup(framer: NWProtocolFramer.Instance) {}
    func stop(framer: NWProtocolFramer.Instance) -> Bool { true }
    func cleanup(framer: NWProtocolFramer.Instance) {}

    static func header(type: UInt32, length: UInt32) -> Data {
        var data = Data(capacity: headerSize)
        for value in [type, length] {
            data.append(contentsOf: [UInt8(value >> 24 & 0xFF), UInt8(value >> 16 & 0xFF),
                                     UInt8(value >> 8 & 0xFF), UInt8(value & 0xFF)])
        }
        return data
    }

    func handleOutput(framer: NWProtocolFramer.Instance, message: NWProtocolFramer.Message, messageLength: Int,
                      isComplete: Bool) {
        let type = (message[Self.metadataKey] as? UInt32) ?? 0
        guard messageLength <= Bridge.maxMessageBytes else {
            framer.markFailed(error: .posix(.EMSGSIZE))
            return
        }
        framer.writeOutput(data: Self.header(type: type, length: UInt32(messageLength)))
        do { try framer.writeOutputNoCopy(length: messageLength) } catch {}
    }

    func handleInput(framer: NWProtocolFramer.Instance) -> Int {
        while true {
            var type: UInt32 = 0
            var length: UInt32 = 0
            let parsed = framer.parseInput(minimumIncompleteLength: Self.headerSize,
                                           maximumLength: Self.headerSize) { buffer, _ in
                guard let buffer, buffer.count >= Self.headerSize else { return 0 }
                let b = [UInt8](buffer.prefix(Self.headerSize))
                type = UInt32(b[0]) << 24 | UInt32(b[1]) << 16 | UInt32(b[2]) << 8 | UInt32(b[3])
                length = UInt32(b[4]) << 24 | UInt32(b[5]) << 16 | UInt32(b[6]) << 8 | UInt32(b[7])
                return Self.headerSize
            }
            guard parsed else { return Self.headerSize }
            guard Int(length) <= Bridge.maxMessageBytes else {
                framer.markFailed(error: .posix(.EMSGSIZE))
                return 0
            }
            let message = NWProtocolFramer.Message(definition: Self.definition)
            message[Self.metadataKey] = type
            if !framer.deliverInputNoCopy(length: Int(length), message: message, isComplete: true) { return 0 }
        }
    }
}
