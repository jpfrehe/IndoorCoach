import Foundation

/// Beispiel-Momente für den Demo-Modus und die UI-Tests (`-uiMoment levelUp|record|comeback|week`). Ihre IDs beginnen mit
/// `demo-`: Die Feier trägt dann den Hinweis „Beispiel mit Demo-Daten“, und das Ledger merkt sich nur, dass das Beispiel
/// einmal gezeigt wurde.
public enum DemoMoments {
    public static let idPrefix = "demo-"
    /// Das eine Beispiel im Demo-Modus (docs/22 §B1, Regel 6).
    public static let defaultKind = "levelUp"
    public static let kinds = ["levelUp", "record", "comeback", "week"]

    public static func isExample(_ moment: Moment) -> Bool { moment.id.hasPrefix(idPrefix) }

    /// Unbekannte Namen fallen auf `levelUp` zurück.
    public static func example(_ kind: String, now: Date) -> MomentBatch {
        func moment(_ id: String, _ kind: Moment.Kind, _ headline: String, _ detail: String?) -> Moment {
            Moment(id: idPrefix + id, kind: kind, date: now, headline: headline, detail: detail, rideID: nil)
        }
        switch kind {
        case "record":
            return MomentBatch([moment("record", .record, "Neue Bestleistung: 5 min · 268 W", "+7 W gegenüber deiner bisherigen Bestleistung (3. Dez.)")])
        case "comeback":
            return MomentBatch([moment("comeback", .comeback, "Du bist zurück", "Nach 12 Tagen Pause wieder im Sattel.")])
        case "week":
            return MomentBatch([moment("week", .weekPlanDone, "Plan der Woche geschafft · 4/4", "Alle geplanten Einheiten dieser Woche sind erledigt.")])
        default:
            return MomentBatch([moment("level-4", .levelUp, "Level 4 · Rollen-Routine", "Etappe 4 von 10: Stilfser Joch, 2757 m"),
                                moment("week", .weekPlanDone, "Plan der Woche geschafft · 4/4", "Alle geplanten Einheiten dieser Woche sind erledigt.")])
        }
    }

    /// Der Coach-Satz zum Beispiel – über dieselben Regeln wie im echten Betrieb, mit erfundenen Werten.
    public static func coachNote(for batch: MomentBatch, now: Date, calendar: Calendar = .current, ledger: MomentLedger = MomentLedger()) -> CoachNote? {
        let start = WinterArc.defaultSeason(containing: now, calendar: calendar).start
        var context = CoachNoteContext(now: now, calendar: calendar)
        switch batch.headline?.kind {
        case .record: context.record = .init(duration: 300, betterBefore: calendar.date(byAdding: .day, value: -150, to: now))
        case .comeback: context.comebackGapDays = 12
        default: context.season = .init(sessions: 12, hours: 9, since: start)
        }
        return CoachNote.make(context, ledger: ledger)
    }
}
