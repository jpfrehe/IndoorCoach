import XCTest
@testable import IndoorCoachBridge

final class BridgeStatusTests: XCTestCase {
    private let utc = TimeZone(identifier: "UTC")!

    func testStatusLinePairedWithFetch() {
        let fetch = Date(timeIntervalSince1970: 1_763_491_320) // 2025-11-18 18:42 UTC
        let line = BridgeFormat.statusLine(
            BridgeStatusInput(folder: .ready, pairedDeviceName: "iPhone", rideCount: 23, lastFetch: fetch, serverError: nil), timeZone: utc)
        XCTAssertEqual(line.text, "Gekoppelt mit iPhone · 23 Fahrten bereit · zuletzt abgeholt 18:42")
        XCTAssertEqual(line.level, .ok)
    }

    func testStatusLineUnpairedAndWarnings() {
        XCTAssertEqual(BridgeFormat.statusLine(.init(folder: .ready, pairedDeviceName: nil, rideCount: 1, lastFetch: nil, serverError: nil)).text,
                       "Noch kein iPhone gekoppelt · 1 Fahrt bereit")
        let reshare = BridgeFormat.statusLine(.init(folder: .needsReshare, pairedDeviceName: "iPhone", rideCount: 3, lastFetch: nil, serverError: nil))
        XCTAssertEqual(reshare, BridgeStatusLine(text: "Ordner neu freigeben", level: .warning))
    }

    func testRideLabelAndDuration() {
        let start = Date(timeIntervalSince1970: 1_763_491_320)
        XCTAssertEqual(BridgeFormat.rideLabel(start: start, durationSeconds: 52 * 60 + 10, timeZone: utc), "18.11. · 52 min")
        XCTAssertEqual(BridgeFormat.durationText(3900), "1 h 05 min")
    }

    func testCodeGroupingAndCountdown() {
        XCTAssertEqual(BridgeFormat.groupedCode("482913"), "482 913")
        XCTAssertEqual(BridgeFormat.countdown(272), "4:32")
        XCTAssertEqual(BridgeFormat.countdown(-5), "0:00")
    }

    func testRealHomeIsNotTheSandboxContainer() {
        let home = RealHome.url().path
        XCTAssertFalse(home.contains("/Library/Containers/"))
        XCTAssertTrue(home.hasPrefix("/"))
    }

    // MARK: Bookmarks

    private struct FakeResolver: FolderBookmarkResolving {
        var stale = false
        var failResolve = false
        var failRefresh = false
        func resolve(bookmark: Data) throws -> (url: URL, isStale: Bool) {
            if failResolve { throw CocoaError(.fileReadCorruptFile) }
            return (URL(fileURLWithPath: "/tmp/x"), stale)
        }
        func makeBookmark(for url: URL) throws -> Data {
            if failRefresh { throw CocoaError(.fileReadNoPermission) }
            return Data([9])
        }
    }

    func testBookmarkResolution() {
        XCTAssertEqual(FolderBookmark.resolve(bookmark: nil, using: FakeResolver()), .none)
        XCTAssertEqual(FolderBookmark.resolve(bookmark: Data([1]), using: FakeResolver()),
                       .accessible(URL(fileURLWithPath: "/tmp/x"), refreshedBookmark: nil))
        XCTAssertEqual(FolderBookmark.resolve(bookmark: Data([1]), using: FakeResolver(stale: true)),
                       .accessible(URL(fileURLWithPath: "/tmp/x"), refreshedBookmark: Data([9])))
        XCTAssertEqual(FolderBookmark.resolve(bookmark: Data([1]), using: FakeResolver(stale: true, failRefresh: true)), .needsReshare)
        XCTAssertEqual(FolderBookmark.resolve(bookmark: Data([1]), using: FakeResolver(failResolve: true)), .needsReshare)
    }

    func testLaunchOptions() {
        let suite = UserDefaults(suiteName: "bridge-test-\(UUID().uuidString)")!
        suite.set("/tmp/rides", forKey: "bridgeFolder")
        suite.set("123456", forKey: "bridgePairingCode")
        suite.set(true, forKey: "bridgeSkipSetup")
        let options = BridgeLaunchOptions.parse(suite)
        XCTAssertEqual(options.folder?.path, "/tmp/rides")
        XCTAssertEqual(options.pairingCode, "123456")
        XCTAssertTrue(options.skipSetup)
        suite.set("12ab56", forKey: "bridgePairingCode")
        XCTAssertNil(BridgeLaunchOptions.parse(suite).pairingCode)
    }
}
