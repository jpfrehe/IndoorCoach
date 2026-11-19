import Foundation
import Testing
@testable import IndoorCoachKit

/// Byte fixtures are built by hand from the Bluetooth SIG Heart Rate Service spec (characteristic 0x2A37).
@Suite("Herzfrequenz-Messung (GATT 0x2A37)")
struct HeartRateMeasurementTests {
    @Test("8-Bit-Puls ohne weitere Felder")
    func eightBit() throws {
        let m = try #require(HeartRateMeasurement.parse(Data([0x00, 72])))
        #expect(m.heartRate == 72)
        #expect(m.contact == .unsupported)
        #expect(m.energyExpendedKJ == nil)
        #expect(m.rrIntervalsMs.isEmpty)
    }

    @Test("16-Bit-Puls little endian")
    func sixteenBit() throws {
        let m = try #require(HeartRateMeasurement.parse(Data([0x01, 0x2C, 0x01])))
        #expect(m.heartRate == 300)
    }

    @Test("Sensorkontakt: nicht unterstützt, nicht erkannt, erkannt")
    func contact() throws {
        #expect(try #require(HeartRateMeasurement.parse(Data([0x00, 60]))).contact == .unsupported)
        #expect(try #require(HeartRateMeasurement.parse(Data([0x04, 60]))).contact == .notDetected)
        #expect(try #require(HeartRateMeasurement.parse(Data([0x06, 60]))).contact == .detected)
    }

    @Test("Energy Expended wird gelesen")
    func energy() throws {
        let m = try #require(HeartRateMeasurement.parse(Data([0x08, 70, 0x10, 0x00])))
        #expect(m.energyExpendedKJ == 16)
        #expect(m.heartRate == 70)
    }

    @Test("RR in 1/1024 s wird zu Millisekunden, mehrere pro Paket")
    func rr() throws {
        let m = try #require(HeartRateMeasurement.parse(Data([0x10, 60, 0x00, 0x04, 0x00, 0x03])))
        #expect(m.rrIntervalsMs.count == 2)
        #expect(abs(m.rrIntervalsMs[0] - 1000) < 0.001)
        #expect(abs(m.rrIntervalsMs[1] - 750) < 0.001)
    }

    @Test("Alle Felder: 16 Bit, Kontakt, Energie, RR")
    func everything() throws {
        let m = try #require(HeartRateMeasurement.parse(Data([0x1F, 0x90, 0x00, 0x05, 0x00, 0x00, 0x02])))
        #expect(m.heartRate == 144)
        #expect(m.contact == .detected)
        #expect(m.energyExpendedKJ == 5)
        #expect(m.rrIntervalsMs.count == 1)
        #expect(abs(m.rrIntervalsMs[0] - 500) < 0.001)
    }

    @Test("Abgeschnittene oder leere Pakete ergeben nil")
    func malformed() {
        #expect(HeartRateMeasurement.parse(Data()) == nil)
        #expect(HeartRateMeasurement.parse(Data([0x00])) == nil)
        #expect(HeartRateMeasurement.parse(Data([0x01, 0x10])) == nil)
        #expect(HeartRateMeasurement.parse(Data([0x08, 70, 0x10])) == nil)
        #expect(HeartRateMeasurement.parse(Data([0x10, 60, 0x00])) == nil)
    }

    @Test("Akkustand 0x2A19")
    func battery() {
        #expect(BatteryLevel.parse(Data([87])) == 87)
        #expect(BatteryLevel.parse(Data([100])) == 100)
        #expect(BatteryLevel.parse(Data([101])) == nil)
        #expect(BatteryLevel.parse(Data()) == nil)
    }
}
