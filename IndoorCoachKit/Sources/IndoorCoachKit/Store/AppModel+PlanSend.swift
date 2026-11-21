import Foundation
import SwiftData

extension AppModel {
    /// „Alle senden“: alle geplanten Einheiten ab heute an intervals.icu. Die Liste wird erst beim Aufruf geholt, nie aus einer alten Ansicht.
    public func sendUpcomingToIntervals() async {
        let today = Calendar.current.startOfDay(for: .now)
        let descriptor = FetchDescriptor<StoredWorkout>(predicate: #Predicate { $0.date >= today }, sortBy: [SortDescriptor(\.date)])
        let upcoming = ((try? context.fetch(descriptor)) ?? []).filter { $0.status == .planned }
        guard !upcoming.isEmpty else {
            show("Keine geplanten Einheiten zum Senden.", error: false); return
        }
        await sendToIntervals(upcoming)
    }
}
