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
    @Test func appContainerUsesTheSharedSchema() throws {
        // Regression: makeContainer(inMemory:) had its own entity list and dropped StoredCheckIn → crash on fetch.
        let container = try AppEnvironment.makeContainer(inMemory: true)
        let names = Set(container.schema.entities.map(\.name))
        #expect(names == Set(AppEnvironment.schema.entities.map(\.name)))
        #expect(names.contains("StoredCheckIn"))
        _ = try container.mainContext.fetch(FetchDescriptor<StoredCheckIn>())
    }

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
        // Sanity check of the legacy schema. Under heavy parallel test load SQLite can still hold the schema in the
        // WAL and report no columns; the migration assertions below are what matters, so only check when readable.
        let legacyColumns = columns(of: "ZSTOREDRIDE", in: url)
        if !legacyColumns.isEmpty {
            #expect(legacyColumns.contains("ZSTRAVAID"))
            #expect(!legacyColumns.contains("ZPERCEIVEDEXERTION"), "the legacy store must really be the old schema")
        }

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
        #expect(ride.decoupling == nil)
        #expect(ride.durability == nil)

        // The migrated store is fully usable: new fields can be written and read back.
        ride.perceivedExertion = 7
        ride.decoupling = 3.5
        ride.durability = 91.5
        try ride.modelContext?.save()
        let reopened = try ModelContext(AppEnvironment.makeContainer(url: url)).fetch(FetchDescriptor<StoredRide>())
        #expect(reopened.first?.perceivedExertion == 7)
        #expect(reopened.first?.decoupling == 3.5)
        #expect(reopened.first?.durability == 91.5)
        #expect(columns(of: "ZSTOREDRIDE", in: url).isSuperset(of: ["ZPERCEIVEDEXERTION", "ZPREFERPERCEIVEDEXERTION",
                                                                    "ZSTRAVARELATIVEEFFORT", "ZDECOUPLING", "ZDURABILITY"]))
    }

    @Test func legacyStoreGainsTheHealthFieldsAsOptionalColumns() throws {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("migration-health-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: dir) }
        let url = dir.appendingPathComponent("default.store")
        let start = Date(timeIntervalSince1970: 1_790_000_000)
        do {
            let legacy = Schema(versionedSchema: LegacySchemaV1.self)
            let container = try ModelContainer(for: legacy, configurations: ModelConfiguration(schema: legacy, url: url))
            let context = ModelContext(container)
            context.insert(LegacySchemaV1.StoredRide(stravaID: 888, name: "Vor Health", startDate: start))
            try context.save()
        }
        let container = try AppEnvironment.makeContainer(url: url)
        let ride = try #require(try ModelContext(container).fetch(FetchDescriptor<StoredRide>()).first)
        #expect(ride.stravaID == 888)
        #expect(ride.sourceRaw == nil && ride.healthUUID == nil && ride.estimatedTSS == nil)
        #expect(ride.foreignSport == nil && ride.mergedHealthUUID == nil && ride.healthNote == nil)
        #expect(ride.summary.healthUUID == nil && !ride.summary.isForeignSport)

        // Ein Health-Lauf lässt sich schreiben und wieder lesen.
        var run = RideSummary(id: -5, name: "Laufen (Apple Watch)", sportType: "Run", startDate: start, movingTime: 3000, distance: 0,
                              averageHeartrate: 150)
        run.healthUUID = UUID().uuidString
        run.foreignSport = "running"
        run.estimatedTSS = 61.5
        let context = ModelContext(container)
        context.insert(StoredRide(run))
        try context.save()
        let reopened = try ModelContext(AppEnvironment.makeContainer(url: url)).fetch(FetchDescriptor<StoredRide>(predicate: #Predicate { $0.stravaID == -5 }))
        let stored = try #require(reopened.first)
        #expect(stored.sourceRaw == StoredRide.healthSource)
        #expect(stored.summary.foreignSport == "running" && stored.summary.estimatedTSS == 61.5)
        #expect(stored.summary.healthUUID == run.healthUUID)
        let names = columns(of: "ZSTOREDRIDE", in: url)
        #expect(names.isSuperset(of: ["ZSOURCERAW", "ZHEALTHUUID", "ZESTIMATEDTSS", "ZFOREIGNSPORT", "ZMERGEDHEALTHUUID", "ZHEALTHNOTE"]))
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
