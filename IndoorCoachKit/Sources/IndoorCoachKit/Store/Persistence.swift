import Foundation
import SwiftData

extension AppEnvironment {
    /// The app's SwiftData schema. New attributes must stay optional or defaulted so existing stores migrate
    /// lightweight (covered by `MigrationTests`).
    public static let schema = Schema([StoredRide.self, StoredWorkout.self])

    /// Opens the store at `url` with the current schema (used by tests; the app uses the default location).
    public static func makeContainer(url: URL) throws -> ModelContainer {
        try ModelContainer(for: schema, configurations: [ModelConfiguration(schema: schema, url: url)])
    }
}
