# IndoorCoach

Persönliche iOS-App zur Planung von Indoor-Rennrad-Einheiten: Strava-Daten auswerten, mit Claude planen,
in den Kalender eintragen und als `.zwo` nach MyWhoosh bringen. Läuft vollständig auf dem iPhone, ohne Backend.

| Heute | Einheit | Plan | Verlauf |
|-------|---------|------|---------|
| ![](snapshots/01-heute.png) | ![](snapshots/02-workout.png) | ![](snapshots/03-plan.png) | ![](snapshots/04-verlauf.png) |

*(Screens aus dem Snapshot-Tool, Demo-Daten. Buttons werden dort als Platzhalter gerendert.)*

## Dokumente

1. [PRD](docs/01-PRD.md) – Ziele, User Stories, Annahmen
2. [Konzept & Architektur](docs/02-KONZEPT.md) – Entscheidungen, Datenmodell, Prompt-Design, MyWhoosh-Optionen, Risiken, Slices
3. [Installation & Einrichtung](docs/03-INSTALLATION.md) – Xcode, Strava-API-App, Claude-Key, MyWhoosh-Import
4. [Status & nächste Schritte](docs/04-STATUS.md)

## Aufbau

```
App/                    App-Hülle (@main, Assets)
Config/Info.plist       URL-Schema für Strava-OAuth, .zwo-Typ
IndoorCoachKit/         Swift Package mit der gesamten Logik und UI
  Sources/IndoorCoachKit/
    Domain/             Workout, Segment, Zonen, TSS/CTL/ATL, .zwo-Export, Profil
    Services/           StravaClient, ClaudeClient + PlanPrompt, Kalender, Keychain, Demo
    Store/              SwiftData-Modelle, AppModel
    UI/                 SwiftUI-Screens
  Tests/                Unit-Tests (swift test)
  Sources/SnapshotTool/ rendert Screens als PNG (macOS)
docs/                   Planung & Konzept
```
