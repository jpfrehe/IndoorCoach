import Foundation
import Testing
@testable import IndoorCoachKit

@Suite("Bridge codec and crypto")
struct BridgeCodecTests {
    static let ride = BridgeRide(id: "fit-1794000000", startDate: Date(timeIntervalSince1970: 1_794_000_000),
                                 durationSeconds: 3_600, byteCount: 1234,
                                 addedAt: Date(timeIntervalSince1970: 1_794_003_700.5))

    static let messages: [BridgeMessage] = [
        .hello(deviceName: "iPhone", protocolVersion: 1),
        .welcome(macName: "Mac", protocolVersion: 1),
        .pairingSecret(Data((0..<32).map { UInt8($0) }), macName: "Mac"),
        .listRides(since: nil),
        .listRides(since: Date(timeIntervalSince1970: 1_700_000_000)),
        .rides([ride, ride]),
        .rides([]),
        .fetchRide(id: "fit-1"),
        .rideData(id: "fit-1794000000", fit: Data((0..<255).map { UInt8($0) })),
        .rideData(id: "fit-2", fit: Data()),
        .failure("kaputt")
    ]

    @Test func roundtripsEveryCase() throws {
        for message in Self.messages {
            let payload = try BridgeCodec.encode(message)
            #expect(try BridgeCodec.decode(type: BridgeCodec.type(of: message), payload: payload) == message)
        }
    }

    @Test func wireTypesAreDistinct() {
        let types = Set(Self.messages.map { BridgeCodec.type(of: $0) })
        #expect(types.count == 8)
        #expect(!types.contains(0))
    }

    @Test func rideDataCarriesRawBytes() throws {
        let fit = Data(repeating: 0xAB, count: 1000)
        let payload = try BridgeCodec.encode(.rideData(id: "fit-1", fit: fit))
        #expect(payload.count == 2 + 5 + 1000)
    }

    @Test func malformedPayloadsThrow() {
        #expect(throws: BridgeError.malformedMessage) { try BridgeCodec.decode(type: BridgeWireType.hello, payload: Data("x".utf8)) }
        #expect(throws: BridgeError.malformedMessage) { try BridgeCodec.decode(type: BridgeWireType.rides, payload: Data()) }
        #expect(throws: BridgeError.malformedMessage) { try BridgeCodec.decode(type: BridgeWireType.rideData, payload: Data([0])) }
        #expect(throws: BridgeError.malformedMessage) { try BridgeCodec.decode(type: BridgeWireType.rideData, payload: Data([0, 9, 65])) }
        #expect(throws: BridgeError.malformedMessage) { try BridgeCodec.decode(type: 99, payload: Data("{}".utf8)) }
    }

    @Test func framerHeaderIsBigEndian() {
        #expect([UInt8](BridgeFramer.header(type: 7, length: 0x0102_0304)) == [0, 0, 0, 7, 1, 2, 3, 4])
    }

    @Test func pairingCodeHasSixDigits() {
        for _ in 0..<200 {
            let code = BridgeCrypto.generatePairingCode()
            #expect(code.count == 6 && code.allSatisfy(\.isASCII) && code.allSatisfy(\.isNumber))
        }
    }

    @Test func secretsAreRandom32Bytes() {
        let a = BridgeCrypto.newPairingSecret()
        #expect(a.count == 32)
        #expect(a != BridgeCrypto.newPairingSecret())
    }

    @Test func pairingKeyIsDeterministicPerCode() {
        #expect(BridgeCrypto.pairingKey(code: "012345") == BridgeCrypto.pairingKey(code: "012345"))
        #expect(BridgeCrypto.pairingKey(code: "012345").count == 32)
        #expect(BridgeCrypto.pairingKey(code: "012345") != BridgeCrypto.pairingKey(code: "012346"))
    }
}
