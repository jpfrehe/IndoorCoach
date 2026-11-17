import Foundation
import SQLite3
import SwiftData
import Testing
@testable import IndoorCoachKit

/// StoredRide as shipped before the Winter Arc features (no perceivedExertion, preferPerceivedExertion,
/// stravaRelativeEffort). Same entity name, so it maps to the same table as the current model.
enum LegacySchemaV1: VersionedSchema {
    static let versionIdentifier = Schema.Version(1, 0, 0)
    static var models: [any PersistentModel.Type] { [StoredRide.self, IndoorCoachKit.StoredWorkout.self] }

    @Model
    final class StoredRide {
        @Attribute(.unique) var stravaID: Int
        var name: String
        var sportType: String
        var startDate: Date
        var movingTime: Int
        var distance: Double
        var averageWatts: Double?
        var weightedAverageWatts: Double?
        var kilojoules: Double?
        var averageHeartrate: Double?
        var maxHeartrate: Double?
        var trainer: Bool
        var isDemo: Bool

        init(stravaID: Int, name: String, startDate: Date) {
            self.stravaID = stravaID
            self.name = name
            sportType = "VirtualRide"
            self.startDate = startDate
            movingTime = 3600
            distance = 31_000
            averageWatts = 205
            weightedAverageWatts = 221
            kilojoules = 738
            averageHeartrate = 148
            maxHeartrate = 171
            trainer = true
            isDemo = false
        }
    }
}

@Suite("SwiftData migration")
@MainActor
struct MigrationTests {
    @Test func storeWithoutRelativeEffortFieldsOpensWithCurrentSchema() throws {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("migration-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: dir) }
        let url = dir.appendingPathComponent("default.store")
        let start = Date(timeIntervalSince1970: 1_790_000_000)

        do {
            let legacy = Schema(versionedSchema: LegacySchemaV1.self)
            let container = try ModelContainer(for: legacy, configurations: ModelConfiguration(schema: legacy, url: url))
            let context = ModelContext(container)
            context.insert(LegacySchemaV1.StoredRide(stravaID: 777, name: "Alte Fahrt", startDate: start))
            try context.save()
        }
        let legacyColumns = columns(of: "ZSTOREDRIDE", in: url)
        #expect(legacyColumns.contains("ZSTRAVAID"))
        #expect(!legacyColumns.contains("ZPERCEIVEDEXERTION"), "the legacy store must really be the old schema")

        let container = try AppEnvironment.makeContainer(url: url)
        let rides = try ModelContext(container).fetch(FetchDescriptor<StoredRide>())
        #expect(rides.count == 1)
        let ride = try #require(rides.first)
        #expect(ride.stravaID == 777)
        #expect(ride.name == "Alte Fahrt")
        #expect(ride.startDate == start)
        #expect(ride.weightedAverageWatts == 221)
        #expect(ride.perceivedExertion == nil)
        #expect(ride.preferPerceivedExertion == false)
        #expect(ride.stravaRelativeEffort == nil)

        // The migrated store is fully usable: new fields can be written and read back.
        ride.perceivedExertion = 7
        try ride.modelContext?.save()
        let reopened = try ModelContext(AppEnvironment.makeContainer(url: url)).fetch(FetchDescriptor<StoredRide>())
        #expect(reopened.first?.perceivedExertion == 7)
        #expect(columns(of: "ZSTOREDRIDE", in: url).isSuperset(of: ["ZPERCEIVEDEXERTION", "ZPREFERPERCEIVEDEXERTION",
                                                                    "ZSTRAVARELATIVEEFFORT"]))
    }

    /// Column names of a Core Data table, read directly via SQLite.
    private func columns(of table: String, in url: URL) -> Set<String> {
        var db: OpaquePointer?
        guard sqlite3_open_v2(url.path, &db, SQLITE_OPEN_READONLY, nil) == SQLITE_OK else { return [] }
        defer { sqlite3_close(db) }
        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(db, "PRAGMA table_info(\(table))", -1, &statement, nil) == SQLITE_OK else { return [] }
        defer { sqlite3_finalize(statement) }
        var names: Set<String> = []
        while sqlite3_step(statement) == SQLITE_ROW {
            if let name = sqlite3_column_text(statement, 1) { names.insert(String(cString: name)) }
        }
        return names
    }
}
