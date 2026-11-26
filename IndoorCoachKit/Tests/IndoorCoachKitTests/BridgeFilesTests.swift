import Foundation
import Testing
@testable import IndoorCoachKit

private func tempDir() throws -> URL {
    let url = FileManager.default.temporaryDirectory.appending(path: "bridge-\(UUID().uuidString)", directoryHint: .isDirectory)
    try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
    return url
}

@Suite("Bridge folder scanner")
struct RideFolderScannerTests {
    let t0 = Date(timeIntervalSince1970: 1_800_000_000)
    func file(_ name: String = "a.fit", size: Int = 100, modified: Date) -> RideFolderScanner.FileInfo {
        .init(url: URL(fileURLWithPath: "/x/\(name)"), size: size, modified: modified)
    }

    @Test func needsTwoStableScansAndMinimumAge() {
        var scanner = RideFolderScanner(minimumAge: 15)
        let f = file(modified: t0)
        #expect(scanner.ready([f], now: t0.addingTimeInterval(60)).isEmpty) // first sighting
        #expect(scanner.ready([f], now: t0.addingTimeInterval(80)) == [f])  // stable and old enough
        #expect(scanner.ready([f], now: t0.addingTimeInterval(100)).isEmpty) // reported once
    }

    @Test func tooYoungFilesWait() {
        var scanner = RideFolderScanner(minimumAge: 15)
        let f = file(modified: t0)
        _ = scanner.ready([f], now: t0.addingTimeInterval(2))
        #expect(scanner.ready([f], now: t0.addingTimeInterval(10)).isEmpty)
        #expect(scanner.ready([f], now: t0.addingTimeInterval(20)) == [f])
    }

    @Test func growingFileWaitsUntilItIsStable() {
        var scanner = RideFolderScanner(minimumAge: 0)
        _ = scanner.ready([file(size: 10, modified: t0)], now: t0.addingTimeInterval(30))
        #expect(scanner.ready([file(size: 20, modified: t0.addingTimeInterval(1))], now: t0.addingTimeInterval(60)).isEmpty)
        #expect(scanner.ready([file(size: 20, modified: t0.addingTimeInterval(1))], now: t0.addingTimeInterval(90)).count == 1)
    }

    @Test func quickLookOnRequestAcceptsYoungStableFiles() {
        var scanner = RideFolderScanner(minimumAge: 15)
        let f = file(modified: t0)
        #expect(scanner.hasUnreported([f]))
        _ = scanner.ready([f], now: t0.addingTimeInterval(3), minimumAge: 3)
        #expect(scanner.ready([f], now: t0.addingTimeInterval(4.5), minimumAge: 3) == [f])
        #expect(!scanner.hasUnreported([f]))
    }

    @Test func changedFileIsReportedAgain() {
        var scanner = RideFolderScanner(minimumAge: 0)
        let v1 = file(size: 10, modified: t0)
        _ = scanner.ready([v1], now: t0.addingTimeInterval(30))
        #expect(scanner.ready([v1], now: t0.addingTimeInterval(60)) == [v1])
        let v2 = file(size: 30, modified: t0.addingTimeInterval(100))
        #expect(scanner.ready([v2], now: t0.addingTimeInterval(130)).isEmpty)
        #expect(scanner.ready([v2], now: t0.addingTimeInterval(160)) == [v2])
    }

    @Test func listsOnlyVisibleFitFilesNonRecursively() throws {
        let dir = try tempDir()
        defer { try? FileManager.default.removeItem(at: dir) }
        try Data([1, 2, 3]).write(to: dir.appending(path: "a.fit"))
        try Data([1]).write(to: dir.appending(path: "B.FIT"))
        try Data([1]).write(to: dir.appending(path: "c.txt"))
        try Data([1]).write(to: dir.appending(path: ".hidden.fit"))
        let sub = dir.appending(path: "sub", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: sub, withIntermediateDirectories: true)
        try Data([1]).write(to: sub.appending(path: "d.fit"))
        let files = RideFolderScanner.listFITFiles(in: dir)
        #expect(files.map(\.url.lastPathComponent) == ["B.FIT", "a.fit"])
        #expect(files.last?.size == 3)
        #expect(RideFolderScanner.listFITFiles(in: dir.appending(path: "missing")).isEmpty)
    }
}

@Suite("Bridge outbox")
struct BridgeOutboxTests {
    @Test func storesRidesAndDedupesByStart() async throws {
        let dir = try tempDir()
        defer { try? FileManager.default.removeItem(at: dir) }
        let outbox = BridgeOutbox(directory: dir)
        let fit = sessionFIT()
        let added = Date(timeIntervalSince1970: 1_800_000_000)
        let ride = try #require(try outbox.add(fit: fit, addedAt: added))
        #expect(ride.id == BridgeRide.id(forStart: rideStart))
        #expect(ride.durationSeconds == (try FITParser.summary(from: fit)).movingTime)
        #expect(ride.byteCount == fit.count)
        let again = try outbox.add(fit: fit, addedAt: added.addingTimeInterval(500))
        #expect(again == ride)
        #expect(outbox.count == 1)
        #expect(await outbox.fitData(id: ride.id) == fit)
        #expect(await outbox.fitData(id: "../index") == nil)
        #expect(await outbox.fitData(id: "fit-1") == nil)
    }

    @Test func unreadableFilesAreNotStored() throws {
        let dir = try tempDir()
        defer { try? FileManager.default.removeItem(at: dir) }
        let outbox = BridgeOutbox(directory: dir)
        #expect(try outbox.add(fit: Data("no fit".utf8)) == nil)
        #expect(outbox.count == 0 && outbox.latest == nil)
    }

    @Test func ridesSinceFiltersByAddedAtAndSortsByStart() async throws {
        let dir = try tempDir()
        defer { try? FileManager.default.removeItem(at: dir) }
        let outbox = BridgeOutbox(directory: dir)
        let t = Date(timeIntervalSince1970: 1_800_000_000)
        try outbox.add(fit: sessionFIT(start: rideStart.addingTimeInterval(86_400)), addedAt: t)
        try outbox.add(fit: sessionFIT(start: rideStart), addedAt: t.addingTimeInterval(100))
        let all = await outbox.rides(since: nil)
        #expect(all.map(\.startDate) == [rideStart, rideStart.addingTimeInterval(86_400)])
        #expect(await outbox.rides(since: t).map(\.startDate) == [rideStart])
        #expect(await outbox.rides(since: t.addingTimeInterval(100)).isEmpty)
        #expect(outbox.latest?.startDate == rideStart.addingTimeInterval(86_400))
    }

    @Test func reloadsIndexAndPrunes() async throws {
        let dir = try tempDir()
        defer { try? FileManager.default.removeItem(at: dir) }
        let first = BridgeOutbox(directory: dir)
        try first.add(fit: sessionFIT(start: rideStart))
        try first.add(fit: sessionFIT(start: rideStart.addingTimeInterval(200 * 86_400)))
        let second = BridgeOutbox(directory: dir)
        #expect(second.count == 2)
        second.prune(keepDays: 180, now: rideStart.addingTimeInterval(201 * 86_400))
        #expect(second.count == 1)
        #expect(await second.fitData(id: BridgeRide.id(forStart: rideStart)) == nil)
        #expect(BridgeOutbox(directory: dir).count == 1)
    }
}
